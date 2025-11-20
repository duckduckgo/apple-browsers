//
//  DefaultBrowserAndDockPromptPresenting.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUIExtensions
import Combine
import BrowserServicesKit
import FeatureFlags

protocol DefaultBrowserAndDockPromptPresenting {
    /// Publisher to let know the banner was dismissed.
    ///
    /// This is used, for example, to close the banner in all windows when it gets closed in one.
    var bannerDismissedPublisher: AnyPublisher<Void, Never> { get }

    /// Attempts to show the SAD/ATT prompt to the user, either as a popover or a banner, based on the user's eligibility for the experiment.
    ///
    /// - Parameter popoverAnchorProvider: A closure that provides the anchor view for the popover. If the popover is eligible to be shown, it will be displayed relative to this view.
    /// - Parameter bannerViewHandler: A closure that takes a `BannerMessageViewController` instance, which can be used to configure and present the banner.
    ///
    /// The function first checks the user's eligibility for the experiment. Depending on which cohort the user falls into, the function will attempt to show either a popover or a banner.
    ///
    /// If the user is eligible for the popover, it will be displayed relative to the view provided by the `popoverAnchorProvider` closure, and it will be dismissed once the user interacts with it (either by confirming or dismissing the popover).
    ///
    /// If the user is eligible for the banner, the function uses the `bannerViewHandler` closure to configure and present the banner. This allows the caller to customize the appearance and behavior of the banner as needed.
    ///
    /// The popover is more ephemeral and will only be shown in a single window, while the banner is more persistent and will be shown in all windows until the user takes an action on it.
    func tryToShowPrompt(popoverAnchorProvider: @escaping () -> NSView?,
                         bannerViewHandler: @escaping (BannerMessageViewController) -> Void,
                         inactiveUserModalWindowProvider: @escaping () -> NSWindow?)
}

enum DefaultBrowserAndDockPromptPresentationType: Equatable {
    case active(ActiveUserPrompt)
    case inactive
}

extension DefaultBrowserAndDockPromptPresentationType {
    enum ActiveUserPrompt {
        case banner
        case popover
    }
}

final class DefaultBrowserAndDockPromptPresenter: DefaultBrowserAndDockPromptPresenting {
    private let coordinator: DefaultBrowserAndDockPrompt
    private let statusUpdateNotifier: DefaultBrowserAndDockPromptStatusNotifying
    private let bannerDismissedSubject = PassthroughSubject<Void, Never>()
    private let uiProvider: DefaultBrowserAndDockPromptUIProviding

    private var popover: NSPopover?
    private var inactiveUserModal: NSWindow?
    private var statusUpdateCancellable: Cancellable?
    private(set) var currentShownPrompt: DefaultBrowserAndDockPromptPresentationType?

    init(
        coordinator: DefaultBrowserAndDockPrompt,
        statusUpdateNotifier: DefaultBrowserAndDockPromptStatusNotifying,
        uiProvider: DefaultBrowserAndDockPromptUIProviding
    ) {
        self.coordinator = coordinator
        self.statusUpdateNotifier = statusUpdateNotifier
        self.uiProvider = uiProvider
    }

    var bannerDismissedPublisher: AnyPublisher<Void, Never> {
        bannerDismissedSubject.eraseToAnyPublisher()
    }

    func tryToShowPrompt(popoverAnchorProvider: @escaping () -> NSView?,
                         bannerViewHandler: @escaping (BannerMessageViewController) -> Void,
                         inactiveUserModalWindowProvider: @escaping () -> NSWindow?) {
        guard let type = coordinator.getPromptType() else { return }

        func showPrompt() {
            switch type {
            case .active(.banner):
                guard let banner = getBanner() else { return }
                bannerViewHandler(banner)
            case .active(.popover):
                guard let view = popoverAnchorProvider() else { return }
                showPopover(below: view)
            case .inactive:
                guard let window = inactiveUserModalWindowProvider() else { return }
                showInactiveUserModal(over: window)
            }

            // Keep track of what type of prompt is shown.
            // If the user modify the SAD/ATT state outside of the banner we need to know the type of prompt it was shown to save its visualisation date.
            currentShownPrompt = type
            // Start subscribing to status updates for SAD/ATT.
            // It's possible that the user may set SAD/ATT outside the prompt (e.g. from Settings). If that happens we want to dismiss the prompt.
            subscribeToStatusUpdates()
        }

        // If we are switching prompt types, ensure the previous prompt is dismissed before showing the new one.
        if type != currentShownPrompt {
            dismissAllPrompts(onCompletion: showPrompt)
        } else {
            showPrompt()
        }
    }

    // MARK: - Private

    private func subscribeToStatusUpdates() {
        statusUpdateCancellable = statusUpdateNotifier
            .statusPublisher
            .dropFirst() // Skip the first value as it represents the current status.
            .prefix(1) // Only one event is necessary as the notifier will send an event only when there's a new update.
            .sink { [weak self] _ in
                guard let self else { return }

                if let currentShownPrompt {
                    self.coordinator.dismissAction(.statusUpdate(prompt: currentShownPrompt))
                }
                clearStatusUpdateData()
                dismissAllPrompts()
            }

        statusUpdateNotifier.startNotifyingStatus(interval: 1.0)
    }

    private func showPopover(below view: NSView) {
        guard let content = coordinator.evaluatePromptEligibility else {
            return
        }

        initializePopover(with: content)
        showPopover(positionedBelow: view)
    }

    private func showInactiveUserModal(over window: NSWindow) {
        guard let content = coordinator.evaluatePromptEligibility else {
            return
        }

        initializeInactiveUserModal(with: content)
        showInactiveUserModal(positionedOver: window)
    }

    private func getBanner() -> BannerMessageViewController? {
        guard let type = coordinator.evaluatePromptEligibility else {
            return nil
        }

        let content = DefaultBrowserAndDockPromptContent.banner(type)

        /// We mark the banner as shown when it gets actioned (either dismiss or confirmation)
        /// Given that we want to show the banner in all windows.
        return BannerMessageViewController(
            message: content.message,
            image: content.icon,
            primaryAction: .init(
                title: content.primaryButtonTitle,
                action: {
                    self.coordinator.confirmAction(for: .active(.banner))
                    self.dismissBanner()
                }
            ),
            secondaryAction: .init(
                title: content.secondaryButtonTitle,
                action: {
                    self.coordinator.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: true))
                    self.dismissBanner()
                }
            ),
            closeAction: {
                self.coordinator.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: false))
                self.dismissBanner()
            })
    }

    private func createPopover(with type: DefaultBrowserAndDockPromptType) -> NSHostingController<DefaultBrowserAndDockPromptPopoverView> {
        let content = DefaultBrowserAndDockPromptContent.popover(type)
        let viewModel = DefaultBrowserAndDockPromptPopoverViewModel(
            title: content.title,
            message: content.message,
            image: content.icon,
            buttonText: content.primaryButtonTitle,
            buttonAction: {
                self.clearStatusUpdateData()
                self.coordinator.confirmAction(for: .active(.popover))
                self.popover?.close()
            },
            secondaryButtonText: content.secondaryButtonTitle,
            secondaryButtonAction: {
                self.clearStatusUpdateData()
                self.coordinator.dismissAction(.userInput(prompt: .active(.popover), shouldHidePermanently: false))
                self.popover?.close()
            })

        let contentView = DefaultBrowserAndDockPromptPopoverView(viewModel: viewModel)

        return NSHostingController(rootView: contentView)
    }

    private func createInactiveUserModal(with type: DefaultBrowserAndDockPromptType) -> NSHostingController<DefaultBrowserAndDockPromptInactiveUserView> {
        let content = DefaultBrowserAndDockPromptContent.inactive(type)
        let viewModel = DefaultBrowserAndDockPromptInactiveUserViewModel(
            message: content.message,
            image: content.icon,
            primaryButtonLabel: content.primaryButtonTitle,
            dismissButtonLabel: content.secondaryButtonTitle,
            primaryButtonAction: { [weak self] in
                guard let self else { return }
                clearStatusUpdateData()
                coordinator.confirmAction(for: .inactive)
                Task { @MainActor in
                    await self.dismissInactiveUserModal()
                }
            },
            dismissButtonAction: {[weak self] in
                guard let self else { return }
                clearStatusUpdateData()
                coordinator.dismissAction(.userInput(prompt: .inactive, shouldHidePermanently: false))
                Task { @MainActor in
                    await self.dismissInactiveUserModal()
                }
            })
        let contentView = DefaultBrowserAndDockPromptInactiveUserView(viewModel: viewModel, browsersComparisonChart: uiProvider.makeBrowserComparisonChart())

        return NSHostingController(rootView: contentView)
    }

    private func dismissBanner() {
        self.clearStatusUpdateData()
        self.bannerDismissedSubject.send()
    }

    private func dismissInactiveUserModal() async {
        await inactiveUserModal?.contentViewController?.dismiss()
        inactiveUserModal = nil
    }

    private func dismissAllPrompts(onCompletion: (() -> Void)? = nil) {
        popover?.close()
        bannerDismissedSubject.send()
        Task { @MainActor in
            await dismissInactiveUserModal()
            onCompletion?()
        }
    }

    private func clearStatusUpdateData() {
        self.statusUpdateNotifier.stopNotifyingStatus()
        self.currentShownPrompt = nil
    }

    private func initializePopover(with type: DefaultBrowserAndDockPromptType) {
        let viewController = createPopover(with: type)
        popover = DefaultBrowserAndDockPromptPopover(viewController: viewController)
    }

    private func showPopover(positionedBelow view: NSView) {
        popover?.show(positionedBelow: view)
        popover?.contentViewController?.view.makeMeFirstResponder()
    }

    private func initializeInactiveUserModal(with type: DefaultBrowserAndDockPromptType) {
        let content = createInactiveUserModal(with: type)
        inactiveUserModal = NSWindow(contentViewController: content)
    }

    private func showInactiveUserModal(positionedOver window: NSWindow) {
        guard let inactiveUserModal else { return }
        window.beginSheet(inactiveUserModal)
    }

}

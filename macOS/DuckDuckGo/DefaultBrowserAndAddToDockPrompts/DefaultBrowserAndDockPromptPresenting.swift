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

    /// **PROMPT ORCHESTRATOR**
    ///
    /// Called from `MainViewController.showSetAsDefaultAndAddToDockIfNeeded()` when a window becomes key.
    /// This is the main entry point for displaying any type of default browser/dock prompt.
    ///
    /// **Decision Flow:**
    /// 1. Asks `coordinator.getPromptType()` to determine eligibility (returns nil if no prompt should show)
    /// 2. Coordinator checks all conditions (see `DefaultBrowserAndDockPromptCoordinator.getPromptType()`)
    /// 3. If eligible, displays the appropriate prompt type:
    ///
    /// **Prompt Types:**
    /// - **`.active(.popover)`**: First-time prompt, shown once after 14 days (default) from install
    ///   - Anchored to address bar or bookmarks bar
    ///   - Dismissed after user interaction
    ///   - Marks `popoverShownDate` in UserDefaults
    ///
    /// - **`.active(.banner)`**: Follow-up prompt, shown 14 days (default) after popover
    ///   - Persistent bar at top of ALL windows
    ///   - Can repeat every 14 days (default) if not permanently dismissed
    ///   - Marks `bannerShownDate` and increments `bannerShownOccurrences`
    ///
    /// - **`.inactive`**: Re-engagement prompt for inactive users
    ///   - Shown after 28 days (default) from install AND 7 days (default) of inactivity
    ///   - Modal sheet over main window
    ///   - Shown only once, marks `inactiveUserModalShownDate`
    ///
    /// **See also:**
    /// - `DefaultBrowserAndDockPromptCoordinator.getPromptType()` - determines which prompt to show
    /// - `DefaultBrowserAndDockPromptTypeDecider` - implements timing logic
    /// - `getBanner()`, `showPopover()`, `showInactiveUserModal()` - create and display prompts
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

    /// Monitors system status changes (default browser/dock status) while a prompt is shown.
    /// If user sets default browser or adds to dock outside the prompt (e.g., via System Settings),
    /// this automatically dismisses the prompt since it's no longer relevant.
    private func subscribeToStatusUpdates() {
        statusUpdateCancellable = statusUpdateNotifier
            .statusPublisher
            .dropFirst() // Skip the first value as it represents the current status.
            .prefix(1) // Only one event is necessary as the notifier will send an event only when there's a new update.
            .sink { [weak self] _ in
                guard let self else { return }

                // User changed status outside the prompt → record it and dismiss
                if let currentShownPrompt {
                    self.coordinator.dismissAction(.statusUpdate(prompt: currentShownPrompt))
                }
                clearStatusUpdateData()
                dismissAllPrompts()
            }

        // Poll every second to detect external status changes
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

    /// Creates the banner view controller with three possible user actions.
    /// Unlike popover, banner is NOT marked as shown until user interacts with it,
    /// so it appears in all windows simultaneously.
    private func getBanner() -> BannerMessageViewController? {
        // Check what we need to prompt about (default browser, dock, or both)
        guard let type = coordinator.evaluatePromptEligibility else {
            return nil
        }

        // Get localized content based on prompt type
        let content = DefaultBrowserAndDockPromptContent.banner(type)

        /// We mark the banner as shown when it gets actioned (either dismiss or confirmation)
        /// Given that we want to show the banner in all windows.
        return BannerMessageViewController(
            message: content.message,
            image: content.icon,
            // Primary button: "Make Default" or "Add to Dock" or both
            primaryAction: .init(
                title: content.primaryButtonTitle,
                action: {
                    // Triggers system prompt and marks banner as shown
                    self.coordinator.confirmAction(for: .active(.banner))
                    self.dismissBanner()
                }
            ),
            // Secondary button: "Never Ask Again" (permanent dismissal)
            secondaryAction: .init(
                title: content.secondaryButtonTitle,
                action: {
                    // Sets isBannerPermanentlyDismissed = true, stops all future banners
                    self.coordinator.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: true))
                    self.dismissBanner()
                }
            ),
            // Close button (X): Dismiss for now, can show again later
            closeAction: {
                // Marks banner as shown but allows it to repeat after delay
                self.coordinator.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: false))
                self.dismissBanner()
            })
    }

    /// Creates the popover view controller (first-time prompt, shown once).
    /// Popover has only two actions: confirm or dismiss (no "Never Ask Again").
    private func createPopover(with type: DefaultBrowserAndDockPromptType) -> NSHostingController<DefaultBrowserAndDockPromptPopoverView> {
        let content = DefaultBrowserAndDockPromptContent.popover(type)
        let viewModel = DefaultBrowserAndDockPromptPopoverViewModel(
            title: content.title,
            message: content.message,
            image: content.icon,
            buttonText: content.primaryButtonTitle,
            // Primary button: "Make Default" or "Add to Dock" or both
            buttonAction: {
                self.clearStatusUpdateData()
                // Triggers system prompt, marks popover as shown (won't show again)
                self.coordinator.confirmAction(for: .active(.popover))
                self.popover?.close()
            },
            secondaryButtonText: content.secondaryButtonTitle,
            // Secondary button: "Not Now" (dismiss, banner will follow later)
            secondaryButtonAction: {
                self.clearStatusUpdateData()
                // Marks popover as shown, banner sequence begins
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

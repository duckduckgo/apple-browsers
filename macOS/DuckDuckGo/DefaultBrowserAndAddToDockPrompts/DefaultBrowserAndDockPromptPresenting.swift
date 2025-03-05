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
    func tryToShowPrompt(popoverAnchorProvider: () -> NSView?,
                         bannerViewHandler: (BannerMessageViewController) -> Void)
}

enum DefaultBrowserAndDockPromptPresentationType {
    case banner
    case popover
}

final class DefaultBrowserAndDockPromptPresenter: DefaultBrowserAndDockPromptPresenting {
    private let coordinator: DefaultBrowserAndDockPrompt
    private let repository: DefaultBrowserAndDockPromptStoring
    private let featureFlagger: FeatureFlagger
    private let bannerDismissedSubject = PassthroughSubject<Void, Never>()

    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: DefaultBrowserAndDockPrompt,
         repository: DefaultBrowserAndDockPromptStoring = DefaultBrowserAndDockPromptStore(),
         featureFlagger: FeatureFlagger) {
        self.coordinator = coordinator
        self.repository = repository
        self.featureFlagger = featureFlagger

        subscribeToLocalOverride()
    }

    var bannerDismissedPublisher: AnyPublisher<Void, Never> {
        bannerDismissedSubject.eraseToAnyPublisher()
    }

    func tryToShowPrompt(popoverAnchorProvider: () -> NSView?,
                         bannerViewHandler: (BannerMessageViewController) -> Void) {
        guard !repository.didShowPrompt(), let type = coordinator.getPromptType() else { return }

        switch type {
        case .banner:
            guard let banner = getBanner() else { return }

            bannerViewHandler(banner)
        case .popover:
            guard let view = popoverAnchorProvider() else { return }

            showPopover(below: view)
        }
    }

    // MARK: - Private

    private func showPopover(below view: NSView) {
        guard let content = coordinator.evaluatePromptEligibility else {
            return
        }

        /// For the popover we mark it as shown when the user actions on it.
        /// Given that we want to show the banner in all windows.
        repository.setPromptShown(true)

        self.initializePopover(with: content)
        self.showPopover(positionedBelow: view)
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
            buttonText: content.primaryButtonTitle,
            buttonAction: {
                self.coordinator.onPromptConfirmation()
                self.repository.setPromptShown(true)
                self.bannerDismissedSubject.send()
            },
            closeAction: {
                self.bannerDismissedSubject.send()
                self.repository.setPromptShown(true)
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
                self.coordinator.onPromptConfirmation()
                self.popover?.close()
            },
            secondaryButtonText: content.secondaryButtonTitle,
            secondaryButtonAction: {
                self.popover?.close()
            })

        let contentView = DefaultBrowserAndDockPromptPopoverView(viewModel: viewModel)

        return NSHostingController(rootView: contentView)
    }

    private func initializePopover(with type: DefaultBrowserAndDockPromptType) {
        let viewController = createPopover(with: type)
        popover = DefaultBrowserAndDockPromptPopover(viewController: viewController)
    }

    private func showPopover(positionedBelow view: NSView) {
        popover?.show(positionedBelow: view)
        popover?.contentViewController?.view.makeMeFirstResponder()
    }

    private func subscribeToLocalOverride() {
        guard let overridesHandler = featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }

        overridesHandler.experimentFlagDidChangePublisher
            .filter { $0.0 == .popoverVsBannerExperiment }
            .sink { (_, cohort) in
                if FeatureFlag.PopoverVSBannerExperimentCohort.cohort(for: cohort) == nil { return }

                /// For testing purposes when we override the local features and because we want to show the prompt.
                /// We set the set prompt flag to false in case it was show in the past.
                self.repository.setPromptShown(false)

                NotificationCenter.default.post(name: .setAsDefaultBrowserAndAddToDockExperimentFlagOverrideDidChange, object: nil)
            }
            .store(in: &cancellables)
    }
}

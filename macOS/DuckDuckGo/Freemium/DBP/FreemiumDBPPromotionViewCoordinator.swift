//
//  FreemiumDBPPromotionViewCoordinator.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation
import Freemium
import OSLog
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import Common
import FoundationExtensions

/// Default implementation of `FreemiumDBPPromotionViewCoordinating`, responsible for managing
/// the visibility of the promotion and responding to user interactions with the promotion view.
final class FreemiumDBPPromotionViewCoordinator: ObservableObject {

    /// Whether the freemium DBP feature is currently available (includes async checks like product availability).
    @Published private(set) var isFeatureAvailable: Bool = false

    /// The view model representing the promotion, which updates based on the user's state. Returns `nil` if the feature is not enabled
    @Published
    private(set) var viewModel: PromotionViewModel?

    /// Callback invoked when the user interacts with the banner (proceed or close).
    /// Set by the promo delegate to route results back through show().
    var onUserAction: ((PromoResult) -> Void)?

    /// Callback invoked when scan results arrive, allowing the delegate
    /// to trigger a re-evaluation of eligibility via refreshEligibility().
    var onScanResultsUpdated: (() -> Void)?

    /// Whether the user dismissed the promotion before queue integration (legacy).
    /// Read-only — current dismissals are handled by PromoService.
    var hasLegacyDismissal: Bool {
        freemiumDBPUserStateManager.didDismissHomePagePromotion
    }

    /// The user's first scan results, if any.
    var firstScanResults: FreemiumDBPMatchResults? {
        freemiumDBPUserStateManager.firstScanResults
    }

    /// Whether the feature flag is enabled (synchronous — no async dependencies).
    var isFeatureFlagEnabled: Bool {
        freemiumDBPFeature.isFeatureFlagEnabled
    }

    /// Whether the feature is available ignoring purchase capability. Used by the fast path while product availability settles.
    var isFeatureAvailableIgnoringPurchaseCapability: Bool {
        freemiumDBPFeature.isAvailableIgnoringPurchaseCapability
    }

    /// The user state manager, which tracks the user's activation status and scan results.
    private var freemiumDBPUserStateManager: FreemiumDBPUserStateManager

    /// Responsible for determining the availability of Freemium DBP.
    private let freemiumDBPFeature: FreemiumDBPFeature

    /// The presenter used to show the Freemium DBP UI.
    private let freemiumDBPPresenter: FreemiumDBPPresenter

    /// A set of cancellables for managing Combine subscriptions.
    var cancellables = Set<AnyCancellable>()

    /// Per-window cancellables for banner-impression observers. Keyed by `ObjectIdentifier(windowController)`
    /// so the subscription — which retains the `@Published` subject and therefore the last emitted
    /// `TabViewModel` → `Tab` → `WebView` — is dropped when the window closes.
    private var perWindowBannerImpressionCancellables: [ObjectIdentifier: AnyCancellable] = [:]

    /// The `NotificationCenter` instance used when subscribing to notifications
    private let notificationCenter: NotificationCenter

    /// The `DataBrokerProtectionFreemiumPixelHandler` instance used to fire pixels
    private let dataBrokerProtectionFreemiumPixelHandler: EventMapping<DataBrokerProtectionFreemiumPixels>

    /// Publisher that emits when contextual onboarding is completed
    private let contextualOnboardingPublisher: AnyPublisher<Bool, Never>

    init(freemiumDBPUserStateManager: FreemiumDBPUserStateManager,
         freemiumDBPFeature: FreemiumDBPFeature,
         freemiumDBPPresenter: FreemiumDBPPresenter = DefaultFreemiumDBPPresenter(),
         notificationCenter: NotificationCenter = .default,
         dataBrokerProtectionFreemiumPixelHandler: EventMapping<DataBrokerProtectionFreemiumPixels> = DataBrokerProtectionFreemiumPixelHandler(),
         contextualOnboardingPublisher: AnyPublisher<Bool, Never> = Empty<Bool, Never>().eraseToAnyPublisher()) {

        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
        self.freemiumDBPFeature = freemiumDBPFeature
        self.freemiumDBPPresenter = freemiumDBPPresenter
        self.notificationCenter = notificationCenter
        self.dataBrokerProtectionFreemiumPixelHandler = dataBrokerProtectionFreemiumPixelHandler
        self.contextualOnboardingPublisher = contextualOnboardingPublisher

        isFeatureAvailable = freemiumDBPFeature.isAvailable

        subscribeToFeatureAvailabilityUpdates()
        observeFreemiumDBPNotifications()
        observeContextualOnboardingCompletion()

        Task { @MainActor [weak self] in
            self?.observeFreemiumDBPBannerImpressions()
        }
    }

    @MainActor
    func refreshViewModel() {
        viewModel = createViewModel()
    }

    @MainActor
    func clearViewModel() {
        viewModel = nil
    }
}

private extension FreemiumDBPPromotionViewCoordinator {

    /// Action to be executed when the user proceeds with the promotion (e.g opens DBP)
    var proceedAction: () async -> Void {
        { @MainActor [weak self] in
            guard let self else { return }

            execute(resultsAction: {
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabResultsClickCount)
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabResultsClick)
            }, orNoResultsAction: {
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabNoResultsClickCount)
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabNoResultsClick)
            }, orPromotionAction: {
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabScanClickCount)
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabScanClick)
            })

            showFreemiumDBP()
            onUserAction?(.actioned)
        }
    }

    /// Action to be executed when the user closes the promotion.
    var closeAction: () -> Void {
        { [weak self] in
            guard let self else { return }

            execute(resultsAction: {
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabResultsDismiss)
            }, orNoResultsAction: {
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabNoResultsDismiss)
            }, orPromotionAction: {
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabScanDismiss)
            })

            onUserAction?(.ignored())
        }
    }

    /// Shows the Freemium DBP user interface via the presenter.
    @MainActor
    func showFreemiumDBP() {
        freemiumDBPPresenter.showFreemiumDBPAndSetActivated(windowControllersManager: Application.appDelegate.windowControllersManager)
    }

    /// Creates the view model for the promotion, updating based on the user's scan results.
    ///
    /// - Returns: The `PromotionViewModel` that represents the current state of the promotion.
    /// Only called from the delegate-controlled `refreshViewModel()` path, where full eligibility
    /// is already enforced by the PromoDelegate. This guard is a defensive check for the feature flag only —
    /// async checks (product availability) are intentionally skipped to avoid startup timing issues.
    func createViewModel() -> PromotionViewModel? {
        guard freemiumDBPFeature.isFeatureFlagEnabled else {
            return nil
        }

        if let results = freemiumDBPUserStateManager.firstScanResults {
            if results.matchesCount > 0 {
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabResultsImpression)
                return .freemiumDBPPromotionScanEngagementResults(
                    resultCount: results.matchesCount,
                    brokerCount: results.brokerCount,
                    proceedAction: proceedAction,
                    closeAction: closeAction
                )
            } else {
                self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabNoResultsImpression)
                return .freemiumDBPPromotionScanEngagementNoResults(
                    proceedAction: proceedAction,
                    closeAction: closeAction
                )
            }
        } else {
            self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabScanImpression)
            return .freemiumDBPPromotion(proceedAction: proceedAction, closeAction: closeAction)
        }
    }

    func observeContextualOnboardingCompletion() {
        contextualOnboardingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCompleted in
                guard let self, isCompleted else { return }
                Logger.freemiumDBP.debug("[Freemium DBP] Contextual Onboarding Completed")
                onScanResultsUpdated?()
            }
            .store(in: &cancellables)
    }

    /// Subscribes to feature availability updates from the `freemiumDBPFeature`'s availability publisher.
    ///
    /// This method listens to the `isAvailablePublisher` of the `freemiumDBPFeature`, which publishes
    /// changes to the feature's availability. It performs the following actions when an update is received:
    func subscribeToFeatureAvailabilityUpdates() {
        freemiumDBPFeature.isAvailablePublisher
            .prepend(freemiumDBPFeature.isAvailable)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available in
                guard let self else { return }
                self.isFeatureAvailable = available
            }
            .store(in: &cancellables)
    }

    func observeFreemiumDBPNotifications() {
        notificationCenter.publisher(for: .freemiumDBPResultPollingComplete)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Logger.freemiumDBP.debug("[Freemium DBP] Received Scan Results Notification")
                self?.onScanResultsUpdated?()
            }
            .store(in: &cancellables)
    }

    /// Executes one of three possible actions based on the state of the user's first scan results.
    ///
    /// This function checks the results of the user's first scan, stored in `freemiumDBPUserStateManager`.
    /// Depending on the state of the scan results, it executes one of the provided actions:
    /// - If there are scan results with a `matchesCount` greater than 0, it calls `resultsAction`.
    /// - If there are scan results, but `matchesCount` is 0, it calls `noResultsAction`.
    /// - If no scan results are available, it calls `promotionAction`.
    ///
    /// - Parameters:
    ///   - resultsAction: The action to execute when there are scan results with one or more matches.
    ///   - noResultsAction: The action to execute when there are scan results but no matches.
    ///   - promotionAction: The action to execute when there are no scan results available.
    func execute(resultsAction: () -> Void, orNoResultsAction noResultsAction: () -> Void, orPromotionAction promotionAction: () -> Void) {
        if let results = freemiumDBPUserStateManager.firstScanResults {
            if results.matchesCount > 0 {
                resultsAction()
            } else {
                noResultsAction()
            }
        } else {
            promotionAction()
        }
    }

}

// MARK: - Freemium DBP Promo Banner Impression Observation

/// Observes per-window tab-selection changes to detect when the New Tab Page becomes the active tab,
/// which is the moment the Freemium DBP promo banner (when visible) is presented to the user.
/// Drives per-impression banner-view counting — `.newTabPageWebViewDidAppear` only fires on
/// webview-to-window attach, not on tab activation back to an existing NTP, so it cannot.
private extension FreemiumDBPPromotionViewCoordinator {

    @MainActor
    func observeFreemiumDBPBannerImpressions() {
        let manager = Application.appDelegate.windowControllersManager

        // Windows that already existed when this observer started: their @Published replay is
        // ambient launch-time state, not a fresh impression event.
        for windowController in manager.mainWindowControllers {
            observeFreemiumDBPBannerImpressions(in: windowController, opened: false)
        }

        // Windows opened later (Cmd-N, deeplinks): the first emission is the user's fresh new tab.
        manager.didRegisterWindowController
            .sink { [weak self] windowController in
                self?.observeFreemiumDBPBannerImpressions(in: windowController, opened: true)
            }
            .store(in: &cancellables)

        manager.didUnregisterWindowController
            .sink { [weak self] windowController in
                self?.perWindowBannerImpressionCancellables.removeValue(forKey: ObjectIdentifier(windowController))
            }
            .store(in: &cancellables)
    }

    @MainActor
    func observeFreemiumDBPBannerImpressions(in windowController: MainWindowController, opened: Bool) {
        let selectedTabPublisher = windowController.mainViewController.tabCollectionViewModel.$selectedTabViewModel
            .compactMap { $0 }

        // The first value @Published replays when we subscribe means very different things depending
        // on when the window was registered:
        //  - For windows that were already open at observer-setup time, the replay is the *current
        //    ambient state* — the user has been looking at this tab; counting it as an impression
        //    would conflate launch noise (e.g. placeholder→restored tab swaps) with real events.
        //    Drop it, and rely on subsequent user-driven changes to fire.
        //  - For just-opened windows, the first emission IS the impression — the user just opened
        //    a new window and is seeing whatever tab landed in it (typically NTP). Keep it.
        let pipeline: AnyPublisher<TabViewModel, Never> = opened
            ? selectedTabPublisher.eraseToAnyPublisher()
            : selectedTabPublisher.dropFirst().eraseToAnyPublisher()

        perWindowBannerImpressionCancellables[ObjectIdentifier(windowController)] = pipeline
            .sink { [weak self] selectedTabViewModel in
                self?.handleSelectedTabChanged(selectedTabViewModel)
            }
    }

    @MainActor
    func handleSelectedTabChanged(_ selectedTabViewModel: TabViewModel) {
        // Burner (Fire) Window NTPs don't render the freemium banner — skip to avoid over-counting.
        guard case .newtab = selectedTabViewModel.tab.content,
              !selectedTabViewModel.tab.burnerMode.isBurner else { return }

        // Banner must actually be presentable. `viewModel == nil` means PromoService / feature
        // gating has not produced a renderable promotion for this user/state.
        guard viewModel != nil else { return }

        execute(resultsAction: {
            self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabResultsImpressionCount)
        }, orNoResultsAction: {
            self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabNoResultsImpressionCount)
        }, orPromotionAction: {
            self.dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.newTabScanImpressionCount)
        })
    }
}

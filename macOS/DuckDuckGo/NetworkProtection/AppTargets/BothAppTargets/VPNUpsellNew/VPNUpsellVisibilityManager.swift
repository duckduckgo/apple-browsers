//
//  VPNUpsellVisibilityManager.swift
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

import BrowserServicesKit
import Combine
import Common
import Foundation
import PixelKit
import Subscription
import VPN

extension VPNUpsellVisibilityManager {
    enum Constants {
        static let defaultBrowserPollingCount = 60
        static let defaultBrowserPollingInterval = 1.0
        static let timeIntervalBeforeShowingUpsell = 600.0
        static let autoDismissDays = 7
    }
}

extension VPNUpsellVisibilityManager {
    enum State: Equatable {
        case uninitialized // Initial state, before setup is called
        case notEligible // User is not new, or already subscribed, or feature flag is off
        case dismissed // User has dismissed the upsell, or it has been auto-dismissed
        case waitingForConditions // 1st launch: waiting for the user to finish contextual onboarding and set default browser
        case waitingForTimer // 1st launch: waiting for the timer to complete after meeting conditions
        case visible // User is eligible and the upsell should be shown
    }
}

/// Manages the visibility and state of VPN upsell messaging based on user onboarding flow.
///
final class VPNUpsellVisibilityManager: ObservableObject {
    // MARK: - Output
    @Published private(set) var state: State = .uninitialized
    @Published private(set) var shouldShowNotificationDot: Bool = false

    // MARK: - Dependencies
    private let isFirstLaunch: Bool
    private let isNewUser: Bool
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let contextualOnboardingPublisher: AnyPublisher<Bool, Never>
    private let featureFlagger: FeatureFlagger
    private let timerDuration: TimeInterval
    private let autoDismissDays: Int
    private var persistor: VPNUpsellUserDefaultsPersisting
    private let pixelHandler: (PrivacyProPixel) -> Void

    // MARK: - State
    private let isDefaultBrowserSubject = PassthroughSubject<Bool, Never>()
    private let canUserPurchaseSubject = PassthroughSubject<Bool, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var defaultBrowserPollingTimer: Timer?
    private var timer: Timer?
    private var defaultBrowserPollingCount = 0

    init(isFirstLaunch: Bool,
         isNewUser: Bool,
         subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         defaultBrowserProvider: DefaultBrowserProvider,
         contextualOnboardingPublisher: AnyPublisher<Bool, Never>,
         featureFlagger: FeatureFlagger,
         persistor: VPNUpsellUserDefaultsPersisting,
         timerDuration: TimeInterval = Constants.timeIntervalBeforeShowingUpsell,
         autoDismissDays: Int = Constants.autoDismissDays,
         pixelHandler: @escaping (PrivacyProPixel) -> Void = { PixelKit.fire($0) }) {
        self.isFirstLaunch = isFirstLaunch
        self.isNewUser = isNewUser
        self.subscriptionManager = subscriptionManager
        self.defaultBrowserProvider = defaultBrowserProvider
        self.contextualOnboardingPublisher = contextualOnboardingPublisher
        self.featureFlagger = featureFlagger
        self.timerDuration = timerDuration
        self.autoDismissDays = autoDismissDays
        self.persistor = persistor
        self.pixelHandler = pixelHandler
    }

    public func setup(isFirstLaunch: Bool) {
        guard state == .uninitialized else {
            return
        }

        updateState(.notEligible)

        guard isUserEligible else {
            return
        }

        canUserPurchaseSubject
            .sink { [weak self] canPurchase in
                guard let self else { return }
                guard canPurchase else {
                    self.updateState(.notEligible)
                    return
                }

                self.start(isFirstLaunch: isFirstLaunch)
            }
            .store(in: &cancellables)

        checkPurchaseEligibility()
    }

    private func start(isFirstLaunch: Bool) {
        if isFirstLaunch {
            monitorFirstLaunchConditions()
        } else {
            updateState(.visible)
        }

        monitorSubscriptionChanges()
    }

    // MARK: - Eligibility

    private var isUserEligible: Bool {
        isNewUser && !subscriptionManager.isUserAuthenticated
    }

    private var isFeatureOn: Bool {
        featureFlagger.isFeatureOn(.vpnToolbarUpsell)
    }

    private var shouldDismiss: Bool {
        shouldDismissAutomatically || persistor.vpnUpsellDismissed
    }

    private var shouldDismissAutomatically: Bool {
        guard let firstPinnedDate = persistor.vpnUpsellFirstPinnedDate else {
            return false
        }

        return firstPinnedDate.daysSinceNow() >= autoDismissDays
    }

    private func checkPurchaseEligibility() {
        switch subscriptionManager.currentEnvironment.purchasePlatform {
        case .appStore:
            subscriptionManager.canPurchasePublisher
                .sink { [weak self] canPurchase in
                    self?.canUserPurchaseSubject.send(canPurchase)
                }
                .store(in: &cancellables)
        case .stripe:
            canUserPurchaseSubject.send(true)
        }
    }

    // MARK: - Monitoring Setup

    private func monitorFirstLaunchConditions() {
        guard state == .notEligible else {
            return
        }

        let isDefaultBrowser = isDefaultBrowserSubject
            .dropFirst()

        Publishers.CombineLatest(
            contextualOnboardingPublisher,
            isDefaultBrowser
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] onboardingDone, isDefault in
            guard let self, onboardingDone, isDefault else {
                return
            }

            self.startTimerIfNeeded()
        }
        .store(in: &cancellables)

        updateState(.waitingForConditions)
        monitorDefaultBrowserChanges()
    }

    private func monitorSubscriptionChanges() {
        NotificationCenter.default
            .publisher(for: .entitlementsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSubscriptionChange()
            }
            .store(in: &cancellables)
    }

    // MARK: - Event Handling

    public func handlePinningChange(isPinned: Bool) {
        guard state == .visible else {
            return
        }

        guard isPinned else {
            dismissUpsell()
            return
        }

        if persistor.vpnUpsellFirstPinnedDate == nil {
            persistor.vpnUpsellFirstPinnedDate = Date()
        }
    }

    public func dismissNotificationDot() {
        persistor.vpnUpsellPopoverViewed = true
        shouldShowNotificationDot = false
    }

    private func startTimerIfNeeded() {
        guard state == .waitingForConditions else {
            return
        }

        resetDefaultBrowserPolling()

        timer = Timer.scheduledTimer(withTimeInterval: timerDuration, repeats: false) { [weak self] _ in
            self?.handleTimerCompletion()
        }

        updateState(.waitingForTimer)
    }

    private func handleTimerCompletion() {
        guard state == .waitingForTimer else {
            return
        }

        updateState(.visible)
    }

    private func handleSubscriptionChange() {
        if case .waitingForTimer = state {
            timer?.invalidate()
            timer = nil
        }

        updateState(.notEligible)
    }

    func dismissUpsell() {
        guard state == .visible else {
            return
        }

        persistor.vpnUpsellDismissed = true

        updateState(.dismissed)
    }

    // MARK: - Default Browser Polling

    private func monitorDefaultBrowserChanges() {
        guard state == .waitingForConditions else {
            return
        }
        NotificationCenter.default.publisher(for: .defaultBrowserPromptPresented)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.defaultBrowserPromptPresented()
            }
            .store(in: &cancellables)
    }

    private func defaultBrowserPromptPresented() {
        guard state == .waitingForConditions else {
            return
        }
        // Poll the default browser status for 60 seconds after the default browser prompt has been presented.
        defaultBrowserPollingTimer = Timer.scheduledTimer(withTimeInterval: Constants.defaultBrowserPollingInterval, repeats: true) { [weak self] _ in
            self?.handleDefaultBrowserPolling()
        }
    }

    private func handleDefaultBrowserPolling() {
        guard state == .waitingForConditions else {
            return
        }

        guard defaultBrowserPollingCount < Constants.defaultBrowserPollingCount else {
            resetDefaultBrowserPolling()
            return
        }

        defaultBrowserPollingCount += 1
        isDefaultBrowserSubject.send(defaultBrowserProvider.isDefault)
    }

    private func resetDefaultBrowserPolling() {
        defaultBrowserPollingTimer?.invalidate()
        defaultBrowserPollingTimer = nil
        defaultBrowserPollingCount = 0
    }

    // MARK: - Upsell Visibility

    private func updateState(_ newState: State) {
        guard !shouldDismiss else {
            state = .dismissed
            return
        }

        guard newState == .visible else {
            state = newState
            return
        }

        guard isFeatureOn, isUserEligible else {
            state = .notEligible
            return
        }

        let previousState = state

        // Fire pixel when transitioning to visible state
        if previousState != .visible {
            pixelHandler(.privacyProToolbarButtonShown)
        }

        state = newState

        shouldShowNotificationDot = !persistor.vpnUpsellPopoverViewed
    }

    deinit {
        timer?.invalidate()
        defaultBrowserPollingTimer?.invalidate()
    }
}

// MARK: - Debug Menu
/// These methods are triggered from the VPN Debug Menu (Debug > VPN > Upsell)
/// They explicitly set the state, bypassing all eligibility checks.
extension VPNUpsellVisibilityManager {
    func makeVisible() {
        state = .visible
    }

    func makeNotEligible() {
        state = .notEligible
    }
}

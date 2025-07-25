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
import Subscription
import VPN

extension VPNUpsellVisibilityManager {
    enum State: Equatable {
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
    @Published private(set) var state: State = .notEligible

    // MARK: - Dependencies
    private let isFirstLaunch: Bool
    private let isNewUser: Bool
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let defaultBrowserPublisher: AnyPublisher<Bool, Never>
    private let contextualOnboardingPublisher: AnyPublisher<Bool, Never>
    private let featureFlagger: FeatureFlagger
    private let timerDuration: TimeInterval
    private let autoDismissDays: Int
    private var persistor: VPNUpsellUserDefaultsPersisting

    // MARK: - State
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    init(isFirstLaunch: Bool,
         isNewUser: Bool,
         subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         defaultBrowserPublisher: AnyPublisher<Bool, Never>,
         contextualOnboardingPublisher: AnyPublisher<Bool, Never>,
         featureFlagger: FeatureFlagger,
         persistor: VPNUpsellUserDefaultsPersisting = VPNUpsellUserDefaultsPersistor(keyValueStore: UserDefaults.standard),
         timerDuration: TimeInterval = 600,
         autoDismissDays: Int = 7) {
        self.isFirstLaunch = isFirstLaunch
        self.isNewUser = isNewUser
        self.subscriptionManager = subscriptionManager
        self.defaultBrowserPublisher = defaultBrowserPublisher
        self.contextualOnboardingPublisher = contextualOnboardingPublisher
        self.featureFlagger = featureFlagger
        self.timerDuration = timerDuration
        self.autoDismissDays = autoDismissDays
        self.persistor = persistor

        guard isUserEligible, isFeatureOn else {
            return
        }

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

    // MARK: - Monitoring Setup

    private func monitorFirstLaunchConditions() {
        guard state == .notEligible else {
            return
        }

        Publishers.CombineLatest(
            contextualOnboardingPublisher,
            defaultBrowserPublisher
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] onboardingDone, isDefault in
            guard onboardingDone, isDefault else {
                return
            }

            self?.startTimerIfNeeded()
        }
        .store(in: &cancellables)

        updateState(.waitingForConditions)
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

    private func startTimerIfNeeded() {
        guard state == .waitingForConditions else {
            return
        }

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

    private func dismissUpsell() {
        guard state == .visible else {
            return
        }

        persistor.vpnUpsellDismissed = true

        updateState(.dismissed)
    }

    // MARK: - Upsell Visibility

    private func updateState(_ newState: State) {
        guard isFeatureOn, isUserEligible else {
            state = .notEligible
            return
        }

        guard !shouldDismiss else {
            state = .dismissed
            return
        }

        state = newState
    }

    deinit {
        timer?.invalidate()
    }
}

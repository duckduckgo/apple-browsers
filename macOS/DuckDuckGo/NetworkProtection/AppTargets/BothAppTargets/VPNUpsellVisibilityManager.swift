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

/// Manages the visibility and state of VPN upsell messaging based on user onboarding flow.
///
final class VPNUpsellVisibilityManager: ObservableObject {
    @Published private(set) var shouldShowUpsell = false

    // MARK: - Dependencies

    private let isFirstLaunch: Bool
    private let isNewUser: Bool
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let defaultBrowserPublisher: AnyPublisher<Bool, Never>
    private let contextualOnboardingPublisher: AnyPublisher<Bool, Never>
    private let featureFlagger: FeatureFlagger
    private let timerDuration: TimeInterval
    private var persistor: VPNUpsellUserDefaultsPersisting

    // MARK: - State
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var timerCompleted = false

    init(isFirstLaunch: Bool,
         isNewUser: Bool,
         subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         defaultBrowserPublisher: AnyPublisher<Bool, Never>,
         contextualOnboardingPublisher: AnyPublisher<Bool, Never>,
         featureFlagger: FeatureFlagger,
         persistor: VPNUpsellUserDefaultsPersisting = VPNUpsellUserDefaultsPersistor(keyValueStore: UserDefaults.standard),
         timerDuration: TimeInterval = 600) {
        self.isFirstLaunch = isFirstLaunch
        self.isNewUser = isNewUser
        self.subscriptionManager = subscriptionManager
        self.defaultBrowserPublisher = defaultBrowserPublisher
        self.contextualOnboardingPublisher = contextualOnboardingPublisher
        self.featureFlagger = featureFlagger
        self.timerDuration = timerDuration
        self.persistor = persistor

        guard isNewUser && !isUserAuthenticated else {
            return
        }

        guard isFirstLaunch else {
            updateUpsellVisibility(shouldShow: true)
            return
        }

        setupMonitoring()
    }

    // MARK: - Eligibility

    private var isFeatureOn: Bool {
        featureFlagger.isFeatureOn(.vpnToolbarUpsell)
    }

    private var isUserAuthenticated: Bool {
        subscriptionManager.isUserAuthenticated
    }

    private var hasBeenManuallyDismissed: Bool {
        persistor.vpnUpsellDismissed
    }

    // MARK: - Monitoring Setup

    private func setupMonitoring() {
        Publishers.CombineLatest(
            contextualOnboardingPublisher,
            defaultBrowserPublisher
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] onboardingDone, isDefault in
            self?.startTimerIfNeeded(onboardingCompleted: onboardingDone, defaultBrowserSet: isDefault)
        }
        .store(in: &cancellables)

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
        guard isFeatureOn, !isUserAuthenticated, !hasBeenManuallyDismissed else {
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

    private func startTimerIfNeeded(onboardingCompleted: Bool, defaultBrowserSet: Bool) {
        guard onboardingCompleted, defaultBrowserSet, timer == nil, !timerCompleted else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: timerDuration, repeats: false) { [weak self] _ in
            self?.handleTimerCompletion()
        }
    }

    private func handleTimerCompletion() {
        timerCompleted = true
        updateUpsellVisibility(shouldShow: timerCompleted)
    }

    private func handleSubscriptionChange() {
        timer?.invalidate()
        timer = nil
        timerCompleted = false
        updateUpsellVisibility(shouldShow: !isUserAuthenticated)
    }

    private func dismissUpsell() {
        persistor.vpnUpsellDismissed = true
        updateUpsellVisibility(shouldShow: false)
    }

    // MARK: - Upsell Visibility

    private func updateUpsellVisibility(shouldShow: Bool) {
        guard isFeatureOn, !isUserAuthenticated, !hasBeenManuallyDismissed else {
            shouldShowUpsell = false
            return
        }

        shouldShowUpsell = shouldShow
    }

    deinit {
        timer?.invalidate()
    }
}

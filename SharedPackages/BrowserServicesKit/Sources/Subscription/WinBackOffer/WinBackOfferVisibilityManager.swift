//
//  WinBackOfferVisibilityManager.swift
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

import Foundation
import Common

protocol WinBackOfferVisibilityManaging {
    var shouldShowUrgencyMessage: Bool { get }
    var shouldShowLaunchMessage: Bool { get }
    var isOfferAvailable: Bool { get }

    func setLaunchMessagePresented(_ newValue: Bool)
    func setOfferRedeemed(_ newValue: Bool)
}

extension WinBackOfferVisibilityManager {
    enum Constants {
        static let cooldownPeriod = 270 * TimeInterval.day
        static let daysBeforeOfferAvailability = 3 * TimeInterval.day
        static let offerAvailabilityPeriod = 5 * TimeInterval.day
    }
}

final class WinBackOfferVisibilityManager: WinBackOfferVisibilityManaging {
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private var winbackOfferStore: any WinbackOfferStoring
    private var winbackOfferFeatureFlagProvider: any WinBackOfferFeatureFlagProvider

    private var hasActiveSubscription: Bool = false
    private var observer: NSObjectProtocol?

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge, winbackOfferStore: any WinbackOfferStoring, winbackOfferFeatureFlagProvider: any WinBackOfferFeatureFlagProvider) {
        self.subscriptionManager = subscriptionManager
        self.winbackOfferStore = winbackOfferStore
        self.winbackOfferFeatureFlagProvider = winbackOfferFeatureFlagProvider

        observeSubscriptionDidChange()
        checkCachedSubscription()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var shouldShowUrgencyMessage: Bool {
        guard let lastChurnDate = winbackOfferStore.getChurnDate(), isOfferAvailable else {
            // Offer no longer valid
            return false
        }

        let offerStartDate = offerStartDate(churnDate: lastChurnDate)
        // Last day of the offer
        return isLastDayOfOffer(startDate: offerStartDate)
    }

    var shouldShowLaunchMessage: Bool {
        isOfferAvailable && !winbackOfferStore.firstDayModalShown
    }

    var isOfferAvailable: Bool {
        guard isFeatureEnabled,
              !hasActiveSubscription,
              let lastChurnDate = winbackOfferStore.getChurnDate() else {
            return false
        }

        // Offer availability window check
        let offerStartDate = offerStartDate(churnDate: lastChurnDate)
        guard offerStartDate.isInThePast(), Date().timeIntervalSince(offerStartDate) <= Constants.offerAvailabilityPeriod else {
            return false
        }

        return !winbackOfferStore.hasRedeemedOffer()
    }

    private var isFeatureEnabled: Bool {
        winbackOfferFeatureFlagProvider.isWinBackOfferFeatureEnabled
    }

    func setLaunchMessagePresented(_ newValue: Bool) {
        winbackOfferStore.firstDayModalShown = newValue
    }

    func setOfferRedeemed(_ newValue: Bool) {
        winbackOfferStore.setHasRedeemedOffer(newValue)
    }

    private func offerStartDate(churnDate: Date) -> Date {
        return churnDate.addingTimeInterval(Constants.daysBeforeOfferAvailability)
    }

    private func isLastDayOfOffer(startDate: Date) -> Bool {
        return Date().timeIntervalSince(startDate) >= Constants.offerAvailabilityPeriod - 1 * TimeInterval.day
    }

    private func checkCachedSubscription() {
        guard isFeatureEnabled else { return }
        Task {
            guard let currentSubscription = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst) else {
                return
            }

            hasActiveSubscription = currentSubscription.status.isActive

            storeChurnDateIfNeeded(newStatus: currentSubscription.status)
        }
    }

    private func observeSubscriptionDidChange() {
        guard isFeatureEnabled else { return }

        observer = NotificationCenter.default.addObserver(forName: .subscriptionDidChange, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            let previousSubscription = notification.userInfo?[UserDefaultsCacheKey.previousSubscription] as? DuckDuckGoSubscription
            let newSubscription = notification.userInfo?[UserDefaultsCacheKey.subscription] as? DuckDuckGoSubscription

            guard let previousSubscription, let newSubscription, previousSubscription.status != newSubscription.status else { return }

            hasActiveSubscription = newSubscription.status.isActive

            storeChurnDateIfNeeded(newStatus: newSubscription.status)
        }
    }

    private func storeChurnDateIfNeeded(newStatus: DuckDuckGoSubscription.Status) {
        guard newStatus == .expired else {
            return
        }

        guard let lastStoredChurnDate = winbackOfferStore.getChurnDate() else {
            // No stored churn date, mark churn.
            resetOffer()
            return
        }

        // User churned in the past, and now they churned again.
        guard Date().timeIntervalSince(lastStoredChurnDate) > Constants.cooldownPeriod else {
            // Still within the cooldown period, no-op.
            return
        }

        // Cooldown period has passed, mark churn.
        resetOffer()
    }

    private func resetOffer() {
        winbackOfferStore.storeChurnDate(Date())
        winbackOfferStore.setHasRedeemedOffer(false)
        winbackOfferStore.firstDayModalShown = false
    }
}

// MARK: - Helpers

extension DuckDuckGoSubscription.Status {
    var isActive: Bool {
        switch self {
        case .autoRenewable, .gracePeriod, .notAutoRenewable:
            return true
        default:
            return false
        }
    }
}

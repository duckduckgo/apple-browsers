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

/// Manages the visibility of the win-back offer.
public protocol WinBackOfferVisibilityManaging {
    /// Whether the urgency message should be shown.
    /// 
    /// The urgency message is shown on the last day of the offer.
    var shouldShowUrgencyMessage: Bool { get }
    /// Whether the launch message should be shown.
    /// 
    /// The launch message is shown on the first launch, once the offer is available.
    var shouldShowLaunchMessage: Bool { get }
    /// Whether the offer is available.
    /// 
    /// Availability depends on feature flag, subscription status, and churn date.
    var isOfferAvailable: Bool { get }
    /// Whether the urgency message has been dismissed.
    /// 
    /// Use this to update the storage when the urgency message is dismissed.
    var didDismissUrgencyMessage: Bool { get set }
    /// Mark the launch message as presented.
    /// 
    /// Use this to update the storage when the launch message is presented.
    func setLaunchMessagePresented(_ newValue: Bool)
    /// Mark the offer as redeemed.
    /// 
    /// Use this to update the storage when the offer is redeemed.
    func setOfferRedeemed(_ newValue: Bool)
}

extension WinBackOfferVisibilityManager {
    enum Constants {
        // After redeeming the offer and churning again, the offer will be available again after 270 days
        static let cooldownPeriod = 270 * TimeInterval.day
        // Offer will be available for 5 days
        static let offerAvailabilityPeriod = 5 * TimeInterval.day
    }
}

/// Default implementation of the WinBackOfferVisibilityManaging protocol.
public final class WinBackOfferVisibilityManager: WinBackOfferVisibilityManaging {
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private var winbackOfferStore: any WinbackOfferStoring
    private var winbackOfferFeatureFlagProvider: any WinBackOfferFeatureFlagProvider
    private let calendar: Calendar
    private let dateProvider: () -> Date
    // The amount of time to wait before user is eligible after initial churn
    private let timeBeforeOfferAvailability: TimeInterval

    private var hasActiveSubscription: Bool = false
    private var observer: NSObjectProtocol?

    public init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
                winbackOfferStore: any WinbackOfferStoring,
                winbackOfferFeatureFlagProvider: any WinBackOfferFeatureFlagProvider,
                calendar: Calendar = Calendar.current,
                dateProvider: @escaping () -> Date = Date.init,
                timeBeforeOfferAvailability: TimeInterval = 3 * TimeInterval.day) {
        self.subscriptionManager = subscriptionManager
        self.winbackOfferStore = winbackOfferStore
        self.winbackOfferFeatureFlagProvider = winbackOfferFeatureFlagProvider
        self.calendar = calendar
        self.dateProvider = dateProvider
        self.timeBeforeOfferAvailability = timeBeforeOfferAvailability

        observeSubscriptionDidChange()
        checkCachedSubscription()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public var shouldShowUrgencyMessage: Bool {
        // Only show if offer was already presented AND it's the last day
        guard let presentationDate = winbackOfferStore.getOfferPresentationDate(),
              isOfferAvailable,
              !didDismissUrgencyMessage else {
            return false
        }

        let now = dateProvider()
        let offerEndDate = presentationDate.addingTimeInterval(Constants.offerAvailabilityPeriod)
        let startOfUrgencyMessaging = calendar.startOfDay(for: offerEndDate.addingTimeInterval(.days(-2)))
        // Show urgency message 2 days before the offer end
        return now >= startOfUrgencyMessaging
    }

    public var shouldShowLaunchMessage: Bool {
        guard isFeatureEnabled,
              winbackOfferStore.getOfferPresentationDate() == nil,
              !hasActiveSubscription,
              let churnDate = winbackOfferStore.getChurnDate(),
              !winbackOfferStore.hasRedeemedOffer() else {
            return false
        }

        let eligibilityDate = churnDate.addingTimeInterval(timeBeforeOfferAvailability)
        return dateProvider() >= eligibilityDate
    }

    public var isOfferAvailable: Bool {
        guard isFeatureEnabled, !hasActiveSubscription else {
            return false
        }

        // Check if already redeemed
        guard !winbackOfferStore.hasRedeemedOffer() else {
            return false
        }

        guard let presentationDate = winbackOfferStore.getOfferPresentationDate() else {
            return false

        }

        // Offer window is active, check if within 5-day window
        let now = dateProvider()
        return now.timeIntervalSince(presentationDate) <= Constants.offerAvailabilityPeriod
    }

    public var didDismissUrgencyMessage: Bool {
        get { winbackOfferStore.didDismissUrgencyMessage }
        set { winbackOfferStore.didDismissUrgencyMessage = newValue }
    }

    private var isFeatureEnabled: Bool {
        winbackOfferFeatureFlagProvider.isWinBackOfferFeatureEnabled
    }

    public func setLaunchMessagePresented(_ newValue: Bool) {
        if newValue && winbackOfferStore.getOfferPresentationDate() == nil {
            // Record presentation timestamp
            winbackOfferStore.storeOfferPresentationDate(dateProvider())
        } else if !newValue {
            // Clear presentation
            winbackOfferStore.storeOfferPresentationDate(nil)
        }
    }

    public func setOfferRedeemed(_ newValue: Bool) {
        winbackOfferStore.setHasRedeemedOffer(newValue)
    }

    private func offerStartDate(churnDate: Date) -> Date {
        return churnDate.addingTimeInterval(timeBeforeOfferAvailability)
    }

    private func isLastDayOfOffer(startDate: Date) -> Bool {
        let now = dateProvider()
        return now.timeIntervalSince(startDate) >= Constants.offerAvailabilityPeriod - 1 * TimeInterval.day
    }

    private func checkCachedSubscription() {
        guard isFeatureEnabled else { return }
        Task {
            guard let currentSubscription = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst) else {
                return
            }

            hasActiveSubscription = currentSubscription.status.isActive

            storeChurnDateIfNeeded(subscription: currentSubscription)
        }
    }

    private func observeSubscriptionDidChange() {
        guard isFeatureEnabled else { return }

        observer = NotificationCenter.default.addObserver(forName: .subscriptionDidChange, object: nil, queue: .main) { [weak self] notification in
            guard let self, let newSubscription = notification.userInfo?[UserDefaultsCacheKey.subscription] as? DuckDuckGoSubscription else { return }

            let wasActive = hasActiveSubscription
            let isNowActive = newSubscription.status.isActive

            switch (wasActive, isNowActive) {
            case (false, true) where isOfferAvailable:
                // User subscribed during the win-back offer
                completeOfferRedemption()
            case (false, true):
                // User subscribed regardless of the win-back offer
                winbackOfferStore.storeOfferPresentationDate(nil)
                winbackOfferStore.didDismissUrgencyMessage = false
            default:
                break
            }

            hasActiveSubscription = isNowActive

            storeChurnDateIfNeeded(subscription: newSubscription)
        }
    }

    private func storeChurnDateIfNeeded(subscription: DuckDuckGoSubscription) {
        guard subscription.status == .expired else {
            return
        }

        let expiryDate = subscription.expiresOrRenewsAt

        guard let lastStoredChurnDate = winbackOfferStore.getChurnDate() else {
            // No stored churn date, mark churn.
            resetOffer(using: expiryDate)
            return
        }

        let now = dateProvider()
        let timeSinceLastChurn = now.timeIntervalSince(lastStoredChurnDate)
        let cooldownHasPassed = timeSinceLastChurn > Constants.cooldownPeriod

        if cooldownHasPassed {
            // Cooldown period has passed, mark churn.
            resetOffer(using: expiryDate)
            return
        }

        // Mark new churn date if previous offer was redeemed.
        if winbackOfferStore.hasRedeemedOffer() {
            winbackOfferStore.storeChurnDate(expiryDate)
        }
    }

    private func completeOfferRedemption() {
        setOfferRedeemed(true)
        winbackOfferStore.storeOfferPresentationDate(nil)
        didDismissUrgencyMessage = false
    }

    private func resetOffer(using churnDate: Date) {
        winbackOfferStore.storeChurnDate(churnDate)
        winbackOfferStore.setHasRedeemedOffer(false)
        winbackOfferStore.storeOfferPresentationDate(nil)
        didDismissUrgencyMessage = false
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

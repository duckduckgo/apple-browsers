//
//  SubscriptionPromoViewModel.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import FeatureFlags
import Foundation
import Persistence
import PixelKit
import PrivacyConfig
import Subscription

protocol SubscriptionPromoPersisting {
    var fireTabVisitCount: Int { get set }
    var promoDismissedDate: Date? { get set }
    var promoActioned: Bool { get set }
    var promoDisplayCount: Int { get set }
    var promoDisplayWindowStart: Date? { get set }
}

struct SubscriptionPromoUserDefaultsPersistor: SubscriptionPromoPersisting {

    enum Key: String {
        case fireTabVisitCount = "subscription-promo.fire-tab-visit-count"
        case promoDismissedDate = "subscription-promo.dismissed-date"
        case promoActioned = "subscription-promo.actioned"
        case promoDisplayCount = "subscription-promo.display-count"
        case promoDisplayWindowStart = "subscription-promo.display-window-start"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var fireTabVisitCount: Int {
        get { keyValueStore.object(forKey: Key.fireTabVisitCount.rawValue) as? Int ?? 0 }
        set { keyValueStore.set(newValue, forKey: Key.fireTabVisitCount.rawValue) }
    }

    var promoDismissedDate: Date? {
        get { keyValueStore.object(forKey: Key.promoDismissedDate.rawValue) as? Date }
        set {
            if let value = newValue {
                keyValueStore.set(value, forKey: Key.promoDismissedDate.rawValue)
            } else {
                keyValueStore.removeObject(forKey: Key.promoDismissedDate.rawValue)
            }
        }
    }

    var promoActioned: Bool {
        get { keyValueStore.object(forKey: Key.promoActioned.rawValue) as? Bool ?? false }
        set { keyValueStore.set(newValue, forKey: Key.promoActioned.rawValue) }
    }

    var promoDisplayCount: Int {
        get { keyValueStore.object(forKey: Key.promoDisplayCount.rawValue) as? Int ?? 0 }
        set { keyValueStore.set(newValue, forKey: Key.promoDisplayCount.rawValue) }
    }

    var promoDisplayWindowStart: Date? {
        get { keyValueStore.object(forKey: Key.promoDisplayWindowStart.rawValue) as? Date }
        set {
            if let value = newValue {
                keyValueStore.set(value, forKey: Key.promoDisplayWindowStart.rawValue)
            } else {
                keyValueStore.removeObject(forKey: Key.promoDisplayWindowStart.rawValue)
            }
        }
    }
}

@MainActor
final class SubscriptionPromoViewModel: ObservableObject {

    static let requiredVisitCount = 3
    private static let dismissCooldownDays = 28
    static let maxDisplaysPerTimeWindow = 4
    private static let displayWindowDays = 28

    private let subscriptionManager: any SubscriptionManager
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private var persistor: SubscriptionPromoPersisting
    private let locale: Locale
    @Published private(set) var shouldShowPromo: Bool = false
    @Published private(set) var isEligibleForFreeTrial: Bool = false

    var onButtonAction: (() -> Void)?
    var onDismissAction: (() -> Void)?

    init(subscriptionManager: any SubscriptionManager,
         featureFlagger: FeatureFlagger,
         pixelFiring: PixelFiring? = PixelKit.shared,
         persistor: SubscriptionPromoPersisting? = nil,
         locale: Locale = .current) {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.persistor = persistor ?? SubscriptionPromoUserDefaultsPersistor(keyValueStore: UserDefaults.standard)
        self.locale = locale
    }

    func restoreState(shouldShowPromo: Bool) {
        self.shouldShowPromo = shouldShowPromo
    }

    func dismiss() {
        pixelFiring?.fire(SubscriptionPromoPixel.promoDismissed(isEligibleForFreeTrial: isEligibleForFreeTrial))
        persistor.promoDismissedDate = Date()
        shouldShowPromo = false
        onDismissAction?()
    }

    func onPromoButtonTapped() {
        pixelFiring?.fire(SubscriptionPromoPixel.promoCtaActioned(isEligibleForFreeTrial: isEligibleForFreeTrial))
        persistor.promoActioned = true
        shouldShowPromo = false
        onButtonAction?()
    }

    /// Display conditions:
    /// - Feature flag enabled (remote releasable)
    /// - Not force-dismissed on this tab (per-tab, lasts for the tab's lifetime)
    /// - US locale only
    /// - Non-subscriber only
    /// - Fire Tab visited >= 3 times
    /// - User has not already actioned (tapped "Try for Free" / "Learn More")
    /// - Not dismissed within the 28-day cooldown
    /// - Not shown more than 4 times in any given 28-day rolling window
    func evaluatePromoVisibility() {
        guard featureFlagger.isFeatureOn(.subscriptionPromoFireWindow) else {
            shouldShowPromo = false
            return
        }

        guard isUSLocale else {
            shouldShowPromo = false
            return
        }

        guard !subscriptionManager.isSubscriptionPresent() else {
            shouldShowPromo = false
            return
        }

        guard persistor.fireTabVisitCount >= Self.requiredVisitCount else {
            shouldShowPromo = false
            return
        }

        guard !persistor.promoActioned else {
            shouldShowPromo = false
            return
        }

        guard !isDismissedWithinCooldown else {
            shouldShowPromo = false
            return
        }

        guard !hasReachedDisplayLimit else {
            shouldShowPromo = false
            return
        }

        isEligibleForFreeTrial = subscriptionManager.isUserEligibleForFreeTrial()
        recordPromoDisplay()
        shouldShowPromo = true

        pixelFiring?.fire(SubscriptionPromoPixel.promoDisplayed(isEligibleForFreeTrial: isEligibleForFreeTrial))
    }

    private var isUSLocale: Bool {
        var regionCode: String?
        if #available(macOS 13, *) {
            regionCode = locale.region?.identifier
        } else {
            regionCode = locale.regionCode
        }
        return (regionCode ?? "US") == "US"
    }

    private var hasReachedDisplayLimit: Bool {
        guard let windowStart = persistor.promoDisplayWindowStart else {
            return false
        }
        let daysSinceWindowStart = Calendar.current.dateComponents([.day], from: windowStart, to: Date()).day ?? 0
        if daysSinceWindowStart >= Self.displayWindowDays {
            return false
        }
        return persistor.promoDisplayCount >= Self.maxDisplaysPerTimeWindow
    }

    private func recordPromoDisplay() {
        if let windowStart = persistor.promoDisplayWindowStart {
            let daysSinceWindowStart = Calendar.current.dateComponents([.day], from: windowStart, to: Date()).day ?? 0
            if daysSinceWindowStart >= Self.displayWindowDays {
                persistor.promoDisplayCount = 0
                persistor.promoDisplayWindowStart = Date()
            }
        } else {
            persistor.promoDisplayWindowStart = Date()
        }
        persistor.promoDisplayCount += 1
    }

    private var isDismissedWithinCooldown: Bool {
        guard let dismissedDate = persistor.promoDismissedDate else {
            return false
        }
        let daysSinceDismissal = Calendar.current.dateComponents([.day], from: dismissedDate, to: Date()).day ?? 0
        return daysSinceDismissal < Self.dismissCooldownDays
    }
}

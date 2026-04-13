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

import Common
import FeatureFlags
import Foundation
import Persistence
import PixelKit
import PrivacyConfig
import Subscription

protocol SubscriptionPromoPersisting {
    var fireTabVisitCount: Int { get set }
    var promoDisplayCount: Int { get set }
    var promoDisplayWindowStart: Date? { get set }
}

struct SubscriptionPromoUserDefaultsPersistor: SubscriptionPromoPersisting {

    enum Key: String {
        case fireTabVisitCount = "subscription-promo.fire-tab-visit-count"
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

enum TabPromoState {
    case notEvaluated
    case evaluated(shouldShowPromo: Bool)
    case dismissed
}

@MainActor
final class SubscriptionPromoViewModel: ObservableObject {

    static let requiredVisitCount = 3
    static let maxDisplaysPerTimeWindow = 4
    private static let displayWindowDays = 28

    private let subscriptionManager: any SubscriptionManager
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private var persistor: SubscriptionPromoPersisting
    private let locale: Locale

    @Published private(set) var shouldShowPromo: Bool = false {
        didSet {
            guard oldValue != shouldShowPromo else { return }
            promoDelegate?.updateVisibility(shouldShowPromo)
        }
    }
    @Published private(set) var isEligibleForFreeTrial: Bool = false

    private weak var promoDelegate: FireWindowSubscriptionPromoDelegate?

    var onButtonAction: (() -> Void)?
    var onPromoEvaluated: ((Bool) -> Void)?
    var onPromoDismissed: (() -> Void)?

    init(subscriptionManager: any SubscriptionManager,
         featureFlagger: FeatureFlagger,
         pixelFiring: PixelFiring? = PixelKit.shared,
         persistor: SubscriptionPromoPersisting? = nil,
         locale: Locale = .current,
         promoDelegate: FireWindowSubscriptionPromoDelegate? = nil) {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.persistor = persistor ?? SubscriptionPromoUserDefaultsPersistor(keyValueStore: UserDefaults.standard)
        self.locale = locale
        self.promoDelegate = promoDelegate
    }

    deinit {
        promoDelegate?.updateVisibility(false)
    }

    func updateForTab(_ state: TabPromoState) {
        switch state {
        case .dismissed:
            shouldShowPromo = false
        case .evaluated(let shouldShow):
            shouldShowPromo = shouldShow
            if shouldShow {
                pixelFiring?.fire(SubscriptionPromoPixel.promoViewed(isEligibleForFreeTrial: isEligibleForFreeTrial))
            }
        case .notEvaluated:
            evaluatePromoVisibility()
        }
    }

    func dismiss() {
        pixelFiring?.fire(SubscriptionPromoPixel.promoDismissed(isEligibleForFreeTrial: isEligibleForFreeTrial))
        shouldShowPromo = false
        onPromoDismissed?()
    }

    func onPromoButtonTapped() {
        pixelFiring?.fire(SubscriptionPromoPixel.promoCtaActioned(isEligibleForFreeTrial: isEligibleForFreeTrial))
        onButtonAction?()
    }

    /// Display conditions:
    /// - Feature flag enabled (remote releasable)
    /// - US locale only
    /// - Non-subscriber only
    /// - Fire Tab visited >= 3 times
    /// - Not shown more than 4 times in any given 28-day rolling window
    /// - 28-day dismiss cooldown is handled by PromoService via `resultWhenHidden`
    private func evaluatePromoVisibility() {
        shouldShowPromo = false
        defer { onPromoEvaluated?(shouldShowPromo) }

        guard featureFlagger.isFeatureOn(.subscriptionPromoFireWindow) else { return }
        guard isUSLocale else { return }
        guard !subscriptionManager.isSubscriptionPresent() else { return }
        guard persistor.fireTabVisitCount >= Self.requiredVisitCount else { return }
        guard !hasReachedDisplayLimit else { return }

        isEligibleForFreeTrial = subscriptionManager.isUserEligibleForFreeTrial()
        recordPromoDisplay()
        shouldShowPromo = true

        pixelFiring?.fire(SubscriptionPromoPixel.promoDisplayed(isEligibleForFreeTrial: isEligibleForFreeTrial))
        pixelFiring?.fire(SubscriptionPromoPixel.promoViewed(isEligibleForFreeTrial: isEligibleForFreeTrial))
    }

    private var isUSLocale: Bool {
        var regionCode: String?
        if #available(macOS 13, *) {
            regionCode = locale.region?.identifier
        } else {
            regionCode = locale.regionCode
        }
        return regionCode == "US"
    }

    private var hasReachedDisplayLimit: Bool {
        guard let windowStart = persistor.promoDisplayWindowStart else {
            return false
        }
        let daysSinceWindowStart = Calendar.current.numberOfDaysBetween(windowStart, and: Date()) ?? 0
        if daysSinceWindowStart >= Self.displayWindowDays {
            return false
        }
        return persistor.promoDisplayCount >= Self.maxDisplaysPerTimeWindow
    }

    private func recordPromoDisplay() {
        if let windowStart = persistor.promoDisplayWindowStart {
            let daysSinceWindowStart = Calendar.current.numberOfDaysBetween(windowStart, and: Date()) ?? 0
            if daysSinceWindowStart >= Self.displayWindowDays {
                persistor.promoDisplayCount = 0
                persistor.promoDisplayWindowStart = Date()
            }
        } else {
            persistor.promoDisplayWindowStart = Date()
        }
        persistor.promoDisplayCount += 1
    }
}

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

import Foundation
import Persistence
import Subscription

protocol SubscriptionPromoPersisting {
    var fireTabVisitCount: Int { get set }
    var promoDismissedDate: Date? { get set }
    var promoActioned: Bool { get set }
}

struct SubscriptionPromoUserDefaultsPersistor: SubscriptionPromoPersisting {

    enum Key: String {
        case fireTabVisitCount = "subscription-promo.fire-tab-visit-count"
        case promoDismissedDate = "subscription-promo.dismissed-date"
        case promoActioned = "subscription-promo.actioned"
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
}

@MainActor
final class SubscriptionPromoViewModel: ObservableObject {

    private static let requiredVisitCount = 3
    private static let dismissCooldownDays = 28

    private let subscriptionManager: any SubscriptionManager
    private var persistor: SubscriptionPromoPersisting
    @Published private(set) var shouldShowPromo: Bool = false
    @Published private(set) var isEligibleForFreeTrial: Bool = false

    var onButtonAction: (() -> Void)?

    init(subscriptionManager: any SubscriptionManager,
         persistor: SubscriptionPromoPersisting? = nil) {
        self.subscriptionManager = subscriptionManager
        self.persistor = persistor ?? SubscriptionPromoUserDefaultsPersistor(keyValueStore: UserDefaults.standard)
    }

    func dismiss() {
        persistor.promoDismissedDate = Date()
        shouldShowPromo = false
    }

    func onPromoButtonTapped() {
        persistor.promoActioned = true
        shouldShowPromo = false
        onButtonAction?()
    }

    func updatePromoVisibility() {
        guard isUSLocale else {
            shouldShowPromo = false
            return
        }

        guard !subscriptionManager.isSubscriptionPresent() else {
            shouldShowPromo = false
            return
        }
        
        print("👀 fire tab visit count \(persistor.fireTabVisitCount)")
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

        isEligibleForFreeTrial = subscriptionManager.isUserEligibleForFreeTrial()
        shouldShowPromo = true
    }

    private var isUSLocale: Bool {
        var regionCode: String?
        if #available(macOS 13, *) {
            regionCode = Locale.current.region?.identifier
        } else {
            regionCode = Locale.current.regionCode
        }
        return (regionCode ?? "US") == "US"
    }

    private var isDismissedWithinCooldown: Bool {
        guard let dismissedDate = persistor.promoDismissedDate else {
            return false
        }
        let daysSinceDismissal = Calendar.current.dateComponents([.day], from: dismissedDate, to: Date()).day ?? 0
        return daysSinceDismissal < Self.dismissCooldownDays
    }
}

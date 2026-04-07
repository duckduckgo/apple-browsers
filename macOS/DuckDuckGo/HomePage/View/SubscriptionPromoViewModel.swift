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
    var fireWindowVisitCount: Int { get set }
    var promoDismissedDate: Date? { get set }
}

struct SubscriptionPromoUserDefaultsPersistor: SubscriptionPromoPersisting {

    enum Key: String {
        case fireWindowVisitCount = "subscription-promo.fire-window-visit-count"
        case promoDismissedDate = "subscription-promo.dismissed-date"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var fireWindowVisitCount: Int {
        get { (try? keyValueStore.object(forKey: Key.fireWindowVisitCount.rawValue) as? Int) ?? 0 }
        set { try? keyValueStore.set(newValue, forKey: Key.fireWindowVisitCount.rawValue) }
    }

    var promoDismissedDate: Date? {
        get { try? keyValueStore.object(forKey: Key.promoDismissedDate.rawValue) as? Date }
        set {
            if let value = newValue {
                try? keyValueStore.set(value, forKey: Key.promoDismissedDate.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.promoDismissedDate.rawValue)
            }
        }
    }
}

@MainActor
final class SubscriptionPromoViewModel: ObservableObject {

    private static let requiredVisitCount = 4
    private static let dismissCooldownDays = 28

    private let subscriptionManager: any SubscriptionManager
    private var persistor: SubscriptionPromoPersisting
    private var hasCountedVisit = false

    @Published private(set) var shouldShowPromo: Bool = false
    @Published private(set) var isEligibleForFreeTrial: Bool = false

    var onButtonAction: (() -> Void)?

    init(subscriptionManager: any SubscriptionManager,
         persistor: SubscriptionPromoPersisting? = nil) {
        self.subscriptionManager = subscriptionManager
        self.persistor = persistor ?? SubscriptionPromoUserDefaultsPersistor(keyValueStore: UserDefaults.standard)
    }

    func onFireWindowAppeared() {
        incrementVisitCountOnce()
        updatePromoVisibility()
    }

    func dismiss() {
        persistor.promoDismissedDate = Date()
        shouldShowPromo = false
    }

    func onPromoButtonTapped() {
        onButtonAction?()
    }

    // MARK: - Private

    private func updatePromoVisibility() {
        guard isUSLocale else {
            shouldShowPromo = false
            return
        }

        guard !subscriptionManager.isSubscriptionPresent() else {
            shouldShowPromo = false
            return
        }

        guard persistor.fireWindowVisitCount >= Self.requiredVisitCount else {
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
        Locale.current.region?.identifier == "US"
    }

    private func incrementVisitCountOnce() {
        guard !hasCountedVisit else { return }
        hasCountedVisit = true
        persistor.fireWindowVisitCount += 1
    }

    private var isDismissedWithinCooldown: Bool {
        guard let dismissedDate = persistor.promoDismissedDate else {
            return false
        }
        let daysSinceDismissal = Calendar.current.dateComponents([.day], from: dismissedDate, to: Date()).day ?? 0
        return daysSinceDismissal < Self.dismissCooldownDays
    }
}

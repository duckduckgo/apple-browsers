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
import Subscription

@MainActor
final class SubscriptionPromoViewModel: ObservableObject {

    enum Keys {
        static let fireWindowVisitCount = "subscriptionPromo.fireWindowVisitCount"
        static let promoDismissedDate = "subscriptionPromo.dismissedDate"
    }

    private static let requiredVisitCount = 4
    private static let dismissCooldownDays = 28

    private let subscriptionManager: any SubscriptionManager
    private let userDefaults: UserDefaults

    @Published private(set) var shouldShowPromo: Bool = false
    @Published private(set) var isEligibleForFreeTrial: Bool = false

    init(subscriptionManager: any SubscriptionManager,
         userDefaults: UserDefaults = .standard) {
        self.subscriptionManager = subscriptionManager
        self.userDefaults = userDefaults
    }

    func onFireWindowAppeared() {
        incrementVisitCount()
        updatePromoVisibility()
    }

    func dismiss() {
        userDefaults.set(Date(), forKey: Keys.promoDismissedDate)
        shouldShowPromo = false
    }

    func onPromoButtonTapped() {
        onButtonAction?()
    }

    var onButtonAction: (() -> Void)?

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

        guard visitCount >= Self.requiredVisitCount else {
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

    private var visitCount: Int {
        userDefaults.integer(forKey: Keys.fireWindowVisitCount)
    }

    private func incrementVisitCount() {
        let current = visitCount
        userDefaults.set(current + 1, forKey: Keys.fireWindowVisitCount)
    }

    private var isDismissedWithinCooldown: Bool {
        guard let dismissedDate = userDefaults.object(forKey: Keys.promoDismissedDate) as? Date else {
            return false
        }
        let daysSinceDismissal = Calendar.current.dateComponents([.day], from: dismissedDate, to: Date()).day ?? 0
        return daysSinceDismissal < Self.dismissCooldownDays
    }
}

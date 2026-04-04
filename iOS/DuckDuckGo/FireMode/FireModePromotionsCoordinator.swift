//
//  FireModePromotionsCoordinator.swift
//  DuckDuckGo
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

import Core
import Foundation
import PrivacyConfig

/// Injectable protocol for coordinating fire mode promotions.
/// Tracks eligibility state and user interactions for promotion surfaces.
protocol FireModePromotionCoordinating {
    func markBurnPerformed()
    func markFireModeVisited()

    var isNTPPromotionEligible: Bool { get }
    func markNTPPromotionShown()
    func markNTPPromotionDismissed()
    func markNTPPromotionEngaged()
}

/// Coordinates fire mode promotion eligibility and state.
final class FireModePromotionsCoordinator: FireModePromotionCoordinating {

    private enum Keys {
        static let hasBurnedTabs = "com.duckduckgo.ios.firePromotion.hasBurnedTabs"
        static let hasVisitedFireMode = "com.duckduckgo.ios.firePromotion.hasVisitedFireMode"
        static let firstSeenDate = "com.duckduckgo.ios.firePromotion.ntp.firstSeenDate"
        static let isDismissed = "com.duckduckgo.ios.firePromotion.ntp.isDismissed"
        static let isEngaged = "com.duckduckgo.ios.firePromotion.ntp.isEngaged"
    }

    static let expirationInterval: TimeInterval = 3 * 24 * 60 * 60

    private let featureFlagger: FeatureFlagger
    private let userDefaults: UserDefaults

    init(featureFlagger: FeatureFlagger,
         userDefaults: UserDefaults = .app) {
        self.featureFlagger = featureFlagger
        self.userDefaults = userDefaults
    }

    // MARK: - State Triggers

    func markBurnPerformed() {
        hasBurnedTabs = true
    }

    func markFireModeVisited() {
        hasVisitedFireMode = true
    }

    // MARK: - NTP Promotion

    /// Shows the promotion when:
    /// - Fire mode feature flag is enabled
    /// - User has burned tabs at least once
    /// - User has NOT visited fire mode themselves
    /// - User has not dismissed or engaged with the promotion
    /// - Promotion has not expired (3 days since first shown)
    var isNTPPromotionEligible: Bool {
        guard featureFlagger.isFeatureOn(for: FeatureFlag.fireMode) else { return false }
        guard hasBurnedTabs else { return false }
        guard !hasVisitedFireMode else { return false }
        guard !isDismissed && !isEngaged else { return false }

        if let firstSeen = firstSeenDate {
            guard Date().timeIntervalSince(firstSeen) < Self.expirationInterval else { return false }
        }

        return true
    }

    func markNTPPromotionShown() {
        if firstSeenDate == nil {
            firstSeenDate = Date()
        }
        // TODO: fire promotion shown pixel
    }

    func markNTPPromotionDismissed() {
        isDismissed = true
        // TODO: fire promotion dismissed pixel
    }

    func markNTPPromotionEngaged() {
        isEngaged = true
        // TODO: fire promotion engaged pixel
    }

    // MARK: - Private

    private var hasBurnedTabs: Bool {
        get { userDefaults.bool(forKey: Keys.hasBurnedTabs) }
        set { userDefaults.set(newValue, forKey: Keys.hasBurnedTabs) }
    }

    private var hasVisitedFireMode: Bool {
        get { userDefaults.bool(forKey: Keys.hasVisitedFireMode) }
        set { userDefaults.set(newValue, forKey: Keys.hasVisitedFireMode) }
    }

    private var firstSeenDate: Date? {
        get { userDefaults.object(forKey: Keys.firstSeenDate) as? Date }
        set { userDefaults.set(newValue, forKey: Keys.firstSeenDate) }
    }

    private var isDismissed: Bool {
        get { userDefaults.bool(forKey: Keys.isDismissed) }
        set { userDefaults.set(newValue, forKey: Keys.isDismissed) }
    }

    private var isEngaged: Bool {
        get { userDefaults.bool(forKey: Keys.isEngaged) }
        set { userDefaults.set(newValue, forKey: Keys.isEngaged) }
    }
}

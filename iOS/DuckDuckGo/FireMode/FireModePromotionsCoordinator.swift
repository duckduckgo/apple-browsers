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

/// Injectable protocol for coordinating fire mode promotions.
/// Tracks eligibility state and user interactions for promotion surfaces.
protocol FireModePromotionCoordinating {
    func markBurnPerformed()
    func markFireModeVisited()

    var isNTPPromotionEligible: Bool { get }
    func markNTPPromotionShown()
    func markNTPPromotionDismissed()
    func markNTPPromotionEngaged()

    var isMenuPromotionEligible: Bool { get }
    func markMenuPromotionShown()
    func markMenuPromotionEngaged()
}

/// Coordinates fire mode promotion eligibility and state.
final class FireModePromotionsCoordinator: FireModePromotionCoordinating {

    private enum Keys {
        static let hasBurnedTabs = "com.duckduckgo.ios.firePromotion.hasBurnedTabs"
        static let hasVisitedFireMode = "com.duckduckgo.ios.firePromotion.hasVisitedFireMode"
        static let firstSeenDate = "com.duckduckgo.ios.firePromotion.ntp.firstSeenDate"
        static let isDismissed = "com.duckduckgo.ios.firePromotion.ntp.isDismissed"
        static let isEngaged = "com.duckduckgo.ios.firePromotion.ntp.isEngaged"
        static let menuPromotionFirstShownDate = "com.duckduckgo.ios.firePromotion.menu.promotionFirstShownDate"
        static let menuPromotionShownCount = "com.duckduckgo.ios.firePromotion.menu.promotionShownCount"
        static let menuPromotionEngaged = "com.duckduckgo.ios.firePromotion.menu.engaged"
    }

    static let ntpExpirationInterval: TimeInterval = 3 * 24 * 60 * 60
    static let menuExpirationInterval: TimeInterval = 14 * 24 * 60 * 60
    static let menuMaxOpenCount = 5

    private let fireModeCapability: FireModeCapable
    private let userDefaults: UserDefaults

    init(fireModeCapability: FireModeCapable,
         userDefaults: UserDefaults = .app) {
        self.fireModeCapability = fireModeCapability
        self.userDefaults = userDefaults
    }

    static func resetState(userDefaults: UserDefaults = .app) {
        let allKeys = [
            Keys.hasBurnedTabs,
            Keys.hasVisitedFireMode,
            Keys.firstSeenDate,
            Keys.isDismissed,
            Keys.isEngaged,
            Keys.menuPromotionFirstShownDate,
            Keys.menuPromotionShownCount,
            Keys.menuPromotionEngaged
        ]
        for key in allKeys {
            userDefaults.removeObject(forKey: key)
        }
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
        guard fireModeCapability.isFireModeEnabled else { return false }
        guard hasBurnedTabs else { return false }
        guard !hasVisitedFireMode else { return false }
        guard !isDismissed && !isEngaged else { return false }

        if let firstSeen = firstSeenDate {
            guard Date().timeIntervalSince(firstSeen) < Self.ntpExpirationInterval else { return false }
        }

        return true
    }

    func markNTPPromotionShown() {
        if firstSeenDate == nil {
            firstSeenDate = Date()
        }
        DailyPixel.fireDailyAndCount(pixel: .fireModeNTPPromotionShown)
    }

    func markNTPPromotionDismissed() {
        isDismissed = true
        Pixel.fire(pixel: .fireModeNTPPromotionDismissed)
    }

    func markNTPPromotionEngaged() {
        isEngaged = true
        Pixel.fire(pixel: .fireModeNTPPromotionEngaged)
    }

    // MARK: - Menu Promotion

    /// Shows the menu promotion when:
    /// - Fire mode feature flag is enabled
    /// - User has NOT visited fire mode themselves
    /// - User has not engaged with the menu promotion
    /// - Promotion has been shown fewer than 5 times
    /// - Promotion has not expired (14 days since first shown)
    var isMenuPromotionEligible: Bool {
        guard fireModeCapability.isFireModeEnabled else { return false }
        guard !hasVisitedFireMode else { return false }
        guard !menuPromotionEngaged else { return false }
        guard menuPromotionShownCount < Self.menuMaxOpenCount else { return false }

        if let firstShown = menuPromotionFirstShownDate {
            guard Date().timeIntervalSince(firstShown) < Self.menuExpirationInterval else { return false }
        }

        return true
    }

    func markMenuPromotionShown() {
        if menuPromotionFirstShownDate == nil {
            menuPromotionFirstShownDate = Date()
        }
        menuPromotionShownCount += 1
        DailyPixel.fireDailyAndCount(pixel: .fireModeMenuPromotionShown)
    }

    func markMenuPromotionEngaged() {
        menuPromotionEngaged = true
        Pixel.fire(pixel: .fireModeMenuPromotionEngaged)
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

    private var menuPromotionFirstShownDate: Date? {
        get { userDefaults.object(forKey: Keys.menuPromotionFirstShownDate) as? Date }
        set { userDefaults.set(newValue, forKey: Keys.menuPromotionFirstShownDate) }
    }

    private var menuPromotionShownCount: Int {
        get { userDefaults.integer(forKey: Keys.menuPromotionShownCount) }
        set { userDefaults.set(newValue, forKey: Keys.menuPromotionShownCount) }
    }

    private var menuPromotionEngaged: Bool {
        get { userDefaults.bool(forKey: Keys.menuPromotionEngaged) }
        set { userDefaults.set(newValue, forKey: Keys.menuPromotionEngaged) }
    }
}

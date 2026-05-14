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
import Persistence
import TipKit

/// Key namespace for fire mode promotion storage (typed storage, no dotted keys).
enum FireModePromotionStorageKeys: String, StorageKeyDescribing {
    case hasBurnedTabs = "fire-promotion-has-burned-tabs"
    case hasVisitedFireMode = "fire-promotion-has-visited-fire-mode"
    case ntpFirstSeenDate = "fire-promotion-ntp-first-seen-date"
    case ntpDismissed = "fire-promotion-ntp-dismissed"
    case ntpEngaged = "fire-promotion-ntp-engaged"
    case menuFirstShownDate = "fire-promotion-menu-first-shown-date"
    case menuShownCount = "fire-promotion-menu-shown-count"
    case menuEngaged = "fire-promotion-menu-engaged"
    case tabSwitcherTipFirstSeenDate = "fire-promotion-tab-switcher-tip-first-seen-date"
}

/// StoringKeys for fire mode promotion state.
struct FireModePromotionKeys: StoringKeys {
    let hasBurnedTabs = StorageKey<Bool>(FireModePromotionStorageKeys.hasBurnedTabs)
    let hasVisitedFireMode = StorageKey<Bool>(FireModePromotionStorageKeys.hasVisitedFireMode)
    let ntpFirstSeenDate = StorageKey<Date>(FireModePromotionStorageKeys.ntpFirstSeenDate)
    let ntpDismissed = StorageKey<Bool>(FireModePromotionStorageKeys.ntpDismissed)
    let ntpEngaged = StorageKey<Bool>(FireModePromotionStorageKeys.ntpEngaged)
    let menuFirstShownDate = StorageKey<Date>(FireModePromotionStorageKeys.menuFirstShownDate)
    let menuShownCount = StorageKey<Int>(FireModePromotionStorageKeys.menuShownCount)
    let menuEngaged = StorageKey<Bool>(FireModePromotionStorageKeys.menuEngaged)
    let tabSwitcherTipFirstSeenDate = StorageKey<Date>(FireModePromotionStorageKeys.tabSwitcherTipFirstSeenDate)
}

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

    var isTabSwitcherTipExpired: Bool { get }
    func markTabSwitcherTipShown()
}

/// Coordinates fire mode promotion eligibility and state.
final class FireModePromotionsCoordinator: FireModePromotionCoordinating {

    static let ntpExpirationInterval: TimeInterval = 3 * 24 * 60 * 60
    static let menuExpirationInterval: TimeInterval = 14 * 24 * 60 * 60
    static let menuMaxOpenCount = 5
    static let tabSwitcherTipExpirationInterval: TimeInterval = 3 * 24 * 60 * 60

    private let fireModeCapability: FireModeCapable
    private let storage: any KeyedStoring<FireModePromotionKeys>

    /// When `storage` is nil, defaults to `UserDefaults.app.keyedStoring()`.
    init(fireModeCapability: FireModeCapable,
         storage: (any KeyedStoring<FireModePromotionKeys>) = UserDefaults.app.keyedStoring()) {
        self.fireModeCapability = fireModeCapability
        self.storage = storage
    }

    /// When `storage` is nil, defaults to `UserDefaults.app.keyedStoring()`.
    static func resetState() {
        let storage = UserDefaults.app.keyedStoring() as any KeyedStoring<FireModePromotionKeys>
        storage.removeValue(for: \.hasBurnedTabs)
        storage.removeValue(for: \.hasVisitedFireMode)
        storage.removeValue(for: \.ntpFirstSeenDate)
        storage.removeValue(for: \.ntpDismissed)
        storage.removeValue(for: \.ntpEngaged)
        storage.removeValue(for: \.menuFirstShownDate)
        storage.removeValue(for: \.menuShownCount)
        storage.removeValue(for: \.menuEngaged)
        storage.removeValue(for: \.tabSwitcherTipFirstSeenDate)
    }

    // MARK: - State Triggers

    func markBurnPerformed() {
        hasBurnedTabs = true
    }

    func markFireModeVisited() {
        hasVisitedFireMode = true
        if #available(iOS 17.0, *) {
            FireTabsTip.hasVisitedFireMode = true
        }
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

    /// Menu promotion is always disabled for now
    /// Code is left in case we want to use it in the future. Should be removed around 1 month after fire mode is released.
    var isMenuPromotionEligible: Bool {
        return false
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

    // MARK: - Tab Switcher Tip

    /// The 3-day expiration is tracked here; view count and X-button dismissal
    /// are handled by TipKit's `maxDisplayCount` and native invalidation.
    var isTabSwitcherTipExpired: Bool {
        guard let firstSeen = tabSwitcherTipFirstSeenDate else { return false }
        return Date().timeIntervalSince(firstSeen) >= Self.tabSwitcherTipExpirationInterval
    }

    func markTabSwitcherTipShown() {
        if tabSwitcherTipFirstSeenDate == nil {
            tabSwitcherTipFirstSeenDate = Date()
        }
    }

    // MARK: - Private

    private var hasBurnedTabs: Bool {
        get { storage.hasBurnedTabs ?? false }
        set { storage.hasBurnedTabs = newValue }
    }

    private var hasVisitedFireMode: Bool {
        get { storage.hasVisitedFireMode ?? false }
        set { storage.hasVisitedFireMode = newValue }
    }

    private var firstSeenDate: Date? {
        get { storage.ntpFirstSeenDate }
        set { storage.ntpFirstSeenDate = newValue }
    }

    private var isDismissed: Bool {
        get { storage.ntpDismissed ?? false }
        set { storage.ntpDismissed = newValue }
    }

    private var isEngaged: Bool {
        get { storage.ntpEngaged ?? false }
        set { storage.ntpEngaged = newValue }
    }

    private var menuPromotionFirstShownDate: Date? {
        get { storage.menuFirstShownDate }
        set { storage.menuFirstShownDate = newValue }
    }

    private var menuPromotionShownCount: Int {
        get { storage.menuShownCount ?? 0 }
        set { storage.menuShownCount = newValue }
    }

    private var menuPromotionEngaged: Bool {
        get { storage.menuEngaged ?? false }
        set { storage.menuEngaged = newValue }
    }

    private var tabSwitcherTipFirstSeenDate: Date? {
        get { storage.tabSwitcherTipFirstSeenDate }
        set { storage.tabSwitcherTipFirstSeenDate = newValue }
    }
}

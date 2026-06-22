//
//  SubscriptionPromoDebugMenu.swift
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

import AppKit
import Common
import FoundationExtensions
import Foundation
import Persistence

final class SubscriptionPromoDebugMenu: NSMenuItem {

    private let debugStore: SubscriptionPromoDebugStore

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = .current
        return formatter
    }()

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public init() {
        self.debugStore = SubscriptionPromoDebugStore(keyValueStore: UserDefaults.standard)
        super.init(title: "Fire Window Subscription Promo", action: nil, keyEquivalent: "")
        self.submenu = makeSubmenu()
    }

    private var persistor: SubscriptionPromoUserDefaultsPersistor {
        SubscriptionPromoUserDefaultsPersistor(keyValueStore: UserDefaults.standard)
    }

    private func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.delegate = self

        let simulatedDateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        simulatedDateItem.tag = 10
        simulatedDateItem.isEnabled = false
        menu.addItem(simulatedDateItem)

        let visitCountItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        visitCountItem.tag = 1
        visitCountItem.isEnabled = false
        menu.addItem(visitCountItem)

        let displayCountItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        displayCountItem.tag = 2
        displayCountItem.isEnabled = false
        menu.addItem(displayCountItem)

        let dismissedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        dismissedItem.tag = 3
        dismissedItem.isEnabled = false
        menu.addItem(dismissedItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Override Today's Date", action: #selector(overrideTodaysDate), target: self))
        menu.addItem(NSMenuItem(title: "Reset Fire Tab Visit Count", action: #selector(resetFireTabVisitCount), target: self))
        menu.addItem(NSMenuItem(title: "Reset Promo Dismissed Date", action: #selector(resetPromoDismissedDate), target: self))
        menu.addItem(NSMenuItem(title: "Reset Promo Display Count", action: #selector(resetPromoDisplayCount), target: self))
        menu.addItem(NSMenuItem(title: "Reset Promo Display Window Start", action: #selector(resetPromoDisplayWindowStart), target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Reset All Promo State", action: #selector(resetAllPromoState), target: self))

        return menu
    }

    @objc func overrideTodaysDate() {
        let alert = NSAlert()
        alert.messageText = "Simulate Today's Date"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let datePicker = NSDatePicker(frame: .init(x: 0, y: 0, width: 200, height: 24))
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonth, .yearMonthDay]
        datePicker.dateValue = debugStore.simulatedTodayDate
        alert.accessoryView = datePicker

        let response = alert.runModal()

        guard case .alertFirstButtonReturn = response else { return }

        let selectedDate = datePicker.dateValue
        debugStore.simulatedTodayDate = selectedDate.addingTimeInterval(TimeInterval.hours(1))
    }

    @objc func resetFireTabVisitCount() {
        var p = persistor
        p.fireTabVisitCount = 0
    }

    @objc func resetPromoDismissedDate() {
        var p = persistor
        p.promoDismissedDate = nil
    }

    @objc func resetPromoDisplayCount() {
        var p = persistor
        p.promoDisplayCount = 0
        p.promoDisplayWindowStart = nil
    }

    @objc func resetPromoDisplayWindowStart() {
        var p = persistor
        p.promoDisplayWindowStart = nil
    }

    @objc func resetAllPromoState() {
        var p = persistor
        p.fireTabVisitCount = 0
        p.promoDismissedDate = nil
        p.promoDisplayCount = 0
        p.promoDisplayWindowStart = nil
        debugStore.reset()
    }
}

extension SubscriptionPromoDebugMenu: NSMenuDelegate {

    func menuWillOpen(_ menu: NSMenu) {
        let today = debugStore.simulatedTodayDate
        menu.item(withTag: 10)?.title = "📅 Today's Date: \(Self.dateFormatter.string(from: today))"

        let visitCount = min(persistor.fireTabVisitCount, SubscriptionPromoConstants.requiredVisitCount)
        menu.item(withTag: 1)?.title = "👀 Fire Tab Visit Count: \(visitCount)/\(SubscriptionPromoConstants.requiredVisitCount)"

        let displayCount = persistor.promoDisplayCount
        menu.item(withTag: 2)?.title = "👀 Promo Display Count: \(displayCount)/\(SubscriptionPromoConstants.maxDisplaysPerTimeWindow)"

        let isDismissed = isDismissedWithinCooldown(asOf: today)
        let daysSinceLastDismissed = daysSinceLastDismissed(asOf: today).map { "\($0)" } ?? "N/A"
        menu.item(withTag: 3)?.title = "👀 Dismissed: \(isDismissed) (days since: \(daysSinceLastDismissed))"
    }

    private func daysSinceLastDismissed(asOf date: Date) -> Int? {
        guard let dismissedDate = persistor.promoDismissedDate else {
            return nil
        }
        return Calendar.current.numberOfDaysBetween(dismissedDate, and: date) ?? 0
    }

    private func isDismissedWithinCooldown(asOf date: Date) -> Bool {
        guard let days = daysSinceLastDismissed(asOf: date) else {
            return false
        }
        return days < SubscriptionPromoConstants.dismissCooldownDays
    }
}

// MARK: - Debug Store

final class SubscriptionPromoDebugStore {

    enum Key: String {
        case simulatedTodayDate = "debug.subscription-promo.simulated-today-date"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var simulatedTodayDate: Date {
        get {
            guard let timestamp = keyValueStore.object(forKey: Key.simulatedTodayDate.rawValue) as? TimeInterval else {
                return Date()
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            keyValueStore.set(newValue.timeIntervalSince1970, forKey: Key.simulatedTodayDate.rawValue)
        }
    }

    func reset() {
        keyValueStore.removeObject(forKey: Key.simulatedTodayDate.rawValue)
    }
}

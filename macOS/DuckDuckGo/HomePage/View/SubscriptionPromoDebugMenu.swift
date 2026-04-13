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
import Foundation

final class SubscriptionPromoDebugMenu: NSMenuItem {

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public init() {
        super.init(title: "Fire Window Subscription Promo", action: nil, keyEquivalent: "")
        self.submenu = makeSubmenu()
    }

    private var persistor: SubscriptionPromoUserDefaultsPersistor {
        SubscriptionPromoUserDefaultsPersistor(keyValueStore: UserDefaults.standard)
    }

    private func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.delegate = self

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
        menu.addItem(NSMenuItem(title: "Reset Fire Tab Visit Count", action: #selector(resetFireTabVisitCount), target: self))
        menu.addItem(NSMenuItem(title: "Reset Promo Dismissed Date", action: #selector(resetPromoDismissedDate), target: self))
        menu.addItem(NSMenuItem(title: "Reset Promo Display Count", action: #selector(resetPromoDisplayCount), target: self))
        menu.addItem(NSMenuItem(title: "Reset Promo Display Window Start", action: #selector(resetPromoDisplayWindowStart), target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Reset All Promo State", action: #selector(resetAllPromoState), target: self))

        return menu
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
    }
}

extension SubscriptionPromoDebugMenu: NSMenuDelegate {

    func menuWillOpen(_ menu: NSMenu) {
        let visitCount = min(persistor.fireTabVisitCount, SubscriptionPromoViewModel.requiredVisitCount)
        menu.item(withTag: 1)?.title = "👀 Fire Tab Visit Count: \(visitCount)/\(SubscriptionPromoViewModel.requiredVisitCount)"

        let displayCount = persistor.promoDisplayCount
        menu.item(withTag: 2)?.title = "👀 Promo Display Count: \(displayCount)/\(SubscriptionPromoViewModel.maxDisplaysPerTimeWindow)"

        let isDismissed = isDismissedWithinCooldown
        let daysSinceLastDismissed = daysSinceLastDismissed.map { "\($0)" } ?? "N/A"
        menu.item(withTag: 3)?.title = "👀 Dismissed: \(isDismissed) (days since: \(daysSinceLastDismissed))"

    }

    private var daysSinceLastDismissed: Int? {
        guard let dismissedDate = persistor.promoDismissedDate else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: dismissedDate, to: Date()).day ?? 0
    }

    private var isDismissedWithinCooldown: Bool {
        guard let days = daysSinceLastDismissed else {
            return false
        }
        return days < SubscriptionPromoViewModel.dismissCooldownDays
    }
}

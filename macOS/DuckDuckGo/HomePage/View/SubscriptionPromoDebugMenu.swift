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

    private func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")

        menu.addItem(NSMenuItem(title: "Reset Fire Tab Visit Count", action: #selector(resetFireTabVisitCount), target: self))
        menu.addItem(NSMenuItem(title: "Reset Promo Dismissed Date", action: #selector(resetPromoDismissedDate), target: self))
        menu.addItem(NSMenuItem(title: "Reset Promo Actioned", action: #selector(resetPromoActioned), target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Reset All Promo State", action: #selector(resetAllPromoState), target: self))

        return menu
    }

    @objc func resetFireTabVisitCount() {
        UserDefaults.standard.removeObject(forKey: SubscriptionPromoUserDefaultsPersistor.Key.fireTabVisitCount.rawValue)
    }

    @objc func resetPromoDismissedDate() {
        UserDefaults.standard.removeObject(forKey: SubscriptionPromoUserDefaultsPersistor.Key.promoDismissedDate.rawValue)
    }

    @objc func resetPromoActioned() {
        UserDefaults.standard.removeObject(forKey: SubscriptionPromoUserDefaultsPersistor.Key.promoActioned.rawValue)
    }

    @objc func resetAllPromoState() {
        resetFireTabVisitCount()
        resetPromoDismissedDate()
        resetPromoActioned()
    }
}

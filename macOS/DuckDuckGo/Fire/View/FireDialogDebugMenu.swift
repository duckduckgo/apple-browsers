//
//  FireDialogDebugMenu.swift
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
import Persistence

@MainActor
final class FireDialogDebugMenu: NSMenuItem {

    private var settings: any KeyedStoring<FireDialogViewSettings> {
        UserDefaults.standard.keyedStoring()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public init() {
        super.init(title: "Fire Dialog", action: nil, keyEquivalent: "")
        self.submenu = makeSubmenu()
    }

    private func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.addItem(NSMenuItem(title: "Reset Fire Dialog Settings", action: #selector(resetSettings), target: self))
        return menu
    }

    /// Removes all stored `FireDialogViewSettings` values, so that the dialog opens in its default state.
    ///
    /// Add new `FireDialogViewSettings` keys here.
    @objc private func resetSettings() {
        settings.removeValue(for: \.lastSelectedClearingOption)
        settings.removeValue(for: \.lastIncludeTabsAndWindowsState)
        settings.removeValue(for: \.lastIncludeHistoryState)
        settings.removeValue(for: \.lastIncludeCookiesAndSiteDataState)
        settings.removeValue(for: \.lastIncludeChatHistoryState)
        settings.removeValue(for: \.lastSectionsExpandedState)
    }
}

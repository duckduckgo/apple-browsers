//
//  AppStoreUpdatesDebugMenu.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import AppUpdaterShared
import Common

final class AppStoreUpdatesDebugMenu: NSMenu {
    private let debugSettings = UpdatesDebugSettings()
    private let forceUpdateMenuItem = NSMenuItem(title: "")

    init() {
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Force Update Available", action: #selector(toggleForceUpdate))
                .targetting(self)
            NSMenuItem.separator()
            NSMenuItem(title: "Reset Debug Settings", action: #selector(resetDebugSettings))
                .targetting(self)
            NSMenuItem.separator()
            forceUpdateMenuItem
        }

        updateMenuItemsState()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        updateMenuItemsState()
    }

    @objc private func toggleForceUpdate() {
        debugSettings.forceUpdateAvailable.toggle()
        updateMenuItemsState()
    }

    @objc private func resetDebugSettings() {
        debugSettings.reset()
        updateMenuItemsState()
    }

    private func updateMenuItemsState() {
        let isForced = debugSettings.forceUpdateAvailable
        forceUpdateMenuItem.title = "Force Update: [\(isForced ? "ON" : "OFF")]"
        forceUpdateMenuItem.isEnabled = false // Just for display
    }
}

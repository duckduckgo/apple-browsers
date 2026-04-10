//
//  TabSuspensionDebugMenu.swift
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

final class TabSuspensionDebugMenu: NSMenu, NSMenuDelegate {

    private let useShortIntervalMenuItem = NSMenuItem(
        title: "Use Short Inactive Interval (5s)",
        action: #selector(toggleShortInterval)
    )

    override init(title: String) {
        super.init(title: title)
        self.delegate = self
        buildItems {
            useShortIntervalMenuItem.targetting(self)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func menuNeedsUpdate(_ menu: NSMenu) {
        useShortIntervalMenuItem.state = NSApp.delegateTyped.tabSuspensionService.useShortInactiveInterval ? .on : .off
    }

    @MainActor
    @objc private func toggleShortInterval(_ sender: NSMenuItem) {
        NSApp.delegateTyped.tabSuspensionService.useShortInactiveInterval.toggle()
    }
}

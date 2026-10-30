//
//  MoreProminentUpdatesDebugMenu.swift
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

struct MoreProminentUpdatesDebugSettings: StoringKeys {
    let menuPrompt = StorageKey<String>(.moreProminentUpdatesDebugMenuPrompt)
    let showsAddressBarButton = StorageKey<Bool>(.moreProminentUpdatesDebugShowsAddressBarButton)
}

enum MoreProminentUpdatesMenuPrompt: String {
    case none
    case row
    case card
}

extension KeyedStoring where Keys == MoreProminentUpdatesDebugSettings {

    var menuPromptStyle: MoreProminentUpdatesMenuPrompt {
        get {
            self.menuPrompt.flatMap(MoreProminentUpdatesMenuPrompt.init(rawValue:)) ?? .none
        }
        nonmutating set {
            self.menuPrompt = newValue.rawValue
        }
    }

    var isShowingAddressBarButton: Bool {
        get {
            self.showsAddressBarButton ?? false
        }
        nonmutating set {
            self.showsAddressBarButton = newValue
        }
    }
}

extension Notification.Name {
    static let moreProminentUpdatesDebugSettingsDidChange = Notification.Name("moreProminentUpdatesDebugSettingsDidChange")
}

/// `Debug → Updates → More Prominent Updates` submenu, for previewing the prominent update prompts in place.
final class MoreProminentUpdatesDebugMenu: NSMenu, NSMenuDelegate {

    private let settings: any KeyedStoring<MoreProminentUpdatesDebugSettings>
    private let notificationCenter: NotificationCenter

    private let menuPromptItems: [MoreProminentUpdatesMenuPrompt: NSMenuItem]
    private let addressBarButtonItem = NSMenuItem(title: "Show Address Bar Update Button", action: #selector(toggleAddressBarButton))

    init(settings: any KeyedStoring<MoreProminentUpdatesDebugSettings> = UserDefaults.standard.keyedStoring(),
         notificationCenter: NotificationCenter = .default) {
        self.settings = settings
        self.notificationCenter = notificationCenter
        self.menuPromptItems = [
            .none: NSMenuItem(title: "No Browser Menu Prompt", action: #selector(selectMenuPrompt), representedObject: MoreProminentUpdatesMenuPrompt.none),
            .row: NSMenuItem(title: "Browser Menu Prompt: Row", action: #selector(selectMenuPrompt), representedObject: MoreProminentUpdatesMenuPrompt.row),
            .card: NSMenuItem(title: "Browser Menu Prompt: Card", action: #selector(selectMenuPrompt), representedObject: MoreProminentUpdatesMenuPrompt.card)
        ]
        super.init(title: "")
        delegate = self

        buildItems {
            menuPromptItems[.none]!.targetting(self)
            menuPromptItems[.row]!.targetting(self)
            menuPromptItems[.card]!.targetting(self)
            NSMenuItem.separator()
            addressBarButtonItem.targetting(self)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let selectedPrompt = settings.menuPromptStyle
        for (prompt, item) in menuPromptItems {
            item.state = prompt == selectedPrompt ? .on : .off
        }
        addressBarButtonItem.state = settings.isShowingAddressBarButton ? .on : .off
    }

    @objc private func selectMenuPrompt(_ sender: NSMenuItem) {
        guard let prompt = sender.representedObject as? MoreProminentUpdatesMenuPrompt else { return }
        settings.menuPromptStyle = prompt
        notificationCenter.post(name: .moreProminentUpdatesDebugSettingsDidChange, object: nil)
    }

    @objc private func toggleAddressBarButton(_ sender: NSMenuItem) {
        settings.isShowingAddressBarButton.toggle()
        notificationCenter.post(name: .moreProminentUpdatesDebugSettingsDidChange, object: nil)
    }
}

//
//  PromptBarPreferencesPersistor.swift
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

import Foundation
import Persistence

protocol PromptBarPreferencesPersistor {
    var isKeyboardShortcutEnabled: Bool { get set }
    var keyboardShortcut: PromptBarShortcut { get set }
    var isMenuBarIconVisible: Bool { get set }
}

struct PromptBarPreferencesUserDefaultsPersistor: PromptBarPreferencesPersistor {

    enum Key: String {
        case keyboardShortcutIsEnabled = "prompt-bar.keyboard-shortcut.is-enabled"
        case keyboardShortcut = "prompt-bar.keyboard-shortcut"
        case menuBarIconIsVisible = "prompt-bar.menu-bar-icon.is-visible"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var isKeyboardShortcutEnabled: Bool {
        get { (try? keyValueStore.object(forKey: Key.keyboardShortcutIsEnabled.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.keyboardShortcutIsEnabled.rawValue) }
    }

    var keyboardShortcut: PromptBarShortcut {
        get {
            guard let data = (try? keyValueStore.object(forKey: Key.keyboardShortcut.rawValue)) as? Data,
                  let shortcut = try? JSONDecoder().decode(PromptBarShortcut.self, from: data) else {
                return .defaultShortcut
            }
            return shortcut
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            try? keyValueStore.set(data, forKey: Key.keyboardShortcut.rawValue)
        }
    }

    var isMenuBarIconVisible: Bool {
        get { (try? keyValueStore.object(forKey: Key.menuBarIconIsVisible.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.menuBarIconIsVisible.rawValue) }
    }
}

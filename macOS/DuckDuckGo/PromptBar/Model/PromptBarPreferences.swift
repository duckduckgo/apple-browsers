//
//  PromptBarPreferences.swift
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
import Combine

/// User-facing Prompt Bar preferences. A single instance is shared between the
/// preferences UI and the controllers that act on these values (menu bar icon,
/// global shortcut registration), so all consumers observe the same object.
final class PromptBarPreferences: ObservableObject {

    @Published var isKeyboardShortcutEnabled: Bool {
        didSet { persistor.isKeyboardShortcutEnabled = isKeyboardShortcutEnabled }
    }

    @Published var keyboardShortcut: PromptBarShortcut {
        didSet { persistor.keyboardShortcut = keyboardShortcut }
    }

    @Published var isMenuBarIconVisible: Bool {
        didSet { persistor.isMenuBarIconVisible = isMenuBarIconVisible }
    }

    /// The icon is a shortcut entry point, so it stays hidden while the shortcut
    /// is off. `isMenuBarIconVisible` keeps its stored value so it can be restored.
    var isMenuBarIconEffectivelyVisible: Bool {
        isMenuBarIconVisible && isKeyboardShortcutEnabled
    }

    var isMenuBarIconEffectivelyVisiblePublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest($isMenuBarIconVisible, $isKeyboardShortcutEnabled)
            .map { $0 && $1 }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private var persistor: PromptBarPreferencesPersistor

    init(persistor: PromptBarPreferencesPersistor = PromptBarPreferencesUserDefaultsPersistor(keyValueStore: NSApp.delegateTyped.keyValueStore)) {
        self.persistor = persistor
        isKeyboardShortcutEnabled = persistor.isKeyboardShortcutEnabled
        keyboardShortcut = persistor.keyboardShortcut
        isMenuBarIconVisible = persistor.isMenuBarIconVisible
    }

    func resetKeyboardShortcutToDefault() {
        keyboardShortcut = .defaultShortcut
    }
}

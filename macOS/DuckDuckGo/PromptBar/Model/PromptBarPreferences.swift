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

    /// The icon is a Duck.ai entry point behind the shortcut, so it stays hidden
    /// unless both are on. Stored values are kept so they can be restored.
    var isMenuBarIconEffectivelyVisible: Bool {
        isMenuBarIconVisible && isKeyboardShortcutEnabled && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature
    }

    var isMenuBarIconEffectivelyVisiblePublisher: AnyPublisher<Bool, Never> {
        let aiChatMenuConfiguration = self.aiChatMenuConfiguration
        let aiChatFeatureChanges = aiChatMenuConfiguration.valuesChangedPublisher
            .map { _ in () }
            .prepend(())

        return Publishers.CombineLatest3($isMenuBarIconVisible, $isKeyboardShortcutEnabled, aiChatFeatureChanges)
            .map { isMenuBarIconVisible, isKeyboardShortcutEnabled, _ in
                isMenuBarIconVisible && isKeyboardShortcutEnabled && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// The shortcut opens Duck.ai, so it stays unregistered while Duck.ai is off.
    var isKeyboardShortcutEffectivelyEnabled: Bool {
        isKeyboardShortcutEnabled && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature
    }

    /// `nil` when no shortcut should be registered.
    var effectiveKeyboardShortcutPublisher: AnyPublisher<PromptBarShortcut?, Never> {
        let aiChatMenuConfiguration = self.aiChatMenuConfiguration
        let aiChatFeatureChanges = aiChatMenuConfiguration.valuesChangedPublisher
            .map { _ in () }
            .prepend(())

        return Publishers.CombineLatest3($isKeyboardShortcutEnabled, $keyboardShortcut, aiChatFeatureChanges)
            .map { isEnabled, shortcut, _ -> PromptBarShortcut? in
                guard isEnabled, aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature else { return nil }
                return shortcut
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private var persistor: PromptBarPreferencesPersistor
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable

    init(persistor: PromptBarPreferencesPersistor = PromptBarPreferencesUserDefaultsPersistor(keyValueStore: NSApp.delegateTyped.keyValueStore),
         aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable) {
        self.persistor = persistor
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        isKeyboardShortcutEnabled = persistor.isKeyboardShortcutEnabled
        keyboardShortcut = persistor.keyboardShortcut
        isMenuBarIconVisible = persistor.isMenuBarIconVisible
    }

    func resetKeyboardShortcutToDefault() {
        keyboardShortcut = .defaultShortcut
    }
}

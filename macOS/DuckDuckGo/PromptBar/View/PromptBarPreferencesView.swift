//
//  PromptBarPreferencesView.swift
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

import PreferencesUI_macOS
import SwiftUI

/// The Prompt Bar rows on the AI Features preferences screen: the system-wide
/// keyboard shortcut (with its recorder) and the menu bar icon visibility.
struct PromptBarPreferencesView: View {

    @ObservedObject var preferences: PromptBarPreferences

    var body: some View {
        ToggleMenuItemWithDescription(UserText.promptBarKeyboardShortcutToggle,
                                      UserText.promptBarKeyboardShortcutCaption,
                                      isOn: $preferences.isKeyboardShortcutEnabled,
                                      spacing: 4)
        .accessibilityIdentifier("Preferences.AIChat.promptBarKeyboardShortcutToggle")
        .padding(.top, Const.Spacing.groupedCheckboxesSeparation)

        PromptBarShortcutRecorderView(shortcut: $preferences.keyboardShortcut)
            .disabled(!preferences.isKeyboardShortcutEnabled)
            .padding(.leading, 19)
            .padding(.bottom, 4)

        ToggleMenuItemWithDescription(UserText.promptBarMenuBarIconToggle,
                                      UserText.promptBarMenuBarIconCaption,
                                      isOn: $preferences.isMenuBarIconVisible,
                                      spacing: 4)
        .accessibilityIdentifier("Preferences.AIChat.promptBarMenuBarIconToggle")
        .disabled(!preferences.isKeyboardShortcutEnabled)
        .padding(.leading, 19)
    }
}

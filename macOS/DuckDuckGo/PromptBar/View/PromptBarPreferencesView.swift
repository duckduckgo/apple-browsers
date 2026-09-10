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

import PixelKit
import PreferencesUI_macOS
import SwiftUI

struct PromptBarPreferencesView: View {

    @ObservedObject var preferences: PromptBarPreferences

    var body: some View {
        ToggleMenuItem(UserText.promptBarMenuBarIconToggle,
                       isOn: $preferences.isMenuBarIconVisible)
        .accessibilityIdentifier("Preferences.AIChat.promptBarMenuBarIconToggle")
        .onChange(of: preferences.isMenuBarIconVisible) { isVisible in
            fire(isVisible ? .settingsMenuBarIconTurnedOn : .settingsMenuBarIconTurnedOff)
        }

        ToggleMenuItem(UserText.promptBarKeyboardShortcutToggle,
                       isOn: $preferences.isKeyboardShortcutEnabled)
        .accessibilityIdentifier("Preferences.AIChat.promptBarKeyboardShortcutToggle")
        .onChange(of: preferences.isKeyboardShortcutEnabled) { isEnabled in
            fire(isEnabled ? .settingsShortcutTurnedOn : .settingsShortcutTurnedOff)
        }

        PromptBarShortcutRecorderView(shortcut: $preferences.keyboardShortcut)
            .disabled(!preferences.isKeyboardShortcutEnabled)
            .padding(.leading, 19)
            .padding(.bottom, 4)
            // Covers both recording a new combo and resetting to the default; the combo itself is never sent.
            .onChange(of: preferences.keyboardShortcut) { _ in
                fire(.settingsShortcutChanged)
            }
    }

    private func fire(_ pixel: PromptBarPixel) {
        PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
    }
}

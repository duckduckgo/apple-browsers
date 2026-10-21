//
//  DaxPetPreferencesView.swift
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

struct DaxPetPreferencesView: View {

    @ObservedObject var preferences: DaxPetPreferences

    var body: some View {
        if preferences.isAvailable {
            ToggleMenuItem(UserText.daxPetToggle, isOn: $preferences.isEnabled)
                .accessibilityIdentifier("Preferences.AIChat.daxPetToggle")

            if preferences.isEnabled, DaxPetScreenLooker.isSupported {
                VStack(alignment: .leading, spacing: 2) {
                    ToggleMenuItem(UserText.daxPetScreenToggle, isOn: $preferences.canSeeForegroundApp)
                        .accessibilityIdentifier("Preferences.AIChat.daxPetScreenToggle")
                    TextMenuItemCaption(UserText.daxPetScreenCaption)
                }
                .padding(.leading, 19)
                .onChange(of: preferences.canSeeForegroundApp) { canSee in
                    // macOS asks once; afterwards it's up to System Settings.
                    if canSee { DaxPetScreenLooker.requestPermission() }
                }
            }
        }
    }
}

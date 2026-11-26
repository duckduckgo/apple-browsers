//
//  KeyboardSettingsView.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import SwiftUI
import DesignResourcesKit
import Core

struct KeyboardSettingsView: View {
    // KeyboardSettings keeps its values in UserDefaults, so writing through it leaves a @State copy
    // unchanged and SwiftUI never redraws: the switch animates but its accessibility value goes stale.
    @State private var onNewTab = KeyboardSettings().onNewTab
    @State private var onAppLaunch = KeyboardSettings().onAppLaunch

    var body: some View {
        List {
            Section(header: Text(UserText.settingsKeyboardShowOn)) {
                SettingsCellView(label: UserText.settingsKeyboardNewTab,
                                 accessory: .toggle(isOn: saving($onNewTab, to: \.onNewTab)))
                SettingsCellView(label: UserText.settingsKeyboardAppLaunch,
                                 accessory: .toggle(isOn: saving($onAppLaunch, to: \.onAppLaunch)))
            }
        }
        .applyInsetGroupedListStyle()
        .navigationBarTitle(UserText.settingsKeyboard, displayMode: .inline)
        .accentColor(Color(designSystemColor: .textPrimary))
    }

    private func saving(_ value: Binding<Bool>, to keyPath: WritableKeyPath<KeyboardSettings, Bool>) -> Binding<Bool> {
        Binding {
            value.wrappedValue
        } set: { newValue in
            value.wrappedValue = newValue
            var settings = KeyboardSettings()
            settings[keyPath: keyPath] = newValue
        }
    }
}

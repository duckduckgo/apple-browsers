//
//  SettingsAIChatShortcutsView.swift
//  DuckDuckGo
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

import SwiftUI
import DesignResourcesKit
import Core

struct SettingsAIChatShortcutsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section {
                SettingsCellView(label: UserText.aiChatSettingsEnableBrowsingMenuToggle,
                                 accessory: .toggle(isOn: viewModel.aiChatBrowsingMenuEnabledBinding))

                SettingsCellView(label: UserText.aiChatSettingsEnableAddressBarToggle,
                                 accessory: .toggle(isOn: viewModel.aiChatAddressBarEnabledBinding))

                SettingsCellView(label: UserText.aiChatSettingsEnableVoiceSearchToggle,
                                 accessory: .toggle(isOn: viewModel.aiChatVoiceSearchEnabledBinding))

                SettingsCellView(label: UserText.aiChatSettingsEnableTabSwitcherToggle,
                                 accessory: .toggle(isOn: viewModel.aiChatTabSwitcherEnabledBinding))
            }
        }
        .applySettingsListModifiers(title: UserText.settingsAiChatShortcuts, displayMode: .inline, viewModel: viewModel)
    }
}

//
//  ThreatProtectionView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Core
import SwiftUI
import DesignResourcesKit

struct ThreatProtectionView: View {

    @EnvironmentObject var viewModel: SettingsViewModel

    var description: SettingsDescription {
        SettingsDescription(imageName: "Radar-Check",
                                     title: UserText.threatProtection,
                                     status: .on,
                                     explanation: UserText.threatProtectionCaption)
    }

    var body: some View {
        List {
            SettingsDescriptionView(content: description)
            ThreatProtectionViewSettings(model: MaliciousSiteProtectionSettingsViewModel(manager: viewModel.maliciousSiteProtectionPreferencesManager))
        }
        .applySettingsListModifiers(title: UserText.threatProtection,
                                    displayMode: .inline,
                                    viewModel: viewModel)
    }
}

struct ThreatProtectionViewSettings: View {
    @ObservedObject private var model: MaliciousSiteProtectionSettingsViewModel

    public init(model: MaliciousSiteProtectionSettingsViewModel) {
        self.model = model
    }

    var body: some View {
        // Smarter Encryption
        Section(footer: Text(LocalizedStringKey(UserText.smarterEncryptionDescription))
            .tint(Color(designSystemColor: .accent))) {
                SettingsCellView(label: UserText.smarterEncryptionTitle,
                                 statusIndicator: StatusIndicatorView(status: .alwaysOn, isDotHidden: true))
        }

        // Scam Blocker
        if model.shouldShowMaliciousSiteProtectionSection {
            Section(footer: VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(UserText.scamBlockerToggleLabel))
                    .tint(Color(designSystemColor: .accent))
                if !model.isMaliciousSiteProtectionOn {
                    Text(UserText.scamBlockerToggleCaption)
                        .foregroundColor(.red)
                }
            })
            {
                SettingsCellView(label: UserText.scamBlockerTitle,
                                 accessory: .toggle(isOn: $model.isMaliciousSiteProtectionOn))
            }
        }
    }
}

//
//  CookiePopUpProtectionView.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import WebExtensions

struct CookiePopUpProtectionView: View {

    @EnvironmentObject var viewModel: SettingsViewModel

    var description: SettingsDescription {
        SettingsDescription(imageName: "SettingsCookiePopUpProtectionContent",
                                     title: UserText.cookiePopUpProtection,
                                     status: viewModel.cookiePopUpProtectionStatus,
                                     explanation: UserText.cookiePopUpProtectionExplanation)
    }

    var body: some View {
        List {
            SettingsDescriptionView(content: description)
            CookiePopUpProtectionViewSettings()
        }
        .applySettingsListModifiers(title: UserText.cookiePopUpProtection,
                                    displayMode: .inline,
                                    viewModel: viewModel)
        .onForwardNavigationAppear {
            if viewModel.isCookiePopupPreferenceSettingEnabled {
                Pixel.fire(pixel: .autoconsentSettingsShown)
            } else {
                Pixel.fire(pixel: .settingsAutoconsentShown)
            }
        }
    }
}

struct CookiePopUpProtectionViewSettings: View {

    @EnvironmentObject var viewModel: SettingsViewModel

    private var isAutoManageEnabled: Bool {
        viewModel.autoManageCookiePopupsBinding.wrappedValue
    }

    var body: some View {
        if viewModel.isCookiePopupPreferenceSettingEnabled {
            Section(footer: Text(UserText.autoManageCookiePopupsExplanation)) {
                SettingsCellView(label: UserText.autoManageCookiePopupsTitle,
                                 accessory: .toggle(isOn: viewModel.autoManageCookiePopupsBinding))
            }

            if isAutoManageEnabled {
                Section(footer: Text(UserText.popUpsWithoutOptOutsExplanation)) {
                    SettingsCellView(label: UserText.popUpsWithoutOptOutsTitle,
                                     accessory: .toggle(isOn: viewModel.popUpsWithoutOptOutsBinding))
                }
            }
        } else {
            Section {
                SettingsCellView(label: UserText.letDuckDuckGoManageCookieConsentPopups,
                                 accessory: .toggle(isOn: viewModel.autoconsentBinding))
            }
        }
    }
}

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
            Pixel.fire(pixel: .settingsAutoconsentShown)
        }
    }
}

struct CookiePopUpProtectionViewSettings: View {

    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        if viewModel.featureFlagger.isFeatureOn(.cookiePopupPreferenceSetting) {
            Section(footer: Text(LocalizedStringKey(UserText.cookiePopupPreferenceExplanation))) {
                SettingsPickerCellView(label: UserText.cookiePopupPreferenceTitle,
                                       options: CookiePopupPreference.allCases,
                                       selectedOption: viewModel.cookiePopupPreferenceBinding)
            }
        } else {
            Section {
                SettingsCellView(label: UserText.letDuckDuckGoManageCookieConsentPopups,
                                 accessory: .toggle(isOn: viewModel.autoconsentBinding))
            }
        }
    }
}

extension CookiePopupPreference: CustomStringConvertible {
    public var description: String {
        switch self {
        case .max:
            return UserText.cookiePopupPreferenceBlockAll
        case .default:
            return UserText.cookiePopupPreferenceBlockStandard
        case .off:
            return UserText.cookiePopupPreferenceDoNotBlock
        }
    }
}

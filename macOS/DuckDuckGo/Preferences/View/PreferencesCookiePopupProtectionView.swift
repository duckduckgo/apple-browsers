//
//  PreferencesCookiePopupProtectionView.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import FeatureFlags
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions
import WebExtensions

extension Preferences {

    struct CookiePopupProtectionView: View {
        @ObservedObject var model: CookiePopupProtectionPreferences

        private let featureFlagger = NSApp.delegateTyped.featureFlagger

        private var isCookiePopupPreferenceSettingEnabled: Bool {
            featureFlagger.isFeatureOn(.cookiePopupPreferenceSetting)
        }

        var body: some View {
            PreferencePane(UserText.cookiePopUpProtection, spacing: 4) {

                // SECTION 1: Status Indicator
                PreferencePaneSection {
                    StatusIndicatorView(status: model.isAutoconsentEnabled ? .on : .off, isLarge: true)
                }

                // SECTION 2: Description
                PreferencePaneSection {
                    VStack(alignment: .leading, spacing: 1) {
                        TextMenuItemCaption(UserText.autoconsentExplanation)
                        TextButton(UserText.learnMore) {
                            model.openNewTab(with: .cookieConsentPopUpManagement)
                        }
                    }
                }

                // SECTION 3: Cookie Pop-up Preference
                PreferencePaneSection {
                    if isCookiePopupPreferenceSettingEnabled {
                        Picker(UserText.cookiePopupPreferenceTitle, selection: $model.cookiePopupPreference) {
                            ForEach(CookiePopupPreference.allCases, id: \.self) { preference in
                                Text(preference.displayName).tag(preference)
                            }
                        }
                        TextMenuItemCaption(UserText.cookiePopupPreferenceExplanation)
                    } else {
                        ToggleMenuItem(UserText.autoconsentCheckboxTitle, isOn: $model.isAutoconsentEnabled)
                    }
                }
            }
        }
    }
}

private extension CookiePopupPreference {
    var displayName: String {
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

//
//  PreferencesThreatProtectionView.swift
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

import Foundation
import SwiftUICore
import PreferencesUI_macOS
import SwiftUIExtensions
import PixelKit
import MaliciousSiteProtection

extension Preferences {

    struct ThreatProtectionView: View {
        @ObservedObject var model: MaliciousSiteProtectionPreferences

        var body: some View {

            // SECTION 1: Scam Blocker
            if model.isFeatureOn {
                PreferencePane(UserText.scamBlockerTitle) {
                    
                    // SECTION 1.1 Scam Blocker Toggle
                    PreferencePaneSection {
                        ToggleMenuItem(UserText.scamBlockerToggleLabel,
                                       isOn: $model.isEnabled)
                        VStack(alignment: .leading, spacing: 1) {
                            TextMenuItemCaption(UserText.scamBlockerToggleCaption)
                            TextButton(UserText.learnMore) {
                                model.openNewTab(with: .maliciousSiteProtectionLearnMore)
                            }
                        }.padding(.leading, 19)
                    }
                }
            }

            // SECTION 2: Smarter Encryption
            PreferencePane(UserText.smarterEncryptionTitle, spacing: 4) {

                // SECTION 2.1 Smarter Encryption Status Indicator
                PreferencePaneSection {
                    StatusIndicatorView(status: .alwaysOn, isLarge: true)
                }

                // SECTION 2.2 Smarter Encryption Description
                PreferencePaneSection {
                    VStack(alignment: .leading, spacing: 1) {
                        TextMenuItemCaption(UserText.smarterEncryptionDescription)
                        TextButton(UserText.learnMore) {
                            model.openNewTab(with: .smarterEncryptionLearnMore)
                        }
                    }
                }

            }
        }
    }
}

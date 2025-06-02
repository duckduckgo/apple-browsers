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

            PreferencePane(UserText.threatProtection, spacing: 4) {
                // SECTION 1: Status Indicator
                PreferencePaneSection {
                    StatusIndicatorView(status: .on, isLarge: true)
                }

                // SECTION 2: Threat Protection Caption
                PreferencePaneSection {
                    VStack(alignment: .leading, spacing: 0) {
                        TextMenuItemCaption(UserText.threatProtectionCaption)
                        TextButton(UserText.learnMore) {
                            model.openNewTab(with: .threatProtectionLearnMore)
                        }
                    }
                }

                // SECTION 3: Smarter Encryption
                PreferencePaneSection {
                    VStack(alignment: .leading, spacing: 0) {
                        TextMenuItemHeader(UserText.smarterEncryptionTitle)
                        TextMenuItemCaption(UserText.statusIndicatorAlwaysOn)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        TextMenuItemCaption(UserText.smarterEncryptionDescription)
                        TextButton(UserText.learnMore) {
                            model.openNewTab(with: .smarterEncryptionLearnMore)
                        }
                    }
                }

                // SECTION 4: Scam Blocker
                PreferencePaneSection {
                    TextMenuItemHeader(UserText.scamBlockerTitle)
                    VStack(alignment: .leading, spacing: 1) {
                        ToggleMenuItem(UserText.scamBlockerToggleLabel,
                                       isOn: $model.isEnabled)
                        VStack(alignment: .leading, spacing: 1) {
                            TextButton(UserText.learnMore) {
                                model.openNewTab(with: .maliciousSiteProtectionLearnMore)
                            }
                            Text(UserText.maliciousDetectionEnabledWarning)
                                .opacity(model.isEnabled ? 0 : 1)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }.padding(.leading, 19)
                    }
                }
            }
        }
    }
}

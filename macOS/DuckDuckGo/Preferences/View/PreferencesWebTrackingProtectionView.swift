//
//  PreferencesWebTrackingProtectionView.swift
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
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions

// MARK: - Layout Constants

private enum Layout {
    enum Spacing {
        static let preferencePane: CGFloat = 4
        static let caption: CGFloat = 1
        static let section: CGFloat = 0
    }

    enum Grid {
        static let columns: Int = 2
        static let cellMinHeight: CGFloat = 90
    }
}

extension Preferences {

    struct WebTrackingProtectionView: View {
        @ObservedObject var model: WebTrackingProtectionPreferences

        // Define all tracking protection features
        private let trackingProtectionFeatures = [
            PreferencesFeature(
                title: UserText.trackingProtectionThirdPartyTrackersTitle,
                description: UserText.trackingProtectionThirdPartyTrackersDescription,
                iconName: "Shield-16"
            ),
            PreferencesFeature(
                title: UserText.trackingProtectionTargetedAdsTitle,
                description: UserText.trackingProtectionTargetedAdsDescription,
                iconName: "Ads-Tracking-Blocked-16"
            ),
            PreferencesFeature(
                title: UserText.trackingProtectionLinkTrackingTitle,
                description: UserText.trackingProtectionLinkTrackingDescription,
                iconName: "Link-Blocked-16"
            ),
            PreferencesFeature(
                title: UserText.trackingProtectionFingerprintingTitle,
                description: UserText.trackingProtectionFingerprintingDescription,
                iconName: "Fingerprint-16"
            ),
            PreferencesFeature(
                title: UserText.trackingProtectionReferrerTitle,
                description: UserText.trackingProtectionReferrerDescription,
                iconName: "Profile-Lock-16"
            ),
            PreferencesFeature(
                title: UserText.trackingProtectionFirstPartyCookiesTitle,
                description: UserText.trackingProtectionFirstPartyCookiesDescription,
                iconName: "Cookie-Blocked-16"
            ),
            PreferencesFeature(
                title: UserText.trackingProtectionCNAMECloakingTitle,
                description: UserText.trackingProtectionCNAMECloakingDescription,
                iconName: "Device-Laptop-Lock-16"
            ),
            PreferencesFeature(
                title: UserText.trackingProtectionGoogleAMPTitle,
                description: UserText.trackingProtectionGoogleAMPDescription,
                iconName: "Eye-Blocked-16"
            ),
            PreferencesFeature(
                title: UserText.trackingProtectionGoogleSignInTitle,
                description: UserText.trackingProtectionGoogleSignInDescription,
                iconName: "Popup-Blocked-16"
            ),
            PreferencesFeature(
                title: UserText.trackingProtectionFacebookTitle,
                description: UserText.trackingProtectionFacebookDescription,
                iconName: "Eye-Blocked-16"
            )
        ]

        var body: some View {
            PreferencePane(UserText.webTrackingProtection, spacing: Layout.Spacing.preferencePane) {

                PreferencePaneSection {
                    StatusIndicatorView(status: .alwaysOn, isLarge: true)
                }

                PreferencePaneSection {
                    ToggleMenuItem(UserText.gpcCheckboxTitle, isOn: $model.isGPCEnabled)
                    VStack(alignment: .leading, spacing: Layout.Spacing.caption) {
                        TextMenuItemCaption(UserText.gpcExplanation)
                        TextButton(UserText.learnMore) {
                            model.openNewTab(with: .gpcLearnMore)
                        }
                    }
                }

                PreferencePaneSection {
                    TextMenuItemHeader(UserText.webTrackingProtectionAlwaysOn)
                    VStack(alignment: .leading, spacing: Layout.Spacing.section) {
                        TextMenuItemCaption(UserText.webTrackingProtectionUpdatedDescription)
                        TextButton(UserText.learnMore) {
                            model.openNewTab(with: .webTrackingProtection)
                        }
                    }
                    PreferencesFeatureGridView(
                        features: trackingProtectionFeatures,
                        columns: Layout.Grid.columns,
                        cellMinHeight: Layout.Grid.cellMinHeight
                    )
                }

            }
        }
    }
}

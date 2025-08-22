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
import UIComponents

// MARK: - Layout Constants

private enum Layout {
    enum Spacing {
        static let preferencePane: CGFloat = 4
        static let caption: CGFloat = 1
        static let section: CGFloat = 0
        static let featureGridPadding: CGFloat = 0
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
            FeatureGridItem(
                title: UserText.trackingProtectionThirdPartyTrackersTitle,
                description: UserText.trackingProtectionThirdPartyTrackersDescription,
                iconName: "Shield-16"
            ),
            FeatureGridItem(
                title: UserText.trackingProtectionTargetedAdsTitle,
                description: UserText.trackingProtectionTargetedAdsDescription,
                iconName: "Ads-Tracking-Blocked-16"
            ),
            FeatureGridItem(
                title: UserText.trackingProtectionLinkTrackingTitle,
                description: UserText.trackingProtectionLinkTrackingDescription,
                iconName: "Link-Blocked-16"
            ),
            FeatureGridItem(
                title: UserText.trackingProtectionFingerprintingTitle,
                description: UserText.trackingProtectionFingerprintingDescription,
                iconName: "Fingerprint-16"
            ),
            FeatureGridItem(
                title: UserText.trackingProtectionReferrerTitle,
                description: UserText.trackingProtectionReferrerDescription,
                iconName: "Profile-Lock-16"
            ),
             FeatureGridItem(
                title: UserText.trackingProtectionGoogleAMPTitle,
                description: UserText.trackingProtectionGoogleAMPDescription,
                iconName: "Eye-Blocked-16"
            ),
            FeatureGridItem(
                title: UserText.trackingProtectionCNAMECloakingTitle,
                description: UserText.trackingProtectionCNAMECloakingDescription,
                iconName: "Device-Laptop-Lock-16"
            ),
            FeatureGridItem(
                title: UserText.trackingProtectionFirstPartyCookiesTitle,
                description: UserText.trackingProtectionFirstPartyCookiesDescription,
                iconName: "Cookie-Blocked-16"
            ),
            FeatureGridItem(
                title: UserText.trackingProtectionGoogleSignInTitle,
                description: UserText.trackingProtectionGoogleSignInDescription,
                iconName: "Popup-Blocked-16"
            ),
            FeatureGridItem(
                title: UserText.trackingProtectionFacebookTitle,
                description: UserText.trackingProtectionFacebookDescription,
                iconName: "Eye-Blocked-16"
            )
        ]

        var body: some View {
            PreferencePane(UserText.webTrackingProtection, spacing: 4) {

                // SECTION 1: Status Indicator
                PreferencePaneSection {
                    StatusIndicatorView(status: .alwaysOn, isLarge: true)
                }

                // SECTION 2: Description
                PreferencePaneSection {
                    VStack(alignment: .leading, spacing: Layout.Spacing.section) {
                        TextMenuItemCaption(UserText.webTrackingProtectionUpdatedDescription)
                        TextButton(UserText.learnMore) {
                            model.openNewTab(with: .webTrackingProtection)
                        }
                    }
                }

                // SECTION 3: Global privacy control
                PreferencePaneSection {
                    ToggleMenuItem(UserText.gpcCheckboxTitle, isOn: $model.isGPCEnabled)
                    VStack(alignment: .leading, spacing: 1) {
                        TextMenuItemCaption(UserText.gpcExplanation)
                        TextButton(UserText.learnMore) {
                            model.openNewTab(with: .gpcLearnMore)
                        }
                    }.padding(.leading, 19)
                }

                PreferencePaneSection {
                    TextMenuItemHeader(UserText.webTrackingProtectionSubtitle)
                    FeatureGridView(
                        features: trackingProtectionFeatures,
                        layoutStyle: .fixed,
                        columns: Layout.Grid.columns,
                        cellMinHeight: Layout.Grid.cellMinHeight,
                        borderWidth: 1
                    ).padding(.top, Layout.Spacing.featureGridPadding)
                }
            }
        }
    }
}

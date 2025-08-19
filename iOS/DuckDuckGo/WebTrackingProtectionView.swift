//
//  WebTrackingProtectionView.swift
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
import UIKit
import DesignResourcesKit

struct WebTrackingProtectionView: View {

    @EnvironmentObject var viewModel: SettingsViewModel
    
    // Define all tracking protection features
    private let trackingProtectionFeatures = [
        SettingsFeature(
            title: UserText.trackingProtectionThirdPartyTrackersTitle,
            description: UserText.trackingProtectionThirdPartyTrackersDescription,
            iconName: "Shield-16"
        ),
        SettingsFeature(
            title: UserText.trackingProtectionTargetedAdsTitle,
            description: UserText.trackingProtectionTargetedAdsDescription,
            iconName: "Ads-Tracking-Blocked-16"
        ),
        SettingsFeature(
            title: UserText.trackingProtectionLinkTrackingTitle,
            description: UserText.trackingProtectionLinkTrackingDescription,
            iconName: "Link-Blocked-16"
        ),
        SettingsFeature(
            title: UserText.trackingProtectionFingerprintingTitle,
            description: UserText.trackingProtectionFingerprintingDescription,
            iconName: "Fingerprint-16"
        ),
        SettingsFeature(
            title: UserText.trackingProtectionReferrerTitle,
            description: UserText.trackingProtectionReferrerDescription,
            iconName: "Profile-Lock-16"
        ),
        SettingsFeature(
            title: UserText.trackingProtectionFirstPartyCookiesTitle,
            description: UserText.trackingProtectionFirstPartyCookiesDescription,
            iconName: "Cookie-Blocked-16"
        ),
        SettingsFeature(
            title: UserText.trackingProtectionCNAMECloakingTitle,
            description: UserText.trackingProtectionCNAMECloakingDescription,
            iconName: "Device-Laptop-Lock-16"
        ),
        SettingsFeature(
            title: UserText.trackingProtectionGoogleAMPTitle,
            description: UserText.trackingProtectionGoogleAMPDescription,
            iconName: "Eye-Blocked-16"
        ),
        SettingsFeature(
            title: UserText.trackingProtectionGoogleSignInTitle,
            description: UserText.trackingProtectionGoogleSignInDescription,
            iconName: "Popup-Blocked-16"
        )
    ]

    var description: SettingsDescription {
        SettingsDescription(imageName: "SettingsWebTrackingProtectionContent",
                                     title: UserText.webTrackingProtection,
                                     status: .alwaysOn,
                                     explanation: nil)
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 16) {
                List {
                    SettingsDescriptionView(content: description)
                    WebTrackingProtectionViewSettings()
                    WebTrackingProtectionFeatureGrid(features: trackingProtectionFeatures)
                }
                .applySettingsListModifiers(title: UserText.webTrackingProtection,
                                            displayMode: .inline,
                                            viewModel: viewModel)
                
            }
        }
        .onForwardNavigationAppear {
            Pixel.fire(pixel: .settingsWebTrackingProtectionOpen)
        }
    }

}

struct WebTrackingProtectionViewSettings: View {

    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        // Single section for GPC and Unprotected Sites
        Section {
            // Global Privacy Control
            SettingsCellView(label: UserText.settingsGPC,
                             accessory: .toggle(isOn: viewModel.gpcBinding))

            // Unprotected Sites in same section
            SettingsCellView(label: UserText.settingsUnprotectedSites,
                              action: { viewModel.presentLegacyView(.unprotectedSites) },
                              disclosureIndicator: true,
                              isButton: true)
        }
    }
}

struct WebTrackingProtectionFeatureGrid: View {

    @EnvironmentObject var viewModel: SettingsViewModel
    let features: [SettingsFeature]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(UserText.settingsAlwaysOn).textCase(.uppercase)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                VStack(alignment: .leading, spacing: 4) {
                    Text(UserText.webTrackingProtectionUpdatedDescription)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .daxFootnoteRegular()
                    Button(UserText.learnMore) {
                        viewModel.openWebTrackingProtectionLearnMore()
                    }.buttonStyle(LinkButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .daxBodyRegular()

            // Feature grid with masonry layout
            SettingsFeatureMasonryView(
                features: features,
                columns: 2,
                spacing: 12
            )
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// Link button style for Learn More buttons
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .daxFootnoteRegular()
            .foregroundColor(Color(designSystemColor: .accent))
            .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}

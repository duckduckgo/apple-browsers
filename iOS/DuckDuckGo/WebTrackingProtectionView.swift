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
import UIComponents

// MARK: - Layout Constants

private enum LayoutConstants {
    static let sectionSpacing: CGFloat = 12
    static let headerSpacing: CGFloat = 8
    static let descriptionSpacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 20
    static let mainStackSpacing: CGFloat = 16
    static let buttonOpacityPressed: Double = 0.5
    static let buttonOpacityNormal: Double = 1.0
}

struct WebTrackingProtectionView: View {

    @EnvironmentObject var viewModel: SettingsViewModel
    
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
        )
    ]

    var description: SettingsDescription {
        SettingsDescription(imageName: "SettingsWebTrackingProtectionContent",
                                     title: UserText.webTrackingProtection,
                                     status: .alwaysOn,
                                     explanation: UserText.webTrackingProtectionUpdatedDescription)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.mainStackSpacing) {
            List {
                SettingsDescriptionView(content: description)
                WebTrackingProtectionViewSettings()
                WebTrackingProtectionFeatureGrid(features: trackingProtectionFeatures)
            }
            .applySettingsListModifiers(title: UserText.webTrackingProtection,
                                        displayMode: .inline,
                                        viewModel: viewModel)
            
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
    let features: [FeatureGridItem]
    
    private var layoutStyle: FeatureGridLayoutStyle {
        .staggered
    }
    
    private var columnCount: Int {
        UIDevice.current.userInterfaceIdiom == .pad ? 3 : 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.sectionSpacing) {
            VStack(alignment: .leading) {
                Text(UserText.webTrackingProtectionSubtitle).textCase(.uppercase)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            .padding(.horizontal, LayoutConstants.horizontalPadding)

            // Use the shared FeatureGridView component
            FeatureGridView(
                features: features,
                layoutStyle: layoutStyle,
                columns: columnCount,
                borderWidth: 1
            )
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

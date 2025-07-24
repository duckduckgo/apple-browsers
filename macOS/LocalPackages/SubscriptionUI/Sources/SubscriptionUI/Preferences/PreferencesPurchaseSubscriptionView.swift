//
//  PreferencesPurchaseSubscriptionView.swift
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

import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions
import BrowserServicesKit
import DesignResourcesKit

public struct PreferencesPurchaseSubscriptionView: View {

    @ObservedObject var model: PreferencesPurchaseSubscriptionModel
    @State private var showingActivateSubscriptionSheet = false

    public init(model: PreferencesPurchaseSubscriptionModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            TextMenuTitle(UserText.preferencesPurchaseSubscriptionTitle)
                .sheet(isPresented: $showingActivateSubscriptionSheet) {
                    SubscriptionAccessView(model: model.sheetModel)
                }

            purchaseSection

            featuresSection

            helpSection
        }
        .onAppear(perform: {
            model.didAppear()
        })
    }

    @ViewBuilder
    private var purchaseSection: some View {
        HStack(alignment: .top) {
            Image(.privacyPro)
                .padding(4)
                .background(Color("BadgeBackground", bundle: .module))
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 8) {
                TextMenuItemHeader(UserText.preferencesSubscriptionInactiveHeader(isPaidAIChatEnabled: model.isPaidAIChatEnabled))
                TextMenuItemCaption(UserText.preferencesSubscriptionInactiveCaption(region: model.subscriptionStorefrontRegion, isPaidAIChatEnabled: model.isPaidAIChatEnabled))

                let purchaseButtonText = model.isUserEligibleForFreeTrial ? UserText.purchaseFreeTrialButton(isSubscriptionRebrandingEnabled: model.isSubscriptionRebrandingEnabled) : UserText.purchaseButton(isSubscriptionRebrandingEnabled: model.isSubscriptionRebrandingEnabled)

                HStack {
                    Button(purchaseButtonText) { model.purchaseAction() }
                        .buttonStyle(DefaultActionButtonStyle(enabled: true))
                    Button(UserText.haveSubscriptionButton) {
                        if model.shouldDirectlyLaunchActivationFlow {
                            model.sheetModel.handleEmailAction()
                        } else {
                            showingActivateSubscriptionSheet.toggle()
                        }

                        model.didClickIHaveASubscription()
                    }
                    .buttonStyle(DismissActionButtonStyle())
                }
                .padding(.top, 10)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 20)
        .roundedBorder()
    }

    @ViewBuilder
    private var featuresSection: some View {
        VStack {
            ForEach(availableFeatures.indices, id: \.self) { index in
                availableFeatures[index]
                // Add divider between features, but not after the last one
                if index < availableFeatures.count - 1 {
                    Divider()
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .padding(10)
        .roundedBorder()
        .padding(.bottom, 20)
    }

    private var availableFeatures: [SectionView] {
        var features: [SectionView] = []

        switch model.subscriptionStorefrontRegion {
        case .usa:
            // VPN
            features.append(SectionView(iconName: "VPN-Icon",
                                      title: UserText.vpnServiceTitle,
                                      description: UserText.vpnServiceDescription))

            // Personal Information Removal
            features.append(SectionView(iconName: "PIR-Icon",
                                      title: UserText.personalInformationRemovalServiceTitle,
                                      description: UserText.personalInformationRemovalServiceDescription))

            // AI Chat (Duck.ai) - Only add if enabled
            if model.isPaidAIChatEnabled {
                features.append(SectionView(iconName: "Ai-Chat-icon",
                                          title: UserText.paidAIChatTitle,
                                          description: UserText.paidAIChatServiceDescription))
            }

            // Identity Theft Restoration
            features.append(SectionView(iconName: "ITR-Icon",
                                      title: UserText.identityTheftRestorationServiceTitle,
                                      description: UserText.identityTheftRestorationServiceDescription))

        case .restOfWorld:
            // VPN
            features.append(SectionView(iconName: "VPN-Icon",
                                      title: UserText.vpnServiceTitle,
                                      description: UserText.vpnServiceDescription))

            // AI Chat (Duck.ai) - Only add if enabled
            if model.isPaidAIChatEnabled {
                features.append(SectionView(iconName: "Ai-Chat-icon",
                                          title: UserText.paidAIChatTitle,
                                          description: UserText.paidAIChatServiceDescription))
            }

            // Identity Theft Restoration
            features.append(SectionView(iconName: "ITR-Icon",
                                      title: UserText.identityTheftRestorationServiceTitle,
                                      description: UserText.identityTheftRestorationServiceDescription))
        }

        return features
    }

    @ViewBuilder
    private var helpSection: some View {
        PreferencePaneSection {
            TextMenuItemHeader(UserText.preferencesSubscriptionFooterTitle, bottomPadding: 0)

            TextMenuItemCaption(UserText.preferencesSubscriptionHelpFooterCaption)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 16) {
                TextButton(UserText.viewFaqsButton, weight: .semibold) { model.openFAQ() }
                TextButton(UserText.preferencesPrivacyPolicyButton, weight: .semibold) { model.openPrivacyPolicy() }
            }
        }
    }
}

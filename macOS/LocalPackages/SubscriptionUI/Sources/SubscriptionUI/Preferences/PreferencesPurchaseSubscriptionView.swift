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

public struct PreferencesPurchaseSubscriptionViewV1: View {

    @ObservedObject var model: PreferencesPurchaseSubscriptionModel
    @State private var showingActivateSubscriptionSheet = false

    public init(model: PreferencesPurchaseSubscriptionModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Title and dialogs
            TextMenuTitle(UserText.preferencesTitle)
                .sheet(isPresented: $showingActivateSubscriptionSheet) {
                    SubscriptionAccessView(model: model.sheetModel)
                }

            // Header
            VStack {
                unauthenticatedHeaderView

                Divider()
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal, -10)

                featureRowsForNoSubscriptionView
            }
            .padding(10)
            .roundedBorder()
            .padding(.top, 4)
            .padding(.bottom, 12)

            // Help section
            helpSection
        }
        .onAppear(perform: {
            model.didAppear()
        })
    }

    @ViewBuilder
    private var unauthenticatedHeaderView: some View {
        UniversalHeaderView {
            Image(.privacyPro)
                .padding(4)
                .background(Color("BadgeBackground", bundle: .module))
                .cornerRadius(4)
        } content: {
            TextMenuItemHeader(UserText.preferencesSubscriptionInactiveHeader)
            switch model.subscriptionStorefrontRegion {
            case .usa:
                TextMenuItemCaption(UserText.preferencesSubscriptionInactiveUSCaption)
            case .restOfWorld:
                TextMenuItemCaption(UserText.preferencesSubscriptionInactiveROWCaption)
            }
        } buttons: {
            Button(UserText.purchaseButton) { model.purchaseAction() }
                .buttonStyle(DefaultActionButtonStyle(enabled: true))
            Button(UserText.haveSubscriptionButton) {
                if model.shouldDirectlyLaunchActivationFlow {
                    model.sheetModel.handleEmailAction()
                } else {
                    showingActivateSubscriptionSheet.toggle()
                }

                model.userEventHandler(.iHaveASubscriptionClick)
            }
            .buttonStyle(DismissActionButtonStyle())
        }
    }

    @ViewBuilder
    private var featureRowsForNoSubscriptionView: some View {
        switch model.subscriptionStorefrontRegion {
        case .usa:
            SectionView(iconName: "VPN-Icon",
                        title: UserText.vpnServiceTitle,
                        description: UserText.vpnServiceDescription)

            Divider()
                .foregroundColor(Color.secondary)

            SectionView(iconName: "PIR-Icon",
                        title: UserText.personalInformationRemovalServiceTitle,
                        description: UserText.personalInformationRemovalServiceDescription)

            Divider()
                .foregroundColor(Color.secondary)

            SectionView(iconName: "ITR-Icon",
                        title: UserText.identityTheftRestorationServiceTitle,
                        description: UserText.identityTheftRestorationServiceDescription)

        case .restOfWorld:
            SectionView(iconName: "VPN-Icon",
                        title: UserText.vpnServiceTitle,
                        description: UserText.vpnServiceDescription)

            Divider()
                .foregroundColor(Color.secondary)

            SectionView(iconName: "ITR-Icon",
                        title: UserText.identityTheftRestorationServiceTitle,
                        description: UserText.identityTheftRestorationServiceDescription)
        }
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

//
//  PreferencesSubscriptionSettingsViewV2.swift
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

public struct PreferencesSubscriptionSettingsViewV2: View {

    @ObservedObject var model: PreferencesSubscriptionSettingsModelV2
    @State private var showingRemoveConfirmationDialog = false

    @State private var manageSubscriptionSheet: ManageSubscriptionSheet?

    public init(model: PreferencesSubscriptionSettingsModelV2) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header part - Title, dialogs and status indicator
            VStack(alignment: .leading, spacing: 4) {
                TextMenuTitle(UserText.preferencesSubscriptionSettingsTitle)

                switch model.settingsState {
                case .subscriptionActive:
                    StatusIndicatorView(status: .custom(UserText.subscribedStatusIndicator, Color(designSystemColor: .alertGreen)), isLarge: true)
                case .subscriptionExpired:
                    expiredHeaderView
                case .subscriptionPendingActivation:
                    pendingActivationHeaderView
                case .subscriptionFreeTrialActive:
                    StatusIndicatorView(status: .custom(UserText.freeTrialActiveStatusIndicator, Color(designSystemColor: .alertGreen)), isLarge: true)
                }
            }
            .padding(.bottom, 16)

            // Sections
            switch model.settingsState {
            case .subscriptionActive, .subscriptionFreeTrialActive:
                activateSection
                settingsSection
                helpSection

            case .subscriptionExpired:
                activateSection
                helpSection

            case .subscriptionPendingActivation:
                helpSection
            }
        }
        .sheet(isPresented: $showingRemoveConfirmationDialog) {
            removeConfirmationDialog
        }
        .sheet(item: $manageSubscriptionSheet) { sheet in
            switch sheet {
            case .apple:
                manageSubscriptionAppStoreDialog
            case .google:
                manageSubscriptionGooglePlayDialog
            }
        }
        .onAppear(perform: {
            model.didAppear()
        })
    }

    @ViewBuilder
    private var pendingActivationHeaderView: some View {
        VStack(alignment: .leading, spacing: 16) {
            StatusIndicatorView(status: .custom(UserText.activatingStatusIndicator, Color(designSystemColor: .alertYellow)), isLarge: true)

            TextMenuItemCaption(UserText.preferencesSubscriptionPendingCaption)

            TextButton(UserText.restorePurchaseButton, weight: .semibold) {
                model.refreshSubscriptionPendingState()
            }

            TextButton(UserText.removeFromThisDeviceButton, weight: .semibold) {
                showingRemoveConfirmationDialog.toggle()
            }
        }
    }

    @ViewBuilder
    private var expiredHeaderView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(.subscriptionExpiredIcon)
                TextMenuItemCaption(model.subscriptionDetails ?? UserText.preferencesSubscriptionInactiveHeader)
            }
            HStack {
                Button(UserText.viewPlansExpiredButtonTitle) { model.purchaseAction() }
                    .buttonStyle(DefaultActionButtonStyle(enabled: true))
                Button(UserText.removeFromThisDeviceButton, action: {
                    showingRemoveConfirmationDialog.toggle()
                })
            }
        }
    }

    @ViewBuilder
    private var activateSection: some View {
        PreferencePaneSection {
            TextMenuItemHeader(UserText.activateSectionTitle, bottomPadding: 0)

            Text(UserText.activateSectionCaption(hasEmail: model.hasEmail, purchasePlatform: model.currentPurchasePlatform))
                .foregroundColor(Color(.textSecondary))

            TextButton(UserText.activateSectionLearnMoreButton) {
                model.openLearnMore()
            }
            .padding(.top, -4)

            if model.hasEmail {
                emailView
                    .padding(.top, 2)

                TextButton(UserText.addToDeviceLinkTitle, weight: .semibold) { model.activationFlowAction() }
                    .padding(.top, 8)
            } else {
                Button(UserText.addToDeviceButtonTitle) { model.activationFlowAction() }
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        PreferencePaneSection {
            TextMenuItemHeader(UserText.settingsSectionTitle, bottomPadding: 0)
            TextMenuItemCaption(model.subscriptionDetails ?? "")
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 14) {
                TextButton(UserText.updatePlanOrCancelButton, weight: .semibold) {
                    Task {
                        switch await model.changePlanOrBillingAction() {
                        case .presentSheet(let sheet):
                            manageSubscriptionSheet = sheet
                        case .navigateToManageSubscription(let navigationAction):
                            navigationAction()
                        }
                    }
                }
                TextButton(UserText.removeFromThisDeviceButton, weight: .semibold) {
                    showingRemoveConfirmationDialog.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private var helpSection: some View {
        PreferencePaneSection {
            TextMenuItemHeader(UserText.preferencesSubscriptionFooterTitle, bottomPadding: 0)

            TextMenuItemCaption(UserText.preferencesSubscriptionHelpFooterCaption)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 14) {
                TextButton(UserText.viewFaqsButton, weight: .semibold) { model.openFAQ() }

                TextButton(UserText.preferencesSubscriptionFeedbackButton, weight: .semibold) { model.openUnifiedFeedbackForm() }

                TextButton(UserText.preferencesPrivacyPolicyButton, weight: .semibold) { model.openPrivacyPolicy() }
            }
        }
    }

    @ViewBuilder
    private var emailView: some View {
        VStack {
            VStack(alignment: .center) {
                HStack(alignment: .center, spacing: 8) {
                    Image("email-icon", bundle: .module)
                        .padding(4)
                        .background(Color(.badgeBackground))
                        .cornerRadius(4)

                    Text(verbatim: model.email ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixMultilineScrollableText()
                        .font(.body)
                        .foregroundColor(Color(.textPrimary))

                    Button(UserText.editEmailButton) { model.editEmailAction() }
                }
            }
            .padding(.vertical, 0)
        }
        .padding(10)
        .roundedBorder()
    }

    @ViewBuilder
    private var removeConfirmationDialog: some View {
        SubscriptionDialog(imageName: "Privacy-Pro-128",
                           title: UserText.removeSubscriptionDialogTitle,
                           description: UserText.removeSubscriptionDialogDescription,
                           buttons: {
            Button(UserText.removeSubscriptionDialogCancel) { showingRemoveConfirmationDialog = false }
            Button(action: {
                showingRemoveConfirmationDialog = false
                model.removeFromThisDeviceAction()
            }, label: {
                Text(UserText.removeSubscriptionDialogConfirm)
                    .foregroundColor(.red)
            })
        })
        .frame(width: 320)
    }

    @ViewBuilder
    private var manageSubscriptionAppStoreDialog: some View {
        SubscriptionDialog(imageName: "app-store",
                           title: UserText.changeSubscriptionDialogTitle,
                           description: UserText.changeSubscriptionAppleDialogDescription,
                           buttons: {
            Button(UserText.changeSubscriptionDialogDone) { manageSubscriptionSheet = nil }
                .buttonStyle(DefaultActionButtonStyle(enabled: true))
        })
        .frame(width: 360)
    }

    @ViewBuilder
    private var manageSubscriptionGooglePlayDialog: some View {
        SubscriptionDialog(imageName: "google-play",
                           title: UserText.changeSubscriptionDialogTitle,
                           description: UserText.changeSubscriptionGoogleDialogDescription,
                           buttons: {
            Button(UserText.changeSubscriptionDialogDone) { manageSubscriptionSheet = nil }
                .buttonStyle(DefaultActionButtonStyle(enabled: true))
        })
        .frame(width: 360)
    }
}

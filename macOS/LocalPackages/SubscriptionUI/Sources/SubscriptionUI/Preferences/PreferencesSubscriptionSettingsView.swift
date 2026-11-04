//
//  PreferencesSubscriptionSettingsView.swift
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
import DesignResourcesKitIcons

public struct PreferencesSubscriptionSettingsView: View {

    @ObservedObject var model: PreferencesSubscriptionSettingsModel
    @State private var showingRemoveConfirmationDialog = false
    @State private var showingInternalSubscriptionAlert = false
    @State private var showingWithdrawalConfirmation = false

    @State private var manageSubscriptionSheet: ManageSubscriptionSheet?
    private var isPaidAIChatOn: () -> Bool

    public init(model: PreferencesSubscriptionSettingsModel, isPaidAIChatOn: @escaping (() -> Bool)) {
        self.model = model
        self.isPaidAIChatOn = isPaidAIChatOn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header part - Title, dialogs and status indicator
            VStack(alignment: .leading, spacing: 4) {
                TextMenuTitle(UserText.preferencesSubscriptionSettingsTitle)

                if model.withdrawal.confirmation != nil {
                    StatusIndicatorView(status: .custom(UserText.notSubscribedStatusIndicator, Color.secondary.opacity(0.33)), isLarge: true)
                } else {
                    switch model.settingsState {
                    case .subscriptionActive:
                        subscriptionActiveHeader
                    case .subscriptionExpired:
                        expiredHeaderView
                    case .subscriptionPendingActivation:
                        pendingActivationHeaderView
                    case .subscriptionFreeTrialActive:
                        subscriptionFreeTrialActiveHeader
                    }
                }
            }
            .padding(.bottom, 16)

            // Sections
            if let confirmation = model.withdrawal.confirmation {
                withdrawnSection(confirmation)
            } else {
                switch model.settingsState {
                case .subscriptionActive, .subscriptionFreeTrialActive:
                    downgradeBanner
                    upgradeSection
                    activateSection
                    settingsSection
                    withdrawalSection
                    helpSection

                case .subscriptionExpired:
                    activateSection
                    helpSection

                case .subscriptionPendingActivation:
                    helpSection
                }
            }
        }
        .sheet(isPresented: $showingRemoveConfirmationDialog) {
            removeConfirmationDialog
        }
        .sheet(isPresented: $showingInternalSubscriptionAlert) {
            internalSubscriptionAlert
        }
        .sheet(item: $manageSubscriptionSheet) { sheet in
            switch sheet {
            case .apple:
                manageSubscriptionAppStoreDialog
            case .google:
                manageSubscriptionGooglePlayDialog
            }
        }
        .sheet(isPresented: $showingWithdrawalConfirmation) {
            withdrawalConfirmationDialog
        }
        .sheet(isPresented: Binding(get: { model.withdrawal.isShowingError },
                                    set: { isShowing in
                                        guard model.withdrawal.isShowingError != isShowing else { return }
                                        model.withdrawal.isShowingError = isShowing
                                    })) {
            withdrawalErrorDialog
        }
        .onAppear(perform: {
            model.didAppear()
        })
        .onDisappear {
            Task { await model.withdrawal.completeWithdrawalIfNeeded() }
        }
    }

    @ViewBuilder
    private var subscriptionActiveHeader: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            StatusIndicatorView(status: .custom(UserText.subscribedStatusIndicator, Color(designSystemColor: .statusGreen)), isLarge: true)
            if let variant = model.tierBadgeToDisplay {
                Rectangle()
                    .fill(Color(designSystemColor: .surfaceDecorationPrimary))
                    .frame(width: 1, height: 8)
                TierBadgeView(variant: variant)
            }
        }
    }

    @ViewBuilder
    private var subscriptionFreeTrialActiveHeader: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            StatusIndicatorView(status: .custom(UserText.freeTrialActiveStatusIndicator, Color(designSystemColor: .statusGreen)), isLarge: true)
            if let variant = model.tierBadgeToDisplay {
                Rectangle()
                    .fill(Color(designSystemColor: .surfaceDecorationPrimary))
                    .frame(width: 1, height: 8)
                TierBadgeView(variant: variant)
            }
        }
    }

    @ViewBuilder
    private var pendingActivationHeaderView: some View {
        VStack(alignment: .leading, spacing: 16) {
            StatusIndicatorView(status: .custom(UserText.activatingStatusIndicator, Color(designSystemColor: .statusYellowPrimary)), isLarge: true)

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
                TextMenuItemCaption(model.subscriptionDetails ?? UserText.preferencesSubscriptionInactiveHeader(isPaidAIChatEnabled: isPaidAIChatOn()))
            }
            HStack {
                Button(model.expiredSubscriptionPurchaseButtonTitle) { model.purchaseAction() }
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
    private var upgradeSection: some View {
        if model.shouldShowUpgrade, let tierName = model.firstAvailableUpgradeTier {
            SubfeatureGroup {
                HStack(alignment: .top, spacing: 12) {
                    Image(.aiChatAdvancedColor24)
                    VStack(alignment: .leading, spacing: 18) {
                        Text(UserText.upgradeSectionCaption)
                            .foregroundColor(Color(.textPrimary))
                            .font(.system(size: 13, weight: .semibold))
                        Button(UserText.upgradeButton(tierName: tierName)) {
                            switch model.viewAllPlansAction(url: .upgradeToTier(tierName)) {
                            case .navigateToPlans(let navigationAction),
                                    .navigateToManageSubscription(let navigationAction):
                                navigationAction()
                            case .presentSheet(let sheet):
                                manageSubscriptionSheet = sheet
                            case .showInternalSubscriptionAlert:
                                showingInternalSubscriptionAlert.toggle()
                            }
                        }
                        .buttonStyle(StandardButtonStyle(topPadding: 8, bottomPadding: 8, horizontalPadding: 12, cornerRadius: 6))
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 10)
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
                if model.shouldShowViewAllPlans {
                    TextButton(UserText.viewAllPlansButtonTitle, weight: .semibold) {
                        switch model.viewAllPlansAction() {
                        case .navigateToPlans(let navigationAction),
                             .navigateToManageSubscription(let navigationAction):
                            navigationAction()
                        case .presentSheet(let sheet):
                            manageSubscriptionSheet = sheet
                        case .showInternalSubscriptionAlert:
                            showingInternalSubscriptionAlert.toggle()
                        }
                    }
                }
                TextButton(model.subscriptionManageButtonText, weight: .semibold) {
                    Task {
                        switch await model.changePlanOrBillingAction() {
                        case .presentSheet(let sheet):
                            manageSubscriptionSheet = sheet
                        case .navigateToManageSubscription(let navigationAction):
                            navigationAction()
                        case .showInternalSubscriptionAlert:
                            showingInternalSubscriptionAlert.toggle()
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
    private var withdrawalSection: some View {
        if let offer = model.withdrawal.offer {
            PreferencePaneSection {
                TextMenuItemHeader(UserText.withdrawSectionTitle, bottomPadding: 0)

                if let eligibleUntil = offer.eligibleUntil {
                    TextMenuItemCaption(UserText.withdrawSectionCaption(eligibleUntil: eligibleUntil))
                        .padding(.bottom, 8)
                }

                TextButton(UserText.withdrawButton, weight: .semibold) {
                    model.withdrawal.withdrawTapped()
                    showingWithdrawalConfirmation = true
                }
                .disabled(model.withdrawal.isWithdrawing)
            }
        }
    }

    @ViewBuilder
    private func withdrawnSection(_ confirmation: SubscriptionWithdrawalConfirmation) -> some View {
        PreferencePaneSection {
            TextMenuItemHeader(UserText.withdrawnInfo(withdrawalDate: confirmation.withdrawalDate), bottomPadding: 0)

            if let refundAmount = confirmation.refundAmount {
                TextMenuItemCaption(UserText.withdrawnRefundInfo(refundAmount: refundAmount))
            }
        }
    }

    @ViewBuilder
    private var withdrawalConfirmationDialog: some View {
        if let offer = model.withdrawal.offer {
            SubscriptionDialog(imageName: "Shield-Disabled-Feature-128",
                               title: UserText.withdrawDialogTitle,
                               description: model.withdrawal.confirmationMessage(for: offer),
                               buttons: {
                Button(UserText.withdrawDialogKeepButton) {
                    showingWithdrawalConfirmation = false
                    model.withdrawal.keepTapped()
                }
                Button(UserText.withdrawDialogConfirmButton) {
                    showingWithdrawalConfirmation = false
                    Task { await model.withdrawal.withdraw() }
                }
                .buttonStyle(DestructiveActionButtonStyle(enabled: true))
            })
            .frame(width: 420)
            .onAppear {
                model.withdrawal.confirmationShown()
            }
        }
    }

    @ViewBuilder
    private var withdrawalErrorDialog: some View {
        let message = UserText.withdrawErrorMessage(helpPageURL: model.withdrawal.helpPageURL.absoluteString)
        SubscriptionDialog(imageName: "Privacy-Pro-128",
                           title: UserText.somethingWentWrongAlertTitle,
                           description: (try? AttributedString(markdown: message)) ?? AttributedString(message),
                           buttons: {
            Button(UserText.okButtonTitle) { model.withdrawal.isShowingError = false }
                .buttonStyle(DefaultActionButtonStyle(enabled: true))
        })
        .environment(\.openURL, OpenURLAction { _ in
            model.withdrawal.isShowingError = false
            model.withdrawal.openHelpPage()
            return .handled
        })
        .frame(width: 420)
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
    private var internalSubscriptionAlert: some View {
        SubscriptionDialog(imageName: "Privacy-Pro-128",
                           title: UserText.changeSubscriptionDialogTitle,
                           description: UserText.changeSubscriptionDialogInternalMessage,
                           buttons: {
            Button(UserText.okButtonTitle) { showingInternalSubscriptionAlert = false }
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

    @ViewBuilder
    private var downgradeBanner: some View {
        if let details = model.cancelPendingDowngradeDetails {
            SubfeatureGroup {
                HStack(spacing: 8) {
                    Image(.subscriptionPendingIcon)
                    Text(details)
                        .font(
                            .system(size: 13)
                        )
                        .foregroundColor(Color(.textSecondary))
                    Spacer()
                    Button(UserText.cancelDowngradeButton) {
                        switch model.cancelPendingDowngrade() {
                        case .cancelApplePendingDowngrade(let cancelAction):
                            cancelAction()
                        case .navigateToManageSubscription(let navigationAction):
                            navigationAction()
                        case .presentSheet(let sheet):
                            manageSubscriptionSheet = sheet
                        case .showInternalSubscriptionAlert:
                            showingInternalSubscriptionAlert.toggle()
                        }
                    }
                }
                .padding(2)
            }
        }
    }
}

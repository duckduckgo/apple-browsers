//
//  SubscriptionSettingsView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import SwiftUI
import DesignResourcesKit
import Core
import Networking
import VPN

enum SubscriptionSettingsViewConfiguration {
    case subscribed
    case expired
    case activating
    case trial
}

struct SubscriptionSettingsView: View {

    @State var configuration: SubscriptionSettingsViewConfiguration
    @Environment(\.dismiss) var dismiss

    @StateObject var viewModel = SubscriptionSettingsViewModel()
    @StateObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var subscriptionNavigationCoordinator: SubscriptionNavigationCoordinator
    var viewPlans: (() -> Void)?
    @State var isShowingStripeView = false
    @State var isShowingGoogleView = false
    @State var isShowingInternalSubscriptionNotice = false
    @State var isShowingRemovalNotice = false
    @State var isShowingFAQView = false
    @State var isShowingLearnMoreView = false
    @State var isShowingActivationView = false
    @State var isShowingManageEmailView = false
    @State var isShowingConnectionError = false
    @State var isShowingSubscriptionError = false
    @State var isShowingSupportView = false

    var body: some View {
        optionsView
            .onFirstAppear {
                Pixel.fire(pixel: .privacyProSubscriptionSettings, debounce: 1)
            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settingsViewModel.state.subscription.shouldDisplayRestoreSubscriptionError) { value in
                if value {
                    isShowingSubscriptionError = true
                }
            }
    }
    
    // MARK: -
    @ViewBuilder
    private var headerSection: some View {
        Section {
            switch configuration {
            case .subscribed:
                SubscriptionSettingsHeaderView(state: .subscribed)
            case .expired:
                SubscriptionSettingsHeaderView(state: .expired(viewModel.state.subscriptionDetails))
            case .activating:
                SubscriptionSettingsHeaderView(state: .activating)
            case .trial:
                SubscriptionSettingsHeaderView(state: .trial)
            }
        }
        .listRowBackground(Color.clear)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var devicesSection: some View {
        Section(header: Text(UserText.subscriptionDevicesSectionHeader(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled)),
                footer: devicesSectionFooter) {

            if let email = viewModel.state.subscriptionEmail, !email.isEmpty {
                NavigationLink(destination: SubscriptionContainerViewFactory.makeEmailFlow(
                    navigationCoordinator: subscriptionNavigationCoordinator,
                    subscriptionManager: AppDependencyProvider.shared.subscriptionManager!,
                    subscriptionFeatureAvailability: settingsViewModel.subscriptionFeatureAvailability,
                    internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                    emailFlow: .manageEmailFlow,
                    dataBrokerProtectionViewControllerProvider: settingsViewModel.dataBrokerProtectionViewControllerProvider,
                    onDisappear: {
                        Task {
                            await viewModel.fetchAndUpdateAccountEmail(cachePolicy: .reloadIgnoringLocalCacheData)
                        }
                    }),
                               isActive: $isShowingManageEmailView) {
                    SettingsCellView(label: UserText.subscriptionEditEmailButton,
                                     subtitle: email)
                }.isDetailLink(false)
            }

            NavigationLink(destination: SubscriptionContainerViewFactory.makeEmailFlow(
                navigationCoordinator: subscriptionNavigationCoordinator,
                subscriptionManager: AppDependencyProvider.shared.subscriptionManager!,
                subscriptionFeatureAvailability: settingsViewModel.subscriptionFeatureAvailability,
                internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                emailFlow: .activationFlow,
                dataBrokerProtectionViewControllerProvider: settingsViewModel.dataBrokerProtectionViewControllerProvider,
                onDisappear: {
                    Task {
                        await viewModel.fetchAndUpdateAccountEmail(cachePolicy: .reloadIgnoringLocalCacheData)
                    }
                }),
                           isActive: $isShowingActivationView) {
                SettingsCustomCell(content: {
                    Text(UserText.subscriptionAddToDeviceButton)
                        .daxBodyRegular()
                    .foregroundColor(Color.init(designSystemColor: .accent)) },
                                   disclosureIndicator: false)
            }.isDetailLink(false)
        }.listRowBackground(Color(designSystemColor: .surface))
    }

    private var devicesSectionFooter: some View {
        let hasEmail = !(viewModel.state.subscriptionEmail ?? "").isEmpty
        let footerText = hasEmail ? UserText.subscriptionDevicesSectionWithEmailFooter(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled) : UserText.subscriptionDevicesSectionNoEmailFooter(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled)
        return Text(.init("\(footerText)")) // required to parse markdown formatting
            .environment(\.openURL, OpenURLAction { _ in
                viewModel.displayLearnMoreView(true)
                return .handled
            })
            .tint(Color(designSystemColor: .accent))
    }

    private var manageSection: some View {
        Section(header: Text(UserText.subscriptionManageTitle),
                footer: manageSectionFooter) {

            switch configuration {
            case .subscribed, .expired, .trial:
                let active = viewModel.state.subscriptionInfo?.isActive ?? false
                SettingsCustomCell(content: {
                    if !viewModel.state.isLoadingSubscriptionInfo {
                        if active {
                            Text(UserText.subscriptionChangePlan)
                                .daxBodyRegular()
                                .foregroundColor(Color.init(designSystemColor: .accent))
                        } else {
                            Text(UserText.subscriptionRestoreNotFoundPlans)
                                .daxBodyRegular()
                                .foregroundColor(Color.init(designSystemColor: .accent))
                        }
                    } else {
                        SwiftUI.ProgressView()
                    }
                },
                                   action: {
                    if !viewModel.state.isLoadingSubscriptionInfo {
                        Task {
                            if active {
                                viewModel.manageSubscription()
                                Pixel.fire(pixel: .privacyProSubscriptionManagementPlanBilling, debounce: 1)
                            } else {
                                viewPlans?()
                            }
                        }
                    }
                },
                                   isButton: true)
                .sheet(isPresented: $isShowingStripeView) {
                    if let stripeViewModel = viewModel.state.stripeViewModel {
                        SubscriptionExternalLinkView(viewModel: stripeViewModel, title: UserText.subscriptionManagePlan)
                    }
                }

                .alert(isPresented: $isShowingInternalSubscriptionNotice) {
                    Alert(
                        title: Text(UserText.subscriptionManageInternalTitle),
                        message: Text(UserText.subscriptionManageInternalMessage)
                    )
                }

                removeFromDeviceView
                
            case .activating:
                restorePurchaseView
                removeFromDeviceView
            }
        }
    }

    @ViewBuilder
    var removeFromDeviceView: some View {
        SettingsCustomCell(content: {
            Text(UserText.subscriptionRemoveFromDevice)
                .daxBodyRegular()
            .foregroundColor(Color.init(designSystemColor: .accent))},
                           action: { viewModel.displayRemovalNotice(true) },
                           isButton: true)
        .alert(isPresented: $isShowingRemovalNotice) {
            Alert(
                title: Text(UserText.subscriptionRemoveFromDeviceConfirmTitle),
                message: Text(UserText.subscriptionRemoveFromDeviceConfirmText(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled)),
                primaryButton: .cancel(Text(UserText.subscriptionRemoveCancel)) {},
                secondaryButton: .destructive(Text(UserText.subscriptionRemove)) {
                    Pixel.fire(pixel: .privacyProSubscriptionManagementRemoval)
                    viewModel.removeSubscription()
                    dismiss()
                }
            )
        }
    }

    @ViewBuilder
    var restorePurchaseView: some View {
        let text = !settingsViewModel.state.subscription.isRestoring ? UserText.subscriptionActivateViaAppleAccountButton : UserText.subscriptionRestoringTitle
        SettingsCustomCell(content: {
            Text(text)
                .daxBodyRegular()
            .foregroundColor(Color.init(designSystemColor: .accent)) },
                           action: {
            Task { await settingsViewModel.restoreAccountPurchase() }
        },
                           isButton: !settingsViewModel.state.subscription.isRestoring )
        .alert(isPresented: $isShowingSubscriptionError) {
            Alert(
                title: Text(UserText.subscriptionAppStoreErrorTitle),
                message: Text(UserText.subscriptionAppStoreErrorMessage),
                dismissButton: .default(Text(UserText.actionOK)) {}
            )
        }
    }

    private var manageSectionFooter: some View {
        let isExpired = !(viewModel.state.subscriptionInfo?.isActive ?? false)
        return  Group {
            if isExpired {
                EmptyView()
            } else {
                Text(viewModel.state.subscriptionDetails)
            }
        }
    }

    @ViewBuilder var helpSection: some View {
        if viewModel.enablesUnifiedFeedbackForm {
            Section {
                faqButton
                supportButton
            } header: {
                Text(UserText.subscriptionHelpAndSupport)
            }
        } else {
            Section(header: Text(UserText.subscriptionHelpAndSupport),
                    footer: Text(UserText.subscriptionFAQFooter(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled))) {
                faqButton
            }
        }
    }

    @ViewBuilder var privacyPolicySection: some View {
        Section {
            SettingsCustomCell(content: {
                Text(UserText.settingsPProSectionFooter)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .accent))
            },
                               action: { viewModel.showTermsOfService() },
                               disclosureIndicator: false,
                               isButton: true)
        }

    }

    @ViewBuilder
    private var faqButton: some View {
        SettingsCustomCell(content: {
            Text(UserText.subscriptionFAQ)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .accent))
        },
                           action: { viewModel.displayFAQView(true) },
                           disclosureIndicator: false,
                           isButton: true)
    }

    @ViewBuilder
    private var supportButton: some View {
        SettingsCustomCell(content: {
            Text(UserText.subscriptionFeedback)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .accent))
        },
                           action: { isShowingSupportView = true },
                           disclosureIndicator: true,
                           isButton: true)
    }

    @ViewBuilder
    private var optionsView: some View {
        NavigationLink(destination: SubscriptionGoogleView(),
                       isActive: $isShowingGoogleView) {
            EmptyView()
        }.hidden()

        NavigationLink(destination: UnifiedFeedbackRootView(viewModel: UnifiedFeedbackFormViewModel(subscriptionManager: AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge,
                                                                                                    apiService: DefaultAPIService(),
                                                                                                    vpnMetadataCollector: DefaultVPNMetadataCollector(),
                                                                                                    dbpMetadataCollector: DefaultDBPMetadataCollector(),
                                                                                                    isPaidAIChatFeatureEnabled: { settingsViewModel.subscriptionFeatureAvailability.isPaidAIChatEnabled },
                                                                                                    source: .ppro)),
                       isActive: $isShowingSupportView) {
            EmptyView()
        }.hidden()

        List {
            headerSection
                .padding(.horizontal, -20)
                .padding(.vertical, -10)
            if configuration == .subscribed || configuration == .expired || configuration == .trial {
                devicesSection
            }
            manageSection
            helpSection
            privacyPolicySection
        }
        .padding(.top, -20)
        .navigationTitle(UserText.settingsPProManageSubscription)
        .applyInsetGroupedListStyle()
        .onChange(of: viewModel.state.shouldDismissView) { value in
            if value {
                dismiss()
            }
        }
        
        // Google Binding
        .onChange(of: viewModel.state.isShowingGoogleView) { value in
            isShowingGoogleView = value
        }
        .onChange(of: isShowingGoogleView) { value in
            viewModel.displayGoogleView(value)
        }
        
        // Stripe Binding
        .onChange(of: viewModel.state.isShowingStripeView) { value in
            isShowingStripeView = value
        }
        .onChange(of: isShowingStripeView) { value in
            viewModel.displayStripeView(value)
        }

        // Internal subscription binding
        .onChange(of: viewModel.state.isShowingInternalSubscriptionNotice) { value in
            isShowingInternalSubscriptionNotice = value
        }
        .onChange(of: isShowingInternalSubscriptionNotice) { value in
            viewModel.displayInternalSubscriptionNotice(value)
        }

        // Removal Notice
        .onChange(of: viewModel.state.isShowingRemovalNotice) { value in
            isShowingRemovalNotice = value
        }
        .onChange(of: isShowingRemovalNotice) { value in
            viewModel.displayRemovalNotice(value)
        }
        
        // FAQ
        .onChange(of: viewModel.state.isShowingFAQView) { value in
            isShowingFAQView = value
        }
        .onChange(of: isShowingFAQView) { value in
            viewModel.displayFAQView(value)
        }

        // Learn More
        .onChange(of: viewModel.state.isShowingLearnMoreView) { value in
            isShowingLearnMoreView = value
        }
        .onChange(of: isShowingLearnMoreView) { value in
            viewModel.displayLearnMoreView(value)
        }

        // Connection Error
        .onChange(of: viewModel.state.isShowingConnectionError) { value in
            isShowingConnectionError = value
        }
        .onChange(of: isShowingConnectionError) { value in
            viewModel.showConnectionError(value)
        }

        .onChange(of: isShowingManageEmailView) { value in
            if value {
                if let email = viewModel.state.subscriptionEmail, !email.isEmpty {
                    Pixel.fire(pixel: .privacyProSubscriptionManagementEmail, debounce: 1)
                }
            }
        }
        
        .onReceive(subscriptionNavigationCoordinator.$shouldPopToSubscriptionSettings) { shouldDismiss in
            if shouldDismiss {
                isShowingActivationView = false
                isShowingManageEmailView = false
            }
        }
        
        .alert(isPresented: $isShowingConnectionError) {
            Alert(
                title: Text(UserText.subscriptionBackendErrorTitle),
                message: Text(UserText.subscriptionBackendErrorMessage),
                dismissButton: .cancel(Text(UserText.subscriptionBackendErrorButton)) {
                    dismiss()
                }
            )
        }
        
        .sheet(isPresented: $isShowingFAQView, content: {
            SubscriptionExternalLinkView(viewModel: viewModel.state.faqViewModel, title: UserText.subscriptionFAQ)
        })

        .sheet(isPresented: $isShowingLearnMoreView, content: {
            SubscriptionExternalLinkView(viewModel: viewModel.state.learnMoreViewModel, title: UserText.subscriptionFAQ)
        })

        .onFirstAppear {
            viewModel.onFirstAppear()
        }
            
    }

    @ViewBuilder
    private var stripeView: some View {
        if let stripeViewModel = viewModel.state.stripeViewModel {
            SubscriptionExternalLinkView(viewModel: stripeViewModel)
        }
    }
}

struct SubscriptionSettingsViewV2: View {

    @State var configuration: SubscriptionSettingsViewConfiguration
    @Environment(\.dismiss) var dismiss

    @StateObject var viewModel = SubscriptionSettingsViewModelV2()
    @StateObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var subscriptionNavigationCoordinator: SubscriptionNavigationCoordinator
    var viewPlans: (() -> Void)?

    @State var isShowingStripeView = false
    @State var isShowingGoogleView = false
    @State var isShowingInternalSubscriptionNotice = false
    @State var isShowingRemovalNotice = false
    @State var isShowingFAQView = false
    @State var isShowingLearnMoreView = false
    @State var isShowingActivationView = false
    @State var isShowingManageEmailView = false
    @State var isShowingConnectionError = false
    @State var isShowingSubscriptionError = false
    @State var isShowingSupportView = false

    var body: some View {
        optionsView
            .onFirstAppear {
                Pixel.fire(pixel: .privacyProSubscriptionSettings, debounce: 1)
            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settingsViewModel.state.subscription.shouldDisplayRestoreSubscriptionError) { value in
                if value {
                    isShowingSubscriptionError = true
                }
            }
    }

    // MARK: -
    @ViewBuilder
    private var headerSection: some View {
        Section {
            switch configuration {
            case .subscribed:
                SubscriptionSettingsHeaderView(state: .subscribed)
            case .expired:
                SubscriptionSettingsHeaderView(state: .expired(viewModel.state.subscriptionDetails))
            case .activating:
                SubscriptionSettingsHeaderView(state: .activating)
            case .trial:
                SubscriptionSettingsHeaderView(state: .trial)
            }
        }
        .listRowBackground(Color.clear)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var devicesSection: some View {
        Section(header: Text(UserText.subscriptionDevicesSectionHeader(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled)),
                footer: devicesSectionFooter) {

            if let email = viewModel.state.subscriptionEmail, !email.isEmpty {
                SettingsCellView(label: UserText.subscriptionEditEmailButton,
                                 subtitle: email,
                                 action: { isShowingManageEmailView = true },
                                 disclosureIndicator: true,
                                 isButton: true)
            }

            SettingsCustomCell(content: {
                Text(UserText.subscriptionAddToDeviceButton)
                    .daxBodyRegular()
                    .foregroundColor(Color.init(designSystemColor: .accent))
            }, action: { isShowingActivationView = true },
                               disclosureIndicator: true, isButton: true)
        }
    }

    private var devicesSectionFooter: some View {
        let hasEmail = !(viewModel.state.subscriptionEmail ?? "").isEmpty
        let footerText = hasEmail ? UserText.subscriptionDevicesSectionWithEmailFooter(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled) : UserText.subscriptionDevicesSectionNoEmailFooter(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled)
        return Text(.init("\(footerText)")) // required to parse markdown formatting
            .environment(\.openURL, OpenURLAction { _ in
                viewModel.displayLearnMoreView(true)
                return .handled
            })
            .tint(Color(designSystemColor: .accent))
    }

    private var manageSection: some View {
        Section(header: Text(UserText.subscriptionManageTitle),
                footer: manageSectionFooter) {

            switch configuration {
            case .subscribed, .expired, .trial:
                let active = viewModel.state.subscriptionInfo?.isActive ?? false
                SettingsCustomCell(content: {
                    if !viewModel.state.isLoadingSubscriptionInfo {
                        if active {
                            Text(UserText.subscriptionChangePlan)
                                .daxBodyRegular()
                                .foregroundColor(Color.init(designSystemColor: .accent))
                        } else {
                            Text(UserText.subscriptionRestoreNotFoundPlans)
                                .daxBodyRegular()
                                .foregroundColor(Color.init(designSystemColor: .accent))
                        }
                    } else {
                        SwiftUI.ProgressView()
                    }
                },
                                   action: {
                    if !viewModel.state.isLoadingSubscriptionInfo {
                        Task {
                            if active {
                                viewModel.manageSubscription()
                                Pixel.fire(pixel: .privacyProSubscriptionManagementPlanBilling, debounce: 1)
                            } else {
                                viewPlans?()
                            }
                        }
                    }
                },
                                   isButton: true)
                .sheet(isPresented: $isShowingStripeView) {
                    if let stripeViewModel = viewModel.state.stripeViewModel {
                        SubscriptionExternalLinkView(viewModel: stripeViewModel, title: UserText.subscriptionManagePlan)
                    }
                }

                .alert(isPresented: $isShowingInternalSubscriptionNotice) {
                    Alert(
                        title: Text(UserText.subscriptionManageInternalTitle),
                        message: Text(UserText.subscriptionManageInternalMessage)
                    )
                }

                removeFromDeviceView

            case .activating:
                restorePurchaseView
                removeFromDeviceView
            }
        }
    }

    @ViewBuilder
    var removeFromDeviceView: some View {
        SettingsCustomCell(content: {
            Text(UserText.subscriptionRemoveFromDevice)
                .daxBodyRegular()
            .foregroundColor(Color.init(designSystemColor: .accent))},
                           action: { viewModel.displayRemovalNotice(true) },
                           isButton: true)
        .alert(isPresented: $isShowingRemovalNotice) {
            Alert(
                title: Text(UserText.subscriptionRemoveFromDeviceConfirmTitle),
                message: Text(UserText.subscriptionRemoveFromDeviceConfirmText(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled)),
                primaryButton: .cancel(Text(UserText.subscriptionRemoveCancel)) {},
                secondaryButton: .destructive(Text(UserText.subscriptionRemove)) {
                    Pixel.fire(pixel: .privacyProSubscriptionManagementRemoval)
                    viewModel.removeSubscription()
                    dismiss()
                }
            )
        }
    }

    @ViewBuilder
    var restorePurchaseView: some View {
        let text = !settingsViewModel.state.subscription.isRestoring ? UserText.subscriptionActivateViaAppleAccountButton : UserText.subscriptionRestoringTitle
        SettingsCustomCell(content: {
            Text(text)
                .daxBodyRegular()
            .foregroundColor(Color.init(designSystemColor: .accent)) },
                           action: {
            Task { await settingsViewModel.restoreAccountPurchase() }
        },
                           isButton: !settingsViewModel.state.subscription.isRestoring )
        .alert(isPresented: $isShowingSubscriptionError) {
            Alert(
                title: Text(UserText.subscriptionAppStoreErrorTitle),
                message: Text(UserText.subscriptionAppStoreErrorMessage),
                dismissButton: .default(Text(UserText.actionOK)) {}
            )
        }
    }

    private var manageSectionFooter: some View {
        let isExpired = !(viewModel.state.subscriptionInfo?.isActive ?? false)
        return  Group {
            if isExpired {
                EmptyView()
            } else {
                Text(viewModel.state.subscriptionDetails)
            }
        }
    }

    @ViewBuilder var helpSection: some View {
        if viewModel.usesUnifiedFeedbackForm {
            Section {
                faqButton
                supportButton
            } header: {
                Text(UserText.subscriptionHelpAndSupport)
            }
        } else {
            Section(header: Text(UserText.subscriptionHelpAndSupport),
                    footer: Text(UserText.subscriptionFAQFooter(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled))) {
                faqButton
            }
        }
    }

    @ViewBuilder var privacyPolicySection: some View {
        Section {
            SettingsCustomCell(content: {
                Text(UserText.settingsPProSectionFooter)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .accent))
            },
                               action: { viewModel.showTermsOfService() },
                               disclosureIndicator: false,
                               isButton: true)
        }

    }

    @ViewBuilder
    private var faqButton: some View {
        SettingsCustomCell(content: {
            Text(UserText.subscriptionFAQ)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .accent))
        },
                           action: { viewModel.displayFAQView(true) },
                           disclosureIndicator: false,
                           isButton: true)
    }

    @ViewBuilder
    private var supportButton: some View {
        SettingsCustomCell(content: {
            Text(UserText.subscriptionFeedback)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .accent))
        },
                           action: { isShowingSupportView = true },
                           disclosureIndicator: true,
                           isButton: true)
    }

    @ViewBuilder
    private var rebrandingMessage: some View {
        if viewModel.showRebrandingMessage {
            HStack(alignment: .top) {
                Text(UserText.subscriptionRebrandingMessage)
                    .font(
                        Font(uiFont: UIFont.daxSubheadSemibold())
                    )
                Spacer()
                Button(action: {
                    viewModel.dismissRebrandingMessage()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var optionsView: some View {
        NavigationLink(
            destination: SubscriptionContainerViewFactory.makeEmailFlowV2(
                navigationCoordinator: subscriptionNavigationCoordinator,
                subscriptionManager: AppDependencyProvider.shared.subscriptionManagerV2!,
                subscriptionFeatureAvailability: settingsViewModel.subscriptionFeatureAvailability,
                internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                emailFlow: .manageEmailFlow,
                dataBrokerProtectionViewControllerProvider: settingsViewModel.dataBrokerProtectionViewControllerProvider,
                widePixel: AppDependencyProvider.shared.widePixel,
                onDisappear: {
                    Task {
                        await viewModel.fetchAndUpdateAccountEmail(cachePolicy: .remoteFirst)
                    }
                }),
            isActive: $isShowingManageEmailView
        ) { EmptyView() }
            .isDetailLink(false)
            .hidden()

        NavigationLink(
            destination: SubscriptionContainerViewFactory.makeEmailFlowV2(
                navigationCoordinator: subscriptionNavigationCoordinator,
                subscriptionManager: AppDependencyProvider.shared.subscriptionManagerV2!,
                subscriptionFeatureAvailability: settingsViewModel.subscriptionFeatureAvailability,
                internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                emailFlow: .activationFlow,
                dataBrokerProtectionViewControllerProvider: settingsViewModel.dataBrokerProtectionViewControllerProvider,
                widePixel: AppDependencyProvider.shared.widePixel,
                onDisappear: {
                    Task {
                        await viewModel.fetchAndUpdateAccountEmail(cachePolicy: .remoteFirst)
                    }
                }),
            isActive: $isShowingActivationView
        ) { EmptyView() }
            .isDetailLink(false)
            .hidden()

        NavigationLink(destination: SubscriptionGoogleView(),
                       isActive: $isShowingGoogleView) {
            EmptyView()
        }.hidden()
        
        NavigationLink(destination: UnifiedFeedbackRootView(viewModel: UnifiedFeedbackFormViewModel(subscriptionManager: AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge,
                                                                                                    apiService: DefaultAPIService(),
                                                                                                    vpnMetadataCollector: DefaultVPNMetadataCollector(), dbpMetadataCollector: DefaultDBPMetadataCollector(),
                                                                                                    isPaidAIChatFeatureEnabled: { settingsViewModel.subscriptionFeatureAvailability.isPaidAIChatEnabled },
                                                                                                    source: .ppro)),
                       isActive: $isShowingSupportView) {
            EmptyView()
        }.hidden()

        List {
            headerSection
                .padding(.horizontal, -20)
                .padding(.vertical, -10)
            rebrandingMessage
            if configuration == .subscribed || configuration == .expired || configuration == .trial {
                devicesSection
            }
            manageSection
            helpSection
            privacyPolicySection
        }
        .padding(.top, -20)
        .navigationTitle(UserText.settingsPProManageSubscription)
        .applyInsetGroupedListStyle()
        .onChange(of: viewModel.state.shouldDismissView) { value in
            if value {
                dismiss()
            }
        }

        // Google Binding
        .onChange(of: viewModel.state.isShowingGoogleView) { value in
            isShowingGoogleView = value
        }
        .onChange(of: isShowingGoogleView) { value in
            viewModel.displayGoogleView(value)
        }

        // Stripe Binding
        .onChange(of: viewModel.state.isShowingStripeView) { value in
            isShowingStripeView = value
        }
        .onChange(of: isShowingStripeView) { value in
            viewModel.displayStripeView(value)
        }

        // Internal subscription binding
        .onChange(of: viewModel.state.isShowingInternalSubscriptionNotice) { value in
            isShowingInternalSubscriptionNotice = value
        }
        .onChange(of: isShowingInternalSubscriptionNotice) { value in
            viewModel.displayInternalSubscriptionNotice(value)
        }

        // Removal Notice
        .onChange(of: viewModel.state.isShowingRemovalNotice) { value in
            isShowingRemovalNotice = value
        }
        .onChange(of: isShowingRemovalNotice) { value in
            viewModel.displayRemovalNotice(value)
        }

        // FAQ
        .onChange(of: viewModel.state.isShowingFAQView) { value in
            isShowingFAQView = value
        }
        .onChange(of: isShowingFAQView) { value in
            viewModel.displayFAQView(value)
        }

        // Learn More
        .onChange(of: viewModel.state.isShowingLearnMoreView) { value in
            isShowingLearnMoreView = value
        }
        .onChange(of: isShowingLearnMoreView) { value in
            viewModel.displayLearnMoreView(value)
        }

        // Connection Error
        .onChange(of: viewModel.state.isShowingConnectionError) { value in
            isShowingConnectionError = value
        }
        .onChange(of: isShowingConnectionError) { value in
            viewModel.showConnectionError(value)
        }

        .onChange(of: isShowingManageEmailView) { value in
            if value {
                if let email = viewModel.state.subscriptionEmail, !email.isEmpty {
                    Pixel.fire(pixel: .privacyProSubscriptionManagementEmail, debounce: 1)
                }
            }
        }

        .onReceive(subscriptionNavigationCoordinator.$shouldPopToSubscriptionSettings) { shouldDismiss in
            if shouldDismiss {
                isShowingActivationView = false
                isShowingManageEmailView = false
            }
        }

        .alert(isPresented: $isShowingConnectionError) {
            Alert(
                title: Text(UserText.subscriptionBackendErrorTitle),
                message: Text(UserText.subscriptionBackendErrorMessage),
                dismissButton: .cancel(Text(UserText.subscriptionBackendErrorButton)) {
                    dismiss()
                }
            )
        }

        .sheet(isPresented: $isShowingFAQView, content: {
            SubscriptionExternalLinkView(viewModel: viewModel.state.faqViewModel, title: UserText.subscriptionFAQ)
        })

        .sheet(isPresented: $isShowingLearnMoreView, content: {
            SubscriptionExternalLinkView(viewModel: viewModel.state.learnMoreViewModel, title: UserText.subscriptionFAQ)
        })

        .onFirstAppear {
            viewModel.onFirstAppear()
        }

    }

    @ViewBuilder
    private var stripeView: some View {
        if let stripeViewModel = viewModel.state.stripeViewModel {
            SubscriptionExternalLinkView(viewModel: stripeViewModel)
        }
    }
}

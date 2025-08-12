//
//  SettingsRootView.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import SwiftUI
import UIKit
import DataBrokerProtection_iOS
import DesignResourcesKit
import Subscription

struct SettingsRootView: View {

    @StateObject var viewModel: SettingsViewModel
    @Environment(\.presentationMode) var presentationMode

    @State private var subscriptionNavigationCoordinator = SubscriptionNavigationCoordinator()
    @State private var shouldDisplayDeepLinkSheet: Bool = false
    @State private var shouldDisplayDeepLinkPush: Bool = false
    @State var deepLinkTarget: SettingsViewModel.SettingsDeepLinkSection?
    @State var isShowingSubscribeFlow = false

    private var settingPrivacyProRedirectURLComponents: URLComponents? {
        SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.appSettings.rawValue)
    }

    var body: some View {

        // Hidden navigationLinks for programatic navigation
        if let target = deepLinkTarget {
            NavigationLink(destination: navigationDestinationView(for: target),
                           isActive: $shouldDisplayDeepLinkPush) {
                EmptyView()
            }
        }

        NavigationLink(destination: navigationDestinationView(for: .subscriptionFlow(redirectURLComponents: settingPrivacyProRedirectURLComponents)),
                       isActive: $isShowingSubscribeFlow) { EmptyView() }

        List {
            if #available(iOS 18.2, *) {
                if viewModel.shouldShowSetAsDefaultBrowser || viewModel.shouldShowImportPasswords {
                    SettingsCompleteSetupView()
                        .listRowBackground(Color(designSystemColor: .surface))
                }
            }
            SettingsPrivacyProtectionsView()
                .listRowBackground(Color(designSystemColor: .surface))
            SettingsSubscriptionView().environmentObject(subscriptionNavigationCoordinator)
                .listRowBackground(Color(designSystemColor: .surface))
            SettingsMainSettingsView()
                .listRowBackground(Color(designSystemColor: .surface))
            SettingsNextStepsView()
                .listRowBackground(Color(designSystemColor: .surface))
            SettingsOthersView()
                .listRowBackground(Color(designSystemColor: .surface))
            SettingsDebugView()
                .listRowBackground(Color(designSystemColor: .surface))
        }
        .navigationBarTitle(UserText.settingsTitle, displayMode: .inline)
        .navigationBarItems(trailing: Button(UserText.navigationTitleDone) {
            viewModel.onRequestDismissSettings?()
        })
        .accentColor(Color(designSystemColor: .textPrimary))
        .environmentObject(viewModel)
        .conditionalInsetGroupedListStyle()
        .onAppear {
            viewModel.onAppear()
        }

        // MARK: Deeplink Modifiers

        .sheet(isPresented: $shouldDisplayDeepLinkSheet, onDismiss: {
            viewModel.onAppear()
            shouldDisplayDeepLinkSheet = false
        }, content: {
            if let target = deepLinkTarget {
                navigationDestinationView(for: target)
            }
        })

        .onReceive(viewModel.$deepLinkTarget.removeDuplicates(), perform: { link in
            guard let link else {
                return
            }

            // Check if navigation is valid before triggering it
            if case .subscriptionSettings = link, !canNavigateToSubscriptionSettings() {
                // Don't navigate if there's no valid subscription settings to show
                return
            }

            self.deepLinkTarget = link

            switch link.type {
            case .sheet:
                DispatchQueue.main.async {
                    self.shouldDisplayDeepLinkSheet = true
                }
            case .navigationLink:
                DispatchQueue.main.async {
                    self.shouldDisplayDeepLinkPush = true
                }
            }
        })

        .onReceive(subscriptionNavigationCoordinator.$shouldPopToAppSettings) { shouldDismiss in
            if shouldDismiss {
                shouldDisplayDeepLinkSheet = false
                shouldDisplayDeepLinkPush = false
            }
        }
        .onReceive(subscriptionNavigationCoordinator.$shouldPushSubscriptionWebView) { shouldPush in
            isShowingSubscribeFlow = shouldPush
        }
    }

    @ViewBuilder func subscriptionFlowNavigationDestination(redirectURLComponents: URLComponents?) -> some View {
        if viewModel.isAuthV2Enabled {
            SubscriptionContainerViewFactory.makeSubscribeFlowV2(redirectURLComponents: redirectURLComponents,
                                                                 navigationCoordinator: subscriptionNavigationCoordinator,
                                                                 subscriptionManager: AppDependencyProvider.shared.subscriptionManagerV2!,
                                                                 subscriptionFeatureAvailability: viewModel.subscriptionFeatureAvailability,
                                                                 privacyProDataReporter: viewModel.privacyProDataReporter,
                                                                 tld: AppDependencyProvider.shared.storageCache.tld,
                                                                 internalUserDecider: AppDependencyProvider.shared.internalUserDecider)
        } else {
            SubscriptionContainerViewFactory.makeSubscribeFlow(redirectURLComponents: redirectURLComponents,
                                                               navigationCoordinator: subscriptionNavigationCoordinator,
                                                               subscriptionManager: AppDependencyProvider.shared.subscriptionManager!,
                                                               subscriptionFeatureAvailability: viewModel.subscriptionFeatureAvailability,
                                                               privacyProDataReporter: viewModel.privacyProDataReporter,
                                                               tld: AppDependencyProvider.shared.storageCache.tld,
                                                               internalUserDecider: AppDependencyProvider.shared.internalUserDecider)
        }
    }

    @ViewBuilder func emailFlowNavigationDestination() -> some View {
        if viewModel.isAuthV2Enabled {
            SubscriptionContainerViewFactory.makeEmailFlowV2(navigationCoordinator: subscriptionNavigationCoordinator,
                                                             subscriptionManager: AppDependencyProvider.shared.subscriptionManagerV2!,
                                                             subscriptionFeatureAvailability: viewModel.subscriptionFeatureAvailability,
                                                             internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                                                             emailFlow: .restoreFlow,
                                                             onDisappear: {})
        } else {
            SubscriptionContainerViewFactory.makeEmailFlow(navigationCoordinator: subscriptionNavigationCoordinator,
                                                           subscriptionManager: AppDependencyProvider.shared.subscriptionManager!,
                                                           subscriptionFeatureAvailability: viewModel.subscriptionFeatureAvailability,
                                                           internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                                                           emailFlow: .restoreFlow,
                                                           onDisappear: {})
        }
    }

    /// Determines the subscription settings view configuration based on current subscription state
    private func subscriptionSettingsConfiguration() -> SubscriptionSettingsViewConfiguration? {
        let isSignedIn = viewModel.state.subscription.isSignedIn
        let hasSubscription = viewModel.state.subscription.hasSubscription
        let hasActiveSubscription = viewModel.state.subscription.hasActiveSubscription
        let hasAnyEntitlements = !viewModel.state.subscription.entitlements.isEmpty
        let isActiveTrialOffer = viewModel.state.subscription.isActiveTrialOffer

        // Signed out - no configuration needed
        guard isSignedIn else { return nil }

        // Signed in, no subscription
        guard hasSubscription else { return .activating }

        // Signed in, has subscription but not active
        guard hasActiveSubscription else { return .expired }

        // Signed in, active subscription but no entitlements
        guard hasAnyEntitlements else { return .activating }

        // Signed in, active subscription with entitlements
        // Check if it's a trial or regular subscription
        return isActiveTrialOffer ? .trial : .subscribed
    }

    /// Checks if navigation to subscription settings is valid
    private func canNavigateToSubscriptionSettings() -> Bool {
        return subscriptionSettingsConfiguration() != nil && viewModel.isAuthV2Enabled
    }

    /// Navigation Views for DeepLink and programmatic navigation
    @ViewBuilder func navigationDestinationView(for target: SettingsViewModel.SettingsDeepLinkSection) -> some View {
        switch target {
        case .dbp:
            if viewModel.isPIREnabled,
               let dbpManager = DataBrokerProtectionIOSManager.shared {
                DataBrokerProtectionViewControllerRepresentation(dbpViewControllerProvider: dbpManager)
            } else {
                SubscriptionPIRMoveToDesktopView()
            }
        case .itr:
            SubscriptionITPView()
        case let .subscriptionFlow(redirectURLComponents):
            subscriptionFlowNavigationDestination(redirectURLComponents: redirectURLComponents)
                .environmentObject(subscriptionNavigationCoordinator)
        case .restoreFlow:
            emailFlowNavigationDestination()
        case .duckPlayer:
            SettingsDuckPlayerView().environmentObject(viewModel)
        case .netP:
            NetworkProtectionRootView()
        case .aiChat:
            SettingsAIFeaturesView().environmentObject(viewModel)
        case .subscriptionSettings:
            if let configuration = subscriptionSettingsConfiguration() {
                SubscriptionSettingsViewV2(configuration: configuration, settingsViewModel: viewModel)
                    .environmentObject(subscriptionNavigationCoordinator)
            }
        }
    }
}

struct InsetGroupedListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        return AnyView(content.applyInsetGroupedListStyle())
    }
}

struct SettingsListModifiers: ViewModifier {
    @EnvironmentObject var viewModel: SettingsViewModel
    let title: String?
    let displayMode: NavigationBarItem.TitleDisplayMode

    func body(content: Content) -> some View {
        content
            .navigationBarTitle(title ?? "", displayMode: displayMode)
            .accentColor(Color(designSystemColor: .textPrimary))
            .environmentObject(viewModel)
            .conditionalInsetGroupedListStyle()
    }
}

extension View {
    func conditionalInsetGroupedListStyle() -> some View {
        self.modifier(InsetGroupedListStyleModifier())
    }

    func applySettingsListModifiers(title: String? = nil, displayMode: NavigationBarItem.TitleDisplayMode = .inline, viewModel: SettingsViewModel) -> some View {
        self.modifier(SettingsListModifiers(title: title, displayMode: displayMode))
            .environmentObject(viewModel)
    }
}

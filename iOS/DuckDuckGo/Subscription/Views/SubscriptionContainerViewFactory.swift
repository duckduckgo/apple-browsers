//
//  SubscriptionContainerViewFactory.swift
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

import SwiftUI
import Subscription
import Common
import BrowserServicesKit
import DataBrokerProtection_iOS

enum SubscriptionContainerViewFactory {

    static func makeSubscribeFlow(redirectURLComponents: URLComponents?,
                                  navigationCoordinator: SubscriptionNavigationCoordinator,
                                  subscriptionManager: SubscriptionManager,
                                  subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                  privacyProDataReporter: PrivacyProDataReporting?,
                                  tld: TLD,
                                  internalUserDecider: InternalUserDecider,
                                  dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?) -> some View {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                             storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                             subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                             authEndpointService: subscriptionManager.authEndpointService)
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                               accountManager: subscriptionManager.accountManager,
                                                               appStoreRestoreFlow: appStoreRestoreFlow,
                                                               authEndpointService: subscriptionManager.authEndpointService)
        let appStoreAccountManagementFlow = DefaultAppStoreAccountManagementFlow(authEndpointService: subscriptionManager.authEndpointService,
                                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                                 accountManager: subscriptionManager.accountManager)

        let redirectPurchaseURL: URL? = {
            guard let redirectURLComponents else { return nil }
            return subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: tld)
        }()

        let origin = redirectURLComponents?.url?.getParameter(named: AttributionParameter.origin)

        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            redirectPurchaseURL: redirectPurchaseURL,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                                       subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                       subscriptionAttributionOrigin: origin,
                                                                       appStorePurchaseFlow: appStorePurchaseFlow,
                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                       appStoreAccountManagementFlow: appStoreAccountManagementFlow,
                                                                       privacyProDataReporter: privacyProDataReporter),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider
        )
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .subscribe, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }

    static func makeRestoreFlow(navigationCoordinator: SubscriptionNavigationCoordinator,
                                subscriptionManager: SubscriptionManager,
                                subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                internalUserDecider: InternalUserDecider,
                                dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?) -> some View {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                             storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                             subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                             authEndpointService: subscriptionManager.authEndpointService)
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                               accountManager: subscriptionManager.accountManager,
                                                               appStoreRestoreFlow: appStoreRestoreFlow,
                                                               authEndpointService: subscriptionManager.authEndpointService)
        let appStoreAccountManagementFlow = DefaultAppStoreAccountManagementFlow(authEndpointService: subscriptionManager.authEndpointService,
                                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                                 accountManager: subscriptionManager.accountManager)

        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                                       subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                       subscriptionAttributionOrigin: nil,
                                                                       appStorePurchaseFlow: appStorePurchaseFlow,
                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                       appStoreAccountManagementFlow: appStoreAccountManagementFlow),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider
        )
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .restore, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }

    static func makeEmailFlow(navigationCoordinator: SubscriptionNavigationCoordinator,
                              subscriptionManager: SubscriptionManager,
                              subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                              internalUserDecider: InternalUserDecider,
                              emailFlow: SubscriptionEmailViewModel.EmailViewFlow = .activationFlow,
                              dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                              onDisappear: @escaping () -> Void) -> some View {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                             storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                             subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                             authEndpointService: subscriptionManager.authEndpointService)
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                               accountManager: subscriptionManager.accountManager,
                                                               appStoreRestoreFlow: appStoreRestoreFlow,
                                                               authEndpointService: subscriptionManager.authEndpointService)
        let appStoreAccountManagementFlow = DefaultAppStoreAccountManagementFlow(authEndpointService: subscriptionManager.authEndpointService,
                                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                                 accountManager: subscriptionManager.accountManager)
        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                                       subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                       subscriptionAttributionOrigin: nil,
                                                                       appStorePurchaseFlow: appStorePurchaseFlow,
                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                       appStoreAccountManagementFlow: appStoreAccountManagementFlow),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider
        )

        viewModel.email.setEmailFlowMode(emailFlow)

        return SubscriptionContainerView(currentView: .email, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
            .onDisappear(perform: { onDisappear() })
    }

    // MARK: - V2

    static func makeSubscribeFlowV2(redirectURLComponents: URLComponents?,
                                    navigationCoordinator: SubscriptionNavigationCoordinator,
                                    subscriptionManager: SubscriptionManagerV2,
                                    subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                    privacyProDataReporter: PrivacyProDataReporting?,
                                    tld: TLD,
                                    internalUserDecider: InternalUserDecider,
                                    dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?) -> some View {

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager())
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow)

        let redirectPurchaseURL: URL? = {
            guard let redirectURLComponents else { return nil }
            return subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: tld)
        }()

        let origin = redirectURLComponents?.url?.getParameter(named: AttributionParameter.origin)


        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            redirectPurchaseURL: redirectPurchaseURL,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                         subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                         subscriptionAttributionOrigin: origin,
                                                                         appStorePurchaseFlow: appStorePurchaseFlow,
                                                                         appStoreRestoreFlow: appStoreRestoreFlow,
                                                                         privacyProDataReporter: privacyProDataReporter,
                                                                         internalUserDecider: internalUserDecider),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider
        )
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .subscribe, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }


    static func makeRestoreFlowV2(navigationCoordinator: SubscriptionNavigationCoordinator,
                                  subscriptionManager: SubscriptionManagerV2,
                                  subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                  internalUserDecider: InternalUserDecider,
                                  dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?) -> some View {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager())
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow)
        let subscriptionPagesUseSubscriptionFeature = DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                                                       subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                                                       subscriptionAttributionOrigin: nil,
                                                                                                       appStorePurchaseFlow: appStorePurchaseFlow,
                                                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                                                       internalUserDecider: internalUserDecider)
        let viewModel = SubscriptionContainerViewModel(subscriptionManager: subscriptionManager,
                                                       isInternalUser: internalUserDecider.isInternalUser,
                                                       userScript: SubscriptionPagesUserScript(),
                                                       subFeature: subscriptionPagesUseSubscriptionFeature,
                                                       dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider)
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .restore, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }

    static func makeEmailFlowV2(navigationCoordinator: SubscriptionNavigationCoordinator,
                                subscriptionManager: SubscriptionManagerV2,
                                subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                internalUserDecider: InternalUserDecider,
                                emailFlow: SubscriptionEmailViewModel.EmailViewFlow = .activationFlow,
                                dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                onDisappear: @escaping () -> Void) -> some View {
        let appStoreRestoreFlow: AppStoreRestoreFlowV2 = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                                      storePurchaseManager: subscriptionManager.storePurchaseManager())
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow)
        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                         subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                         subscriptionAttributionOrigin: nil,
                                                                         appStorePurchaseFlow: appStorePurchaseFlow,
                                                                         appStoreRestoreFlow: appStoreRestoreFlow,
                                                                         internalUserDecider: internalUserDecider),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider
        )

        viewModel.email.setEmailFlowMode(emailFlow)
        
        return SubscriptionContainerView(currentView: .email, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
            .onDisappear(perform: { onDisappear() })
    }
}

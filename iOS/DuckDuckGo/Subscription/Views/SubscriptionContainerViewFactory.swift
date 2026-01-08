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
import PrivacyConfig
import DataBrokerProtection_iOS
import PixelKit

enum SubscriptionContainerViewFactory {

    static func makeSubscribeFlowV2(redirectURLComponents: URLComponents?,
                                    navigationCoordinator: SubscriptionNavigationCoordinator,
                                    subscriptionManager: SubscriptionManagerV2,
                                    subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                    subscriptionDataReporter: SubscriptionDataReporting?,
                                    userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                    tld: TLD,
                                    internalUserDecider: InternalUserDecider,
                                    dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                    wideEvent: WideEventManaging) -> some View {

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager())
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow,
                                                                 wideEvent: wideEvent)

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
            userScriptsDependencies: userScriptsDependencies,
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                         subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                         subscriptionAttributionOrigin: origin,
                                                                         appStorePurchaseFlow: appStorePurchaseFlow,
                                                                         appStoreRestoreFlow: appStoreRestoreFlow,
                                                                         subscriptionDataReporter: subscriptionDataReporter,
                                                                         internalUserDecider: internalUserDecider,
                                                                         wideEvent: wideEvent),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider
        )
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .subscribe, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }


    static func makeRestoreFlowV2(navigationCoordinator: SubscriptionNavigationCoordinator,
                                  subscriptionManager: SubscriptionManagerV2,
                                  subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                  userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                  internalUserDecider: InternalUserDecider,
                                  wideEvent: WideEventManaging,
                                  dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?) -> some View {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager())
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow,
                                                                 wideEvent: wideEvent)
        let subscriptionPagesUseSubscriptionFeature = DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                                                       subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                                                       subscriptionAttributionOrigin: nil,
                                                                                                       appStorePurchaseFlow: appStorePurchaseFlow,
                                                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                                                       internalUserDecider: internalUserDecider,
                                                                                                       wideEvent: wideEvent)
        let viewModel = SubscriptionContainerViewModel(subscriptionManager: subscriptionManager,
                                                       isInternalUser: internalUserDecider.isInternalUser,
                                                       userScript: SubscriptionPagesUserScript(),
                                                       userScriptsDependencies: userScriptsDependencies,
                                                       subFeature: subscriptionPagesUseSubscriptionFeature,
                                                       dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider)
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .restore, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }

    static func makePlansFlowV2(redirectURLComponents: URLComponents?,
                                navigationCoordinator: SubscriptionNavigationCoordinator,
                                subscriptionManager: SubscriptionManagerV2,
                                subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                internalUserDecider: InternalUserDecider,
                                dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                wideEvent: WideEventManaging) -> some View {

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager())
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow,
                                                                 wideEvent: wideEvent)

        let origin = redirectURLComponents?.url?.getParameter(named: AttributionParameter.origin)

        // Build plans URL from subscription manager (respects custom base URL)
        // and preserve all query parameters from redirectURLComponents
        var plansURL = subscriptionManager.url(for: .plans)
        if let queryItems = redirectURLComponents?.queryItems {
            for item in queryItems {
                if let value = item.value {
                    plansURL = plansURL.appendingParameter(name: item.name, value: value)
                }
            }
        }

        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            redirectPurchaseURL: plansURL,
            flowType: .planUpdate,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            userScriptsDependencies: userScriptsDependencies,
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                         subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                         subscriptionAttributionOrigin: origin,
                                                                         appStorePurchaseFlow: appStorePurchaseFlow,
                                                                         appStoreRestoreFlow: appStoreRestoreFlow,
                                                                         internalUserDecider: internalUserDecider,
                                                                         wideEvent: wideEvent),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider
        )
        return SubscriptionContainerView(currentView: .subscribe, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }

    static func makeEmailFlowV2(navigationCoordinator: SubscriptionNavigationCoordinator,
                                subscriptionManager: SubscriptionManagerV2,
                                subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                internalUserDecider: InternalUserDecider,
                                emailFlow: SubscriptionEmailViewModel.EmailViewFlow = .activationFlow,
                                dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                wideEvent: WideEventManaging,
                                onDisappear: @escaping () -> Void) -> some View {
        let appStoreRestoreFlow: AppStoreRestoreFlowV2 = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                                      storePurchaseManager: subscriptionManager.storePurchaseManager())
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow,
                                                                 wideEvent: wideEvent)
        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            userScriptsDependencies: userScriptsDependencies,
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                         subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                         subscriptionAttributionOrigin: nil,
                                                                         appStorePurchaseFlow: appStorePurchaseFlow,
                                                                         appStoreRestoreFlow: appStoreRestoreFlow,
                                                                         internalUserDecider: internalUserDecider,
                                                                         wideEvent: wideEvent),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider
        )

        viewModel.email.setEmailFlowMode(emailFlow)
        
        return SubscriptionContainerView(currentView: .email, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
            .onDisappear(perform: { onDisappear() })
    }
}

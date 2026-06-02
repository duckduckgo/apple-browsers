//
//  SubscriptionBridgePlaygroundFeature.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Core
import Foundation
import PixelKit
import Subscription
import UserScript

struct SubscriptionBridgePlaygroundFeature: JSBridgePlaygroundFeature {

    let displayName = "Subscription Expiration Notification"
    let messageHandlerName = SubscriptionPagesUserScript.context
    let messageContext = SubscriptionPagesUserScript.context
    let featureName = SubscriptionPagesUseSubscriptionFeatureConstants.featureName

    var baseURL: URL {
        AppDependencyProvider.shared.subscriptionManager.url(for: .baseURL)
    }

    var knownMethods: [JSBridgePlaygroundMethod] {
        [
            JSBridgePlaygroundMethod(name: "getUserSettings", sampleParamsJSON: "{}"),
            JSBridgePlaygroundMethod(name: "requestNotificationsPermission", sampleParamsJSON: "{}"),
            JSBridgePlaygroundMethod(
                name: "subscriptionSelected",
                sampleParamsJSON: #"{"id": "ddg.privacy.pro.monthly.renews.us", "scheduleNotification": {"daysBeforeCancel": 3}}"#
            )
        ]
    }

    @MainActor
    func makeUserScripts() -> [UserScript] {
        let subscriptionManager = AppDependencyProvider.shared.subscriptionManager
        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!

        let pendingTransactionHandler = DefaultPendingTransactionHandler(
            userDefaults: subscriptionUserDefaults,
            pixelHandler: SubscriptionPixelHandler(source: .mainApp, pixelKit: nil)
        )
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(
            subscriptionManager: subscriptionManager,
            storePurchaseManager: subscriptionManager.storePurchaseManager(),
            pendingTransactionHandler: pendingTransactionHandler
        )
        let appStorePurchaseFlow = PlaygroundMockAppStorePurchaseFlow()
        let subscriptionFeatureAvailability = BrowserServicesKit.DefaultSubscriptionFeatureAvailability(
            privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager,
            purchasePlatform: .appStore,
            featureFlagProvider: SubscriptionPageFeatureFlagAdapter(featureFlagger: AppDependencyProvider.shared.featureFlagger)
        )
        let subscriptionFlowsExecuter = DefaultSubscriptionFlowsExecuter(
            subscriptionManager: subscriptionManager,
            appStorePurchaseFlow: appStorePurchaseFlow,
            wideEvent: AppDependencyProvider.shared.wideEvent,
            pendingTransactionHandler: pendingTransactionHandler
        )
        let subFeature = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: subscriptionManager,
            subscriptionFeatureAvailability: subscriptionFeatureAvailability,
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: appStorePurchaseFlow,
            appStoreRestoreFlow: appStoreRestoreFlow,
            internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
            wideEvent: AppDependencyProvider.shared.wideEvent,
            pendingTransactionHandler: pendingTransactionHandler,
            subscriptionFlowsExecuter: subscriptionFlowsExecuter,
            requestValidator: DefaultScriptRequestValidator(subscriptionManager: subscriptionManager),
            expirationReminderScheduler: AppDependencyProvider.shared.subscriptionExpirationReminderScheduler
        )

        let userScript = SubscriptionPagesUserScript()
        userScript.registerSubfeature(delegate: subFeature)
        return [userScript]
    }
}

/// Mock that drives the production purchase handler down the success path so the
/// scheduler integration can be exercised without StoreKit.
private final class PlaygroundMockAppStorePurchaseFlow: AppStorePurchaseFlow {

    func purchaseSubscription(with subscriptionIdentifier: String, includeProTier: Bool) async -> Result<PurchaseResult, AppStorePurchaseFlowError> {
        .success((transactionJWS: "playground-mock-jws", accountCreationDuration: nil))
    }

    func completeSubscriptionPurchase(with transactionJWS: TransactionJWS, additionalParams: [String: String]?) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError> {
        .success(PurchaseUpdate.completed)
    }

    func changeTier(to subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
        .success("playground-mock-jws")
    }
}


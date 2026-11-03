//
//  SubscriptionPagesUseSubscriptionFeatureDependencies.swift
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

import Foundation
import Subscription
import BrowserServicesKit
import PrivacyConfig
import FoundationExtensions
import PixelKit
import WideEvent
import FeatureFlags_iOS

struct SubscriptionPagesUseSubscriptionFeatureDependencies {
    let pendingTransactionHandler: PendingTransactionHandling
    let appStoreRestoreFlow: AppStoreRestoreFlow
    let appStorePurchaseFlow: AppStorePurchaseFlow
    let subscriptionFlowsExecuter: DefaultSubscriptionFlowsExecuter

    static func make(subscriptionManager: SubscriptionManager, wideEvent: WideEventManaging) -> Self {
        let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup(bundle: .subs))!
        let pendingTransactionHandler = DefaultPendingTransactionHandler(userDefaults: userDefaults,
                                                                         pixelHandler: SubscriptionPixelHandler(source: .mainApp, pixelKit: PixelKit.shared))
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: subscriptionManager,
                                                             storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                             pendingTransactionHandler: pendingTransactionHandler)
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionManager: subscriptionManager,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                               appStoreRestoreFlow: appStoreRestoreFlow,
                                                               wideEvent: wideEvent,
                                                               pendingTransactionHandler: pendingTransactionHandler)
        let subscriptionFlowsExecuter = DefaultSubscriptionFlowsExecuter(subscriptionManager: subscriptionManager,
                                                                         appStorePurchaseFlow: appStorePurchaseFlow,
                                                                         wideEvent: wideEvent,
                                                                         pendingTransactionHandler: pendingTransactionHandler)
        return Self(pendingTransactionHandler: pendingTransactionHandler,
                    appStoreRestoreFlow: appStoreRestoreFlow,
                    appStorePurchaseFlow: appStorePurchaseFlow,
                    subscriptionFlowsExecuter: subscriptionFlowsExecuter)
    }
}

extension DefaultSubscriptionPagesUseSubscriptionFeature {

    static func make(configuration: SubscriptionFlowConfiguration,
                     subscriptionDataReporter: SubscriptionDataReporting?,
                     context: SubscriptionFlowContext) -> DefaultSubscriptionPagesUseSubscriptionFeature {
        let dependencies = SubscriptionPagesUseSubscriptionFeatureDependencies.make(subscriptionManager: context.subscriptionManager,
                                                                                   wideEvent: context.wideEvent)
        let schedulesExpirationReminders = configuration.schedulesExpirationReminders
        let featureFlagger = context.featureFlagger
        return DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: context.subscriptionManager,
            subscriptionFeatureAvailability: context.subscriptionFeatureAvailability,
            subscriptionAttributionOrigin: configuration.subscriptionAttributionOrigin,
            planChangeEntry: configuration.planChangeEntry,
            appStorePurchaseFlow: dependencies.appStorePurchaseFlow,
            appStoreRestoreFlow: dependencies.appStoreRestoreFlow,
            subscriptionDataReporter: subscriptionDataReporter,
            internalUserDecider: context.internalUserDecider,
            wideEvent: context.wideEvent,
            pendingTransactionHandler: dependencies.pendingTransactionHandler,
            subscriptionFlowsExecuter: dependencies.subscriptionFlowsExecuter,
            requestValidator: DefaultScriptRequestValidator(subscriptionManager: context.subscriptionManager),
            expirationReminderScheduler: schedulesExpirationReminders ? AppDependencyProvider.shared.subscriptionExpirationReminderScheduler : nil,
            isExpirationReminderFeatureEnabled: {
                schedulesExpirationReminders && featureFlagger.isFeatureOn(.subscriptionExpirationReminderNotification)
            },
            subscriptionExperimentAttributionProvider: DefaultSubscriptionExperimentAttributionProvider(featureFlagger: featureFlagger))
    }
}

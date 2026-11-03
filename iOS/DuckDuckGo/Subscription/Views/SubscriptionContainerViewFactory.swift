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

enum SubscriptionContainerViewFactory {

    static func makeView(for flow: SubscriptionFlow,
                         context: SubscriptionFlowContext,
                         navigationCoordinator: SubscriptionNavigationCoordinator) -> some View {
        SubscriptionContainerView(currentView: flow.currentView,
                                  viewModel: makeViewModel(for: flow, context: context),
                                  featureFlagger: context.featureFlagger)
            .environmentObject(navigationCoordinator)
    }

    static func makeViewModel(for flow: SubscriptionFlow, context: SubscriptionFlowContext) -> SubscriptionContainerViewModel {
        let configuration = flow.configuration(subscriptionManager: context.subscriptionManager, featureFlagger: context.featureFlagger)
        let purchaseDependencies = flow.purchaseDependencies
        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: context.subscriptionManager,
            initialURL: configuration.initialURL,
            flowType: configuration.flowType,
            isInternalUser: context.internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            userScriptsDependencies: context.userScriptsDependencies,
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeature.make(configuration: configuration,
                                                                             subscriptionDataReporter: purchaseDependencies?.subscriptionDataReporter,
                                                                             context: context),
            dataBrokerProtectionViewControllerProvider: context.dataBrokerProtectionViewControllerProvider,
            onboardingKeyValueStore: purchaseDependencies?.onboardingKeyValueStore,
            meetsPIRLocaleRequirement: purchaseDependencies?.meetsPIRLocaleRequirement ?? { false },
            onRequestDuckAIChat: purchaseDependencies?.onRequestDuckAIChat
        )
        if let emailFlowMode = flow.emailFlowMode {
            viewModel.email.setEmailFlowMode(emailFlowMode)
        }
        return viewModel
    }
}

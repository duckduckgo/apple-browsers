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
import PrivacyConfig

/// The flows the container can show. Associated values are inputs only the caller knows for this call.
enum SubscriptionFlow {
    case subscribe(redirectURLComponents: URLComponents?, landingURL: URL? = nil, dependencies: SubscriptionPurchaseDependencies)
    case plans(redirectURLComponents: URLComponents?)
    case restore
    case email(SubscriptionEmailViewModel.EmailViewFlow)

    static func makePlanOrSubscribeFlow(redirectURLComponents: URLComponents?, dependencies: SubscriptionPurchaseDependencies) -> SubscriptionFlow {
        if let redirectURLComponents, SubscriptionPurchaseFlowPath.isPlansPath(redirectURLComponents.path) {
            return .plans(redirectURLComponents: redirectURLComponents)
        }
        return .subscribe(redirectURLComponents: redirectURLComponents, dependencies: dependencies)
    }

    var containerView: SubscriptionContainerView.CurrentViewType {
        switch self {
        case .subscribe, .plans: return .subscriptionFlowView
        case .restore: return .restoreView
        case .email: return .emailView
        }
    }

    func configuration(subscriptionManager: SubscriptionManager, featureFlagger: FeatureFlagger) -> SubscriptionFlowConfiguration {
        switch self {
        case let .subscribe(redirectURLComponents, landingURL, dependencies):
            return .subscribe(redirectURLComponents: redirectURLComponents,
                              landingURL: landingURL,
                              subscriptionManager: subscriptionManager,
                              tld: dependencies.tld,
                              performanceOptimizedPaywalls: dependencies.performanceOptimizedPaywallsProvider,
                              featureFlagger: featureFlagger,
                              isDebugOverlayEnabled: dependencies.isDebugOverlayEnabled)
        case let .plans(redirectURLComponents):
            return .plans(redirectURLComponents: redirectURLComponents, subscriptionManager: subscriptionManager)
        case .restore:
            return .restore()
        case let .email(emailScreenMode):
            return .email(emailScreenMode)
        }
    }
}

enum SubscriptionContainerViewFactory {

    static func makeView(for flow: SubscriptionFlow,
                         context: SubscriptionFlowContext,
                         navigationCoordinator: SubscriptionNavigationCoordinator) -> some View {
        SubscriptionContainerView(currentView: flow.containerView,
                                  viewModel: makeViewModel(for: flow, context: context),
                                  featureFlagger: context.featureFlagger)
            .environmentObject(navigationCoordinator)
    }

    static func makeViewModel(for flow: SubscriptionFlow, context: SubscriptionFlowContext) -> SubscriptionContainerViewModel {
        let purchaseDependencies: SubscriptionPurchaseDependencies?
        switch flow {
        case let .subscribe(_, _, dependencies): purchaseDependencies = dependencies
        case .plans, .restore, .email: purchaseDependencies = nil
        }
        let configuration = flow.configuration(subscriptionManager: context.subscriptionManager, featureFlagger: context.featureFlagger)
        return makeViewModel(configuration: configuration,
                             purchaseDependencies: purchaseDependencies,
                             context: context)
    }

    static func makeCancellationFlowViewModel(context: SubscriptionFlowContext) -> SubscriptionContainerViewModel {
        makeViewModel(configuration: .cancellation(subscriptionManager: context.subscriptionManager),
                      purchaseDependencies: nil,
                      context: context)
    }

    private static func makeViewModel(configuration: SubscriptionFlowConfiguration,
                                      purchaseDependencies: SubscriptionPurchaseDependencies?,
                                      context: SubscriptionFlowContext) -> SubscriptionContainerViewModel {
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
        if let emailScreenMode = configuration.emailScreenMode {
            viewModel.email.setEmailFlowMode(emailScreenMode)
        }
        return viewModel
    }
}

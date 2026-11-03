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
import FoundationExtensions
import BrowserServicesKit
import PrivacyConfig
import DataBrokerProtection_iOS
import PixelKit
import WideEvent
import FeatureFlags_iOS
import Persistence

enum SubscriptionContainerViewFactory {

    private static var subscriptionUserDefaults: UserDefaults {
        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        return UserDefaults(suiteName: subscriptionAppGroup)!
    }

    struct SubscriptionFlowDependencies {
        let pendingTransactionHandler: PendingTransactionHandling
        let appStoreRestoreFlow: AppStoreRestoreFlow
        let appStorePurchaseFlow: AppStorePurchaseFlow
        let subscriptionFlowsExecuter: DefaultSubscriptionFlowsExecuter

        static func make(subscriptionManager: SubscriptionManager, wideEvent: WideEventManaging) -> Self {
            let pendingTransactionHandler = DefaultPendingTransactionHandler(userDefaults: SubscriptionContainerViewFactory.subscriptionUserDefaults,
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

    struct SubscriptionFlowConfiguration: Equatable {
        var initialURL: URL?
        var flowType: SubscriptionFlowType = .firstPurchase
        var subscriptionAttributionOrigin: String?
        var planChangeEntry: String?
        var schedulesExpirationReminders = true

        static func subscribe(redirectURLComponents: URLComponents?,
                              landingURL: URL?,
                              subscriptionManager: SubscriptionManager,
                              tld: TLD,
                              performanceOptimizedPaywalls: any PerformanceOptimizedPaywallsProviding,
                              featureFlagger: FeatureFlagger,
                              isDebugOverlayEnabled: Bool) -> Self {
            var initialURL = SubscribeFlowInitialURLBuilder.makeInitialURL(redirectURLComponents: redirectURLComponents,
                                                                           landingURL: landingURL,
                                                                           subscriptionManager: subscriptionManager,
                                                                           tld: tld,
                                                                           performanceOptimizedPaywalls: performanceOptimizedPaywalls,
                                                                           featureFlagger: featureFlagger)
            if isDebugOverlayEnabled {
                initialURL = initialURL.appendingParameter(name: "debug", value: "1")
            }
            return Self(initialURL: initialURL,
                        subscriptionAttributionOrigin: queryValue(named: AttributionParameter.origin, in: redirectURLComponents))
        }

        static func plans(redirectURLComponents: URLComponents?, subscriptionManager: SubscriptionManager) -> Self {
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
            return Self(initialURL: plansURL,
                        flowType: .planUpdate,
                        subscriptionAttributionOrigin: queryValue(named: AttributionParameter.origin, in: redirectURLComponents),
                        planChangeEntry: queryValue(named: SubscriptionURL.PlanChangeParameter.entry, in: redirectURLComponents))
        }

        static func cancellation(subscriptionManager: SubscriptionManager) -> Self {
            Self(initialURL: subscriptionManager.url(for: .cancellationFlow),
                 flowType: .cancellation,
                 planChangeEntry: SubscriptionPlanChangeOrigin.cancellationFlow.rawValue,
                 schedulesExpirationReminders: false)
        }

        private static func queryValue(named name: String, in redirectURLComponents: URLComponents?) -> String? {
            redirectURLComponents?.queryItems?.first(where: { $0.name == name })?.value
        }
    }

    struct SubscriptionFlowContext {
        let subscriptionManager: SubscriptionManager
        let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
        let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
        let internalUserDecider: InternalUserDecider
        let dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?
        let wideEvent: WideEventManaging
        let featureFlagger: FeatureFlagger
    }

    struct PurchaseOptions {
        let subscriptionDataReporter: SubscriptionDataReporting?
        let tld: TLD
        let isDebugOverlayEnabled: Bool
        let performanceOptimizedPaywallsProvider: any PerformanceOptimizedPaywallsProviding
        let onboardingKeyValueStore: ThrowingKeyValueStoring?
        let meetsPIRLocaleRequirement: () -> Bool
        let onRequestDuckAIChat: ((String?) -> Bool)?
    }

    enum SubscriptionFlow {
        case subscribe(redirectURLComponents: URLComponents?, landingURL: URL? = nil, options: PurchaseOptions)
        case plans(redirectURLComponents: URLComponents?)
        case restore
        case email(SubscriptionEmailViewModel.EmailViewFlow)
        case cancellation

        static func makePlanChangeOrSubscribeFlow(redirectURLComponents: URLComponents?, options: PurchaseOptions) -> SubscriptionFlow {
            if let redirectURLComponents, SubscriptionPurchaseFlowPath.isPlansPath(redirectURLComponents.path) {
                return .plans(redirectURLComponents: redirectURLComponents)
            }
            return .subscribe(redirectURLComponents: redirectURLComponents, options: options)
        }

        var currentView: SubscriptionContainerView.CurrentViewType {
            switch self {
            case .restore: return .restore
            case .email: return .email
            case .subscribe, .plans, .cancellation: return .subscribe
            }
        }

        var emailFlowMode: SubscriptionEmailViewModel.EmailViewFlow? {
            switch self {
            case .subscribe, .restore: return .restoreFlow
            case .email(let emailFlow): return emailFlow
            case .plans, .cancellation: return nil
            }
        }

        var purchaseOptions: PurchaseOptions? {
            guard case let .subscribe(_, _, options) = self else { return nil }
            return options
        }

        func configuration(subscriptionManager: SubscriptionManager, featureFlagger: FeatureFlagger) -> SubscriptionFlowConfiguration {
            switch self {
            case let .subscribe(redirectURLComponents, landingURL, options):
                return .subscribe(redirectURLComponents: redirectURLComponents,
                                  landingURL: landingURL,
                                  subscriptionManager: subscriptionManager,
                                  tld: options.tld,
                                  performanceOptimizedPaywalls: options.performanceOptimizedPaywallsProvider,
                                  featureFlagger: featureFlagger,
                                  isDebugOverlayEnabled: options.isDebugOverlayEnabled)
            case let .plans(redirectURLComponents):
                return .plans(redirectURLComponents: redirectURLComponents, subscriptionManager: subscriptionManager)
            case .cancellation:
                return .cancellation(subscriptionManager: subscriptionManager)
            case .restore, .email:
                return SubscriptionFlowConfiguration()
            }
        }
    }

    /// Creates a tier-change performer for native cancel-pending-downgrade (Settings). Caller owns the instance.
    static func makeSubscriptionFlowsExecuter(subscriptionManager: SubscriptionManager,
                                              wideEvent: WideEventManaging) -> DefaultSubscriptionFlowsExecuter {
        SubscriptionFlowDependencies.make(subscriptionManager: subscriptionManager, wideEvent: wideEvent).subscriptionFlowsExecuter
    }

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
        let purchaseOptions = flow.purchaseOptions
        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: context.subscriptionManager,
            initialURL: configuration.initialURL,
            flowType: configuration.flowType,
            isInternalUser: context.internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            userScriptsDependencies: context.userScriptsDependencies,
            subFeature: makeSubscriptionFeature(configuration: configuration,
                                                subscriptionDataReporter: purchaseOptions?.subscriptionDataReporter,
                                                context: context),
            dataBrokerProtectionViewControllerProvider: context.dataBrokerProtectionViewControllerProvider,
            onboardingKeyValueStore: purchaseOptions?.onboardingKeyValueStore,
            meetsPIRLocaleRequirement: purchaseOptions?.meetsPIRLocaleRequirement ?? { false },
            onRequestDuckAIChat: purchaseOptions?.onRequestDuckAIChat
        )
        if let emailFlowMode = flow.emailFlowMode {
            viewModel.email.setEmailFlowMode(emailFlowMode)
        }
        return viewModel
    }

    private static func makeSubscriptionFeature(configuration: SubscriptionFlowConfiguration,
                                                subscriptionDataReporter: SubscriptionDataReporting?,
                                                context: SubscriptionFlowContext) -> DefaultSubscriptionPagesUseSubscriptionFeature {
        let dependencies = SubscriptionFlowDependencies.make(subscriptionManager: context.subscriptionManager, wideEvent: context.wideEvent)
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

enum SubscribeFlowInitialURLBuilder {

    static func makeInitialURL(redirectURLComponents: URLComponents?,
                               landingURL: URL?,
                               subscriptionManager: SubscriptionManager,
                               tld: TLD,
                               performanceOptimizedPaywalls: any PerformanceOptimizedPaywallsProviding,
                               featureFlagger: FeatureFlagger) -> URL {
        // A landing URL is an explicit destination, like the post-purchase welcome page, never a paywall.
        if let landingURL { return landingURL }

        let purchaseURL = redirectURLComponents.map {
            subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: $0, tld: tld)
        } ?? subscriptionManager.url(for: .purchase)

        // Existing subscribers and intercepted `/pro` URLs keep the legacy paywall.
        guard !subscriptionManager.isSubscriptionPresent(),
              redirectURLComponents?.path != SubscriptionPurchaseFlowPath.pro.rawValue else { return purchaseURL }

        guard let performanceOptimizedPaywallURL = SubscriptionURL.performanceOptimizedPaywallURL(
            basedOn: purchaseURL,
            paths: performanceOptimizedPaywalls.paths,
            isTrialEligible: subscriptionManager.isUserEligibleForFreeTrial(),
            isPersonalInformationRemovalAvailable: subscriptionManager.currentStorefrontRegion == .usa
        ) else { return purchaseURL }

        // Only enroll users who can be shown either paywall.
        guard let cohort = featureFlagger.resolveCohort(for: FeatureFlag.performanceOptimizedPaywalls)
            as? FeatureFlag.PerformanceOptimizedPaywallsCohort else {
            return purchaseURL
        }
        let paywallURL = cohort == .treatment ? performanceOptimizedPaywallURL : purchaseURL
        return paywallURL.removingParameters(named: ["experiment_perfpaywall"])
            .appendingParameter(name: "experiment_perfpaywall", value: cohort.rawValue)
    }
}

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

    /// Creates a tier-change performer for native cancel-pending-downgrade (Settings). Caller owns the instance.
    static func makeSubscriptionFlowsExecuter(subscriptionManager: SubscriptionManager,
                                              wideEvent: WideEventManaging) -> DefaultSubscriptionFlowsExecuter {
        SubscriptionFlowDependencies.make(subscriptionManager: subscriptionManager, wideEvent: wideEvent).subscriptionFlowsExecuter
    }

    private static func makeSubscriptionFeature(configuration: SubscriptionFlowConfiguration,
                                                subscriptionManager: SubscriptionManager,
                                                subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                                subscriptionDataReporter: SubscriptionDataReporting? = nil,
                                                internalUserDecider: InternalUserDecider,
                                                wideEvent: WideEventManaging,
                                                featureFlagger: FeatureFlagger) -> DefaultSubscriptionPagesUseSubscriptionFeature {
        let dependencies = SubscriptionFlowDependencies.make(subscriptionManager: subscriptionManager, wideEvent: wideEvent)
        let schedulesExpirationReminders = configuration.schedulesExpirationReminders
        return DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: subscriptionManager,
            subscriptionFeatureAvailability: subscriptionFeatureAvailability,
            subscriptionAttributionOrigin: configuration.subscriptionAttributionOrigin,
            planChangeEntry: configuration.planChangeEntry,
            appStorePurchaseFlow: dependencies.appStorePurchaseFlow,
            appStoreRestoreFlow: dependencies.appStoreRestoreFlow,
            subscriptionDataReporter: subscriptionDataReporter,
            internalUserDecider: internalUserDecider,
            wideEvent: wideEvent,
            pendingTransactionHandler: dependencies.pendingTransactionHandler,
            subscriptionFlowsExecuter: dependencies.subscriptionFlowsExecuter,
            requestValidator: DefaultScriptRequestValidator(subscriptionManager: subscriptionManager),
            expirationReminderScheduler: schedulesExpirationReminders ? AppDependencyProvider.shared.subscriptionExpirationReminderScheduler : nil,
            isExpirationReminderFeatureEnabled: {
                schedulesExpirationReminders && featureFlagger.isFeatureOn(.subscriptionExpirationReminderNotification)
            },
            subscriptionExperimentAttributionProvider: DefaultSubscriptionExperimentAttributionProvider(featureFlagger: featureFlagger))
    }

    static func makeSubscribeFlowV2(redirectURLComponents: URLComponents?,
                                    landingURL: URL? = nil,
                                    navigationCoordinator: SubscriptionNavigationCoordinator,
                                    subscriptionManager: SubscriptionManager,
                                    subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                    subscriptionDataReporter: SubscriptionDataReporting?,
                                    userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                    tld: TLD,
                                    internalUserDecider: InternalUserDecider,
                                    dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                    wideEvent: WideEventManaging,
                                    featureFlagger: FeatureFlagger,
                                    isDebugOverlayEnabled: Bool,
                                    performanceOptimizedPaywallsProvider: any PerformanceOptimizedPaywallsProviding,
                                    onboardingKeyValueStore: ThrowingKeyValueStoring?,
                                    meetsPIRLocaleRequirement: @escaping () -> Bool,
                                    onRequestDuckAIChat: ((String?) -> Bool)? = nil) -> some View {

        let configuration = SubscriptionFlowConfiguration.subscribe(redirectURLComponents: redirectURLComponents,
                                                                    landingURL: landingURL,
                                                                    subscriptionManager: subscriptionManager,
                                                                    tld: tld,
                                                                    performanceOptimizedPaywalls: performanceOptimizedPaywallsProvider,
                                                                    featureFlagger: featureFlagger,
                                                                    isDebugOverlayEnabled: isDebugOverlayEnabled)

        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            initialURL: configuration.initialURL,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            userScriptsDependencies: userScriptsDependencies,
            subFeature: makeSubscriptionFeature(configuration: configuration,
                                                subscriptionManager: subscriptionManager,
                                                subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                subscriptionDataReporter: subscriptionDataReporter,
                                                internalUserDecider: internalUserDecider,
                                                wideEvent: wideEvent,
                                                featureFlagger: featureFlagger),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider,
            onboardingKeyValueStore: onboardingKeyValueStore,
            meetsPIRLocaleRequirement: meetsPIRLocaleRequirement,
            onRequestDuckAIChat: onRequestDuckAIChat
        )
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .subscribe, viewModel: viewModel, featureFlagger: featureFlagger)
            .environmentObject(navigationCoordinator)
    }

    @ViewBuilder
    static func makePurchaseFlowV2(redirectURLComponents: URLComponents?,
                                   navigationCoordinator: SubscriptionNavigationCoordinator,
                                   subscriptionManager: SubscriptionManager,
                                   subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                   subscriptionDataReporter: SubscriptionDataReporting?,
                                   userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                   tld: TLD,
                                   internalUserDecider: InternalUserDecider,
                                   dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                   wideEvent: WideEventManaging,
                                   featureFlagger: FeatureFlagger,
                                   isDebugOverlayEnabled: Bool,
                                   performanceOptimizedPaywallsProvider: any PerformanceOptimizedPaywallsProviding,
                                   onboardingKeyValueStore: ThrowingKeyValueStoring?,
                                   meetsPIRLocaleRequirement: @escaping () -> Bool,
                                   onRequestDuckAIChat: ((String?) -> Bool)? = nil) -> some View {
        if let redirectURLComponents,
           SubscriptionPurchaseFlowPath.isPlansPath(redirectURLComponents.path) {
            makePlansFlowV2(redirectURLComponents: redirectURLComponents,
                            navigationCoordinator: navigationCoordinator,
                            subscriptionManager: subscriptionManager,
                            subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                            userScriptsDependencies: userScriptsDependencies,
                            internalUserDecider: internalUserDecider,
                            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider,
                            wideEvent: wideEvent,
                            featureFlagger: featureFlagger)
        } else {
            makeSubscribeFlowV2(redirectURLComponents: redirectURLComponents,
                                navigationCoordinator: navigationCoordinator,
                                subscriptionManager: subscriptionManager,
                                subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                subscriptionDataReporter: subscriptionDataReporter,
                                userScriptsDependencies: userScriptsDependencies,
                                tld: tld,
                                internalUserDecider: internalUserDecider,
                                dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider,
                                wideEvent: wideEvent,
                                featureFlagger: featureFlagger,
                                isDebugOverlayEnabled: isDebugOverlayEnabled,
                                performanceOptimizedPaywallsProvider: performanceOptimizedPaywallsProvider,
                                onboardingKeyValueStore: onboardingKeyValueStore,
                                meetsPIRLocaleRequirement: meetsPIRLocaleRequirement,
                                onRequestDuckAIChat: onRequestDuckAIChat)
        }
    }

    static func makeRestoreFlowV2(navigationCoordinator: SubscriptionNavigationCoordinator,
                                  subscriptionManager: SubscriptionManager,
                                  subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                  userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                  internalUserDecider: InternalUserDecider,
                                  wideEvent: WideEventManaging,
                                  dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                  featureFlagger: FeatureFlagger) -> some View {

        let viewModel = SubscriptionContainerViewModel(subscriptionManager: subscriptionManager,
                                                       isInternalUser: internalUserDecider.isInternalUser,
                                                       userScript: SubscriptionPagesUserScript(),
                                                       userScriptsDependencies: userScriptsDependencies,
                                                       subFeature: makeSubscriptionFeature(configuration: SubscriptionFlowConfiguration(),
                                                                                           subscriptionManager: subscriptionManager,
                                                                                           subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                                           internalUserDecider: internalUserDecider,
                                                                                           wideEvent: wideEvent,
                                                                                           featureFlagger: featureFlagger),
                                                       dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider,
                                                       onboardingKeyValueStore: nil,
                                                       meetsPIRLocaleRequirement: { false })
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .restore, viewModel: viewModel, featureFlagger: featureFlagger)
            .environmentObject(navigationCoordinator)
    }

    static func makePlansFlowV2(redirectURLComponents: URLComponents?,
                                navigationCoordinator: SubscriptionNavigationCoordinator,
                                subscriptionManager: SubscriptionManager,
                                subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                internalUserDecider: InternalUserDecider,
                                dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                wideEvent: WideEventManaging,
                                featureFlagger: FeatureFlagger) -> some View {

        let configuration = SubscriptionFlowConfiguration.plans(redirectURLComponents: redirectURLComponents,
                                                                subscriptionManager: subscriptionManager)

        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            initialURL: configuration.initialURL,
            flowType: configuration.flowType,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            userScriptsDependencies: userScriptsDependencies,
            subFeature: makeSubscriptionFeature(configuration: configuration,
                                                subscriptionManager: subscriptionManager,
                                                subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                internalUserDecider: internalUserDecider,
                                                wideEvent: wideEvent,
                                                featureFlagger: featureFlagger),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider,
            onboardingKeyValueStore: nil,
            meetsPIRLocaleRequirement: { false }
        )
        return SubscriptionContainerView(currentView: .subscribe, viewModel: viewModel, featureFlagger: featureFlagger)
            .environmentObject(navigationCoordinator)
    }

    static func makeCancellationFlowViewModel(subscriptionManager: SubscriptionManager,
                                              subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                              userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                              internalUserDecider: InternalUserDecider,
                                              dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                              wideEvent: WideEventManaging,
                                              featureFlagger: FeatureFlagger) -> SubscriptionContainerViewModel {

        let configuration = SubscriptionFlowConfiguration.cancellation(subscriptionManager: subscriptionManager)

        return SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            initialURL: configuration.initialURL,
            flowType: configuration.flowType,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            userScriptsDependencies: userScriptsDependencies,
            subFeature: makeSubscriptionFeature(configuration: configuration,
                                                subscriptionManager: subscriptionManager,
                                                subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                internalUserDecider: internalUserDecider,
                                                wideEvent: wideEvent,
                                                featureFlagger: featureFlagger),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider,
            onboardingKeyValueStore: nil,
            meetsPIRLocaleRequirement: { false }
        )
    }

    static func makeEmailFlowV2(navigationCoordinator: SubscriptionNavigationCoordinator,
                                subscriptionManager: SubscriptionManager,
                                subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                internalUserDecider: InternalUserDecider,
                                emailFlow: SubscriptionEmailViewModel.EmailViewFlow = .activationFlow,
                                dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
                                wideEvent: WideEventManaging,
                                featureFlagger: FeatureFlagger,
                                onDisappear: @escaping () -> Void) -> some View {
        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            userScriptsDependencies: userScriptsDependencies,
            subFeature: makeSubscriptionFeature(configuration: SubscriptionFlowConfiguration(),
                                                subscriptionManager: subscriptionManager,
                                                subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                internalUserDecider: internalUserDecider,
                                                wideEvent: wideEvent,
                                                featureFlagger: featureFlagger),
            dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider,
            onboardingKeyValueStore: nil,
            meetsPIRLocaleRequirement: { false }
        )

        viewModel.email.setEmailFlowMode(emailFlow)

        return SubscriptionContainerView(currentView: .email, viewModel: viewModel, featureFlagger: featureFlagger)
            .environmentObject(navigationCoordinator)
            .onDisappear(perform: { onDisappear() })
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

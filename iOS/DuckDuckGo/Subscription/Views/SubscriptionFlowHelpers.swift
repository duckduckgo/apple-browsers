//
//  SubscriptionFlowHelpers.swift
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
import Common
import FoundationExtensions
import BrowserServicesKit
import PrivacyConfig
import DataBrokerProtection_iOS
import WideEvent
import FeatureFlags_iOS
import Persistence

struct SubscriptionFlowContext {
    let subscriptionManager: SubscriptionManager
    let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    let internalUserDecider: InternalUserDecider
    let dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?
    let wideEvent: WideEventManaging
    let featureFlagger: FeatureFlagger
}

struct SubscriptionPurchaseDependencies {
    let subscriptionDataReporter: SubscriptionDataReporting?
    let tld: TLD
    let isDebugOverlayEnabled: Bool
    let performanceOptimizedPaywallsProvider: any PerformanceOptimizedPaywallsProviding
    let onboardingKeyValueStore: ThrowingKeyValueStoring?
    let meetsPIRLocaleRequirement: () -> Bool
    let onRequestDuckAIChat: ((String?) -> Bool)?
}

enum SubscriptionFlow {
    case subscribe(redirectURLComponents: URLComponents?, landingURL: URL? = nil, dependencies: SubscriptionPurchaseDependencies)
    case plans(redirectURLComponents: URLComponents?)
    case restore
    case email(SubscriptionEmailViewModel.EmailViewFlow)
    case cancellation

    static func makePlanOrSubscribeFlow(redirectURLComponents: URLComponents?, dependencies: SubscriptionPurchaseDependencies) -> SubscriptionFlow {
        if let redirectURLComponents, SubscriptionPurchaseFlowPath.isPlansPath(redirectURLComponents.path) {
            return .plans(redirectURLComponents: redirectURLComponents)
        }
        return .subscribe(redirectURLComponents: redirectURLComponents, dependencies: dependencies)
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

    var purchaseDependencies: SubscriptionPurchaseDependencies? {
        guard case let .subscribe(_, _, dependencies) = self else { return nil }
        return dependencies
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
        case .cancellation:
            return .cancellation(subscriptionManager: subscriptionManager)
        case .restore, .email:
            return SubscriptionFlowConfiguration()
        }
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

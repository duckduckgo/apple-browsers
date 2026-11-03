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

/// App-wide dependencies shared by every subscription flow.
struct SubscriptionFlowContext {
    let subscriptionManager: SubscriptionManager
    let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    let internalUserDecider: InternalUserDecider
    let dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?
    let wideEvent: WideEventManaging
    let featureFlagger: FeatureFlagger
}

/// Dependencies only the subscribe flow needs: building the paywall URL, purchase attribution and post-checkout onboarding.
struct SubscriptionPurchaseDependencies {
    let subscriptionDataReporter: SubscriptionDataReporting?
    let tld: TLD
    let isDebugOverlayEnabled: Bool
    let performanceOptimizedPaywallsProvider: any PerformanceOptimizedPaywallsProviding
    let onboardingKeyValueStore: ThrowingKeyValueStoring?
    let meetsPIRLocaleRequirement: () -> Bool
    let onRequestDuckAIChat: ((String?) -> Bool)?
}

/// Everything a flow decides for itself, built from its inputs. Each flow has one builder that sets every field.
struct SubscriptionFlowConfiguration: Equatable {
    let containerView: SubscriptionContainerView.CurrentViewType
    let emailScreenMode: SubscriptionEmailViewModel.EmailViewFlow?
    let initialURL: URL?
    let flowType: SubscriptionFlowType
    let subscriptionAttributionOrigin: String?
    let planChangeEntry: String?
    let schedulesExpirationReminders: Bool

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
        return Self(containerView: .subscriptionFlowView,
                    emailScreenMode: .restoreFlow,
                    initialURL: initialURL,
                    flowType: .firstPurchase,
                    subscriptionAttributionOrigin: queryValue(named: AttributionParameter.origin, in: redirectURLComponents),
                    planChangeEntry: nil,
                    schedulesExpirationReminders: true)
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
        return Self(containerView: .subscriptionFlowView,
                    emailScreenMode: nil,
                    initialURL: plansURL,
                    flowType: .planUpdate,
                    subscriptionAttributionOrigin: queryValue(named: AttributionParameter.origin, in: redirectURLComponents),
                    planChangeEntry: queryValue(named: SubscriptionURL.PlanChangeParameter.entry, in: redirectURLComponents),
                    schedulesExpirationReminders: true)
    }

    static func restore() -> Self {
        Self(containerView: .restoreView,
             emailScreenMode: .restoreFlow,
             initialURL: nil,
             flowType: .firstPurchase,
             subscriptionAttributionOrigin: nil,
             planChangeEntry: nil,
             schedulesExpirationReminders: true)
    }

    static func email(_ emailScreenMode: SubscriptionEmailViewModel.EmailViewFlow) -> Self {
        Self(containerView: .emailView,
             emailScreenMode: emailScreenMode,
             initialURL: nil,
             flowType: .firstPurchase,
             subscriptionAttributionOrigin: nil,
             planChangeEntry: nil,
             schedulesExpirationReminders: true)
    }

    static func cancellation(subscriptionManager: SubscriptionManager) -> Self {
        Self(containerView: .subscriptionFlowView,
             emailScreenMode: nil,
             initialURL: subscriptionManager.url(for: .cancellationFlow),
             flowType: .cancellation,
             subscriptionAttributionOrigin: nil,
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

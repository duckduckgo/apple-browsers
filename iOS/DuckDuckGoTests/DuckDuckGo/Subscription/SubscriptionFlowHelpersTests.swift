//
//  SubscriptionFlowHelpersTests.swift
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
import Testing
import BrowserServicesKit
import Common
import PrivacyConfig
@_spi(Testing) import WideEvent
@testable import DuckDuckGo
@testable import Subscription
import SubscriptionTestingUtilities

private struct PerformanceOptimizedPaywallsProviderStub: PerformanceOptimizedPaywallsProviding {
    let isEnabled = false
    let paths = SubscriptionURL.PerformanceOptimizedPaywallPaths.default
}

@MainActor
@Suite("Subscription flow configuration")
struct SubscriptionFlowConfigurationTests {

    private typealias Configuration = SubscriptionFlowConfiguration

    private let subscriptionManager = SubscriptionManagerMock()

    private func redirectURLComponents(origin: String, entry: String) -> URLComponents {
        var components = URLComponents(string: "https://duckduckgo.com/subscriptions/plans")!
        components.queryItems = [
            URLQueryItem(name: AttributionParameter.origin, value: origin),
            URLQueryItem(name: SubscriptionURL.PlanChangeParameter.entry, value: entry)
        ]
        return components
    }

    @available(iOS 16, macOS 13, *)
    @Test("subscribe uses the initial URL, adds the debug parameter only when enabled and reads the origin", .timeLimit(.minutes(1)),
          arguments: [true, false])
    func subscribeConfiguration(isDebugOverlayEnabled: Bool) {
        let landingURL = URL(string: "https://duckduckgo.com/subscriptions/welcome")!

        let configuration = Configuration.subscribe(redirectURLComponents: redirectURLComponents(origin: "funnel_test", entry: "settings"),
                                                    landingURL: landingURL,
                                                    subscriptionManager: subscriptionManager,
                                                    tld: TLD(),
                                                    performanceOptimizedPaywalls: PerformanceOptimizedPaywallsProviderStub(),
                                                    featureFlagger: PrivacyConfig.MockFeatureFlagger(),
                                                    isDebugOverlayEnabled: isDebugOverlayEnabled)

        let expectedURL = isDebugOverlayEnabled ? landingURL.appendingParameter(name: "debug", value: "1") : landingURL
        #expect(configuration == Configuration(initialURL: expectedURL,
                                               flowType: .firstPurchase,
                                               subscriptionAttributionOrigin: "funnel_test",
                                               planChangeEntry: nil,
                                               schedulesExpirationReminders: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("plans keeps every redirect query parameter and reads the origin and plan change entry", .timeLimit(.minutes(1)))
    func plansConfigurationWithRedirect() {
        let components = redirectURLComponents(origin: "funnel_test", entry: "settings")

        let configuration = Configuration.plans(redirectURLComponents: components, subscriptionManager: subscriptionManager)

        let expectedURL = subscriptionManager.url(for: .plans)
            .appendingParameter(name: AttributionParameter.origin, value: "funnel_test")
            .appendingParameter(name: SubscriptionURL.PlanChangeParameter.entry, value: "settings")
        #expect(configuration == Configuration(initialURL: expectedURL,
                                               flowType: .planUpdate,
                                               subscriptionAttributionOrigin: "funnel_test",
                                               planChangeEntry: "settings",
                                               schedulesExpirationReminders: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("plans without a redirect opens the plans URL with no origin or plan change entry", .timeLimit(.minutes(1)))
    func plansConfigurationWithoutRedirect() {
        let configuration = Configuration.plans(redirectURLComponents: nil, subscriptionManager: subscriptionManager)

        #expect(configuration == Configuration(initialURL: subscriptionManager.url(for: .plans),
                                               flowType: .planUpdate,
                                               subscriptionAttributionOrigin: nil,
                                               planChangeEntry: nil,
                                               schedulesExpirationReminders: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("cancellation opens the cancellation URL with its plan change entry and no expiration reminders", .timeLimit(.minutes(1)))
    func cancellationConfiguration() {
        let configuration = Configuration.cancellation(subscriptionManager: subscriptionManager)

        #expect(configuration == Configuration(initialURL: subscriptionManager.url(for: .cancellationFlow),
                                               flowType: .cancellation,
                                               subscriptionAttributionOrigin: nil,
                                               planChangeEntry: SubscriptionPlanChangeOrigin.cancellationFlow.rawValue,
                                               schedulesExpirationReminders: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("The default configuration, used by restore and email, has no URL, origin or plan change entry", .timeLimit(.minutes(1)))
    func defaultConfiguration() {
        #expect(Configuration() == Configuration(initialURL: nil,
                                                 flowType: .firstPurchase,
                                                 subscriptionAttributionOrigin: nil,
                                                 planChangeEntry: nil,
                                                 schedulesExpirationReminders: true))
    }
}

@MainActor
@Suite("Subscription flows")
struct SubscriptionFlowTests {

    private typealias Flow = SubscriptionFlow
    private typealias Configuration = SubscriptionFlowConfiguration

    private let subscriptionManager = SubscriptionManagerMock()
    private let featureFlagger = PrivacyConfig.MockFeatureFlagger()

    private let options = SubscriptionPurchaseOptions(
        subscriptionDataReporter: nil,
        tld: TLD(),
        isDebugOverlayEnabled: false,
        performanceOptimizedPaywallsProvider: PerformanceOptimizedPaywallsProviderStub(),
        onboardingKeyValueStore: nil,
        meetsPIRLocaleRequirement: { true },
        onRequestDuckAIChat: nil)

    private func redirectURLComponents(path: String) -> URLComponents {
        var components = URLComponents(string: "https://duckduckgo.com")!
        components.path = path
        components.queryItems = [URLQueryItem(name: SubscriptionURL.PlanChangeParameter.entry, value: "settings")]
        return components
    }

    @available(iOS 16, macOS 13, *)
    @Test("makePlanOrSubscribeFlow with a plans path makes the plans flow", .timeLimit(.minutes(1)),
          arguments: [SubscriptionPurchaseFlowPath.plans, .proPlans])
    func planOrSubscribeWithPlansPathMakesPlans(path: SubscriptionPurchaseFlowPath) {
        let components = redirectURLComponents(path: path.rawValue)

        let flow = Flow.makePlanOrSubscribeFlow(redirectURLComponents: components, options: options)

        guard case .plans(let flowComponents) = flow else {
            Issue.record("Expected the plans flow")
            return
        }
        #expect(flowComponents == components)
    }

    @available(iOS 16, macOS 13, *)
    @Test("makePlanOrSubscribeFlow without a plans path makes the subscribe flow with its purchase options", .timeLimit(.minutes(1)),
          arguments: [Optional<String>.none, SubscriptionPurchaseFlowPath.purchase.rawValue, SubscriptionPurchaseFlowPath.pro.rawValue])
    func planOrSubscribeWithoutPlansPathMakesSubscribe(path: String?) {
        let components = path.map { redirectURLComponents(path: $0) }

        let flow = Flow.makePlanOrSubscribeFlow(redirectURLComponents: components, options: options)

        guard case .subscribe(let flowComponents, let landingURL, let flowOptions) = flow else {
            Issue.record("Expected the subscribe flow")
            return
        }
        #expect(flowComponents == components)
        #expect(landingURL == nil)
        #expect(flowOptions.meetsPIRLocaleRequirement())
    }

    @available(iOS 16, macOS 13, *)
    @Test("subscribe shows the subscribe view in restore email mode with its purchase options", .timeLimit(.minutes(1)))
    func subscribeFlow() {
        let flow = Flow.subscribe(redirectURLComponents: nil, options: options)

        #expect(flow.purchaseOptions?.meetsPIRLocaleRequirement() == true)
        #expect(flow.currentView == .subscribe)
        #expect(flow.emailFlowMode == .restoreFlow)
    }

    @available(iOS 16, macOS 13, *)
    @Test("plans shows the subscribe view and leaves the email mode unset", .timeLimit(.minutes(1)))
    func plansFlow() {
        let components = redirectURLComponents(path: SubscriptionPurchaseFlowPath.plans.rawValue)
        let flow = Flow.plans(redirectURLComponents: components)

        #expect(flow.purchaseOptions?.meetsPIRLocaleRequirement() == nil)
        #expect(flow.currentView == .subscribe)
        #expect(flow.emailFlowMode == nil)
        #expect(flow.configuration(subscriptionManager: subscriptionManager, featureFlagger: featureFlagger)
                == Configuration.plans(redirectURLComponents: components, subscriptionManager: subscriptionManager))
    }

    @available(iOS 16, macOS 13, *)
    @Test("restore shows the restore view in restore email mode with the default configuration", .timeLimit(.minutes(1)))
    func restoreFlow() {
        let flow = Flow.restore

        #expect(flow.purchaseOptions?.meetsPIRLocaleRequirement() == nil)
        #expect(flow.currentView == .restore)
        #expect(flow.emailFlowMode == .restoreFlow)
        #expect(flow.configuration(subscriptionManager: subscriptionManager, featureFlagger: featureFlagger) == Configuration())
    }

    @available(iOS 16, macOS 13, *)
    @Test("email shows the email view in its own email mode with the default configuration", .timeLimit(.minutes(1)),
          arguments: [SubscriptionEmailViewModel.EmailViewFlow.activationFlow, .restoreFlow, .manageEmailFlow])
    func emailFlow(emailFlow: SubscriptionEmailViewModel.EmailViewFlow) {
        let flow = Flow.email(emailFlow)

        #expect(flow.purchaseOptions?.meetsPIRLocaleRequirement() == nil)
        #expect(flow.currentView == .email)
        #expect(flow.emailFlowMode == emailFlow)
        #expect(flow.configuration(subscriptionManager: subscriptionManager, featureFlagger: featureFlagger) == Configuration())
    }

    @available(iOS 16, macOS 13, *)
    @Test("cancellation leaves the email mode unset and uses the cancellation configuration", .timeLimit(.minutes(1)))
    func cancellationFlow() {
        let flow = Flow.cancellation

        #expect(flow.purchaseOptions?.meetsPIRLocaleRequirement() == nil)
        #expect(flow.emailFlowMode == nil)
        #expect(flow.configuration(subscriptionManager: subscriptionManager, featureFlagger: featureFlagger)
                == Configuration.cancellation(subscriptionManager: subscriptionManager))
    }
}

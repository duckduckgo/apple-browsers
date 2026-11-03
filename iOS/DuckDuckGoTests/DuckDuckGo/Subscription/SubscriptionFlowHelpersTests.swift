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
    @Test("subscribe starts on the subscribe screen, adds the debug parameter only when enabled and reads the origin", .timeLimit(.minutes(1)),
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
        #expect(configuration == Configuration(initialScreen: .subscribe,
                                               emailScreenMode: .restoreFlow,
                                               initialURL: expectedURL,
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
        #expect(configuration == Configuration(initialScreen: .subscribe,
                                               emailScreenMode: nil,
                                               initialURL: expectedURL,
                                               flowType: .planUpdate,
                                               subscriptionAttributionOrigin: "funnel_test",
                                               planChangeEntry: "settings",
                                               schedulesExpirationReminders: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("plans without a redirect opens the plans URL with no origin or plan change entry", .timeLimit(.minutes(1)))
    func plansConfigurationWithoutRedirect() {
        let configuration = Configuration.plans(redirectURLComponents: nil, subscriptionManager: subscriptionManager)

        #expect(configuration == Configuration(initialScreen: .subscribe,
                                               emailScreenMode: nil,
                                               initialURL: subscriptionManager.url(for: .plans),
                                               flowType: .planUpdate,
                                               subscriptionAttributionOrigin: nil,
                                               planChangeEntry: nil,
                                               schedulesExpirationReminders: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("restore starts on the restore screen with the email screen in restore mode", .timeLimit(.minutes(1)))
    func restoreConfiguration() {
        #expect(Configuration.restore() == Configuration(initialScreen: .restore,
                                                         emailScreenMode: .restoreFlow,
                                                         initialURL: nil,
                                                         flowType: .firstPurchase,
                                                         subscriptionAttributionOrigin: nil,
                                                         planChangeEntry: nil,
                                                         schedulesExpirationReminders: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("email starts on the email screen in the requested mode", .timeLimit(.minutes(1)),
          arguments: [SubscriptionEmailViewModel.EmailViewFlow.activationFlow, .restoreFlow, .manageEmailFlow])
    func emailConfiguration(emailScreenMode: SubscriptionEmailViewModel.EmailViewFlow) {
        #expect(Configuration.email(emailScreenMode) == Configuration(initialScreen: .email,
                                                                      emailScreenMode: emailScreenMode,
                                                                      initialURL: nil,
                                                                      flowType: .firstPurchase,
                                                                      subscriptionAttributionOrigin: nil,
                                                                      planChangeEntry: nil,
                                                                      schedulesExpirationReminders: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("cancellation opens the cancellation URL with its plan change entry and no expiration reminders", .timeLimit(.minutes(1)))
    func cancellationConfiguration() {
        let configuration = Configuration.cancellation(subscriptionManager: subscriptionManager)

        #expect(configuration == Configuration(initialScreen: .subscribe,
                                               emailScreenMode: nil,
                                               initialURL: subscriptionManager.url(for: .cancellationFlow),
                                               flowType: .cancellation,
                                               subscriptionAttributionOrigin: nil,
                                               planChangeEntry: SubscriptionPlanChangeOrigin.cancellationFlow.rawValue,
                                               schedulesExpirationReminders: false))
    }
}

@MainActor
@Suite("Subscription flows")
struct SubscriptionFlowTests {

    private typealias Flow = SubscriptionFlow
    private typealias Configuration = SubscriptionFlowConfiguration

    private let subscriptionManager = SubscriptionManagerMock()
    private let featureFlagger = PrivacyConfig.MockFeatureFlagger()

    private let dependencies = SubscriptionPurchaseDependencies(
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

    private func configuration(of flow: Flow) -> Configuration {
        flow.configuration(subscriptionManager: subscriptionManager, featureFlagger: featureFlagger)
    }

    @available(iOS 16, macOS 13, *)
    @Test("makePlanOrSubscribeFlow with a plans path makes the plans flow", .timeLimit(.minutes(1)),
          arguments: [SubscriptionPurchaseFlowPath.plans, .proPlans])
    func planOrSubscribeWithPlansPathMakesPlans(path: SubscriptionPurchaseFlowPath) {
        let components = redirectURLComponents(path: path.rawValue)

        let flow = Flow.makePlanOrSubscribeFlow(redirectURLComponents: components, dependencies: dependencies)

        guard case .plans(let flowComponents) = flow else {
            Issue.record("Expected the plans flow")
            return
        }
        #expect(flowComponents == components)
    }

    @available(iOS 16, macOS 13, *)
    @Test("makePlanOrSubscribeFlow without a plans path makes the subscribe flow with its purchase dependencies", .timeLimit(.minutes(1)),
          arguments: [Optional<String>.none, SubscriptionPurchaseFlowPath.purchase.rawValue, SubscriptionPurchaseFlowPath.pro.rawValue])
    func planOrSubscribeWithoutPlansPathMakesSubscribe(path: String?) {
        let components = path.map { redirectURLComponents(path: $0) }

        let flow = Flow.makePlanOrSubscribeFlow(redirectURLComponents: components, dependencies: dependencies)

        guard case .subscribe(let flowComponents, let landingURL, let flowDependencies) = flow else {
            Issue.record("Expected the subscribe flow")
            return
        }
        #expect(flowComponents == components)
        #expect(landingURL == nil)
        #expect(flowDependencies.meetsPIRLocaleRequirement())
    }

    @available(iOS 16, macOS 13, *)
    @Test("subscribe uses the subscribe configuration built from its purchase dependencies", .timeLimit(.minutes(1)))
    func subscribeFlow() {
        let landingURL = URL(string: "https://duckduckgo.com/subscriptions/welcome")!

        #expect(configuration(of: .subscribe(redirectURLComponents: nil, landingURL: landingURL, dependencies: dependencies))
                == Configuration.subscribe(redirectURLComponents: nil,
                                           landingURL: landingURL,
                                           subscriptionManager: subscriptionManager,
                                           tld: TLD(),
                                           performanceOptimizedPaywalls: PerformanceOptimizedPaywallsProviderStub(),
                                           featureFlagger: featureFlagger,
                                           isDebugOverlayEnabled: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("plans uses the plans configuration", .timeLimit(.minutes(1)))
    func plansFlow() {
        let components = redirectURLComponents(path: SubscriptionPurchaseFlowPath.plans.rawValue)

        #expect(configuration(of: .plans(redirectURLComponents: components))
                == Configuration.plans(redirectURLComponents: components, subscriptionManager: subscriptionManager))
    }

    @available(iOS 16, macOS 13, *)
    @Test("restore uses the restore configuration", .timeLimit(.minutes(1)))
    func restoreFlow() {
        #expect(configuration(of: .restore) == Configuration.restore())
    }

    @available(iOS 16, macOS 13, *)
    @Test("email uses the email configuration in its own mode", .timeLimit(.minutes(1)),
          arguments: [SubscriptionEmailViewModel.EmailViewFlow.activationFlow, .restoreFlow, .manageEmailFlow])
    func emailFlow(emailScreenMode: SubscriptionEmailViewModel.EmailViewFlow) {
        #expect(configuration(of: .email(emailScreenMode)) == Configuration.email(emailScreenMode))
    }

    @available(iOS 16, macOS 13, *)
    @Test("cancellation uses the cancellation configuration", .timeLimit(.minutes(1)))
    func cancellationFlow() {
        #expect(configuration(of: .cancellation) == Configuration.cancellation(subscriptionManager: subscriptionManager))
    }
}

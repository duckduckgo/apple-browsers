//
//  SubscriptionContainerViewFactoryTests.swift
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
@Suite("Subscription container view factory flow configuration")
struct SubscriptionFlowConfigurationTests {

    private typealias Configuration = SubscriptionContainerViewFactory.SubscriptionFlowConfiguration

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
@Suite("Subscription container view factory flow dependencies")
struct SubscriptionFlowDependenciesTests {

    private let subscriptionManager = SubscriptionManagerMock()
    private let wideEvent = WideEventMock()

    private func makeDependencies() -> SubscriptionContainerViewFactory.SubscriptionFlowDependencies {
        SubscriptionContainerViewFactory.SubscriptionFlowDependencies.make(subscriptionManager: subscriptionManager,
                                                                           wideEvent: wideEvent)
    }

    @available(iOS 16, macOS 13, *)
    @Test("make builds the default App Store flow chain", .timeLimit(.minutes(1)))
    func makeBuildsDefaultChain() {
        let dependencies = makeDependencies()

        #expect(dependencies.pendingTransactionHandler is DefaultPendingTransactionHandler)
        #expect(dependencies.appStoreRestoreFlow is DefaultAppStoreRestoreFlow)
        #expect(dependencies.appStorePurchaseFlow is DefaultAppStorePurchaseFlow)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each call to make builds fresh instances", .timeLimit(.minutes(1)))
    func makeBuildsFreshInstances() {
        let first = makeDependencies()
        let second = makeDependencies()

        #expect(first.pendingTransactionHandler as AnyObject !== second.pendingTransactionHandler as AnyObject)
        #expect(first.appStoreRestoreFlow as AnyObject !== second.appStoreRestoreFlow as AnyObject)
        #expect(first.appStorePurchaseFlow as AnyObject !== second.appStorePurchaseFlow as AnyObject)
        #expect(first.subscriptionFlowsExecuter !== second.subscriptionFlowsExecuter)
    }

    @available(iOS 16, macOS 13, *)
    @Test("makeSubscriptionFlowsExecuter builds a fresh executer per call", .timeLimit(.minutes(1)))
    func makeSubscriptionFlowsExecuterBuildsFreshInstances() {
        let first = SubscriptionContainerViewFactory.makeSubscriptionFlowsExecuter(subscriptionManager: subscriptionManager,
                                                                                   wideEvent: wideEvent)
        let second = SubscriptionContainerViewFactory.makeSubscriptionFlowsExecuter(subscriptionManager: subscriptionManager,
                                                                                    wideEvent: wideEvent)

        #expect(first !== second)
    }
}

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
@_spi(Testing) import Persistence
@_spi(Testing) import WideEvent
@testable import DuckDuckGo
@testable import Subscription
import SubscriptionTestingUtilities

@MainActor
@Suite("Subscription container view factory view model")
struct SubscriptionContainerViewFactoryTests {

    private let subscriptionManager = SubscriptionManagerMock()

    private func makeContext() -> SubscriptionFlowContext {
        let userScriptsDependencies = DefaultScriptSourceProvider.Dependencies(appSettings: AppSettingsMock(),
                                                                              sync: MockDDGSyncing(),
                                                                              privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                                                              contentBlockingManager: ContentBlockerRulesManagerMock(),
                                                                              fireproofing: MockFireproofing(),
                                                                              contentScopeExperimentsManager: MockContentScopeExperimentManager(),
                                                                              internalUserDecider: PrivacyConfig.MockInternalUserDecider(),
                                                                              syncErrorHandler: CapturingAdapterErrorHandler(),
                                                                              webExtensionAvailability: nil)
        return SubscriptionFlowContext(subscriptionManager: subscriptionManager,
                                       subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true),
                                       userScriptsDependencies: userScriptsDependencies,
                                       internalUserDecider: PrivacyConfig.MockInternalUserDecider(),
                                       dataBrokerProtectionViewControllerProvider: nil,
                                       wideEvent: WideEventMock(),
                                       featureFlagger: PrivacyConfig.MockFeatureFlagger(),
                                       expirationReminderScheduler: SubscriptionExpirationReminderSchedulerMock())
    }

    private func makeViewModel(for flow: SubscriptionFlow) -> SubscriptionContainerViewModel {
        SubscriptionContainerViewFactory.makeViewModel(for: flow, context: makeContext())
    }

    @available(iOS 16, macOS 13, *)
    @Test("subscribe loads its URL in restore email mode and gets the onboarding store", .timeLimit(.minutes(1)))
    func subscribeViewModel() {
        let landingURL = URL(string: "https://duckduckgo.com/subscriptions/welcome")!
        let dependencies = SubscriptionPurchaseDependencies(subscriptionDataReporter: nil,
                                                            tld: TLD(),
                                                            isDebugOverlayEnabled: false,
                                                            performanceOptimizedPaywallsProvider: PerformanceOptimizedPaywallsProviderStub(),
                                                            onboardingKeyValueStore: MockThrowingKeyValueStore(),
                                                            meetsPIRLocaleRequirement: { false },
                                                            onRequestDuckAIChat: nil)

        let viewModel = makeViewModel(for: .subscribe(redirectURLComponents: nil, landingURL: landingURL, dependencies: dependencies))

        let hasOnboardingStore = viewModel.flow.onboardingPersistor != nil
        #expect(viewModel.flow.initialURL == landingURL)
        #expect(viewModel.flow.flowType == .firstPurchase)
        #expect(viewModel.email.state.currentFlow == .restoreFlow)
        #expect(hasOnboardingStore)
    }

    @available(iOS 16, macOS 13, *)
    @Test("plans loads the plans URL, keeps the default email mode and gets no onboarding store", .timeLimit(.minutes(1)))
    func plansViewModel() {
        var components = URLComponents(string: "https://duckduckgo.com/subscriptions/plans")!
        components.queryItems = [URLQueryItem(name: SubscriptionURL.PlanChangeParameter.entry, value: "settings")]

        let viewModel = makeViewModel(for: .plans(redirectURLComponents: components))

        let hasOnboardingStore = viewModel.flow.onboardingPersistor != nil
        #expect(viewModel.flow.initialURL
                == SubscriptionFlowConfiguration.plans(redirectURLComponents: components, subscriptionManager: subscriptionManager).initialURL)
        #expect(viewModel.flow.flowType == .planUpdate)
        #expect(viewModel.email.state.currentFlow == .activationFlow)
        #expect(!hasOnboardingStore)
    }

    @available(iOS 16, macOS 13, *)
    @Test("restore falls back to the purchase URL in restore email mode and gets no onboarding store", .timeLimit(.minutes(1)))
    func restoreViewModel() {
        let viewModel = makeViewModel(for: .restore)

        let hasOnboardingStore = viewModel.flow.onboardingPersistor != nil
        #expect(viewModel.flow.initialURL == subscriptionManager.url(for: .purchase))
        #expect(viewModel.flow.flowType == .firstPurchase)
        #expect(viewModel.email.state.currentFlow == .restoreFlow)
        #expect(!hasOnboardingStore)
    }

    @available(iOS 16, macOS 13, *)
    @Test("email uses the requested email mode and gets no onboarding store", .timeLimit(.minutes(1)),
          arguments: [SubscriptionEmailViewModel.EmailViewFlow.activationFlow, .restoreFlow, .manageEmailFlow])
    func emailViewModel(emailScreenMode: SubscriptionEmailViewModel.EmailViewFlow) {
        let viewModel = makeViewModel(for: .email(emailScreenMode))

        let hasOnboardingStore = viewModel.flow.onboardingPersistor != nil
        #expect(viewModel.email.state.currentFlow == emailScreenMode)
        #expect(!hasOnboardingStore)
    }

    @available(iOS 16, macOS 13, *)
    @Test("cancellation loads the cancellation URL, keeps the default email mode and gets no onboarding store", .timeLimit(.minutes(1)))
    func cancellationViewModel() {
        let viewModel = makeViewModel(for: .cancellation)

        let hasOnboardingStore = viewModel.flow.onboardingPersistor != nil
        #expect(viewModel.flow.initialURL == subscriptionManager.url(for: .cancellationFlow))
        #expect(viewModel.flow.flowType == .cancellation)
        #expect(viewModel.email.state.currentFlow == .activationFlow)
        #expect(!hasOnboardingStore)
    }
}

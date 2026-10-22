//
//  FreemiumPIREligibilityCheckerTests.swift
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

import DataBrokerProtection_iOS
import FeatureFlags_iOS
@_spi(Testing) import Networking
@_spi(Testing) import Persistence
import SubscriptionTestingUtilities
import Testing
@testable import DuckDuckGo

@Suite("Freemium PIR eligibility")
struct FreemiumPIREligibilityCheckerTests {

    private let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.personalInformationRemoval, .dbpFreemiumPIR])
    private let subscriptionManager = SubscriptionManagerMock()
    private let debugSettings = FreemiumPIRDebugSettings(keyValueStore: MockKeyValueFileStore())
    // The checker holds the delegate weakly, so the suite keeps it alive.
    private let runPrerequisitesDelegate = MockRunPrerequisitesDelegate()

    private func makeChecker() -> DefaultFreemiumPIREligibilityChecker {
        DefaultFreemiumPIREligibilityChecker(featureFlagger: featureFlagger,
                                             runPrerequisitesDelegate: runPrerequisitesDelegate,
                                             subscriptionManager: subscriptionManager,
                                             freemiumPIRDebugSettings: debugSettings)
    }

    @available(iOS 16, *)
    @Test("Entry point shows when every gate passes", .timeLimit(.minutes(1)))
    func entryPointShowsWhenEveryGatePasses() {
        #expect(makeChecker().canShowEntryPoint())
    }

    @available(iOS 16, *)
    @Test("Entry point hides when App Store products are unavailable", .timeLimit(.minutes(1)))
    func entryPointHidesWhenAppStoreProductsAreUnavailable() {
        subscriptionManager.hasAppStoreProductsAvailable = false

        #expect(!makeChecker().canShowEntryPoint())
    }

    @available(iOS 16, *)
    @Test("Entry point shows on Stripe without App Store products", .timeLimit(.minutes(1)))
    func entryPointShowsOnStripeWithoutAppStoreProducts() {
        subscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        subscriptionManager.hasAppStoreProductsAvailable = false

        #expect(makeChecker().canShowEntryPoint())
    }

    @available(iOS 16, *)
    @Test("Debug override bypasses purchase eligibility", .timeLimit(.minutes(1)))
    func debugOverrideBypassesPurchaseEligibility() {
        subscriptionManager.hasAppStoreProductsAvailable = false
        debugSettings.setEligibilityForced(true)

        #expect(makeChecker().canShowEntryPoint())
    }

    @available(iOS 16, *)
    @Test("Entry point hides for signed-in users even with the debug override", .timeLimit(.minutes(1)))
    func entryPointHidesForSignedInUsersEvenWithDebugOverride() {
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        debugSettings.setEligibilityForced(true)

        #expect(!makeChecker().canShowEntryPoint())
    }

    @available(iOS 16, *)
    @Test("Entry point hides when the Freemium flag is off", .timeLimit(.minutes(1)))
    func entryPointHidesWhenFreemiumFlagIsOff() {
        featureFlagger.enabledFeatureFlags = [.personalInformationRemoval]

        #expect(!makeChecker().canShowEntryPoint())
    }

    @available(iOS 16, *)
    @Test("Entry point hides when the PIR flag is off", .timeLimit(.minutes(1)))
    func entryPointHidesWhenPIRFlagIsOff() {
        featureFlagger.enabledFeatureFlags = [.dbpFreemiumPIR]

        #expect(!makeChecker().canShowEntryPoint())
    }

    @available(iOS 16, *)
    @Test("Entry point hides when the locale requirement is not met", .timeLimit(.minutes(1)))
    func entryPointHidesWhenLocaleRequirementIsNotMet() {
        runPrerequisitesDelegate.meetsLocaleRequirement = false

        #expect(!makeChecker().canShowEntryPoint())
    }
}

private final class MockRunPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate {
    var meetsLocaleRequirement = true

    var meetsProfileRunPrequisite: Bool { true }
    var meetsEntitlementRunPrequisite: Bool { true }

    func isUserAuthenticated() async -> Bool { false }
    func isUserEligibleForFreeTrial() -> Bool { false }
    func validateRunPrerequisites() async -> Bool { true }
    func validateRunPrerequisites(usingCachedProfileState profileState: DBPProfileState) async -> Bool { true }
}

//
//  SubscriptionFeatureAvailabilityTests.swift
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

import XCTest
import Common
import Combine
import PrivacyConfig
import PrivacyConfigTestsUtils
import Subscription
@testable import BrowserServicesKit

final class SubscriptionFeatureAvailabilityTests: XCTestCase {

    var internalUserDeciderStore: MockInternalUserStoring!
    var privacyConfig: MockPrivacyConfiguration!
    var privacyConfigurationManager: MockPrivacyConfigurationManager!

    override func setUp() {
        super.setUp()
        internalUserDeciderStore = MockInternalUserStoring()
        privacyConfig = MockPrivacyConfiguration()

        privacyConfigurationManager = MockPrivacyConfigurationManager(privacyConfig: privacyConfig,
                                                                      internalUserDecider: DefaultInternalUserDecider(store: internalUserDeciderStore))
    }

    override func tearDown() {
        internalUserDeciderStore = nil
        privacyConfig = nil

        privacyConfigurationManager = nil
        super.tearDown()
    }

    // MARK: - Tests for App Store

    func testSubscriptionPurchaseNotAllowedWhenAllFlagsDisabledAndNotInternalUser() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [:]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertFalse(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testSubscriptionPurchaseAllowedWhenAllowPurchaseFlagEnabled() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.allowPurchase])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [:]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testSubscriptionPurchaseAllowedWhenAllFlagsDisabledAndInternalUser() {
        internalUserDeciderStore.isInternalUser = true
        XCTAssertTrue(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [:]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    // MARK: - Tests for Pro Tier Purchase

    func testProTierPurchaseDisabledWhenFeatureFlagDisabled() {
        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [.proTierPurchase: false]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertFalse(subscriptionFeatureAvailability.isProTierPurchaseEnabled)
    }

    func testProTierPurchaseEnabledWhenFeatureFlagEnabled() {
        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [.proTierPurchase: true]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertTrue(subscriptionFeatureAvailability.isProTierPurchaseEnabled)
    }

    // MARK: - Tests for DuckAI Premium

    func testPaidAIChatDisabledWhenFeatureFlagDisabled() {
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.paidAIChat))

        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [.paidAIChat: false]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertFalse(subscriptionFeatureAvailability.isPaidAIChatEnabled)
    }

    func testPaidAIChatEnabledWhenFeatureFlagEnabled() {
        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.paidAIChat])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.paidAIChat))

        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [.paidAIChat: true]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertTrue(subscriptionFeatureAvailability.isPaidAIChatEnabled)
    }

    // MARK: - Tests for Stripe

    func testStripeSubscriptionPurchaseNotAllowedWhenAllFlagsDisabledAndNotInternalUser() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [:]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .stripe,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertFalse(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testStripeSubscriptionPurchaseAllowedWhenAllowPurchaseFlagEnabled() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.allowPurchaseStripe])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [:]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .stripe,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testStripeSubscriptionPurchaseAllowedWhenAllFlagsDisabledAndInternalUser() {
        internalUserDeciderStore.isInternalUser = true
        XCTAssertTrue(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [:]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .stripe,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    // MARK: - Tests for Alternate Stripe Payment Flow Support

    func testSupportsAlternateStripePaymentFlowDisabledWhenProviderReturnsFalse() {
        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [.supportsAlternateStripePaymentFlow: false]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertFalse(subscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled)
    }

    func testSupportsAlternateStripePaymentFlowEnabledWhenProviderReturnsTrue() {
        let featureFlagProvider = MockSubscriptionPageFeatureFlagProvider()
        featureFlagProvider.flags = [.supportsAlternateStripePaymentFlow: true]

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     featureFlagProvider: featureFlagProvider)
        XCTAssertTrue(subscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled)
    }

    // MARK: - Helper

    private func makeSubfeatureEnabledCheck(for enabledSubfeatures: [PrivacyProSubfeature]) -> (any PrivacySubfeature, AppVersionProvider) -> Bool {
        return { privacySubfeature, _ in
            guard let subfeature = privacySubfeature as? PrivacyProSubfeature else { return false }
            return enabledSubfeatures.contains(subfeature)
        }
    }
}

class MockSubscriptionPageFeatureFlagProvider: SubscriptionPageFeatureFlagProviding {
    var flags: [SubscriptionPageFeatureFlag: Bool] = [:]

    func isEnabled(_ flag: SubscriptionPageFeatureFlag) -> Bool {
        return flags[flag] ?? false
    }
}

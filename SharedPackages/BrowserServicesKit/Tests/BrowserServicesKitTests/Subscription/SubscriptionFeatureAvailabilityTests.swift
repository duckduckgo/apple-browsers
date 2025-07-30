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

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     paidAIChatFlagStatusProvider: { true },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { false })
        XCTAssertFalse(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testSubscriptionPurchaseAllowedWhenAllowPurchaseFlagEnabled() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.allowPurchase])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     paidAIChatFlagStatusProvider: { true },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { false })
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testSubscriptionPurchaseAllowedWhenAllFlagsDisabledAndInternalUser() {
        internalUserDeciderStore.isInternalUser = true
        XCTAssertTrue(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     paidAIChatFlagStatusProvider: { true },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { false })
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    // MARK: - Tests for DuckAI Premium

    func testPaidAIChatDisabledWhenFeatureFlagDisabled() {
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.paidAIChat))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     paidAIChatFlagStatusProvider: { false },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { false })
        XCTAssertFalse(subscriptionFeatureAvailability.isPaidAIChatEnabled)
    }

    func testPaidAIChatEnabledWhenFeatureFlagEnabled() {
        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.paidAIChat])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.paidAIChat))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     paidAIChatFlagStatusProvider: { true },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { false })
        XCTAssertTrue(subscriptionFeatureAvailability.isPaidAIChatEnabled)
    }

    // MARK: - Tests for Stripe

    func testStripeSubscriptionPurchaseNotAllowedWhenAllFlagsDisabledAndNotInternalUser() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .stripe,
                                                                                     paidAIChatFlagStatusProvider: { true },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { false })
        XCTAssertFalse(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testStripeSubscriptionPurchaseAllowedWhenAllowPurchaseFlagEnabled() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.allowPurchaseStripe])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .stripe,
                                                                                     paidAIChatFlagStatusProvider: { true },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { false })
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testStripeSubscriptionPurchaseAllowedWhenAllFlagsDisabledAndInternalUser() {
        internalUserDeciderStore.isInternalUser = true
        XCTAssertTrue(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .stripe,
                                                                                     paidAIChatFlagStatusProvider: { true },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { false })
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    // MARK: - Tests for Alternate Stripe Payment Flow Support

    func testSupportsAlternateStripePaymentFlowDisabledWhenProviderReturnsFalse() {
        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     paidAIChatFlagStatusProvider: { false },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { false })
        XCTAssertFalse(subscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled)
    }

    func testSupportsAlternateStripePaymentFlowEnabledWhenProviderReturnsTrue() {
        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     purchasePlatform: .appStore,
                                                                                     paidAIChatFlagStatusProvider: { false },
                                                                                     supportsAlternateStripePaymentFlowStatusProvider: { true })
        XCTAssertTrue(subscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled)
    }

    // MARK: - Helper

    private func makeSubfeatureEnabledCheck(for enabledSubfeatures: [PrivacyProSubfeature]) -> (any PrivacySubfeature) -> Bool {
        return {
            guard let subfeature = $0 as? PrivacyProSubfeature else { return false }
            return enabledSubfeatures.contains(subfeature)
        }
    }
}

class MockPrivacyConfiguration: PrivacyConfiguration {

    var isSubfeatureEnabledCheck: ((any PrivacySubfeature) -> Bool)?
    func isSubfeatureEnabled(_ subfeature: any BrowserServicesKit.PrivacySubfeature, versionProvider: BrowserServicesKit.AppVersionProvider, randomizer: (Range<Double>) -> Double, defaultValue: Bool) -> Bool {
        isSubfeatureEnabledCheck?(subfeature) ?? false
    }

    func isEnabled(featureKey: BrowserServicesKit.PrivacyFeature, versionProvider: BrowserServicesKit.AppVersionProvider, defaultValue: Bool) -> Bool {
        true
    }

    func stateFor(featureKey: BrowserServicesKit.PrivacyFeature, versionProvider: BrowserServicesKit.AppVersionProvider) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
        return .enabled
    }

    func stateFor(_ subfeature: any BrowserServicesKit.PrivacySubfeature, versionProvider: BrowserServicesKit.AppVersionProvider, randomizer: (Range<Double>) -> Double) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
        if isSubfeatureEnabledCheck?(subfeature) == true {
            return .enabled
        }
        return .disabled(.disabledInConfig)
    }

    func stateFor(subfeatureID: BrowserServicesKit.SubfeatureID, parentFeatureID: BrowserServicesKit.ParentFeatureID, versionProvider: BrowserServicesKit.AppVersionProvider, randomizer: (Range<Double>) -> Double) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
        return .enabled
    }

    func cohorts(for subfeature: any BrowserServicesKit.PrivacySubfeature) -> [BrowserServicesKit.PrivacyConfigurationData.Cohort]? {
        return nil
    }

    func cohorts(subfeatureID: BrowserServicesKit.SubfeatureID, parentFeatureID: BrowserServicesKit.ParentFeatureID) -> [BrowserServicesKit.PrivacyConfigurationData.Cohort]? {
        return nil
    }

    func settings(for subfeature: any BrowserServicesKit.PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
        return nil
    }

    var identifier: String = "abcd"
    var version: String? = "123456789"
    var userUnprotectedDomains: [String] = []
    var tempUnprotectedDomains: [String] = []
    var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist = .init(json: ["state": "disabled"])!
    func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] { [] }
    func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool { true }
    func isProtected(domain: String?) -> Bool { false }
    func isUserUnprotected(domain: String?) -> Bool { false }
    func isTempUnprotected(domain: String?) -> Bool { false }
    func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool { false }
    func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings { .init() }
    func userEnabledProtection(forDomain: String) {}
    func userDisabledProtection(forDomain: String) {}
}

class MockPrivacyConfigurationManager: PrivacyConfigurationManaging {
    var currentConfigString: String = ""
    var currentConfig: Data {
        currentConfigString.data(using: .utf8)!
    }
    var updatesSubject = PassthroughSubject<Void, Never>()
    let updatesPublisher: AnyPublisher<Void, Never>
    var privacyConfig: PrivacyConfiguration
    let internalUserDecider: InternalUserDecider
    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        .downloaded
    }

    init(privacyConfig: PrivacyConfiguration, internalUserDecider: InternalUserDecider) {
        self.updatesPublisher = updatesSubject.eraseToAnyPublisher()
        self.privacyConfig = privacyConfig
        self.internalUserDecider = internalUserDecider
    }
}

//
//  FreemiumDBPFeatureTests.swift
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
@testable import DuckDuckGo_Privacy_Browser
import Subscription
import BrowserServicesKit
import SubscriptionTestingUtilities
import Freemium
import Combine

final class FreemiumDBPFeatureTests: XCTestCase {

    private var sut: FreemiumDBPFeature!
    private var mockPrivacyConfigurationManager: MockPrivacyConfigurationManaging!
    private var mockAccountManager: MockAccountManager!
    private var mockSubscriptionManager: SubscriptionManagerMock!
    private var mockFreemiumDBPUserStateManagerManager: MockFreemiumDBPUserStateManager!
    private var mockFeatureDisabler: MockFeatureDisabler!
    private var mockStorePurchaseManager: StorePurchaseManagerMock!
    private var testUserDefaults: UserDefaults!

    private var cancellables: Set<AnyCancellable> = []

    override func setUpWithError() throws {

        mockPrivacyConfigurationManager = MockPrivacyConfigurationManaging()
        mockAccountManager = MockAccountManager()
        let mockSubscriptionService = SubscriptionEndpointServiceMock()
        let mockAuthService = AuthEndpointServiceMock()
        mockStorePurchaseManager = StorePurchaseManagerMock()
        let mockSubscriptionFeatureMappingCache = SubscriptionFeatureMappingCacheMock()

        let currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                         purchasePlatform: .appStore)

        mockSubscriptionManager = SubscriptionManagerMock(accountManager: mockAccountManager,
                                                          subscriptionEndpointService: mockSubscriptionService,
                                                          authEndpointService: mockAuthService,
                                                          storePurchaseManager: mockStorePurchaseManager,
                                                          currentEnvironment: currentEnvironment,
                                                          canPurchase: false,
                                                          subscriptionFeatureMappingCache: mockSubscriptionFeatureMappingCache)

        mockFreemiumDBPUserStateManagerManager = MockFreemiumDBPUserStateManager()
        mockFeatureDisabler = MockFeatureDisabler()

        // Create isolated UserDefaults for testing
        testUserDefaults = UserDefaults(suiteName: "FreemiumDBPFeatureTests-\(UUID().uuidString)")!
    }

    override func tearDownWithError() throws {
        // Clean up test UserDefaults by removing the specific key we use
        testUserDefaults.removeObject(forKey: FreemiumDBPFeatureKeys.featureFlagOverride)
        testUserDefaults.removeObject(forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride)
        testUserDefaults = nil
        try super.tearDownWithError()
    }

    func testWhenPrivacyProNotAvailable_thenFreemiumDBPIsNotAvailable() throws {
        // Given
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = false
        mockAccountManager.accessToken = nil
        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)
        // When
        let result = sut.isAvailable

        // Then
        XCTAssertFalse(result)
    }

    func testWhenAllConditionsAreNotMet_thenFreemiumDBPIsNotAvailable() throws {
        // Given
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockSubscriptionManager.canPurchase = false
        mockAccountManager.accessToken = "some_token"
        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)
        // When
        let result = sut.isAvailable

        // Then
        XCTAssertFalse(result)
    }

    func testWhenUserAlreadySubscribed_thenFreemiumDBPIsNotAvailable() throws {
        // Given
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = "some_token"
        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)
        // When
        let result = sut.isAvailable

        // Then
        XCTAssertFalse(result)
    }

    func testWhenUserDidNotActivate_thenOffboardingIsNotExecuted() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = false
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil

        // When
        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)

        // Then
        XCTAssertFalse(mockFeatureDisabler.disableAndDeleteWasCalled)
    }

    func testWhenUserdidActivate_andFeatureIsDisabled_andUserCanPurchase_andUserIsNotSubscribed_thenOffboardingIsExecuted() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil

        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)

        // When
        sut.subscribeToDependencyUpdates()
        mockPrivacyConfigurationManager.updatesSubject.send()

        // Then
        XCTAssertTrue(mockFreemiumDBPUserStateManagerManager.didCallResetAllState)
        XCTAssertTrue(mockFeatureDisabler.disableAndDeleteWasCalled)
    }

    func testWhenUserdidActivate_andFeatureIsDisabled_andUserCanPurchase_andUserIsSubscribed_thenOffboardingIsNotExecuted() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = "some_token"

        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)

        // When
        sut.subscribeToDependencyUpdates()
        mockPrivacyConfigurationManager.updatesSubject.send()

        // Then
        XCTAssertFalse(mockFreemiumDBPUserStateManagerManager.didCallResetAllState)
        XCTAssertFalse(mockFeatureDisabler.disableAndDeleteWasCalled)
    }

    func testWhenUserdidActivate_andFeatureIsEnabled_andUserCanPurchase_andUserIsNotSubscribed_thenOffboardingIsNotExecuted() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil

        // When
        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)

        // Then
        XCTAssertTrue(mockFreemiumDBPUserStateManagerManager.didActivate)
        XCTAssertFalse(mockFeatureDisabler.disableAndDeleteWasCalled)
    }

    func testWhenUserdidActivate_andFeatureIsDisabled_andUserCannotPurchase_thenOffboardingIsNotExecuted() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = false
        mockAccountManager.accessToken = nil

        // When
        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)

        // Then
        XCTAssertTrue(mockFreemiumDBPUserStateManagerManager.didActivate)
        XCTAssertFalse(mockFeatureDisabler.disableAndDeleteWasCalled)
    }

    func testWhenFeatureFlagValueChangesToEnabled_thenIsAvailablePublisherEmitsCorrectValue() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        let expectation = XCTestExpectation(description: "isAvailablePublisher emits values")

        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)

        XCTAssertFalse(sut.isAvailable)

        var isAvailableResult = false
        sut.isAvailablePublisher
            .sink { isAvailable in
                isAvailableResult = isAvailable
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut.subscribeToDependencyUpdates()
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockPrivacyConfigurationManager.updatesSubject.send()

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(isAvailableResult)
    }

    func testWhenFeatureFlagValueChangesToDisabled_thenIsAvailablePublisherEmitsCorrectValue() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        let expectation = XCTestExpectation(description: "isAvailablePublisher emits values")

        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)

        XCTAssertTrue(sut.isAvailable)

        var isAvailableResult = false
        sut.isAvailablePublisher
            .sink { isAvailable in
                isAvailableResult = isAvailable
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut.subscribeToDependencyUpdates()
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockPrivacyConfigurationManager.updatesSubject.send()

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(isAvailableResult)
    }

    func testSubscriptionStatusChangesToSubscribed_thenIsAvailablePublisherEmitsCorrectValue() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        let expectation = XCTestExpectation(description: "isAvailablePublisher emits values")

        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)

        XCTAssertTrue(sut.isAvailable)

        var isAvailableResult = false
        sut.isAvailablePublisher
            .sink { isAvailable in
                isAvailableResult = isAvailable
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut.subscribeToDependencyUpdates()
        mockAccountManager.accessToken = "some_token"
        NotificationCenter.default.post(name: .subscriptionDidChange, object: nil)

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(isAvailableResult)
    }

    func testSubscriptionStatusChangesToUnsubscribed_thenIsAvailablePublisherEmitsCorrectValue() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = "some_token"
        let expectation = XCTestExpectation(description: "isAvailablePublisher emits values")

        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)

        XCTAssertFalse(sut.isAvailable)

        var isAvailableResult = false
        sut.isAvailablePublisher
            .sink { isAvailable in
                isAvailableResult = isAvailable
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut.subscribeToDependencyUpdates()
        mockAccountManager.accessToken = nil
        NotificationCenter.default.post(name: .subscriptionDidChange, object: nil)

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(isAvailableResult)
    }

    func testIsAvailablePublisherEmitsWhenCanPurchaseChangesOnAppStore() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = false
        mockAccountManager.accessToken = nil

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        let expectation = XCTestExpectation(description: "isAvailablePublisher emits when canPurchase changes")
        var results: [Bool] = []
        sut.isAvailablePublisher
            .sink { isAvailable in
                results.append(isAvailable)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.subscribeToDependencyUpdates()

        // When
        mockSubscriptionManager.canPurchase = true
        mockSubscriptionManager.canPurchaseSubject.send(true)

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(results, [true])
    }

    func testIsAvailablePublisherDoesNotEmitWhenCanPurchaseChangesOnNonAppStore() {
        // Given
        let nonAppStoreEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)
        mockSubscriptionManager.currentEnvironment = nonAppStoreEnvironment
        mockFreemiumDBPUserStateManagerManager.didActivate = false
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = false
        mockAccountManager.accessToken = nil

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        let expectation = XCTestExpectation(description: "isAvailablePublisher does not emit on canPurchase change for non-appStore")
        expectation.isInverted = true

        sut.isAvailablePublisher
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.subscribeToDependencyUpdates()

        // When
        mockSubscriptionManager.canPurchase = true
        mockSubscriptionManager.canPurchaseSubject.send(true)

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    @available(macOS 12.0, *)
    func testWhenStorefrontIsUSA_andCanPurchase_andNotSubscribed_thenIsAvailable() throws {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .usa
        let currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        mockSubscriptionManager.currentEnvironment = currentEnvironment

        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)
        // When
        let result = sut.isAvailable

        // Then
        XCTAssertTrue(result)
    }

    @available(macOS 12.0, *)
    func testWhenStorefrontIsNotUSA_andCanPurchase_andNotSubscribed_thenIsNotAvailable() throws {
        // Given
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .restOfWorld
        let currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        mockSubscriptionManager.currentEnvironment = currentEnvironment

        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)
        // When
        let result = sut.isAvailable

        // Then
        XCTAssertFalse(result)
    }

    @available(macOS 12.0, *)
    func testWhenPlatformIsStripe_thenStorefrontIsIgnoredAndIsAvailable() throws {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .restOfWorld
        let currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)
        mockSubscriptionManager.currentEnvironment = currentEnvironment

        sut = DefaultFreemiumDBPFeature(privacyConfigurationManager: mockPrivacyConfigurationManager,
                                        subscriptionManager: mockSubscriptionManager,
                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
                                        featureDisabler: mockFeatureDisabler,
                                        userDefaults: testUserDefaults)
        // When
        let result = sut.isAvailable

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - Override Functionality Tests

    func testWhenFeatureFlagOverrideIsSetToTrue_thenIsAvailableIsTrue() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false } // Real value is false
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .usa

        // Set override to true
        testUserDefaults.set(true, forKey: FreemiumDBPFeatureKeys.featureFlagOverride)

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        // When
        let result = sut.isAvailable

        // Then
        XCTAssertTrue(result, "Override should make feature available even when privacy config is disabled")
    }

    func testWhenFeatureFlagOverrideIsSetToFalse_thenIsAvailableIsFalse() {
        // Given
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true } // Real value is true
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .usa

        // Set override to false
        testUserDefaults.set(false, forKey: FreemiumDBPFeatureKeys.featureFlagOverride)

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        // When
        let result = sut.isAvailable

        // Then
        XCTAssertFalse(result, "Override should make feature unavailable even when privacy config is enabled")
    }

    func testWhenNoOverrideIsSet_thenRealFeatureFlagValueIsUsed() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .usa

        // No override set in UserDefaults

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        // When
        let result = sut.isAvailable

        // Then
        XCTAssertTrue(result, "Should use real privacy config value when no override is set")
    }

    @available(macOS 12.0, *)
    func testWhenStorefrontOverrideIsSetToTrue_thenIsAvailableIsTrue() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .restOfWorld // Real value is non-USA

        // Set override to true
        testUserDefaults.set(true, forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride)

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        // When
        let result = sut.isAvailable

        // Then
        XCTAssertTrue(result, "Override should make feature available even when storefront is non-USA")
    }

    @available(macOS 12.0, *)
    func testWhenStorefrontOverrideIsSetToFalse_thenIsAvailableIsFalse() {
        // Given
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in true }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .usa // Real value is USA

        // Set override to false
        testUserDefaults.set(false, forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride)

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        // When
        let result = sut.isAvailable

        // Then
        XCTAssertFalse(result, "Override should make feature unavailable even when storefront is USA")
    }

    @available(macOS 12.0, *)
    func testWhenFeatureFlagOverrideIsTrueAndStorefrontIsNonUSA_thenIsAvailableIsFalse() {
        // Given: Real storefront is non-USA and there's no storefront override
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .restOfWorld

        // When: Only the feature flag is overridden to true
        testUserDefaults.set(true, forKey: FreemiumDBPFeatureKeys.featureFlagOverride)

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        // Then: The feature should still be unavailable due to the storefront check
        let result = sut.isAvailable
        XCTAssertFalse(result, "Feature flag override should not affect storefront eligibility")
    }

    @available(macOS 12.0, *)
    func testWhenStorefrontOverrideIsTrueAndFeatureFlagIsFalse_thenIsAvailableIsFalse() {
        // Given: Real feature flag is false and there's no flag override
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .restOfWorld

        // When: Only the storefront is overridden to true
        testUserDefaults.set(true, forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride)

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        // Then: The feature should still be unavailable due to the feature flag check
        let result = sut.isAvailable
        XCTAssertFalse(result, "Storefront override should not affect feature flag eligibility")
    }

    func testWhenFeatureFlagOverrideIsSetAndPublisherUpdates_thenOverrideTakesPrecedence() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil
        mockStorePurchaseManager.currentStorefrontRegion = .usa

        // Set override to true
        testUserDefaults.set(true, forKey: FreemiumDBPFeatureKeys.featureFlagOverride)

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        let expectation = XCTestExpectation(description: "Publisher emits with override value")
        var emittedValue: Bool?

        sut.isAvailablePublisher
            .sink { isAvailable in
                emittedValue = isAvailable
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut.subscribeToDependencyUpdates()
        // Simulate a privacy config update which would normally set isAvailable to false
        mockPrivacyConfigurationManager.updatesSubject.send()

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(emittedValue, true, "Publisher should emit override value even when real config changes")
    }

    func testWhenFeatureDisablerIsInjected_thenInjectedInstanceIsUsed() {
        // Given
        let injectedFeatureDisabler = MockFeatureDisabler()
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockAccountManager.accessToken = nil
        // Need to set up conditions for shouldDisableAndDelete to be true
        mockSubscriptionManager.canPurchase = true
        mockStorePurchaseManager.currentStorefrontRegion = .usa

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: injectedFeatureDisabler,
            userDefaults: testUserDefaults
        )

        // When
        sut.subscribeToDependencyUpdates()
        mockPrivacyConfigurationManager.updatesSubject.send()

        // Then
        XCTAssertTrue(injectedFeatureDisabler.disableAndDeleteWasCalled, "Injected feature disabler should be used")
        XCTAssertFalse(mockFeatureDisabler.disableAndDeleteWasCalled, "Default feature disabler should not be used")
    }

    func testWhenUserDefaultsIsInjected_thenInjectedInstanceIsUsed() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        let anotherUserDefaults = UserDefaults(suiteName: "AnotherTestSuite-\(UUID().uuidString)")!
        defer {
            anotherUserDefaults.removeObject(forKey: FreemiumDBPFeatureKeys.featureFlagOverride)
            anotherUserDefaults.removeObject(forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride)
        }

        // Set override in the injected UserDefaults
        anotherUserDefaults.set(true, forKey: FreemiumDBPFeatureKeys.featureFlagOverride)

        // Don't set override in the default testUserDefaults
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockSubscriptionManager.canPurchase = true
        mockAccountManager.accessToken = nil

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: anotherUserDefaults
        )

        // When
        let result = sut.isAvailable

        // Then
        XCTAssertTrue(result, "Should use override from injected UserDefaults instance")
    }

    func testOffboarding_WhenConditionsMetAndNoOverride_TriggersSuccessfully() {
        // Given
        mockFreemiumDBPUserStateManagerManager.didActivate = true
        mockPrivacyConfigurationManager.mockConfig.isSubfeatureKeyEnabled = { _, _ in false }
        mockAccountManager.accessToken = nil
        mockSubscriptionManager.canPurchase = true
        mockStorePurchaseManager.currentStorefrontRegion = .usa

        // Ensure no overrides are set
        testUserDefaults.removeObject(forKey: FreemiumDBPFeatureKeys.featureFlagOverride)
        testUserDefaults.removeObject(forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride)

        sut = DefaultFreemiumDBPFeature(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            subscriptionManager: mockSubscriptionManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManagerManager,
            featureDisabler: mockFeatureDisabler,
            userDefaults: testUserDefaults
        )

        // When
        sut.subscribeToDependencyUpdates()
        mockPrivacyConfigurationManager.updatesSubject.send()

        // Then
        XCTAssertTrue(mockFreemiumDBPUserStateManagerManager.didCallResetAllState, "Should offboard when conditions are met and no override is active")
        XCTAssertTrue(mockFeatureDisabler.disableAndDeleteWasCalled, "Should disable and delete when conditions are met and no override is active")
    }
}

final class MockFeatureDisabler: DataBrokerProtectionFeatureDisabling {
    var disableAndDeleteWasCalled = false

    func disableAndDelete() {
        disableAndDeleteWasCalled = true
    }

    func reset() {
        disableAndDeleteWasCalled = false
    }
}

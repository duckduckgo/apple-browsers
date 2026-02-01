//
//  SubscriptionPagesUseSubscriptionFeatureTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import WebKit
import PixelKit
import PrivacyConfig
@testable import DuckDuckGo
@testable import Common
@testable import UserScript
@testable import Subscription
import SubscriptionTestingUtilities
import PixelKitTestingUtilities
import Networking

final class SubscriptionPagesUseSubscriptionFeatureTests: XCTestCase {
    
    var sut: DefaultSubscriptionPagesUseSubscriptionFeature!
    var mockSubscriptionManager: SubscriptionManagerMock!
    var mockStripePurchaseFlow: StripePurchaseFlowMock!
    var mockSubscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock!
    var mockNotificationCenter: NotificationCenter!
    var mockWideEvent: WideEventMock!
    var mockInternalUserDecider: MockInternalUserDecider!
    var mockTierEventReporter: MockSubscriptionTierEventReporter!

    @MainActor
    override func setUp() {
        super.setUp()
        
        mockSubscriptionManager = SubscriptionManagerMock()
        mockStripePurchaseFlow = StripePurchaseFlowMock(prepareSubscriptionPurchaseResult: .success((purchaseUpdate: .completed, accountCreationDuration: nil)))
        mockSubscriptionFeatureAvailability = SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true)
        mockNotificationCenter = NotificationCenter()
        mockWideEvent = WideEventMock()
        mockInternalUserDecider = MockInternalUserDecider(isInternalUser: true)
        mockTierEventReporter = MockSubscriptionTierEventReporter()

        sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: "",
            appStorePurchaseFlow: AppStorePurchaseFlowMock(),
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            tierEventReporter: mockTierEventReporter,
            pendingTransactionHandler: MockPendingTransactionHandler())
    }
    
    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        mockStripePurchaseFlow = nil
        mockSubscriptionFeatureAvailability = nil
        mockNotificationCenter = nil
        mockWideEvent = nil
        mockTierEventReporter = nil
        super.tearDown()
    }
    
    func testGetFeatureConfig_WhenPaidAIChatEnabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isPaidAIChatEnabled = true

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureConfigurationResponse else {
            XCTFail("Expected GetFeatureValue type")
            return
        }
        
        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertTrue(featureValue.usePaidDuckAi)
    }
    
    func testGetFeatureConfig_WhenPaidAIChatDisabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isPaidAIChatEnabled = false

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureConfigurationResponse else {
            XCTFail("Expected GetFeatureValue type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertFalse(featureValue.usePaidDuckAi)
    }
    
    func testGetFeatureConfig_WhenStripeSupported_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled = true

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureConfigurationResponse else {
            XCTFail("Expected GetFeatureConfigurationResponse type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertTrue(featureValue.useAlternateStripePaymentFlow)
    }

    func testGetFeatureConfig_WhenStripeNotSupported_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled = false

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureConfigurationResponse else {
            XCTFail("Expected GetFeatureConfigurationResponse type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertFalse(featureValue.useAlternateStripePaymentFlow)
    }

    func testGetFeatureConfig_WhenBothFeaturesEnabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isPaidAIChatEnabled = true
        mockSubscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled = true

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureConfigurationResponse else {
            XCTFail("Expected GetFeatureConfigurationResponse type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertTrue(featureValue.usePaidDuckAi)
        XCTAssertTrue(featureValue.useAlternateStripePaymentFlow)
        XCTAssertTrue(featureValue.useGetSubscriptionTierOptions)
    }

    func testGetFeatureConfig_WhenBothFeaturesDisabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isPaidAIChatEnabled = false
        mockSubscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled = false

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureConfigurationResponse else {
            XCTFail("Expected GetFeatureConfigurationResponse type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertFalse(featureValue.usePaidDuckAi)
        XCTAssertFalse(featureValue.useAlternateStripePaymentFlow)
    }

    // MARK: - GetSubscriptionTierOptions Tests

    func testGetSubscriptionTierOptions_WhenProTierEnabled_PassesTrueToIncludeProTier() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isProTierPurchaseEnabled = true
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = true
        
        let expectedTierOptions = SubscriptionTierOptions(
            platform: .ios,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: [
                        SubscriptionOption(id: "1",
                                           cost: SubscriptionOptionCost(displayPrice: "5 USD", recurrence: "monthly"),
                                           offer: nil)
                    ]
                )
            ]
        )
        
        let mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(expectedTierOptions)
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        // When
        let result = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(mockStorePurchaseManager.subscriptionTierOptionsIncludeProTierCalled, true, "Should pass true to includeProTier when Pro tier is enabled")
        
        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .ios)
        XCTAssertEqual(tierOptions.products.count, 1)
        XCTAssertEqual(tierOptions.products[0].tier, .plus)
        XCTAssertFalse(tierOptions.products[0].options.isEmpty, "Should have purchase options when purchase is allowed")
    }

    func testGetSubscriptionTierOptions_WhenProTierDisabled_PassesFalseToIncludeProTier() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isProTierPurchaseEnabled = false
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = true
        
        let tierOptionsWithPurchase = SubscriptionTierOptions(
            platform: .ios,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: [
                        SubscriptionOption(id: "1",
                                           cost: SubscriptionOptionCost(displayPrice: "5 USD", recurrence: "monthly"),
                                           offer: nil)
                    ]
                )
            ]
        )
        
        let mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(tierOptionsWithPurchase)
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        // When
        let result = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(mockStorePurchaseManager.subscriptionTierOptionsIncludeProTierCalled, false, "Should pass false to includeProTier when Pro tier is disabled")
        
        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .ios)
        XCTAssertFalse(tierOptions.products[0].options.isEmpty, "Should still have purchase options when purchase is allowed")
    }

    func testGetSubscriptionTierOptions_WhenPurchaseNotAllowed_StripsPurchaseOptions() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isProTierPurchaseEnabled = true
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = false
        
        let tierOptionsWithPurchase = SubscriptionTierOptions(
            platform: .ios,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: [
                        SubscriptionOption(id: "1",
                                           cost: SubscriptionOptionCost(displayPrice: "5 USD", recurrence: "monthly"),
                                           offer: nil)
                    ]
                )
            ]
        )
        
        let mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(tierOptionsWithPurchase)
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        // When
        let result = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(mockStorePurchaseManager.subscriptionTierOptionsIncludeProTierCalled, true, "Should still pass Pro tier flag correctly")
        
        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .ios)
        XCTAssertTrue(tierOptions.products[0].options.isEmpty, "Should strip purchase options when purchase is not allowed")
    }

    func testGetSubscriptionTierOptions_WhenNoOptionsAvailable_ReturnsEmpty() async throws {
        // Given
        let mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.subscriptionTierOptionsResult = .failure(.tieredProductsNoProductsAvailable)
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        // When
        let result = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .ios)
        XCTAssertTrue(tierOptions.products.isEmpty, "Should return empty tier options when none are available")
    }

    // MARK: - Tier Options Pixel Tests

    func testGetSubscriptionTierOptions_AlwaysFiresRequestedPixel() async throws {
        // Given
        let expectedTierOptions = SubscriptionTierOptions(
            platform: .ios,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: []
                )
            ]
        )
        let mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(expectedTierOptions)
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertTrue(mockTierEventReporter.requestedCalled, "Should fire requested pixel")
    }

    func testGetSubscriptionTierOptions_OnSuccess_FiresSuccessPixel() async throws {
        // Given
        let expectedTierOptions = SubscriptionTierOptions(
            platform: .ios,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: []
                )
            ]
        )
        let mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(expectedTierOptions)
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertTrue(mockTierEventReporter.successCalled, "Should fire success pixel")
        XCTAssertFalse(mockTierEventReporter.failureCalled, "Should not fire failure pixel on success")
    }

    func testGetSubscriptionTierOptions_OnFailure_FiresFailurePixel() async throws {
        // Given
        let mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.subscriptionTierOptionsResult = .failure(.tieredProductsNoProductsAvailable)
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertTrue(mockTierEventReporter.failureCalled, "Should fire failure pixel")
        XCTAssertNotNil(mockTierEventReporter.failureError, "Should include error in failure pixel")
        XCTAssertFalse(mockTierEventReporter.successCalled, "Should not fire success pixel on failure")
    }

    func testGetSubscriptionTierOptions_WithProTierPresent_FiresUnexpectedProTierPixel() async throws {
        // Given
        let tierOptionsWithProTier = SubscriptionTierOptions(
            platform: .ios,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: []
                ),
                SubscriptionTier(
                    tier: .pro,
                    features: [TierFeature(product: .networkProtection, name: .pro)],
                    options: []
                )
            ]
        )
        let mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(tierOptionsWithProTier)
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertTrue(mockTierEventReporter.unexpectedProTierCalled, "Should fire unexpected pro tier pixel")
    }

    func testGetSubscriptionTierOptions_WithoutProTier_DoesNotFireUnexpectedProTierPixel() async throws {
        // Given
        let tierOptionsWithoutProTier = SubscriptionTierOptions(
            platform: .ios,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: []
                )
            ]
        )
        let mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(tierOptionsWithoutProTier)
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertFalse(mockTierEventReporter.unexpectedProTierCalled, "Should not fire unexpected pro tier pixel")
    }

    @MainActor
    func testAppStoreSuccess_EmitsWidePixelWithContextAndDurations() async throws {
        let originURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionSelected", body: "", webView: webView)

        let storeManager = StorePurchaseManagerMock()
        storeManager.isEligibleForFreeTrialResult = true
        mockSubscriptionManager.resultStorePurchaseManager = storeManager

        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.purchaseSubscriptionResult = .success((transactionJWS: "jws", accountCreationDuration: nil))
        purchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        _ = await sut.subscriptionSelected(params: ["id": "yearly"], original: message)

        XCTAssertEqual(mockWideEvent.started.count, 1)
        XCTAssertEqual(mockWideEvent.completions.count, 1)

        let started = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionPurchaseWideEventData)
        XCTAssertEqual(started.purchasePlatform, .appStore)
        XCTAssertEqual(started.subscriptionIdentifier, "yearly")
        XCTAssertEqual(started.freeTrialEligible, true)
        XCTAssertEqual(started.contextData.name, "funnel_appsettings_ios")

        let updated = try XCTUnwrap(mockWideEvent.updates.last as? SubscriptionPurchaseWideEventData)
        XCTAssertNotNil(updated.activateAccountDuration?.start)
        XCTAssertNotNil(updated.activateAccountDuration?.end)

        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionPurchaseWideEventData)
        XCTAssertEqual(completion.1, .success(reason: nil))
    }

    @MainActor
    func testAppStoreCancelled_EmitsWideEventCancelled() async throws {
        let originURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_onboarding_ios")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionSelected", body: "", webView: webView)

        let storeManager = StorePurchaseManagerMock()
        mockSubscriptionManager.resultStorePurchaseManager = storeManager

        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.purchaseSubscriptionResult = .failure(.cancelledByUser)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        _ = await sut.subscriptionSelected(params: ["id": "monthly"], original: message)

        XCTAssertEqual(mockWideEvent.started.count, 1)
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(completion.1, .cancelled)
    }

    @MainActor
    func testOriginPrecedence_UsesAttributionOriginOverURL() async throws {
        let urlOrigin = URL(string: "https://duckduckgo.com/subscriptions")!
        let webView = MockURLWebView(url: urlOrigin)
        let message = MockWKScriptMessage(name: "subscriptionSelected", body: "", webView: webView)

        let storeManager = StorePurchaseManagerMock()
        mockSubscriptionManager.resultStorePurchaseManager = storeManager

        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.purchaseSubscriptionResult = .failure(.cancelledByUser)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        _ = await sut.subscriptionSelected(params: ["id": "monthly"], original: message)

        let started = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionPurchaseWideEventData)
        XCTAssertEqual(started.contextData.name, SubscriptionFunnelOrigin.appSettings.rawValue)
    }

    // MARK: - SubscriptionChangeSelected Tests

    @MainActor
    func testSubscriptionChangeSelected_WhenTierChangeSucceeds_SetsIdleStatus() async throws {
        // Given
        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.changeTierResult = .success("mock-transaction-jws")
        purchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        let params: [String: Any] = ["id": "yearly-pro", "change": "upgrade"]
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "")

        // When
        _ = await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertEqual(sut.transactionStatus, .idle)
        XCTAssertNil(sut.transactionError)
        XCTAssertTrue(purchaseFlow.changeTierCalled)
        XCTAssertEqual(purchaseFlow.changeTierSubscriptionIdentifier, "yearly-pro")
    }

    @MainActor
    func testSubscriptionChangeSelected_WhenUserCancels_SetsCancelledError() async throws {
        // Given
        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.changeTierResult = .failure(.cancelledByUser)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        let params: [String: Any] = ["id": "yearly-pro", "change": "upgrade"]
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "")

        // When
        _ = await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertEqual(sut.transactionStatus, .idle)
        XCTAssertEqual(sut.transactionError, .cancelledByUser)
        XCTAssertTrue(purchaseFlow.changeTierCalled)
    }

    @MainActor
    func testSubscriptionChangeSelected_WhenPurchaseFails_SetsPurchaseFailedError() async throws {
        // Given
        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.changeTierResult = .failure(.purchaseFailed(NSError(domain: "test", code: 0)))

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        let params: [String: Any] = ["id": "yearly-pro", "change": "upgrade"]
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "")

        // When
        _ = await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertEqual(sut.transactionStatus, .idle)
        XCTAssertEqual(sut.transactionError, .purchaseFailed)
        XCTAssertTrue(purchaseFlow.changeTierCalled)
    }

    @MainActor
    func testSubscriptionChangeSelected_WhenCompletionFails_SetsMissingEntitlementsError() async throws {
        // Given
        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.changeTierResult = .success("mock-transaction-jws")
        purchaseFlow.completeSubscriptionPurchaseResult = .failure(.missingEntitlements)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        let params: [String: Any] = ["id": "yearly-pro", "change": "upgrade"]
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "")

        // When
        _ = await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertEqual(sut.transactionStatus, .idle)
        XCTAssertEqual(sut.transactionError, .missingEntitlements)
    }

    @MainActor
    func testSubscriptionChangeSelected_WhenInvalidParams_ReturnsNilWithoutCallingFlow() async throws {
        // Given
        let purchaseFlow = AppStorePurchaseFlowMock()

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        // Invalid params - missing "id"
        let params: [String: Any] = ["change": "upgrade"]
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "")

        // When
        let result = await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertNil(result)
        XCTAssertFalse(purchaseFlow.changeTierCalled)
        XCTAssertEqual(sut.transactionStatus, .idle)
    }

    @MainActor
    func testSubscriptionChangeSelected_CallsChangeTierWithCorrectIdentifier() async throws {
        // Given
        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.changeTierResult = .failure(.cancelledByUser)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        let params: [String: Any] = ["id": "monthly-plus", "change": "downgrade"]
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "")

        // When
        _ = await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertTrue(purchaseFlow.changeTierCalled)
        XCTAssertEqual(purchaseFlow.changeTierSubscriptionIdentifier, "monthly-plus")
    }
    
    // MARK: - Pending Transaction Tests
    
    @MainActor
    func testSubscriptionSelected_WhenTransactionPendingAuthentication_CallsMarkPurchasePending() async throws {
        // Given
        let mockPendingTransactionHandler = MockPendingTransactionHandler()
        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.purchaseSubscriptionResult = .failure(.transactionPendingAuthentication)
        
        let storeManager = StorePurchaseManagerMock()
        mockSubscriptionManager.resultStorePurchaseManager = storeManager
        
        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: "",
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: mockPendingTransactionHandler
        )
        
        let originURL = URL(string: "https://duckduckgo.com/subscriptions")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionSelected", body: "", webView: webView)
        
        // When
        _ = await sut.subscriptionSelected(params: ["id": "yearly"], original: message)
        
        // Then
        XCTAssertTrue(mockPendingTransactionHandler.markPurchasePendingCalled, "markPurchasePending should be called when transaction is pending authentication")
    }

    // MARK: - Plan Change Wide Event Tests

    @MainActor
    func testTierChangeSuccess_EmitsWideEventSuccess() async throws {
        let originURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "", webView: webView)

        // Set up existing subscription
        let existingSubscription = DuckDuckGoSubscription(
            productId: "ddg.privacy.plus.monthly.renews.us",
            name: "Plus Monthly",
            billingPeriod: .monthly,
            startedAt: Date(),
            expiresOrRenewsAt: Date().addingTimeInterval(30 * 24 * 60 * 60),
            platform: .apple,
            status: .autoRenewable,
            activeOffers: [],
            tier: .plus,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionManager.resultSubscription = .success(existingSubscription)

        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.changeTierResult = .success("jws-token")
        purchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        _ = await sut.subscriptionChangeSelected(params: ["id": "ddg.privacy.pro.monthly.renews.us", "change": "upgrade"], original: message)

        XCTAssertEqual(mockWideEvent.started.count, 1)
        XCTAssertEqual(mockWideEvent.completions.count, 1)

        let started = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionPlanChangeWideEventData)
        XCTAssertEqual(started.purchasePlatform, .appStore)
        XCTAssertEqual(started.fromPlan, "ddg.privacy.plus.monthly.renews.us")
        XCTAssertEqual(started.toPlan, "ddg.privacy.pro.monthly.renews.us")
        XCTAssertEqual(started.changeType, .upgrade)

        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionPlanChangeWideEventData)
        XCTAssertEqual(completion.1, .success(reason: nil))

        XCTAssertTrue(purchaseFlow.changeTierCalled)
        XCTAssertEqual(purchaseFlow.changeTierSubscriptionIdentifier, "ddg.privacy.pro.monthly.renews.us")
    }

    @MainActor
    func testTierChangeCancelled_EmitsWideEventCancelled() async throws {
        let originURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "", webView: webView)

        // Set up existing subscription
        let existingSubscription = DuckDuckGoSubscription(
            productId: "ddg.privacy.plus.monthly.renews.us",
            name: "Plus Monthly",
            billingPeriod: .monthly,
            startedAt: Date(),
            expiresOrRenewsAt: Date().addingTimeInterval(30 * 24 * 60 * 60),
            platform: .apple,
            status: .autoRenewable,
            activeOffers: [],
            tier: .plus,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionManager.resultSubscription = .success(existingSubscription)

        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.changeTierResult = .failure(.cancelledByUser)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        _ = await sut.subscriptionChangeSelected(params: ["id": "ddg.privacy.pro.monthly.renews.us", "change": "upgrade"], original: message)

        XCTAssertEqual(mockWideEvent.started.count, 1)
        XCTAssertEqual(mockWideEvent.completions.count, 1)

        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionPlanChangeWideEventData)
        XCTAssertEqual(completion.1, .cancelled)
    }

    @MainActor
    func testTierChangeFailure_EmitsWideEventFailure() async throws {
        let originURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "", webView: webView)

        // Set up existing subscription
        let existingSubscription = DuckDuckGoSubscription(
            productId: "ddg.privacy.pro.yearly.renews.us",
            name: "Pro Yearly",
            billingPeriod: .yearly,
            startedAt: Date(),
            expiresOrRenewsAt: Date().addingTimeInterval(365 * 24 * 60 * 60),
            platform: .apple,
            status: .autoRenewable,
            activeOffers: [],
            tier: .pro,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionManager.resultSubscription = .success(existingSubscription)

        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.changeTierResult = .failure(.purchaseFailed(NSError(domain: "Test", code: -1)))

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        _ = await sut.subscriptionChangeSelected(params: ["id": "ddg.privacy.plus.yearly.renews.us", "change": "downgrade"], original: message)

        XCTAssertEqual(mockWideEvent.started.count, 1)
        XCTAssertEqual(mockWideEvent.completions.count, 1)

        let started = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionPlanChangeWideEventData)
        XCTAssertEqual(started.changeType, .downgrade)

        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionPlanChangeWideEventData)
        XCTAssertEqual(completion.1, .failure)
    }

    @MainActor
    func testTierChangeWithNilChangeType_EmitsWideEventWithNilChangeType() async throws {
        let originURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionChangeSelected", body: "", webView: webView)

        // Set up existing subscription
        let existingSubscription = DuckDuckGoSubscription(
            productId: "ddg.privacy.pro.monthly.renews.us",
            name: "Pro Monthly",
            billingPeriod: .monthly,
            startedAt: Date(),
            expiresOrRenewsAt: Date().addingTimeInterval(30 * 24 * 60 * 60),
            platform: .apple,
            status: .autoRenewable,
            activeOffers: [],
            tier: .pro,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionManager.resultSubscription = .success(existingSubscription)

        let purchaseFlow = AppStorePurchaseFlowMock()
        purchaseFlow.changeTierResult = .success("jws-token")
        purchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        // No "change" parameter provided
        _ = await sut.subscriptionChangeSelected(params: ["id": "ddg.privacy.pro.yearly.renews.us"], original: message)

        XCTAssertEqual(mockWideEvent.started.count, 1)

        let started = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionPlanChangeWideEventData)
        XCTAssertNil(started.changeType)
        XCTAssertEqual(started.fromPlan, "ddg.privacy.pro.monthly.renews.us")
        XCTAssertEqual(started.toPlan, "ddg.privacy.pro.yearly.renews.us")
    }
}

final class MockURLWebView: WKWebView {
    private let mockedURL: URL
    init(url: URL) {
        self.mockedURL = url
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var url: URL? { mockedURL }
}

final class MockPendingTransactionHandler: PendingTransactionHandling {
    var markPurchasePendingCalled = false
    var handleSubscriptionActivatedCalled = false
    var handlePendingTransactionApprovedCalled = false
    
    func markPurchasePending() {
        markPurchasePendingCalled = true
    }
    
    func handleSubscriptionActivated() {
        handleSubscriptionActivatedCalled = true
    }
    
    func handlePendingTransactionApproved() {
        handlePendingTransactionApprovedCalled = true
    }
}


final class MockSubscriptionTierEventReporter: SubscriptionTierEventReporting {
    var requestedCalled = false
    var successCalled = false
    var failureCalled = false
    var failureError: Error?
    var unexpectedProTierCalled = false

    func reportTierOptionsRequested() {
        requestedCalled = true
    }

    func reportTierOptionsSuccess() {
        successCalled = true
    }

    func reportTierOptionsFailure(error: Error) {
        failureCalled = true
        failureError = error
    }

    func reportTierOptionsUnexpectedProTier() {
        unexpectedProTierCalled = true
    }
}

//
//  SubscriptionPagesUseSubscriptionFeatureTests.swift
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

import Common
import Networking
import NetworkingTestingUtils
import SubscriptionTestingUtilities
import WebKit
import XCTest
import UserScript
import PixelKit
import PixelKitTestingUtilities

@testable import DuckDuckGo_Privacy_Browser
@testable import Subscription

final class SubscriptionPagesUseSubscriptionFeatureTests: XCTestCase {

    private var sut: SubscriptionPagesUseSubscriptionFeature!

    private var mockStorePurchaseManager: StorePurchaseManagerMock!
    private var subscriptionManager: SubscriptionManagerMock!
    private var subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandling!
    private var mockUIHandler: SubscriptionUIHandlerMock!
    private var mockSubscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock!
    private var mockFreemiumDBPUserStateManager: MockFreemiumDBPUserStateManager!
    private var mockPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler!
    private var mockNotificationCenter: NotificationCenter!
    private var mockWideEvent: WideEventMock!
    private var mockEventReporter: MockSubscriptionEventReporter!
    private var broker: UserScriptMessageBroker!

    private struct Constants {
        static let subscriptionOptions = SubscriptionOptions(platform: SubscriptionPlatformName.macos,
                                                             options: [
                                                                SubscriptionOption(id: "1",
                                                                                   cost: SubscriptionOptionCost(displayPrice: "9 USD", recurrence: "monthly")),
                                                                SubscriptionOption(id: "2",
                                                                                   cost: SubscriptionOptionCost(displayPrice: "99 USD", recurrence: "yearly"))
                                                             ],
                                                               availableEntitlements: [.networkProtection, .dataBrokerProtection, .identityTheftRestoration])
        static let mockParams: [String: String] = [:]
        @MainActor static let mockScriptMessage = MockWKScriptMessage(name: "", body: "", webView: WKWebView() )
    }

    @MainActor
    override func setUpWithError() throws {
        broker = UserScriptMessageBroker(context: "testBroker")
        mockStorePurchaseManager = StorePurchaseManagerMock()
        subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager
        subscriptionManager.resultURL = URL(string: "https://duckduckgo.com/subscription/feature")!
        subscriptionSuccessPixelHandler = SubscriptionAttributionPixelHandler()
        let mockStripePurchaseFlowV2 = StripePurchaseFlowMock(subscriptionOptionsResult: .failure(.noProductsFound), prepareSubscriptionPurchaseResult: .failure(.noProductsFound))
        mockUIHandler = SubscriptionUIHandlerMock { _ in }
        mockSubscriptionFeatureAvailability = SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true,
                                                                                  usesUnifiedFeedbackForm: false)
        mockFreemiumDBPUserStateManager = MockFreemiumDBPUserStateManager()
        mockPixelHandler = MockDataBrokerProtectionFreemiumPixelHandler()
        mockNotificationCenter = NotificationCenter()
        mockWideEvent = WideEventMock()
        mockEventReporter = MockSubscriptionEventReporter()

        sut = SubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                      subscriptionSuccessPixelHandler: subscriptionSuccessPixelHandler,
                                                      stripePurchaseFlow: mockStripePurchaseFlowV2,
                                                      uiHandler: mockUIHandler,
                                                      subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
                                                      freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager,
                                                      notificationCenter: mockNotificationCenter,
                                                      dataBrokerProtectionFreemiumPixelHandler: mockPixelHandler,
                                                      aiChatURL: URL.duckDuckGo,
                                                      wideEvent: mockWideEvent,
                                                      subscriptionEventReporter: mockEventReporter,
                                                      pendingTransactionHandler: MockPendingTransactionHandler())
        sut.with(broker: broker)
    }

    override func tearDown() {
        mockFreemiumDBPUserStateManager = nil
        mockNotificationCenter = nil
        mockPixelHandler = nil
        mockStorePurchaseManager = nil
        mockSubscriptionFeatureAvailability = nil
        mockUIHandler = nil
        mockWideEvent = nil
        mockEventReporter = nil
        subscriptionManager = nil
        subscriptionSuccessPixelHandler = nil
        sut = nil
        broker = nil
    }

    func testGetFeatureConfig_WhenPaidAIChatEnabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isPaidAIChatEnabled = true

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureValue else {
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
        guard let featureValue = result as? GetFeatureValue else {
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
        guard let featureValue = result as? GetFeatureValue else {
            XCTFail("Expected GetFeatureValue type")
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
        guard let featureValue = result as? GetFeatureValue else {
            XCTFail("Expected GetFeatureValue type")
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
        guard let featureValue = result as? GetFeatureValue else {
            XCTFail("Expected GetFeatureValue type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)

        XCTAssertTrue(featureValue.usePaidDuckAi)
        XCTAssertTrue(featureValue.useAlternateStripePaymentFlow)
    }

    func testGetFeatureConfig_WhenBothFeaturesDisabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isPaidAIChatEnabled = false
        mockSubscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled = false

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureValue else {
            XCTFail("Expected GetFeatureValue type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)

        XCTAssertFalse(featureValue.usePaidDuckAi)
        XCTAssertFalse(featureValue.useAlternateStripePaymentFlow)
    }

    func testGetFeatureConfig_WhenTierMessagingEnabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isTierMessagingEnabled = true

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureValue else {
            XCTFail("Expected GetFeatureValue type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)

        XCTAssertTrue(featureValue.useGetSubscriptionTierOptions)
    }

    func testGetFeatureConfig_WhenTierMessagingDisabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isTierMessagingEnabled = false

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureValue else {
            XCTFail("Expected GetFeatureValue type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)

        XCTAssertFalse(featureValue.useGetSubscriptionTierOptions)
    }

    // MARK: - Feature Selection Tests

    @MainActor
    func testFeatureSelected_NetworkProtection_PostsCorrectNotification() async throws {
        // Given
        let params = ["productFeature": "Network Protection"]
        let expectation = expectation(description: "Network protection notification posted")

        let observer = mockNotificationCenter.addObserver(forName: .ToggleNetworkProtectionInMainWindow, object: sut, queue: nil) { _ in
            expectation.fulfill()
        }
        defer { mockNotificationCenter.removeObserver(observer) }

        // When
        let result = try await sut.featureSelected(params: params, original: Constants.mockScriptMessage)

        // Then
        XCTAssertNil(result)
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    @MainActor
    func testFeatureSelected_DataBrokerProtection_PostsNotificationAndShowsTab() async throws {
        // Given
        let params = ["productFeature": "Data Broker Protection"]
        let dbpNotificationExpectation = expectation(description: "DBP notification posted")
        let uiHandlerExpectation = expectation(description: "UI handler show tab called")

        let observer = mockNotificationCenter.addObserver(forName: .openPersonalInformationRemoval, object: sut, queue: nil) { _ in
            dbpNotificationExpectation.fulfill()
        }
        defer { mockNotificationCenter.removeObserver(observer) }

        mockUIHandler.setDidPerformActionCallback { action in
            if case .didShowTab(.dataBrokerProtection) = action {
                uiHandlerExpectation.fulfill()
            }
        }

        // When
        let result = try await sut.featureSelected(params: params, original: Constants.mockScriptMessage)

        // Then
        XCTAssertNil(result)
        await fulfillment(of: [dbpNotificationExpectation, uiHandlerExpectation], timeout: 1.0)
    }

    @MainActor
    func testFeatureSelected_IdentityTheftRestoration_ShowsCorrectTab() async throws {
        // Given
        let params = ["productFeature": "Identity Theft Restoration"]
        let uiHandlerExpectation = expectation(description: "UI handler show tab called")

        mockUIHandler.setDidPerformActionCallback { action in
            if case .didShowTab(.identityTheftRestoration(let url)) = action {
                XCTAssertNotNil(url)
                uiHandlerExpectation.fulfill()
            }
        }

        // When
        let result = try await sut.featureSelected(params: params, original: Constants.mockScriptMessage)

        // Then
        XCTAssertNil(result)
        await fulfillment(of: [uiHandlerExpectation], timeout: 1.0)
    }

    @MainActor
    func testFeatureSelected_IdentityTheftRestorationGlobal_ShowsCorrectTab() async throws {
        // Given
        let params = ["productFeature": "Global Identity Theft Restoration"]
        let uiHandlerExpectation = expectation(description: "UI handler show tab called")

        mockUIHandler.setDidPerformActionCallback { action in
            if case .didShowTab(.identityTheftRestoration(let url)) = action {
                XCTAssertNotNil(url)
                uiHandlerExpectation.fulfill()
            }
        }

        // When
        let result = try await sut.featureSelected(params: params, original: Constants.mockScriptMessage)

        // Then
        XCTAssertNil(result)
        await fulfillment(of: [uiHandlerExpectation], timeout: 1.0)
    }

    @MainActor
    func testFeatureSelected_PaidAIChat_ShowsCorrectTab() async throws {
        // Given
        let params = ["productFeature": "Duck.ai"]
        let uiHandlerExpectation = expectation(description: "UI handler show tab called")

        mockUIHandler.setDidPerformActionCallback { action in
            if case .didShowTab(.aiChat(let url)) = action {
                XCTAssertNotNil(url)
                uiHandlerExpectation.fulfill()
            }
        }

        // When
        let result = try await sut.featureSelected(params: params, original: Constants.mockScriptMessage)

        // Then
        XCTAssertNil(result)
        await fulfillment(of: [uiHandlerExpectation], timeout: 1.0)
    }

    @MainActor
    func testFeatureSelected_UnknownFeature_DoesNothing() async throws {
        // Given
        let params = ["productFeature": "unknown"]
        let uiHandlerExpectation = expectation(description: "UI handler should not be called")
        uiHandlerExpectation.isInverted = true

        mockUIHandler.setDidPerformActionCallback { action in
            if case .didShowTab = action {
                uiHandlerExpectation.fulfill()
            }
        }

        // When
        let result = try await sut.featureSelected(params: params, original: Constants.mockScriptMessage)

        // Then
        XCTAssertNil(result)
        await fulfillment(of: [uiHandlerExpectation], timeout: 0.1)
    }

    @MainActor
    func testAppStoreSuccess_EmitsWideEventWithContext() async throws {
        throw XCTSkip("Temporarily disabled")

        let originURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_macos")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionSelected", body: [:], webView: webView)

        subscriptionManager.resultURL = URL(string: "https://duckduckgo.com/subscriptions")!
        mockStorePurchaseManager.isEligibleForFreeTrialResult = true
        mockUIHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)

        _ = try await sut.subscriptionSelected(params: ["id": "yearly"], original: message)

        XCTAssertEqual(mockWideEvent.started.count, 2)
        XCTAssertEqual(mockWideEvent.completions.count, 2)
        let startedFirst = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionPurchaseWideEventData)
        let startedSecond = try XCTUnwrap(mockWideEvent.started.last as? SubscriptionRestoreWideEventData)
        XCTAssertEqual(startedFirst.contextData.name, "funnel_appsettings_macos")
        XCTAssertEqual(startedSecond.contextData.name, "funnel_onpurchasecheck_multiple")
    }

    // MARK: - GetSubscriptionTierOptions Tests

    func testGetSubscriptionTierOptions_WhenProTierEnabled_PassesTrueToIncludeProTier() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isProTierPurchaseEnabled = true
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = true

        let expectedTierOptions = SubscriptionTierOptions(
            platform: .macos,
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

        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(expectedTierOptions)

        // When
        let result = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(mockStorePurchaseManager.subscriptionTierOptionsIncludeProTierCalled, true, "Should pass true to includeProTier when Pro tier is enabled")

        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .macos)
        XCTAssertEqual(tierOptions.products.count, 1)
        XCTAssertEqual(tierOptions.products[0].tier, .plus)
        XCTAssertFalse(tierOptions.products[0].options.isEmpty, "Should have purchase options when purchase is allowed")
    }

    func testGetSubscriptionTierOptions_WhenProTierDisabled_PassesFalseToIncludeProTier() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isProTierPurchaseEnabled = false
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = true

        let tierOptionsWithPurchase = SubscriptionTierOptions(
            platform: .macos,
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

        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(tierOptionsWithPurchase)

        // When
        let result = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(mockStorePurchaseManager.subscriptionTierOptionsIncludeProTierCalled, false, "Should pass false to includeProTier when Pro tier is disabled")

        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .macos)
        XCTAssertFalse(tierOptions.products[0].options.isEmpty, "Should still have purchase options when purchase is allowed")
    }

    func testGetSubscriptionTierOptions_WhenPurchaseNotAllowed_StripsPurchaseOptions() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isProTierPurchaseEnabled = true
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = false

        let tierOptionsWithPurchase = SubscriptionTierOptions(
            platform: .macos,
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

        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(tierOptionsWithPurchase)

        // When
        let result = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(mockStorePurchaseManager.subscriptionTierOptionsIncludeProTierCalled, true, "Should still pass Pro tier flag correctly")

        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .macos)
        XCTAssertTrue(tierOptions.products[0].options.isEmpty, "Should strip purchase options when purchase is not allowed")
    }

    func testGetSubscriptionTierOptions_WhenNoOptionsAvailable_ReturnsEmpty() async throws {
        // Given
        mockStorePurchaseManager.subscriptionTierOptionsResult = .failure(.tieredProductsNoProductsAvailable)

        // When
        let result = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .macos)
        XCTAssertTrue(tierOptions.products.isEmpty, "Should return empty tier options when none are available")
    }

    // MARK: - Stripe Tier Options Tests

    @MainActor
    func testGetSubscriptionTierOptions_Stripe_WhenProTierEnabled_PassesTrueToIncludeProTier() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isProTierPurchaseEnabled = true
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = true

        let expectedTierOptions = SubscriptionTierOptions(
            platform: .stripe,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: [
                        SubscriptionOption(id: "stripe-monthly-plus",
                                           cost: SubscriptionOptionCost(displayPrice: "9.99 USD", recurrence: "monthly"),
                                           offer: nil)
                    ]
                )
            ]
        )

        let mockStripePurchaseFlow = StripePurchaseFlowMock(
            subscriptionOptionsResult: .success(.empty),
            prepareSubscriptionPurchaseResult: .failure(.noProductsFound),
            subscriptionTierOptionsResult: .success(expectedTierOptions)
        )

        // Set environment to use Stripe
        let stripeSubscriptionManager = SubscriptionManagerMock()
        stripeSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        stripeSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager
        stripeSubscriptionManager.resultURL = URL(string: "https://duckduckgo.com/subscription/feature")!

        let stripeSut = SubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: stripeSubscriptionManager,
            subscriptionSuccessPixelHandler: subscriptionSuccessPixelHandler,
            stripePurchaseFlow: mockStripePurchaseFlow,
            uiHandler: mockUIHandler,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager,
            notificationCenter: mockNotificationCenter,
            dataBrokerProtectionFreemiumPixelHandler: mockPixelHandler,
            aiChatURL: URL.duckDuckGo,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )
        stripeSut.with(broker: broker)

        // When
        let result = try await stripeSut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(mockStripePurchaseFlow.subscriptionTierOptionsIncludeProTierCalled, true, "Should pass true to includeProTier for Stripe when Pro tier is enabled")

        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .stripe)
    }

    @MainActor
    func testGetSubscriptionTierOptions_Stripe_WhenProTierDisabled_PassesFalseToIncludeProTier() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isProTierPurchaseEnabled = false
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = true

        let expectedTierOptions = SubscriptionTierOptions(
            platform: .stripe,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: [
                        SubscriptionOption(id: "stripe-monthly-plus",
                                           cost: SubscriptionOptionCost(displayPrice: "9.99 USD", recurrence: "monthly"),
                                           offer: nil)
                    ]
                )
            ]
        )

        let mockStripePurchaseFlow = StripePurchaseFlowMock(
            subscriptionOptionsResult: .success(.empty),
            prepareSubscriptionPurchaseResult: .failure(.noProductsFound),
            subscriptionTierOptionsResult: .success(expectedTierOptions)
        )

        // Set environment to use Stripe
        let stripeSubscriptionManager = SubscriptionManagerMock()
        stripeSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        stripeSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager
        stripeSubscriptionManager.resultURL = URL(string: "https://duckduckgo.com/subscription/feature")!

        let stripeSut = SubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: stripeSubscriptionManager,
            subscriptionSuccessPixelHandler: subscriptionSuccessPixelHandler,
            stripePurchaseFlow: mockStripePurchaseFlow,
            uiHandler: mockUIHandler,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager,
            notificationCenter: mockNotificationCenter,
            dataBrokerProtectionFreemiumPixelHandler: mockPixelHandler,
            aiChatURL: URL.duckDuckGo,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )
        stripeSut.with(broker: broker)

        // When
        let result = try await stripeSut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(mockStripePurchaseFlow.subscriptionTierOptionsIncludeProTierCalled, false, "Should pass false to includeProTier for Stripe when Pro tier is disabled")

        guard let tierOptions = result as? SubscriptionTierOptions else {
            XCTFail("Expected SubscriptionTierOptions type")
            return
        }

        XCTAssertEqual(tierOptions.platform, .stripe)
    }

    // MARK: - Tier Options Pixel Tests

    func testGetSubscriptionTierOptions_AlwaysFiresRequestedPixel() async throws {
        // Given
        let expectedTierOptions = SubscriptionTierOptions(
            platform: .macos,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: []
                )
            ]
        )
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(expectedTierOptions)

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertTrue(mockEventReporter.reportedTierOptionEvents.contains { $0.eventName == SubscriptionPixel.subscriptionTierOptionsRequested.name })
    }

    func testGetSubscriptionTierOptions_OnSuccess_FiresSuccessPixel() async throws {
        // Given
        let expectedTierOptions = SubscriptionTierOptions(
            platform: .macos,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: []
                )
            ]
        )
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(expectedTierOptions)

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertTrue(mockEventReporter.reportedTierOptionEvents.contains { $0.eventName == SubscriptionPixel.subscriptionTierOptionsSuccess.name })
        XCTAssertFalse(mockEventReporter.reportedTierOptionEvents.contains { $0.eventName == SubscriptionPixel.subscriptionTierOptionsFailure(error: NSError(domain: "test", code: 0)).name })
    }

    func testGetSubscriptionTierOptions_OnFailure_FiresFailurePixel() async throws {
        // Given
        mockStorePurchaseManager.subscriptionTierOptionsResult = .failure(.tieredProductsNoProductsAvailable)

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertTrue(mockEventReporter.reportedTierOptionEvents.contains { $0.eventName == SubscriptionPixel.subscriptionTierOptionsFailure(error: NSError(domain: "test", code: 0)).name })
        XCTAssertFalse(mockEventReporter.reportedTierOptionEvents.contains { $0.eventName == SubscriptionPixel.subscriptionTierOptionsSuccess.name })
    }

    func testGetSubscriptionTierOptions_OnFailure_FiresFailurePixelWithError() async throws {
        // Given
        mockStorePurchaseManager.subscriptionTierOptionsResult = .failure(.tieredProductsNoProductsAvailable)

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        // The error is now embedded in the pixel enum (SubscriptionPixel.subscriptionTierOptionsFailure(error:))
        let failureEvent = mockEventReporter.reportedTierOptionEvents.first { $0.eventName == SubscriptionPixel.subscriptionTierOptionsFailure(error: NSError(domain: "test", code: 0)).name }
        XCTAssertNotNil(failureEvent, "Failure pixel should be fired")
        XCTAssertFalse(mockEventReporter.reportedTierOptionEvents.contains { $0.eventName == SubscriptionPixel.subscriptionTierOptionsSuccess.name })
    }

    func testGetSubscriptionTierOptions_OnFailure_DoesNotFireSuccessPixel() async throws {
        // Given
        mockStorePurchaseManager.subscriptionTierOptionsResult = .failure(.tieredProductsNoProductsAvailable)

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertFalse(mockEventReporter.reportedTierOptionEvents.contains { $0.eventName == SubscriptionPixel.subscriptionTierOptionsSuccess.name })
    }

    func testGetSubscriptionTierOptions_WithProTierPresent_FiresUnexpectedProTierPixel() async throws {
        // Given
        let tierOptionsWithProTier = SubscriptionTierOptions(
            platform: .macos,
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
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(tierOptionsWithProTier)

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertTrue(mockEventReporter.reportedTierOptionEvents.contains { $0.eventName == SubscriptionPixel.subscriptionTierOptionsUnexpectedProTier.name })
    }

    func testGetSubscriptionTierOptions_WithoutProTier_DoesNotFireUnexpectedProTierPixel() async throws {
        // Given
        let tierOptionsWithoutProTier = SubscriptionTierOptions(
            platform: .macos,
            products: [
                SubscriptionTier(
                    tier: .plus,
                    features: [TierFeature(product: .networkProtection, name: .plus)],
                    options: []
                )
            ]
        )
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(tierOptionsWithoutProTier)

        // When
        _ = try await sut.getSubscriptionTierOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertFalse(mockEventReporter.reportedTierOptionEvents.contains { $0.eventName == SubscriptionPixel.subscriptionTierOptionsUnexpectedProTier.name })
    }

    // MARK: - subscriptionChangeSelected Tests

    @MainActor
    func testSubscriptionChangeSelected_AppStore_Success_CompletesFlow() async throws {
        // Given
        let params: [String: Any] = ["id": "yearly-pro", "change": "upgrade"]
        let message = Constants.mockScriptMessage

        // Set up authenticated user with existing subscription
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // Set up successful purchase
        mockStorePurchaseManager.purchaseSubscriptionResult = .success("test-transaction-jws")

        // Set up successful confirmation
        let subscription = DuckDuckGoSubscription(
            productId: "yearly-pro",
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
        subscriptionManager.confirmPurchaseResponse = .success(subscription)

        var didPresentProgress = false
        var didDismissProgress = false
        var didUpdateProgress = false

        mockUIHandler.setDidPerformActionCallback { action in
            switch action {
            case .didPresentProgressViewController:
                didPresentProgress = true
            case .didDismissProgressViewController:
                didDismissProgress = true
            case .didUpdateProgressViewController:
                didUpdateProgress = true
            default:
                break
            }
        }

        // When
        _ = try await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertTrue(didPresentProgress, "Should present progress view")
        XCTAssertTrue(didUpdateProgress, "Should update progress view during completion")
        XCTAssertTrue(didDismissProgress, "Should dismiss progress view")
    }

    @MainActor
    func testSubscriptionChangeSelected_AppStore_UserCancelled_DismissesWithoutAlert() async throws {
        // Given
        let params: [String: Any] = ["id": "yearly-pro", "change": "upgrade"]
        let message = Constants.mockScriptMessage

        // Set up authenticated user
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // Set up cancelled purchase
        mockStorePurchaseManager.purchaseSubscriptionResult = .failure(.purchaseCancelledByUser)

        var didShowAlert = false
        var didDismissProgress = false

        mockUIHandler.setDidPerformActionCallback { action in
            switch action {
            case .didShowAlert:
                didShowAlert = true
            case .didDismissProgressViewController:
                didDismissProgress = true
            default:
                break
            }
        }

        // When
        _ = try await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertFalse(didShowAlert, "Should NOT show alert when user cancels")
        XCTAssertTrue(didDismissProgress, "Should dismiss progress view")
        XCTAssertTrue(mockEventReporter.reportedActivationErrors.contains { error in
            if case .cancelledByUser = error { return true }
            return false
        }, "Should report cancelled by user error")
    }

    @MainActor
    func testSubscriptionChangeSelected_AppStore_PurchaseFailed_ShowsAlert() async throws {
        // Given
        let params: [String: Any] = ["id": "yearly-pro", "change": "upgrade"]
        let message = Constants.mockScriptMessage

        // Set up authenticated user
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // Set up failed purchase
        mockStorePurchaseManager.purchaseSubscriptionResult = .failure(.productNotFound)

        var shownAlertType: SubscriptionAlertType?
        mockUIHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)
        mockUIHandler.setDidPerformActionCallback { action in
            if case .didShowAlert(let alertType) = action {
                shownAlertType = alertType
            }
        }

        // When
        _ = try await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertEqual(shownAlertType, .somethingWentWrong, "Should show 'Something Went Wrong' alert")
        XCTAssertTrue(mockEventReporter.reportedActivationErrors.contains { error in
            if case .purchaseFailed = error { return true }
            return false
        }, "Should report purchase failed error")
    }

    @MainActor
    func testSubscriptionChangeSelected_Stripe_CompletesWithoutAlert() async throws {
        // Given
        let params: [String: Any] = ["id": "stripe-yearly-pro", "change": "upgrade"]
        let message = Constants.mockScriptMessage

        // Set environment to Stripe
        subscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)

        // Set up authenticated user
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        var didShowAlert = false
        var didDismissProgress = false

        mockUIHandler.setDidPerformActionCallback { action in
            switch action {
            case .didShowAlert:
                didShowAlert = true
            case .didDismissProgressViewController:
                didDismissProgress = true
            default:
                break
            }
        }

        // When
        _ = try await sut.subscriptionChangeSelected(params: params, original: message)

        // Then
        XCTAssertFalse(didShowAlert, "Stripe tier change should not show any alert")
        XCTAssertTrue(didDismissProgress, "Should dismiss progress view")
        // Note: For Stripe, the handler sends a redirect with the access token via pushPurchaseUpdate
        // The actual redirect message can't be easily verified without mocking the broker
    }

    @MainActor
    func testSubscriptionChangeSelected_ReportsErrorForAllErrorTypes() async throws {
        // Given
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        let errorCases: [StorePurchaseManagerError] = [
            .productNotFound,
            .purchaseFailed(NSError(domain: "test", code: 0)),
            .purchaseCancelledByUser
        ]

        for error in errorCases {
            mockEventReporter.reportedActivationErrors.removeAll()
            mockStorePurchaseManager.purchaseSubscriptionResult = .failure(error)
            mockUIHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)

            let params: [String: Any] = ["id": "yearly-pro", "change": "upgrade"]

            // When
            _ = try await sut.subscriptionChangeSelected(params: params, original: Constants.mockScriptMessage)

            // Then
            XCTAssertFalse(mockEventReporter.reportedActivationErrors.isEmpty,
                          "Should report error for \(error)")
        }
    }
}

// MARK: - Mocks

final class MockSubscriptionEventReporter: SubscriptionEventReporter {

    struct TierOptionEventRecord {
        let eventName: String
    }

    var reportedActivationErrors: [SubscriptionError] = []
    var reportedTierOptionEvents: [TierOptionEventRecord] = []

    func report(subscriptionActivationError: SubscriptionError) {
        reportedActivationErrors.append(subscriptionActivationError)
    }

    func report(subscriptionTierOptionEvent: PixelKitEvent) {
        reportedTierOptionEvents.append(TierOptionEventRecord(eventName: subscriptionTierOptionEvent.name))
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

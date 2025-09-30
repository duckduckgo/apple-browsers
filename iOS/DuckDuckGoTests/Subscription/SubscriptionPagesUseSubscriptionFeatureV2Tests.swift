//
//  SubscriptionPagesUseSubscriptionFeatureV2Tests.swift
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
@testable import DuckDuckGo
@testable import BrowserServicesKit
@testable import Common
@testable import UserScript
@testable import Subscription
import SubscriptionTestingUtilities
import PixelKitTestingUtilities

final class SubscriptionPagesUseSubscriptionFeatureV2Tests: XCTestCase {
    
    var sut: DefaultSubscriptionPagesUseSubscriptionFeatureV2!
    var mockSubscriptionManager: SubscriptionManagerMockV2!
    var mockStripePurchaseFlow: StripePurchaseFlowMockV2!
    var mockSubscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock!
    var mockNotificationCenter: NotificationCenter!
    var mockWidePixel: WidePixelMock!
    var mockInternalUserDecider: MockInternalUserDecider!

    @MainActor
    override func setUp() {
        super.setUp()
        
        mockSubscriptionManager = SubscriptionManagerMockV2()
        mockStripePurchaseFlow = StripePurchaseFlowMockV2(subscriptionOptionsResult: .success(.empty), prepareSubscriptionPurchaseResult: .success((purchaseUpdate: .completed, accountCreationDuration: nil)))
        mockSubscriptionFeatureAvailability = SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true)
        mockNotificationCenter = NotificationCenter()
        mockWidePixel = WidePixelMock()
        mockInternalUserDecider = MockInternalUserDecider(isInternalUser: true)

        sut = DefaultSubscriptionPagesUseSubscriptionFeatureV2(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: "",
            appStorePurchaseFlow: AppStorePurchaseFlowMockV2(),
            appStoreRestoreFlow: AppStoreRestoreFlowMockV2(),
            subscriptionDataReporter: nil,
            subscriptionFreeTrialsHelper: MockSubscriptionFreeTrialsHelping(),
            internalUserDecider: mockInternalUserDecider,
            widePixel: mockWidePixel)
    }
    
    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        mockStripePurchaseFlow = nil
        mockSubscriptionFeatureAvailability = nil
        mockNotificationCenter = nil
        mockWidePixel = nil
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
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
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
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
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
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
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
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
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
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
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
        guard let featureValue = result as? GetFeatureConfigurationResponse else {
            XCTFail("Expected GetFeatureConfigurationResponse type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
        XCTAssertFalse(featureValue.usePaidDuckAi)
        XCTAssertFalse(featureValue.useAlternateStripePaymentFlow)
    }

    @MainActor
    func testAppStoreSuccess_EmitsWidePixelWithContextAndDurations() async throws {
        let originURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionSelected", body: "", webView: webView)

        let storeManager = StorePurchaseManagerMockV2()
        storeManager.isEligibleForFreeTrialResult = true
        mockSubscriptionManager.resultStorePurchaseManager = storeManager

        let purchaseFlow = AppStorePurchaseFlowMockV2()
        purchaseFlow.purchaseSubscriptionResult = .success((transactionJWS: "jws", accountCreationDuration: nil))
        purchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeatureV2(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMockV2(),
            subscriptionDataReporter: nil,
            subscriptionFreeTrialsHelper: MockSubscriptionFreeTrialsHelping(),
            internalUserDecider: mockInternalUserDecider,
            widePixel: mockWidePixel
        )

        _ = await sut.subscriptionSelected(params: ["id": "yearly"], original: message)

        XCTAssertEqual(mockWidePixel.started.count, 1)
        XCTAssertEqual(mockWidePixel.completions.count, 1)

        let started = try XCTUnwrap(mockWidePixel.started.first as? SubscriptionPurchaseWidePixelData)
        XCTAssertEqual(started.purchasePlatform, .appStore)
        XCTAssertEqual(started.subscriptionIdentifier, "yearly")
        XCTAssertEqual(started.freeTrialEligible, true)
        XCTAssertEqual(started.contextData.name, "funnel_appsettings_ios")

        let updated = try XCTUnwrap(mockWidePixel.updates.last as? SubscriptionPurchaseWidePixelData)
        XCTAssertNotNil(updated.activateAccountDuration?.start)
        XCTAssertNotNil(updated.activateAccountDuration?.end)

        let completion = try XCTUnwrap(mockWidePixel.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionPurchaseWidePixelData)
        XCTAssertEqual(completion.1, .success(reason: nil))
    }

    @MainActor
    func testAppStoreCancelled_EmitsWidePixelCancelled() async throws {
        let originURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_onboarding_ios")!
        let webView = MockURLWebView(url: originURL)
        let message = MockWKScriptMessage(name: "subscriptionSelected", body: "", webView: webView)

        let storeManager = StorePurchaseManagerMockV2()
        mockSubscriptionManager.resultStorePurchaseManager = storeManager

        let purchaseFlow = AppStorePurchaseFlowMockV2()
        purchaseFlow.purchaseSubscriptionResult = .failure(.cancelledByUser)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeatureV2(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMockV2(),
            subscriptionDataReporter: nil,
            subscriptionFreeTrialsHelper: MockSubscriptionFreeTrialsHelping(),
            internalUserDecider: mockInternalUserDecider,
            widePixel: mockWidePixel
        )

        _ = await sut.subscriptionSelected(params: ["id": "monthly"], original: message)

        XCTAssertEqual(mockWidePixel.started.count, 1)
        XCTAssertEqual(mockWidePixel.completions.count, 1)
        let completion = try XCTUnwrap(mockWidePixel.completions.first)
        XCTAssertEqual(completion.1, .cancelled)
    }

    @MainActor
    func testOriginPrecedence_UsesAttributionOriginOverURL() async throws {
        let urlOrigin = URL(string: "https://duckduckgo.com/subscriptions")!
        let webView = MockURLWebView(url: urlOrigin)
        let message = MockWKScriptMessage(name: "subscriptionSelected", body: "", webView: webView)

        let storeManager = StorePurchaseManagerMockV2()
        mockSubscriptionManager.resultStorePurchaseManager = storeManager

        let purchaseFlow = AppStorePurchaseFlowMockV2()
        purchaseFlow.purchaseSubscriptionResult = .failure(.cancelledByUser)

        let sut = DefaultSubscriptionPagesUseSubscriptionFeatureV2(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: SubscriptionFunnelOrigin.appSettings.rawValue,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMockV2(),
            subscriptionDataReporter: nil,
            subscriptionFreeTrialsHelper: MockSubscriptionFreeTrialsHelping(),
            internalUserDecider: mockInternalUserDecider,
            widePixel: mockWidePixel
        )

        _ = await sut.subscriptionSelected(params: ["id": "monthly"], original: message)

        let started = try XCTUnwrap(mockWidePixel.started.first as? SubscriptionPurchaseWidePixelData)
        XCTAssertEqual(started.contextData.name, SubscriptionFunnelOrigin.appSettings.rawValue)
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

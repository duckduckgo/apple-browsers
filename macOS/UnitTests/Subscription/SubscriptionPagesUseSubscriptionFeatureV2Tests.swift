//
//  SubscriptionPagesUseSubscriptionFeatureV2Tests.swift
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
@testable import DuckDuckGo_Privacy_Browser
@testable import Subscription
import Common
import Networking
import SubscriptionTestingUtilities
import NetworkingTestingUtils

final class SubscriptionPagesUseSubscriptionFeatureV2Tests: XCTestCase {

    private var sut: SubscriptionPagesUseSubscriptionFeatureV2!

    private var mockStorePurchaseManager: StorePurchaseManagerMockV2!
    private var subscriptionManagerV2: SubscriptionManagerV2!
    private var subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandler!
    private var mockUIHandler: SubscriptionUIHandlerMock!
    private var mockSubscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock!
    private var mockFreemiumDBPUserStateManager: MockFreemiumDBPUserStateManager!
    private var mockFreemiumDBPExperimentManager: MockFreemiumDBPExperimentManager!
    private var mockPixelHandler: MockFreemiumDBPExperimentPixelHandler!
    private var mockFeatureFlagger: MockFeatureFlagger!

    private struct Constants {
        static let subscriptionOptions = SubscriptionOptionsV2(platform: SubscriptionPlatformName.macos,
                                                             options: [
                                                                SubscriptionOptionV2(id: "1",
                                                                                   cost: SubscriptionOptionCost(displayPrice: "9 USD", recurrence: "monthly")),
                                                                SubscriptionOptionV2(id: "2",
                                                                                   cost: SubscriptionOptionCost(displayPrice: "99 USD", recurrence: "yearly"))
                                                             ],
                                                               availableEntitlements: [.networkProtection, .dataBrokerProtection, .identityTheftRestoration])
        static let mockParams: [String: String] = [:]
        @MainActor static let mockScriptMessage = MockWKScriptMessage(name: "", body: "", webView: WKWebView() )
    }

    @MainActor
    override func setUpWithError() throws {
        let apiService = MockAPIService()
        apiService.authorizationRefresherCallback = { _ in
            return OAuthTokensFactory.makeValidTokenContainer().accessToken
        }
        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        let authService = DefaultOAuthService(baseURL: OAuthEnvironment.staging.url, apiService: apiService)
        // keychain storage
        let tokenStorage = MockTokenStorage()
        let legacyAccountStorage = MockLegacyTokenStorage()

        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            legacyTokenStorage: legacyAccountStorage,
                                            authService: authService)
        mockStorePurchaseManager = StorePurchaseManagerMockV2()
        let subscriptionEndpointService = DefaultSubscriptionEndpointServiceV2(apiService: apiService,
                                                                               baseURL: subscriptionEnvironment.serviceEnvironment.url)

        subscriptionManagerV2 = DefaultSubscriptionManagerV2(storePurchaseManager: mockStorePurchaseManager,
                                                           oAuthClient: authClient,
                                                           subscriptionEndpointService: subscriptionEndpointService,
                                                           subscriptionEnvironment: subscriptionEnvironment,
                                                           pixelHandler: MockPixelHandler())
        subscriptionSuccessPixelHandler = PrivacyProSubscriptionAttributionPixelHandler()
        let mockStripePurchaseFlowV2 = StripePurchaseFlowMockV2(subscriptionOptionsResult: .failure(.noProductsFound), prepareSubscriptionPurchaseResult: .failure(.noProductsFound))
        mockUIHandler = SubscriptionUIHandlerMock { _ in }
        mockSubscriptionFeatureAvailability = SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true,
                                                                                  usesUnifiedFeedbackForm: false)
        mockFreemiumDBPUserStateManager = MockFreemiumDBPUserStateManager()
        mockFreemiumDBPExperimentManager = MockFreemiumDBPExperimentManager()
        mockPixelHandler = MockFreemiumDBPExperimentPixelHandler()
        mockFeatureFlagger = MockFeatureFlagger()

        sut = SubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManagerV2,
                                                        subscriptionSuccessPixelHandler: subscriptionSuccessPixelHandler,
                                                        stripePurchaseFlow: mockStripePurchaseFlowV2,
                                                        uiHandler: mockUIHandler,
                                                        subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
                                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager,
                                                        freemiumDBPPixelExperimentManager: mockFreemiumDBPExperimentManager,
                                                        notificationCenter: .default,
                                                        freemiumDBPExperimentPixelHandler: mockPixelHandler,
                                                        featureFlagger: mockFeatureFlagger)
    }

    // MARK: - Free Trials

    @MainActor
    func testGetSubscriptionOptions_FreeTrialFlagOn_AndFreeTrialOptionsAvailable_ReturnsFreeTrialOptions() async throws {
        // Given
        mockFeatureFlagger.isFeatureOn = { _ in true }
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = true

        let freeTrialOptions = SubscriptionOptionsV2(
            platform: .macos,
            options: [SubscriptionOptionV2(id: "free-trial-monthly-from-store-manager", cost: SubscriptionOptionCost(displayPrice: "0 USD", recurrence: "monthly"))],
            availableEntitlements: [.networkProtection]
        )

        mockStorePurchaseManager.freeTrialSubscriptionOptionsResult = freeTrialOptions
        mockStorePurchaseManager.subscriptionOptionsResult = Constants.subscriptionOptions

        // When
        let result = try await sut.getSubscriptionOptions(params: Constants.mockParams, original: Constants.mockScriptMessage)

        // Then
        let subscriptionOptionsResult = try XCTUnwrap(result as? SubscriptionOptionsV2)
        XCTAssertEqual(subscriptionOptionsResult, freeTrialOptions)
    }

    @MainActor
    func testGetSubscriptionOptions_FreeTrialFlagOn_AndFreeTrialReturnsNil_ReturnsRegularOptions() async throws {
        // Given
        mockFeatureFlagger.isFeatureOn = { _ in true }
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = true

        mockStorePurchaseManager.freeTrialSubscriptionOptionsResult = nil
        mockStorePurchaseManager.subscriptionOptionsResult = Constants.subscriptionOptions

        // When
        let result = try await sut.getSubscriptionOptions(params: Constants.mockParams, original: Constants.mockScriptMessage)

        // Then
        let subscriptionOptionsResult = try XCTUnwrap(result as? SubscriptionOptionsV2)
        XCTAssertEqual(subscriptionOptionsResult, Constants.subscriptionOptions)
    }

    @MainActor
    func testGetSubscriptionOptions_FreeTrialFlagOff_AndFreeTrialOptionsAvailable_ReturnsRegularOptions() async throws {
        // Given
        mockFeatureFlagger.isFeatureOn = { _ in false }
        mockSubscriptionFeatureAvailability.isSubscriptionPurchaseAllowed = true

        let freeTrialOptions = SubscriptionOptionsV2(
            platform: .macos,
            options: [SubscriptionOptionV2(id: "free-trial-monthly-from-store-manager", cost: SubscriptionOptionCost(displayPrice: "0 USD", recurrence: "monthly"))],
            availableEntitlements: [.networkProtection]
        )

        mockStorePurchaseManager.freeTrialSubscriptionOptionsResult = freeTrialOptions
        mockStorePurchaseManager.subscriptionOptionsResult = Constants.subscriptionOptions

        // When
        let result = try await sut.getSubscriptionOptions(params: Constants.mockParams, original: Constants.mockScriptMessage)

        // Then
        let subscriptionOptionsResult = try XCTUnwrap(result as? SubscriptionOptionsV2)
        XCTAssertEqual(subscriptionOptionsResult, Constants.subscriptionOptions)
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
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
        XCTAssertTrue(featureValue.useDuckAiPro)
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
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
        XCTAssertFalse(featureValue.useDuckAiPro)
    }
}

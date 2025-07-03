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

import Common
import Networking
import NetworkingTestingUtils
import SubscriptionTestingUtilities
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser
@testable import Subscription

final class SubscriptionPagesUseSubscriptionFeatureV2Tests: XCTestCase {

    private var sut: SubscriptionPagesUseSubscriptionFeatureV2!

    private var mockStorePurchaseManager: StorePurchaseManagerMockV2!
    private var subscriptionManagerV2: SubscriptionManagerV2!
    private var subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandler!
    private var mockUIHandler: SubscriptionUIHandlerMock!
    private var mockSubscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock!
    private var mockFreemiumDBPUserStateManager: MockFreemiumDBPUserStateManager!
    private var mockPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockNotificationCenter: NotificationCenter!

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
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.\(#function)")!
        subscriptionManagerV2 = DefaultSubscriptionManagerV2(storePurchaseManager: mockStorePurchaseManager,
                                                             oAuthClient: authClient,
                                                             userDefaults: userDefaults,
                                                             subscriptionEndpointService: subscriptionEndpointService,
                                                             subscriptionEnvironment: subscriptionEnvironment,
                                                             pixelHandler: MockPixelHandler())
        subscriptionSuccessPixelHandler = PrivacyProSubscriptionAttributionPixelHandler()
        let mockStripePurchaseFlowV2 = StripePurchaseFlowMockV2(subscriptionOptionsResult: .failure(.noProductsFound), prepareSubscriptionPurchaseResult: .failure(.noProductsFound))
        mockUIHandler = SubscriptionUIHandlerMock { _ in }
        mockSubscriptionFeatureAvailability = SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true,
                                                                                  usesUnifiedFeedbackForm: false)
        mockFreemiumDBPUserStateManager = MockFreemiumDBPUserStateManager()
        mockPixelHandler = MockDataBrokerProtectionFreemiumPixelHandler()
        mockFeatureFlagger = MockFeatureFlagger()
        mockNotificationCenter = NotificationCenter()

        sut = SubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManagerV2,
                                                        subscriptionSuccessPixelHandler: subscriptionSuccessPixelHandler,
                                                        stripePurchaseFlow: mockStripePurchaseFlowV2,
                                                        uiHandler: mockUIHandler,
                                                        subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
                                                        freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager,
                                                        notificationCenter: mockNotificationCenter,
                                                        dataBrokerProtectionFreemiumPixelHandler: mockPixelHandler,
                                                        featureFlagger: mockFeatureFlagger,
                                                        aiChatURL: URL.duckDuckGo)
    }

    // MARK: - Free Trials

    @MainActor
    func testGetSubscriptionOptions_FreeTrialFlagOn_AndFreeTrialOptionsAvailable_ReturnsFreeTrialOptions() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProFreeTrial]
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
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProFreeTrial]
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
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
        XCTAssertFalse(featureValue.usePaidDuckAi)
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
}

//
//  SubscriptionPagesUseSubscriptionFeatureFreeTrialsTests.swift
//  DuckDuckGo
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
import BrowserServicesKit
import SubscriptionTestingUtilities
import Core
@testable import Subscription
@testable import DuckDuckGo


final class SubscriptionPagesUseSubscriptionFeatureFreeTrialsTests: XCTestCase {

    private var sut: (any SubscriptionPagesUseSubscriptionFeature)!

    private var mockSubscriptionManager: SubscriptionManagerMock!
    private var mockAccountManager: AccountManagerMock!
    private var mockStorePurchaseManager: StorePurchaseManagerMock!
    private var mockSubscriptionFreeTrialsHelper: MockSubscriptionFreeTrialsHelper!
    private var mockAppStorePurchaseFlow: AppStorePurchaseFlowMock!

    override func setUpWithError() throws {
        mockAccountManager = AccountManagerMock()
        mockStorePurchaseManager = StorePurchaseManagerMock()
        mockSubscriptionManager = SubscriptionManagerMock(accountManager: mockAccountManager,
                                                      subscriptionEndpointService: SubscriptionEndpointServiceMock(),
                                                      authEndpointService: AuthEndpointServiceMock(),
                                                          storePurchaseManager: mockStorePurchaseManager,
                                                      currentEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
                                                      canPurchase: true,
                                                      subscriptionFeatureMappingCache: SubscriptionFeatureMappingCacheMock())

        mockAppStorePurchaseFlow = AppStorePurchaseFlowMock()
        mockSubscriptionFreeTrialsHelper = MockSubscriptionFreeTrialsHelper()

        sut = DefaultSubscriptionPagesUseSubscriptionFeature(subscriptionManager: mockSubscriptionManager,
                                                             subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
                                                             subscriptionAttributionOrigin: nil,
                                                             appStorePurchaseFlow: mockAppStorePurchaseFlow,
                                                             appStoreRestoreFlow: AppStoreRestoreFlowMock(),
                                                             appStoreAccountManagementFlow: AppStoreAccountManagementFlowMock(),
                                                             subscriptionFreeTrialsHelper: mockSubscriptionFreeTrialsHelper)
    }

    func testWhenFreeTrialsNotAvailable_thenStandardSubscriptionOptionsAreReturned() async throws {
        // Given
        mockAccountManager.accessToken = nil
        mockSubscriptionManager.canPurchase = true
        mockSubscriptionFreeTrialsHelper.areFreeTrialsEnabledValue = false
        mockStorePurchaseManager.subscriptionOptionsResult = .mockStandard

        // When
        let result = await sut.getSubscriptionOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(result as? SubscriptionOptions, .mockStandard)
    }

    func testWhenFreeTrialsAreAvailable_thenFreeTrialSubscriptionOptionsAreReturned() async throws {
        // Given
        mockAccountManager.accessToken = nil
        mockSubscriptionManager.canPurchase = true
        mockSubscriptionFreeTrialsHelper.areFreeTrialsEnabledValue = true
        mockStorePurchaseManager.freeTrialSubscriptionOptionsResult = .mockFreeTrial

        // When
        let result = await sut.getSubscriptionOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(result as? SubscriptionOptions, .mockFreeTrial)
    }

    func testWhenFailedToFetchSubscriptionOptions_thenEmptyOptionsAreReturned() async throws {
        // Given
        mockAccountManager.accessToken = nil
        mockSubscriptionManager.canPurchase = true
        mockSubscriptionFreeTrialsHelper.areFreeTrialsEnabledValue = false
        mockStorePurchaseManager.subscriptionOptionsResult = nil

        // When
        let result = await sut.getSubscriptionOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(result as? SubscriptionOptions, .empty)
        XCTAssertEqual(sut.transactionError, .failedToGetSubscriptionOptions)
    }

    func testWhenFreeTrialsAreAvailableAndFreeTrialOptionsAreNil_thenFallbackToStandardOptions() async throws {
        // Given
        mockAccountManager.accessToken = nil
        mockSubscriptionManager.canPurchase = true
        mockSubscriptionFreeTrialsHelper.areFreeTrialsEnabledValue = true
        mockStorePurchaseManager.freeTrialSubscriptionOptionsResult = nil
        mockStorePurchaseManager.subscriptionOptionsResult = .mockStandard

        // When
        let result = await sut.getSubscriptionOptions(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        XCTAssertEqual(result as? SubscriptionOptions, .mockStandard, "Should return standard subscription options as a fallback when free trial options are nil.")
    }
}

private extension SubscriptionOptions {
    static let mockStandard = SubscriptionOptions(platform: .ios,
                                                   options: [
                                                       SubscriptionOption(id: "1",
                                                                          cost: SubscriptionOptionCost(displayPrice: "9", recurrence: "monthly")),
                                                       SubscriptionOption(id: "2",
                                                                          cost: SubscriptionOptionCost(displayPrice: "99", recurrence: "yearly"))
                                                   ],
                                                   features: [
                                                       SubscriptionFeature(name: .networkProtection),
                                                       SubscriptionFeature(name: .dataBrokerProtection),
                                                       SubscriptionFeature(name: .identityTheftRestoration)
                                                   ])

    static let mockFreeTrial = SubscriptionOptions(platform: .ios,
                                                    options: [
                                                        SubscriptionOption(id: "3",
                                                                           cost: SubscriptionOptionCost(displayPrice: "0", recurrence: "monthly-free-trial"), offer: .init(type: .freeTrial, id: "1", durationInDays: 4, isUserEligible: true)),
                                                        SubscriptionOption(id: "4",
                                                                           cost: SubscriptionOptionCost(displayPrice: "0", recurrence: "yearly-free-trial"), offer: .init(type: .freeTrial, id: "1", durationInDays: 4, isUserEligible: true))
                                                    ],
                                                    features: [
                                                        SubscriptionFeature(name: .networkProtection)
                                                    ])
}

final class MockSubscriptionFreeTrialsHelper: SubscriptionFreeTrialsHelping {
    var areFreeTrialsEnabledValue = false
    var areFreeTrialsEnabled: Bool {
        areFreeTrialsEnabledValue
    }
    var origin: String = ""
}

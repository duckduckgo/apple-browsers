//
//  SubscriptionPagesUseSubscriptionFeatureSimplifiedPaywallTests.swift
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
import BrowserServicesKit
import SubscriptionTestingUtilities
import Core
import PixelKit
import PixelExperimentKit
@testable import Subscription
@testable import DuckDuckGo


final class SubscriptionPagesUseSubscriptionFeatureSimplifiedPaywallTests: XCTestCase {

    private var sut: (any SubscriptionPagesUseSubscriptionFeature)!

    private var mockSubscriptionManager: SubscriptionManagerMock!
    private var mockAccountManager: AccountManagerMock!
    private var mockStorePurchaseManager: StorePurchaseManagerMock!
    private var mockAppStorePurchaseFlow: AppStorePurchaseFlowMock!

    override func setUp() async throws {
        PixelKit.configureExperimentKit(featureFlagger: MockFeatureFlagger(), eventTracker: ExperimentEventTracker(), fire: { _, _, _ in })

        mockAccountManager = AccountManagerMock()
        mockStorePurchaseManager = StorePurchaseManagerMock()
        mockSubscriptionManager = SubscriptionManagerMock(
            accountManager: mockAccountManager,
            subscriptionEndpointService: SubscriptionEndpointServiceMock(),
            authEndpointService: AuthEndpointServiceMock(),
            storePurchaseManager: mockStorePurchaseManager,
            currentEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
            canPurchase: true,
            subscriptionFeatureMappingCache: SubscriptionFeatureMappingCacheMock())

        mockAppStorePurchaseFlow = AppStorePurchaseFlowMock()

        sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: mockAppStorePurchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            appStoreAccountManagementFlow: AppStoreAccountManagementFlowMock(),
        subscriptionFreeTrialsHelper: MockSubscriptionFreeTrialsHelper())
    }

    func testWhenSubscriptionSelectedIncludesExperimentParameters_thenSubscriptionPurchasedReceivesExperimentParameters() async throws {

        // Given
        mockAccountManager.accessToken = nil
        mockSubscriptionManager.canPurchase = true
        mockAppStorePurchaseFlow.purchaseSubscriptionResult = .success("")
        mockAppStorePurchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)
        mockAppStorePurchaseFlow.purchaseSubscriptionBlock = { self.mockAccountManager.accessToken = "token" }

        let experimentNameKey = "experimentName"
        let experimentNameValue = "simplifiedPaywall"
        let experimentTreatmentKey = "experimentCohort"
        let experimentTreatmentValue = "treatment"

        let params: [String: Any] = [
            "id": "monthly-free-trial",
            "experiment": [
                "name": "simplifiedPaywall",
                "cohort": "treatment"
            ]
        ]

        // When
        _ = await sut.subscriptionSelected(params: params, original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let additionalParams = mockAppStorePurchaseFlow.completeSubscriptionAdditionalParams else {
            XCTFail("Additional params not found")
            return
        }

        XCTAssertEqual(
            additionalParams[experimentNameKey],
            experimentNameValue)
        XCTAssertEqual(
            additionalParams[experimentTreatmentKey],
            experimentTreatmentValue)
    }

    func testWhenSubscriptionSelectedDoesntIncludeExperimentParameters_thenSubscriptionPurchasedDoesntReceiveExperimentParameters() async throws {

        // Given
        mockAccountManager.accessToken = nil
        mockSubscriptionManager.canPurchase = true
        mockAppStorePurchaseFlow.purchaseSubscriptionResult = .success("")
        mockAppStorePurchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)
        mockAppStorePurchaseFlow.purchaseSubscriptionBlock = { self.mockAccountManager.accessToken = "token" }

        let experimentNameKey = "experimentName"
        let experimentTreatmentKey = "experimentCohort"

        let params: [String: Any] = [
            "id": "monthly-free-trial"
        ]

        // When
        _ = await sut.subscriptionSelected(params: params, original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let additionalParams = mockAppStorePurchaseFlow.completeSubscriptionAdditionalParams else {

            // This is fine and acceptable.
            return
        }

        // Even though the above guard exiting is acceptable, we also check
        // that the parameters that should be missing are missing, because
        // other code changes could cause additional params to be added in
        // the future, which should not make this test fail on its own.
        XCTAssertNil(additionalParams[experimentNameKey])
        XCTAssertNil(additionalParams[experimentTreatmentKey])
    }
}

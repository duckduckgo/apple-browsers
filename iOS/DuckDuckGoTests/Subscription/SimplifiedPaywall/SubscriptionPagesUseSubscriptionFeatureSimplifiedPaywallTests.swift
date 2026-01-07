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
import PrivacyConfig
import PixelKitTestingUtilities
import NetworkingTestingUtils

// For Diego to refactor or remove

// final class SubscriptionPagesUseSubscriptionFeatureSimplifiedPaywallTests: XCTestCase {
//
//    private var sut: (any SubscriptionPagesUseSubscriptionFeature)!
//
//    private var mockSubscriptionManager: SubscriptionManagerMockV2!
//
//    private var mockStorePurchaseManager: StorePurchaseManagerMockV2!
//    private var mockAppStorePurchaseFlow: AppStorePurchaseFlowMockV2!
//    private var mockAppStoreRestoreFlow: AppStoreRestoreFlowMockV2!
//    private var mockInternalUserDecider: MockInternalUserDecider!
//    private var mockWideEvent: WideEventMock!
//
//    override func setUp() async throws {
//        PixelKit.configureExperimentKit(featureFlagger: MockFeatureFlagger(), eventTracker: ExperimentEventTracker(), fire: { _, _, _ in })
//
//        mockStorePurchaseManager = StorePurchaseManagerMockV2()
//        mockSubscriptionManager = SubscriptionManagerMockV2()
//        mockAppStorePurchaseFlow = AppStorePurchaseFlowMockV2()
//        mockAppStoreRestoreFlow = AppStoreRestoreFlowMockV2()
//        mockInternalUserDecider = MockInternalUserDecider()
//        mockWideEvent = WideEventMock()
//
//        sut = DefaultSubscriptionPagesUseSubscriptionFeatureV2(
//            subscriptionManager: mockSubscriptionManager,
//            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
//            subscriptionAttributionOrigin: nil,
//            appStorePurchaseFlow: mockAppStorePurchaseFlow,
//            appStoreRestoreFlow: mockAppStoreRestoreFlow,
//            internalUserDecider: mockInternalUserDecider,
//            wideEvent: mockWideEvent)
//    }
//
//    func testWhenSubscriptionSelectedIncludesExperimentParameters_thenSubscriptionPurchasedReceivesExperimentParameters() async throws {
//
//        // Given
//        //        mockAccountManager.accessToken = nil
//        mockSubscriptionManager.hasAppStoreProductsAvailable = true
//        mockAppStorePurchaseFlow.purchaseSubscriptionResult = .success((transactionJWS: "jws", accountCreationDuration: nil))
//        mockAppStorePurchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)
////        mockAppStorePurchaseFlow.purchaseSubscriptionBlock = { self.mockAccountManager.accessToken = "token" }
//
//        let experimentNameKey = "experimentName"
//        let experimentNameValue = "simplifiedPaywall"
//        let experimentTreatmentKey = "experimentCohort"
//        let experimentTreatmentValue = "treatment"
//
//        let params: [String: Any] = [
//            "id": "monthly-free-trial",
//            "experiment": [
//                "name": "simplifiedPaywall",
//                "cohort": "treatment"
//            ]
//        ]
//
//        // When
//        _ = await sut.subscriptionSelected(params: params, original: MockWKScriptMessage(name: "", body: ""))
//
//        // Then
////        guard let additionalParams = mockAppStorePurchaseFlow.completeSubscriptionAdditionalParams else {
////            XCTFail("Additional params not found")
////            return
////        }
//
//        XCTAssertEqual(
//            additionalParams[experimentNameKey],
//            experimentNameValue)
//        XCTAssertEqual(
//            additionalParams[experimentTreatmentKey],
//            experimentTreatmentValue)
//    }
//
//    func testWhenSubscriptionSelectedDoesntIncludeExperimentParameters_thenSubscriptionPurchasedDoesntReceiveExperimentParameters() async throws {
//
//        // Given
////        mockAccountManager.accessToken = nil
//        mockSubscriptionManager.hasAppStoreProductsAvailable = true
//        mockAppStorePurchaseFlow.purchaseSubscriptionResult = .success((transactionJWS: "jws", accountCreationDuration: nil))
//        mockAppStorePurchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)
//        mockAppStorePurchaseFlow.purchaseSubscriptionBlock = { self.mockAccountManager.accessToken = "token" }
//
//        let experimentNameKey = "experimentName"
//        let experimentTreatmentKey = "experimentCohort"
//
//        let params: [String: Any] = [
//            "id": "monthly-free-trial"
//        ]
//
//        // When
//        _ = await sut.subscriptionSelected(params: params, original: MockWKScriptMessage(name: "", body: ""))
//
//        // Then
//        guard let additionalParams = mockAppStorePurchaseFlow.completeSubscriptionAdditionalParams else {
//
//            // This is fine and acceptable.
//            return
//        }
//
//        // Even though the above guard exiting is acceptable, we also check
//        // that the parameters that should be missing are missing, because
//        // other code changes could cause additional params to be added in
//        // the future, which should not make this test fail on its own.
//        XCTAssertNil(additionalParams[experimentNameKey])
//        XCTAssertNil(additionalParams[experimentTreatmentKey])
//    }
// }

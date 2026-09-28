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
@_spi(Testing) import PixelKit
@_spi(Testing) import WideEvent
import PixelExperimentKit
@testable import Subscription
@testable import DuckDuckGo
import PrivacyConfig
@_spi(Testing) import Networking
import BrowserServicesKitTestsUtils
import FeatureFlags_iOS
import WebKit

final class SubscriptionPagesUseSubscriptionFeatureSimplifiedPaywallTests: XCTestCase {

    private var sut: (any SubscriptionPagesUseSubscriptionFeature)!

    private var mockSubscriptionManager: SubscriptionManagerMock!
    private var mockStorePurchaseManager: StorePurchaseManagerMock!
    private var mockAppStorePurchaseFlow: AppStorePurchaseFlowMock!
    private var mockAppStoreRestoreFlow: AppStoreRestoreFlowMock!
    private var mockInternalUserDecider: PrivacyConfig.MockInternalUserDecider!
    private var mockWideEvent: WideEventMock!
    private var mockPendingTransactionHandler: MockPendingTransactionHandler!
    private var mockRequestValidator: ScriptRequestValidatorMock!
    private var mockExperimentFeatureFlagger: PrivacyConfig.MockFeatureFlagger!

    override func setUp() async throws {
        PixelKit.configureExperimentKit(featureFlagger: MockFeatureFlagger(), eventTracker: ExperimentEventTracker(), fire: { _, _, _ in })

        mockStorePurchaseManager = StorePurchaseManagerMock()
        mockStorePurchaseManager.hasActiveSubscriptionResult = false

        mockSubscriptionManager = SubscriptionManagerMock()
        mockSubscriptionManager.resultStorePurchaseManager = mockStorePurchaseManager

        mockAppStorePurchaseFlow = AppStorePurchaseFlowMock()
        mockAppStoreRestoreFlow = AppStoreRestoreFlowMock()
        mockInternalUserDecider = PrivacyConfig.MockInternalUserDecider(isInternalUser: true)
        mockWideEvent = WideEventMock()
        mockPendingTransactionHandler = MockPendingTransactionHandler()
        mockRequestValidator = ScriptRequestValidatorMock()
        mockExperimentFeatureFlagger = PrivacyConfig.MockFeatureFlagger(featuresStub: [
            FeatureFlag.subscriptionConcurrentExperiments.rawValue: true
        ])

        let subscriptionFlowsExecuter = DefaultSubscriptionFlowsExecuter(
            subscriptionManager: mockSubscriptionManager,
            appStorePurchaseFlow: mockAppStorePurchaseFlow,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler()
        )

        sut = DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: mockAppStorePurchaseFlow,
            appStoreRestoreFlow: mockAppStoreRestoreFlow,
            internalUserDecider: mockInternalUserDecider,
            wideEvent: mockWideEvent,
            pendingTransactionHandler: mockPendingTransactionHandler,
            subscriptionFlowsExecuter: subscriptionFlowsExecuter,
            requestValidator: mockRequestValidator,
            subscriptionExperimentAttributionProvider: DefaultSubscriptionExperimentAttributionProvider(
                featureFlagger: mockExperimentFeatureFlagger))
    }

    func testWhenSubscriptionSelectedIncludesExperimentParameters_thenSubscriptionPurchasedReceivesExperimentParameters() async throws {

        // Given
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockAppStorePurchaseFlow.purchaseSubscriptionResult = .success((transactionJWS: "jws", accountCreationDuration: nil))
        mockAppStorePurchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)

        let params: [String: Any] = [
            "id": "monthly-free-trial",
            "experiment": [
                "name": "simplifiedPaywall",
                "cohort": "treatment"
            ]
        ]

        // When
        _ = await sut.subscriptionSelected(params: params, original: WKScriptMessage.mock())

        // Then
        XCTAssertEqual(
            mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution,
            .multiple([SubscriptionExperiment(experimentName: "simplifiedPaywall", experimentCohort: "treatment")]))
    }

    func testWhenSubscriptionSelectedDoesntIncludeExperimentParameters_thenSubscriptionPurchasedDoesntReceiveExperimentParameters() async throws {

        // Given
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockAppStorePurchaseFlow.purchaseSubscriptionResult = .success((transactionJWS: "jws", accountCreationDuration: nil))
        mockAppStorePurchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)

        let params: [String: Any] = [
            "id": "monthly-free-trial"
        ]

        // When
        _ = await sut.subscriptionSelected(params: params, original: WKScriptMessage.mock())

        // Then
        XCTAssertNil(mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution)
    }

    func testWhenConcurrentExperimentsAreDisabledThenLegacyExperimentIsForwarded() async throws {
        prepareSuccessfulPurchase()
        mockExperimentFeatureFlagger.featuresStub[FeatureFlag.subscriptionConcurrentExperiments.rawValue] = false
        setNativeExperiments(["native": "treatment"])
        let params: [String: Any] = [
            "id": "monthly-free-trial",
            "experiment": ["name": "legacy", "cohort": "control"],
            "experiments": [["name": "multiple", "cohort": "treatment"]]
        ]

        _ = await sut.subscriptionSelected(params: params, original: WKScriptMessage.mock())

        XCTAssertEqual(
            mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution,
            .legacy(SubscriptionExperiment(experimentName: "legacy", experimentCohort: "control")))
    }

    func testWhenConcurrentExperimentsAreDisabledAndLegacyExperimentIsAbsentThenAttributionIsOmitted() async throws {
        prepareSuccessfulPurchase()
        mockExperimentFeatureFlagger.featuresStub[FeatureFlag.subscriptionConcurrentExperiments.rawValue] = false
        setNativeExperiments(["native": "treatment"])
        let params: [String: Any] = [
            "id": "monthly-free-trial",
            "experiments": [["name": "multiple", "cohort": "treatment"]]
        ]

        _ = await sut.subscriptionSelected(params: params, original: WKScriptMessage.mock())

        XCTAssertNil(mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution)
    }

    func testWhenSubscriptionSelectedIncludesMultipleExperimentsThenAllAreForwarded() async throws {
        prepareSuccessfulPurchase()
        let params: [String: Any] = [
            "id": "monthly-free-trial",
            "experiments": [
                ["name": "first", "cohort": "control"],
                ["name": "second", "cohort": "treatment"]
            ]
        ]

        _ = await sut.subscriptionSelected(params: params, original: WKScriptMessage.mock())

        XCTAssertEqual(mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution, .multiple([
            SubscriptionExperiment(experimentName: "first", experimentCohort: "control"),
            SubscriptionExperiment(experimentName: "second", experimentCohort: "treatment")
        ]))
    }

    func testWhenBothMultipleAndLegacyExperimentsArePresentThenMultipleExperimentsTakePrecedence() async throws {
        prepareSuccessfulPurchase()
        let params: [String: Any] = [
            "id": "monthly-free-trial",
            "experiment": ["name": "legacy", "cohort": "control"],
            "experiments": [["name": "multiple", "cohort": "treatment"]]
        ]

        _ = await sut.subscriptionSelected(params: params, original: WKScriptMessage.mock())

        XCTAssertEqual(
            mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution,
            .multiple([SubscriptionExperiment(experimentName: "multiple", experimentCohort: "treatment")]))
    }

    func testWhenMultipleExperimentsIsEmptyThenLegacyExperimentIsUsed() async throws {
        prepareSuccessfulPurchase()
        let params: [String: Any] = [
            "id": "monthly-free-trial",
            "experiment": ["name": "legacy", "cohort": "control"],
            "experiments": []
        ]

        _ = await sut.subscriptionSelected(params: params, original: WKScriptMessage.mock())

        XCTAssertEqual(
            mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution,
            .multiple([SubscriptionExperiment(experimentName: "legacy", experimentCohort: "control")]))
    }

    func testWhenFrontEndAndNativeExperimentsOverlapThenFrontEndCohortTakesPrecedence() async throws {
        prepareSuccessfulPurchase()
        setNativeExperiments([
            "shared": "native",
            "native": "treatment"
        ])
        let params: [String: Any] = [
            "id": "monthly-free-trial",
            "experiments": [
                ["name": "shared", "cohort": "front-end"],
                ["name": "front-end", "cohort": "control"]
            ]
        ]

        _ = await sut.subscriptionSelected(params: params, original: WKScriptMessage.mock())

        XCTAssertEqual(mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution, .multiple([
            SubscriptionExperiment(experimentName: "shared", experimentCohort: "front-end"),
            SubscriptionExperiment(experimentName: "front-end", experimentCohort: "control"),
            SubscriptionExperiment(experimentName: "native", experimentCohort: "treatment")
        ]))
    }

    func testWhenFrontEndRepeatsAnExperimentNameThenTheFirstAssignmentTakesPrecedence() async throws {
        prepareSuccessfulPurchase()
        let params: [String: Any] = [
            "id": "monthly-free-trial",
            "experiments": [
                ["name": "duplicate", "cohort": "first"],
                ["name": "duplicate", "cohort": "second"]
            ]
        ]

        _ = await sut.subscriptionSelected(params: params, original: WKScriptMessage.mock())

        XCTAssertEqual(
            mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution,
            .multiple([SubscriptionExperiment(experimentName: "duplicate", experimentCohort: "first")]))
    }

    func testWhenOnlyNativeExperimentIsActiveThenItIsForwarded() async throws {
        prepareSuccessfulPurchase()
        setNativeExperiments(["native": "treatment"])

        _ = await sut.subscriptionSelected(params: ["id": "monthly-free-trial"], original: WKScriptMessage.mock())

        XCTAssertEqual(
            mockAppStorePurchaseFlow.completeSubscriptionExperimentAttribution,
            .multiple([SubscriptionExperiment(experimentName: "native", experimentCohort: "treatment")]))
    }

    private func prepareSuccessfulPurchase() {
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockAppStorePurchaseFlow.purchaseSubscriptionResult = .success((transactionJWS: "jws", accountCreationDuration: nil))
        mockAppStorePurchaseFlow.completeSubscriptionPurchaseResult = .success(.completed)
    }

    private func setNativeExperiments(_ experiments: [String: String]) {
        mockExperimentFeatureFlagger.allActiveExperiments = experiments.mapValues {
            ExperimentData(parentID: PrivacyFeature.privacyPro.rawValue, cohortID: $0, enrollmentDate: Date())
        }
    }
}

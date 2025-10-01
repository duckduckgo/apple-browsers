//
//  WideEventTests.swift
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
@testable import PixelKit
import Foundation

final class WideEventTests: XCTestCase {

    var wideEvent: WideEvent!
    var testDefaults: UserDefaults!
    var capturedPixels: [(name: String, parameters: [String: String])] = []
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        wideEvent = WideEvent(storage: WideEventUserDefaultsStorage(userDefaults: testDefaults))
        capturedPixels.removeAll()
        setupMockPixelKit()
    }

    override func tearDown() {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        PixelKit.tearDown()

        super.tearDown()
    }

    private func setupMockPixelKit() {
        let mockFireRequest: PixelKit.FireRequest = { pixelName, headers, parameters, allowedQueryReservedCharacters, callBackOnMainThread, onComplete in
            self.capturedPixels.append((name: pixelName, parameters: parameters))
            DispatchQueue.main.async {
                onComplete(true, nil)
            }
        }

        PixelKit.setUp(
            dryRun: false,
            appVersion: "1.0.0-test",
            source: "test",
            defaultHeaders: [:],
            dateGenerator: Date.init,
            defaults: testDefaults,
            fireRequest: mockFireRequest
        )
    }

    // MARK: - Basic Flow Management Tests

    func testFlowPersistenceAndDataIntegrity() throws {
        let subscriptionData = makeTestSubscriptionData(
            platform: .appStore,
            contextName: "test-flow",
            subscriptionIdentifier: "test-subscription-id"
        )

        wideEvent.startFlow(subscriptionData)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)

        XCTAssertEqual(retrievedData.purchasePlatform, .appStore)
        XCTAssertEqual(retrievedData.contextData.name, "test-flow")
        XCTAssertEqual(retrievedData.subscriptionIdentifier, "test-subscription-id")
    }

    func testFlowUpdateWithDataReplacement() throws {
        let initialData = makeTestSubscriptionData(platform: .stripe, contextName: "initial")
        wideEvent.startFlow(initialData)

        let updatedData = initialData
        updatedData.failingStep = .accountCreate
        updatedData.subscriptionIdentifier = "updated-subscription"
        updatedData.freeTrialEligible = true
        wideEvent.updateFlow(updatedData)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: initialData.globalData.id)
        XCTAssertEqual(retrievedData.purchasePlatform, .stripe)
        XCTAssertEqual(retrievedData.failingStep, .accountCreate)
        XCTAssertEqual(retrievedData.subscriptionIdentifier, "updated-subscription")
        XCTAssertEqual(retrievedData.freeTrialEligible, true)
    }

    func testFlowCancellationClearsStorage() throws {
        let subscriptionData = makeTestSubscriptionData(contextName: "cancellation-test")
        wideEvent.startFlow(subscriptionData)

        _ = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)

        let expectation = XCTestExpectation(description: "Flow cancelled")
        wideEvent.completeFlow(subscriptionData, status: .cancelled) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let retrievedData = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)
        XCTAssertNil(retrievedData)

        XCTAssert(capturedPixels.count >= 1 && capturedPixels.count <= 2)
        XCTAssertEqual(capturedPixels[0].parameters["feature.status"], "CANCELLED")
    }

    // MARK: - Error Handling Tests

    func testGetFlowDataForNonExistentFlow() {
        let nonExistentGlobalID = UUID().uuidString
        let result = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: nonExistentGlobalID)
        XCTAssertNil(result)
    }

    func testDiscardFlowDeletesStoredData() throws {
        let subscriptionData = makeTestSubscriptionData(contextName: "discard-test")
        wideEvent.startFlow(subscriptionData)

        // Verify flow exists
        _ = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)

        // Discard the flow
        wideEvent.discardFlow(subscriptionData)

        // Verify flow is deleted from storage
        let retrievedData = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)
        XCTAssertNil(retrievedData, "Flow should be deleted from storage after discard")

        // Verify no pixel was fired
        XCTAssertEqual(capturedPixels.count, 0, "No pixel should be fired when discarding a flow")
    }

    func testDiscardFlowForNonExistentFlow() {
        let data = makeTestSubscriptionData()
        wideEvent.discardFlow(data)

        // Verify no pixel was fired
        XCTAssertEqual(capturedPixels.count, 0)
    }

    func testDiscardFlowAfterUpdates() throws {
        let subscriptionData = makeTestSubscriptionData(platform: .stripe, contextName: "discard-with-updates")
        wideEvent.startFlow(subscriptionData)

        // Update the flow multiple times
        let updatedData = subscriptionData
        updatedData.subscriptionIdentifier = "test-subscription"
        updatedData.freeTrialEligible = true
        wideEvent.updateFlow(updatedData)

        updatedData.failingStep = .accountCreate
        wideEvent.updateFlow(updatedData)

        // Verify flow exists with updates
        let retrievedBeforeDiscard = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)
        XCTAssertEqual(retrievedBeforeDiscard.subscriptionIdentifier, "test-subscription")
        XCTAssertEqual(retrievedBeforeDiscard.failingStep, .accountCreate)
        XCTAssertTrue(retrievedBeforeDiscard.freeTrialEligible)

        // Discard the flow
        wideEvent.discardFlow(updatedData)

        // Verify flow is deleted
        let retrievedAfterDiscard = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)
        XCTAssertNil(retrievedAfterDiscard, "Updated flow should be deleted from storage after discard")

        // Verify no pixel was fired
        XCTAssertEqual(capturedPixels.count, 0, "No pixel should be fired when discarding a flow")
    }

    func testSerializationFailure() throws {
        struct NonSerializableData: WideEventData {
            static let pixelName = "non_serializable"
            let closure: () -> Void = { }
            var contextData: WideEventContextData = WideEventContextData()
            var appData: WideEventAppData = WideEventAppData()
            var globalData: WideEventGlobalData = WideEventGlobalData(platform: "", sampleRate: 1.0)
            var errorData: WideEventErrorData?
            func pixelParameters() -> [String: String] { [:] }

            enum CodingError: Error { case encodingNotSupported }

            init() {}

            init(from decoder: Decoder) throws { throw CodingError.encodingNotSupported }
            func encode(to encoder: Encoder) throws { throw CodingError.encodingNotSupported }
        }

        let nonSerializableData = NonSerializableData()
        wideEvent.startFlow(nonSerializableData)
    }

    func testCompleteFlowWithoutPixelKit() throws {
        PixelKit.tearDown()

        let subscriptionData = makeTestSubscriptionData()
        wideEvent.startFlow(subscriptionData)

        let expectation = XCTestExpectation(description: "Completion called")
        wideEvent.completeFlow(subscriptionData, status: .success) { success, error in
            XCTAssertFalse(success)
            guard let error = error, case WideEventError.invalidFlowState = error else {
                XCTFail("Expected invalidFlowState error, got \(String(describing: error))")
                return
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(capturedPixels.count, 0)
    }

    // MARK: - Measurement Tests

    func testBasicMeasurementOperations() throws {
        let data = makeTestSubscriptionData()
        wideEvent.startFlow(data)

        let started = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        started.createAccountDuration = WideEvent.MeasuredInterval.startingNow()
        wideEvent.updateFlow(started)

        let dataAfterStart = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        XCTAssertNotNil(dataAfterStart.createAccountDuration?.start)
        XCTAssertNil(dataAfterStart.createAccountDuration?.end)

        let stopped = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        stopped.createAccountDuration?.complete()
        wideEvent.updateFlow(stopped)

        let dataAfterStop = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.start)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.end)
    }

    func testInstanceBasedMeasurements() throws {
        let data = makeTestSubscriptionData()
        wideEvent.startFlow(data)

        XCTAssertNil(data.createAccountDuration)
        data.createAccountDuration = WideEvent.MeasuredInterval.startingNow()
        XCTAssertNotNil(data.createAccountDuration?.start)
        XCTAssertNil(data.createAccountDuration?.end)

        data.createAccountDuration?.complete()
        XCTAssertNotNil(data.createAccountDuration?.start)
        XCTAssertNotNil(data.createAccountDuration?.end)
    }

    func testMeasurementWithExtremeDurations() throws {
        let data = makeTestSubscriptionData()
        wideEvent.startFlow(data)

        // Test very short duration
        let shortStart = Date()
        let shortEnd = shortStart.addingTimeInterval(0.001)

        let short = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        short.createAccountDuration = WideEvent.MeasuredInterval(start: shortStart, end: shortEnd)
        wideEvent.updateFlow(short)

        // Test very long duration
        let longStart = Date(timeIntervalSince1970: 0)
        let longEnd = longStart.addingTimeInterval(3600 * 24)
        let long = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        long.completePurchaseDuration = WideEvent.MeasuredInterval(start: longStart, end: longEnd)
        wideEvent.updateFlow(long)

        let typed = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        var parameters: [String: String] = [:]
        parameters["global.platform"] = "macOS"
        parameters["global.type"] = "app"
        parameters["global.sample_rate"] = "1.0"
        parameters["app.name"] = typed.appData.name
        parameters["app.version"] = typed.appData.version

        if let formFactor = typed.appData.formFactor { parameters["global.form_factor"] = formFactor }
        parameters["feature.name"] = SubscriptionPurchaseWideEventData.pixelName

        if let name = typed.contextData.name { parameters["context.name"] = name }
        parameters.merge(typed.pixelParameters(), uniquingKeysWith: { _, new in new })

        XCTAssertEqual(parameters["feature.data.ext.account_creation_latency_ms_bucketed"], "1000")
        XCTAssertEqual(parameters["feature.data.ext.account_payment_latency_ms_bucketed"], "600000")
    }

    func testStopMeasurementWhenNeverStarted() throws {
        let data = makeTestSubscriptionData()
        wideEvent.startFlow(data)

        let now = Date()
        let updated = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        updated.createAccountDuration = WideEvent.MeasuredInterval(start: now, end: now)
        wideEvent.updateFlow(updated)

        let dataAfterStop = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.start)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.end)
        XCTAssertEqual(dataAfterStop.createAccountDuration?.start, dataAfterStop.createAccountDuration?.end)
    }

    func testComprehensiveParameterFlattening() throws {
        let testError = makeTestError(domain: "TestErrorDomain", code: 12345)

        let subscriptionData = SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            failingStep: .accountCreate,
            subscriptionIdentifier: "ddg.privacy.pro.monthly",
            freeTrialEligible: true,
            createAccountDuration: WideEvent.MeasuredInterval(
                start: Date(timeIntervalSince1970: 1000),
                end: Date(timeIntervalSince1970: 1002.5)
            ),
            errorData: WideEventErrorData(error: testError),
            contextData: WideEventContextData(name: "test-funnel"),
            appData: WideEventAppData()
        )

        wideEvent.startFlow(subscriptionData)
        let typed = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)
        var parameters: [String: String] = [:]

        parameters["global.platform"] = "macOS"
        parameters["global.type"] = "app"
        parameters["global.sample_rate"] = "1.0"
        parameters["app.name"] = typed.appData.name
        parameters["app.version"] = typed.appData.version
        if let formFactor = typed.appData.formFactor { parameters["global.form_factor"] = formFactor }
        parameters["feature.name"] = SubscriptionPurchaseWideEventData.pixelName
        if let name = typed.contextData.name { parameters["context.name"] = name }

        parameters.merge(typed.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(typed.errorData!.pixelParameters(), uniquingKeysWith: { _, new in new })

        // Feature parameters
        XCTAssertEqual(parameters["feature.data.ext.purchase_platform"], "app_store")
        XCTAssertEqual(parameters["feature.data.ext.failing_step"], "ACCOUNT_CREATE")
        XCTAssertEqual(parameters["feature.data.ext.subscription_identifier"], "ddg.privacy.pro.monthly")
        XCTAssertEqual(parameters["feature.data.ext.free_trial_eligible"], "true")

        // Measurement parameters
        XCTAssertEqual(parameters["feature.data.ext.account_creation_latency_ms_bucketed"], "5000")

        // Error parameters
        XCTAssertEqual(parameters["feature.data.error.domain"], "TestErrorDomain")
        XCTAssertEqual(parameters["feature.data.error.code"], "12345")

        // Context parameters
        XCTAssertEqual(parameters["context.name"], "test-funnel")

        // Global parameters
        XCTAssertNotNil(parameters["global.platform"])
        XCTAssertEqual(parameters["global.type"], "app")
        XCTAssertEqual(parameters["global.sample_rate"], "1.0")

        // Feature metadata
        XCTAssertEqual(parameters["feature.name"], "subscription-purchase")
        XCTAssertNil(parameters["feature.status"])
    }

    func testJsonParameterNesting() throws {
        struct TestProvider: WideEventParameterProviding {
            func pixelParameters() -> [String: String] {
                return [
                    "app.name": "DuckDuckGo",
                    "feature.status": "SUCCESS"
                ]
            }
        }

        let jsonString = try TestProvider().jsonParameters()
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

        let app = object?["app"] as? [String: Any]
        let feature = object?["feature"] as? [String: Any]

        XCTAssertEqual(app?["name"] as? String, "DuckDuckGo")
        XCTAssertEqual(feature?["status"] as? String, "SUCCESS")
    }

    func testErrorDataCapturesUnderlyingErrors() {
        let deepError = NSError(domain: "DeepDomain", code: 3)

        let deepErrorData = WideEventErrorData(error: deepError)

        XCTAssertEqual(deepErrorData.domain, "DeepDomain")
        XCTAssertEqual(deepErrorData.code, 3)
        XCTAssertEqual(deepErrorData.underlyingErrors.count, 0)

        let nestedError = NSError(domain: "NestedDomain", code: 2, userInfo: [NSUnderlyingErrorKey: deepError])
        let rootError = NSError(domain: "RootDomain", code: 1, userInfo: [NSUnderlyingErrorKey: nestedError])

        let errorData = WideEventErrorData(error: rootError)

        XCTAssertEqual(errorData.domain, "RootDomain")
        XCTAssertEqual(errorData.code, 1)

        XCTAssertEqual(errorData.underlyingErrors.count, 2)
        XCTAssertEqual(errorData.underlyingErrors.first?.domain, "NestedDomain")
        XCTAssertEqual(errorData.underlyingErrors.first?.code, 2)
        XCTAssertEqual(errorData.underlyingErrors.last?.domain, "DeepDomain")
        XCTAssertEqual(errorData.underlyingErrors.last?.code, 3)

        let parameters = errorData.pixelParameters()
        XCTAssertEqual(parameters[WideEventParameter.Feature.errorDomain], "RootDomain")
        XCTAssertEqual(parameters[WideEventParameter.Feature.errorCode], "1")
        XCTAssertEqual(parameters[WideEventParameter.Feature.underlyingErrorDomain], "NestedDomain")
        XCTAssertEqual(parameters[WideEventParameter.Feature.underlyingErrorCode], "2")
        XCTAssertEqual(parameters[WideEventParameter.Feature.underlyingErrorDomain + "2"], "DeepDomain")
        XCTAssertEqual(parameters[WideEventParameter.Feature.underlyingErrorCode + "2"], "3")
    }

    func testActiveFlowManagement() throws {
        let data1 = makeTestSubscriptionData(contextName: "flow-1")
        let data2 = makeTestSubscriptionData(contextName: "flow-2")

        wideEvent.startFlow(data1)
        wideEvent.startFlow(data2)

        let allFlows = wideEvent.getAllFlowData(SubscriptionPurchaseWideEventData.self)
        XCTAssertEqual(allFlows.count, 2)
    }

    func testNilAndEmptyValues() throws {
        let data = makeTestSubscriptionData()
        data.subscriptionIdentifier = nil
        data.contextData.name = nil

        wideEvent.startFlow(data)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data.globalData.id)
        XCTAssertNil(retrievedData.subscriptionIdentifier)
        XCTAssertNil(retrievedData.contextData.name)

        let expectation = XCTestExpectation(description: "completeFlow")
        wideEvent.completeFlow(retrievedData, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssert(capturedPixels.count >= 1 && capturedPixels.count <= 2)
    }

    func testFlowRestartWithSameContextID() throws {
        let data1 = makeTestSubscriptionData(platform: .appStore, contextName: "first")
        wideEvent.startFlow(data1)

        let updated1 = data1
        updated1.subscriptionIdentifier = "subscription"
        wideEvent.updateFlow(updated1)

        let data2 = makeTestSubscriptionData(platform: .stripe, contextName: "second")
        wideEvent.startFlow(data2)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWideEventData.self, globalID: data2.globalData.id)
        XCTAssertEqual(retrievedData.purchasePlatform, .stripe)
        XCTAssertEqual(retrievedData.contextData.name, "second")
        XCTAssertNil(retrievedData.subscriptionIdentifier)
    }

    func testSamplingDecisionAtStartSkipsPersistenceWhenNotSampled() throws {
        let notSampled = makeTestSubscriptionData()
        notSampled.globalData.sampleRate = 0.0

        wideEvent.startFlow(notSampled)

        XCTAssertNil(wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: notSampled.globalData.id))

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(SubscriptionPurchaseWideEventData.self, globalID: notSampled.globalData.id, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(capturedPixels.count, 0)
    }

    // MARK: - Test Utilities

    func makeTestSubscriptionData(
        platform: SubscriptionPurchaseWideEventData.PurchasePlatform = .appStore,
        contextName: String? = nil,
        subscriptionIdentifier: String? = nil,
        freeTrialEligible: Bool? = nil
    ) -> SubscriptionPurchaseWideEventData {
        let contextData = WideEventContextData(name: contextName)
        return SubscriptionPurchaseWideEventData(
            purchasePlatform: platform,
            subscriptionIdentifier: subscriptionIdentifier,
            freeTrialEligible: freeTrialEligible ?? false,
            contextData: contextData
        )
    }

    func makeTestError(domain: String = "TestDomain", code: Int = 999) -> NSError {
        return NSError(domain: domain, code: code, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: "UnderlyingDomain", code: 123)
        ])
    }

    func XCTUnwrapFlow<T: WideEventData>(_ type: T.Type, globalID: String, file: StaticString = #file, line: UInt = #line) throws -> T {
        guard let flow = wideEvent.getFlowData(type, globalID: globalID) else {
            XCTFail("Expected flow data for \(type) with globalID \(globalID)", file: file, line: line)
            throw TestError.flowNotFound
        }
        return flow
    }

    enum TestError: Error {
        case flowNotFound
    }
}

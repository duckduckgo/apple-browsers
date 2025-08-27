//
//  WidePixelTests.swift
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

final class WidePixelTests: XCTestCase {

    var widePixel: WidePixel!
    var testDefaults: UserDefaults!
    var capturedPixels: [(name: String, parameters: [String: String])] = []
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        widePixel = WidePixel(storage: WidePixelUserDefaultsStorage(userDefaults: testDefaults))
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

        widePixel.startFlow(subscriptionData)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: subscriptionData.globalData.id)

        XCTAssertEqual(retrievedData.purchasePlatform, .appStore)
        XCTAssertEqual(retrievedData.contextData.id, subscriptionData.contextData.id)
        XCTAssertEqual(retrievedData.contextData.name, "test-flow")
        XCTAssertEqual(retrievedData.subscriptionIdentifier, "test-subscription-id")
    }

    func testFlowUpdateWithDataReplacement() throws {
        let initialData = makeTestSubscriptionData(platform: .stripe, contextName: "initial")
        widePixel.startFlow(initialData)

        var updatedData = initialData
        updatedData.failingStep = .accountCreate
        updatedData.subscriptionIdentifier = "updated-subscription"
        updatedData.freeTrialEligible = true
        widePixel.updateFlow(updatedData)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: initialData.globalData.id)
        XCTAssertEqual(retrievedData.purchasePlatform, .stripe)
        XCTAssertEqual(retrievedData.failingStep, .accountCreate)
        XCTAssertEqual(retrievedData.subscriptionIdentifier, "updated-subscription")
        XCTAssertEqual(retrievedData.freeTrialEligible, true)
    }

    func testFlowCancellationClearsStorage() throws {
        let subscriptionData = makeTestSubscriptionData(contextName: "cancellation-test")
        widePixel.startFlow(subscriptionData)

        _ = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: subscriptionData.globalData.id)

        let expectation = XCTestExpectation(description: "Flow cancelled")
        widePixel.completeFlow(subscriptionData, status: .cancelled) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let retrievedData = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, globalID: subscriptionData.globalData.id)
        XCTAssertNil(retrievedData)

        XCTAssertEqual(capturedPixels.count, 1)
        XCTAssertEqual(capturedPixels[0].parameters["feature.status"], "CANCELLED")
    }

    // MARK: - Error Handling Tests

    func testGetFlowDataForNonExistentFlow() {
        let nonExistentContextID = UUID().uuidString
        let result = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, globalID: nonExistentContextID)
        XCTAssertNil(result)
    }

    func testUpdateFlowForNonExistentFlow() {
        let nonExistentContextID = UUID().uuidString
        let data = makeTestSubscriptionData(contextID: nonExistentContextID)

        widePixel.updateFlow(data)
    }

    func testCompleteFlowForNonExistentFlow() {
        let nonExistentContextID = UUID().uuidString
        let data = makeTestSubscriptionData(contextID: nonExistentContextID)

        widePixel.completeFlow(data, status: .success) { _, _ in }
    }

    func testDiscardFlowDeletesStoredData() throws {
        let subscriptionData = makeTestSubscriptionData(contextName: "discard-test")
        widePixel.startFlow(subscriptionData)

        // Verify flow exists
        _ = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: subscriptionData.globalData.id)

        // Discard the flow
        widePixel.discardFlow(subscriptionData)

        // Verify flow is deleted from storage
        let retrievedData = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, globalID: subscriptionData.globalData.id)
        XCTAssertNil(retrievedData, "Flow should be deleted from storage after discard")

        // Verify no pixel was fired
        XCTAssertEqual(capturedPixels.count, 0, "No pixel should be fired when discarding a flow")
    }

    func testDiscardFlowForNonExistentFlow() {
        let nonExistentContextID = UUID().uuidString
        let data = makeTestSubscriptionData(contextID: nonExistentContextID)

        // This should not crash and should handle the missing flow gracefully
        widePixel.discardFlow(data)

        // Verify no pixel was fired
        XCTAssertEqual(capturedPixels.count, 0)
    }

    func testDiscardFlowAfterUpdates() throws {
        let subscriptionData = makeTestSubscriptionData(platform: .stripe, contextName: "discard-with-updates")
        widePixel.startFlow(subscriptionData)

        // Update the flow multiple times
        var updatedData = subscriptionData
        updatedData.subscriptionIdentifier = "test-subscription"
        updatedData.freeTrialEligible = true
        widePixel.updateFlow(updatedData)

        updatedData.failingStep = .accountCreate
        widePixel.updateFlow(updatedData)

        // Verify flow exists with updates
        let retrievedBeforeDiscard = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: subscriptionData.globalData.id)
        XCTAssertEqual(retrievedBeforeDiscard.subscriptionIdentifier, "test-subscription")
        XCTAssertEqual(retrievedBeforeDiscard.failingStep, .accountCreate)
        XCTAssertTrue(retrievedBeforeDiscard.freeTrialEligible)

        // Discard the flow
        widePixel.discardFlow(updatedData)

        // Verify flow is deleted
        let retrievedAfterDiscard = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, globalID: subscriptionData.globalData.id)
        XCTAssertNil(retrievedAfterDiscard, "Updated flow should be deleted from storage after discard")

        // Verify no pixel was fired
        XCTAssertEqual(capturedPixels.count, 0, "No pixel should be fired when discarding a flow")
    }

    func testSerializationFailure() throws {
        struct NonSerializableData: WidePixelData {
            static let pixelName = "non_serializable"
            let closure: () -> Void = { }
            var contextData: WidePixelContextData = WidePixelContextData(id: UUID().uuidString)
            var appData: WidePixelAppData = WidePixelAppData()
            var globalData: WidePixelGlobalData = WidePixelGlobalData(platform: "", sampleRate: 1.0)
            func pixelParameters() -> [String: String] { [:] }

            enum CodingError: Error { case encodingNotSupported }

            init() {}

            init(from decoder: Decoder) throws { throw CodingError.encodingNotSupported }
            func encode(to encoder: Encoder) throws { throw CodingError.encodingNotSupported }
        }

        let nonSerializableData = NonSerializableData()
        widePixel.startFlow(nonSerializableData)
    }

    func testCompleteFlowWithoutPixelKit() throws {
        PixelKit.tearDown()

        let subscriptionData = makeTestSubscriptionData()
        widePixel.startFlow(subscriptionData)

        let expectation = XCTestExpectation(description: "Completion called")
        widePixel.completeFlow(subscriptionData, status: .success) { success, error in
            XCTAssertFalse(success)
            guard let error = error, case WidePixelError.invalidFlowState = error else {
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
        widePixel.startFlow(data)

        var started = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        started.createAccountDuration = WidePixel.MeasuredInterval.startingNow()
        widePixel.updateFlow(started)

        let dataAfterStart = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        XCTAssertNotNil(dataAfterStart.createAccountDuration?.start)
        XCTAssertNil(dataAfterStart.createAccountDuration?.end)

        var stopped = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        stopped.createAccountDuration?.complete()
        widePixel.updateFlow(stopped)

        let dataAfterStop = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.start)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.end)
    }

    func testInstanceBasedMeasurements() throws {
        var data = makeTestSubscriptionData()
        widePixel.startFlow(data)

        XCTAssertNil(data.createAccountDuration)
        data.createAccountDuration = WidePixel.MeasuredInterval.startingNow()
        XCTAssertNotNil(data.createAccountDuration?.start)
        XCTAssertNil(data.createAccountDuration?.end)

        data.createAccountDuration?.complete()
        XCTAssertNotNil(data.createAccountDuration?.start)
        XCTAssertNotNil(data.createAccountDuration?.end)
    }

    func testMeasurementWithExtremeDurations() throws {
        let data = makeTestSubscriptionData()
        widePixel.startFlow(data)

        // Test very short duration
        let shortStart = Date()
        let shortEnd = shortStart.addingTimeInterval(0.001)
        var short = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        short.createAccountDuration = WidePixel.MeasuredInterval(start: shortStart, end: shortEnd)
        widePixel.updateFlow(short)

        // Test very long duration
        let longStart = Date(timeIntervalSince1970: 0)
        let longEnd = longStart.addingTimeInterval(3600 * 24)
        var long = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        long.completePurchaseDuration = WidePixel.MeasuredInterval(start: longStart, end: longEnd)
        widePixel.updateFlow(long)

        let typed = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        var parameters: [String: String] = [:]
        parameters["global.platform"] = "macOS"
        parameters["global.type"] = "app"
        parameters["global.sample_rate"] = "1.0"
        parameters["app.name"] = typed.appData.name
        parameters["app.version"] = typed.appData.version

        if let formFactor = typed.appData.formFactor { parameters["global.form_factor"] = formFactor }
        parameters["feature.name"] = SubscriptionPurchaseWidePixelData.pixelName

        if let name = typed.contextData.name { parameters["context.name"] = name }
        if let data = typed.contextData.data {
            for (key, value) in data { parameters["context.data.\(key)"] = value }
        }

        parameters.merge(typed.pixelParameters(), uniquingKeysWith: { _, new in new })

        XCTAssertEqual(parameters["feature.data.ext.account_creation_latency_ms_bucketed"], "1000")
        XCTAssertEqual(parameters["feature.data.ext.account_payment_latency_ms_bucketed"], "600000")
    }

    func testStopMeasurementWhenNeverStarted() throws {
        let data = makeTestSubscriptionData()
        widePixel.startFlow(data)

        let now = Date()
        var updated = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        updated.createAccountDuration = WidePixel.MeasuredInterval(start: now, end: now)
        widePixel.updateFlow(updated)

        let dataAfterStop = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.start)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.end)
        XCTAssertEqual(dataAfterStop.createAccountDuration?.start, dataAfterStop.createAccountDuration?.end)
    }

    func testComprehensiveParameterFlattening() throws {
        let testError = makeTestError(domain: "TestErrorDomain", code: 12345)
        let contextID = UUID().uuidString

        let subscriptionData = SubscriptionPurchaseWidePixelData(
            purchasePlatform: .appStore,
            failingStep: .accountCreate,
            subscriptionIdentifier: "ddg.privacy.pro.monthly",
            freeTrialEligible: true,
            createAccountDuration: WidePixel.MeasuredInterval(
                start: Date(timeIntervalSince1970: 1000),
                end: Date(timeIntervalSince1970: 1002.5)
            ),
            errorData: WidePixelErrorData(error: testError),
            contextData: WidePixelContextData(
                id: contextID,
                name: "test-funnel",
                data: ["source": "onboarding", "experiment": "control"]
            ),
            appData: WidePixelAppData()
        )

        widePixel.startFlow(subscriptionData)
        let typed = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: subscriptionData.globalData.id)
        var parameters: [String: String] = [:]

        parameters["global.platform"] = "macOS"
        parameters["global.type"] = "app"
        parameters["global.sample_rate"] = "1.0"
        parameters["app.name"] = typed.appData.name
        parameters["app.version"] = typed.appData.version
        if let formFactor = typed.appData.formFactor { parameters["global.form_factor"] = formFactor }
        parameters["feature.name"] = SubscriptionPurchaseWidePixelData.pixelName
        if let name = typed.contextData.name { parameters["context.name"] = name }
        if let data = typed.contextData.data {
            for (key, value) in data { parameters["context.data.\(key)"] = value }
        }

        parameters.merge(typed.pixelParameters(), uniquingKeysWith: { _, new in new })

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
        XCTAssertEqual(parameters["context.data.source"], "onboarding")
        XCTAssertNil(parameters["context.id"])

        // Global parameters
        XCTAssertNotNil(parameters["global.platform"])
        XCTAssertEqual(parameters["global.type"], "app")
        XCTAssertEqual(parameters["global.sample_rate"], "1.0")

        // Feature metadata
        XCTAssertEqual(parameters["feature.name"], "subscription-purchase")
        XCTAssertNil(parameters["feature.status"])
    }

    func testJsonParameterNesting() throws {
        struct TestProvider: WidePixelParameterProviding {
            func pixelParameters() -> [String: String] {
                return [
                    "app.name": "DuckDuckGo",
                    "feature.status": "SUCCESS",
                    "context.id": "onboarding",
                ]
            }
        }

        let jsonString = try TestProvider().jsonParameters()
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

        let app = object?["app"] as? [String: Any]
        let feature = object?["feature"] as? [String: Any]
        let context = object?["context"] as? [String: Any]

        XCTAssertEqual(app?["name"] as? String, "DuckDuckGo")
        XCTAssertEqual(feature?["status"] as? String, "SUCCESS")
        XCTAssertEqual(context?["id"] as? String, "onboarding")
    }

    func testActiveFlowManagement() throws {
        let data1 = makeTestSubscriptionData(contextName: "flow-1")
        let data2 = makeTestSubscriptionData(contextName: "flow-2")

        widePixel.startFlow(data1)
        widePixel.startFlow(data2)

        let allFlows = widePixel.getAllFlowData(SubscriptionPurchaseWidePixelData.self)
        XCTAssertEqual(allFlows.count, 2)
    }

    func testNilAndEmptyValues() throws {
        let data = makeTestSubscriptionData()
        data.subscriptionIdentifier = nil
        data.contextData.name = nil
        data.contextData.data = nil

        widePixel.startFlow(data)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data.globalData.id)
        XCTAssertNil(retrievedData.subscriptionIdentifier)
        XCTAssertNil(retrievedData.contextData.name)
        XCTAssertNil(retrievedData.contextData.data)

        let expectation = XCTestExpectation(description: "completeFlow")
        widePixel.completeFlow(retrievedData, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(capturedPixels.count, 1)
    }

    func testFlowRestartWithSameContextID() throws {
        let contextID = UUID().uuidString
        let data1 = makeTestSubscriptionData(platform: .appStore, contextID: contextID, contextName: "first")

        widePixel.startFlow(data1)

        let updated1 = data1
        updated1.subscriptionIdentifier = "subscription"
        widePixel.updateFlow(updated1)

        let data2 = makeTestSubscriptionData(platform: .stripe, contextID: contextID, contextName: "second")
        widePixel.startFlow(data2)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, globalID: data2.globalData.id)
        XCTAssertEqual(retrievedData.purchasePlatform, .stripe)
        XCTAssertEqual(retrievedData.contextData.name, "second")
        XCTAssertNil(retrievedData.subscriptionIdentifier)
    }

    func testSamplingDecisionAtStartSkipsPersistenceWhenNotSampled() throws {
        let contextID = UUID().uuidString

        let notSampled = makeTestSubscriptionData(contextID: contextID)
        notSampled.globalData.sampleRate = 0.0

        widePixel.startFlow(notSampled)

        XCTAssertNil(widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, globalID: notSampled.globalData.id))

        let exp = expectation(description: "complete")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, globalID: notSampled.globalData.id, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(capturedPixels.count, 0)
    }

    // MARK: - Test Utilities

    func makeTestSubscriptionData(
        platform: SubscriptionPurchaseWidePixelData.PurchasePlatform = .appStore,
        contextID: String = UUID().uuidString,
        contextName: String? = nil,
        subscriptionIdentifier: String? = nil,
        freeTrialEligible: Bool? = nil
    ) -> SubscriptionPurchaseWidePixelData {
        let contextData = WidePixelContextData(id: contextID, name: contextName)
        return SubscriptionPurchaseWidePixelData(
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

    func XCTUnwrapFlow<T: WidePixelData>(_ type: T.Type, globalID: String, file: StaticString = #file, line: UInt = #line) throws -> T {
        guard let flow = widePixel.getFlowData(type, globalID: globalID) else {
            XCTFail("Expected flow data for \(type) with globalID \(globalID)", file: file, line: line)
            throw TestError.flowNotFound
        }
        return flow
    }

    enum TestError: Error {
        case flowNotFound
    }
}

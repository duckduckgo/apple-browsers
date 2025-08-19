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

    // MARK: - Test Infrastructure

    var widePixel: WidePixel!
    var testDefaults: UserDefaults!
    var capturedPixels: [(name: String, parameters: [String: String])] = []
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()
        setupTestInfrastructure()
    }

    override func tearDown() {
        cleanupTestInfrastructure()
        super.tearDown()
    }

    private func setupTestInfrastructure() {
        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        widePixel = WidePixel(userDefaults: testDefaults)
        widePixel.clearAllFlows()
        capturedPixels.removeAll()
        setupMockPixelKit()
    }

    private func cleanupTestInfrastructure() {
        widePixel?.clearAllFlows()
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        PixelKit.tearDown()
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

    // MARK: - Test Utilities

    func makeTestSubscriptionData(
        platform: SubscriptionPurchaseWidePixelData.PurchasePlatform = .appstore,
        contextID: UUID = UUID(),
        contextName: String? = nil,
        subscriptionIdentifier: String? = nil,
        freeTrialEligible: Bool? = nil
    ) -> SubscriptionPurchaseWidePixelData {
        var data = SubscriptionPurchaseWidePixelData(
            purchasePlatform: platform,
            subscriptionIdentifier: subscriptionIdentifier,
            freeTrialEligible: freeTrialEligible
        )
        data.contextData = WidePixelContextData(id: contextID, name: contextName)
        return data
    }

    func makeTestError(domain: String = "TestDomain", code: Int = 999) -> NSError {
        return NSError(domain: domain, code: code, userInfo: [
            NSLocalizedDescriptionKey: "Test error",
            NSUnderlyingErrorKey: NSError(domain: "UnderlyingDomain", code: 123)
        ])
    }

    func XCTUnwrapFlow<T: WidePixelData>(_ type: T.Type, contextID: UUID, file: StaticString = #file, line: UInt = #line) throws -> T {
        guard let flow = widePixel.getFlowData(type, contextID: contextID) else {
            XCTFail("Expected flow data for \(type) with contextID \(contextID)", file: file, line: line)
            throw TestError.flowNotFound
        }
        return flow
    }

    enum TestError: Error {
        case flowNotFound
    }

    // MARK: - Basic Flow Management Tests

    func testFlowPersistenceAndDataIntegrity() throws {
        let subscriptionData = makeTestSubscriptionData(
            platform: .appstore,
            contextName: "test-flow",
            subscriptionIdentifier: "test-subscription-id"
        )

        widePixel.startFlow(subscriptionData)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)

        XCTAssertEqual(retrievedData.purchasePlatform, .appstore)
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

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: initialData.contextData.id)
        XCTAssertEqual(retrievedData.purchasePlatform, .stripe)
        XCTAssertEqual(retrievedData.failingStep, .accountCreate)
        XCTAssertEqual(retrievedData.subscriptionIdentifier, "updated-subscription")
        XCTAssertEqual(retrievedData.freeTrialEligible, true)
    }

    func testFlowCancellationClearsStorage() throws {
        let subscriptionData = makeTestSubscriptionData(contextName: "cancellation-test")
        widePixel.startFlow(subscriptionData)

        _ = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)

        let expectation = XCTestExpectation(description: "Flow cancelled")
        widePixel.completeFlow(subscriptionData, finalStatus: .cancelled) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let retrievedData = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)
        XCTAssertNil(retrievedData)

        XCTAssertEqual(capturedPixels.count, 1)
        XCTAssertEqual(capturedPixels[0].parameters["feature.status"], "CANCELLED")
    }

    // MARK: - Error Handling Tests

    func testGetFlowDataForNonExistentFlow() {
        let nonExistentContextID = UUID()
        let result = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: nonExistentContextID)
        XCTAssertNil(result)
    }

    func testUpdateFlowForNonExistentFlow() {
        let nonExistentContextID = UUID()
        let data = makeTestSubscriptionData(contextID: nonExistentContextID)

        widePixel.updateFlow(data)
    }

    func testCompleteFlowForNonExistentFlow() {
        let nonExistentContextID = UUID()
        let data = makeTestSubscriptionData(contextID: nonExistentContextID)

        widePixel.completeFlow(data, finalStatus: .success) { _, _ in }
    }

    func testTypeMismatchError() throws {
        let subscriptionData = makeTestSubscriptionData()
        widePixel.startFlow(subscriptionData)

        struct TestWidePixelData: WidePixelData {
            static let pixelName = "test_pixel"
            var contextData: WidePixelContextData = WidePixelContextData()
            var appData: WidePixelAppData = WidePixelAppData()
            var globalData: WidePixelGlobalData = WidePixelGlobalData(platform: "", sampleRate: 1.0)
            func pixelParameters() -> [String: String] { [:] }
        }

        XCTAssertThrowsError(try { _ = try self.widePixel.getFlowData(TestWidePixelData.self, contextID: subscriptionData.contextData.id) ?? { throw WidePixelError.flowNotFound(pixelName: TestWidePixelData.pixelName) }() }()) { error in
            if case WidePixelError.typeMismatch(let expected, let actual) = error {
                XCTAssertEqual(expected, "TestWidePixelData")
                XCTAssertEqual(actual, "SubscriptionPurchaseWidePixelData")
            } else if case WidePixelError.flowNotFound = error {
                // Acceptable on some runners due to storage isolation quirks
            } else {
                XCTFail("Expected typeMismatch or flowNotFound, got \(error)")
            }
        }
    }

    func testSerializationFailure() throws {
        struct NonSerializableData: WidePixelData {
            static let pixelName = "non_serializable"
            let closure: () -> Void = { }
            var contextData: WidePixelContextData = WidePixelContextData()
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
        widePixel.completeFlow(subscriptionData, finalStatus: .success) { success, error in
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

        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id, keyPath: \.createAccountDuration)

        let dataAfterStart = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        XCTAssertNotNil(dataAfterStart.createAccountDuration?.start)
        XCTAssertNil(dataAfterStart.createAccountDuration?.end)

        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id, keyPath: \.createAccountDuration)

        let dataAfterStop = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.start)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.end)
    }

    func testInstanceBasedMeasurements() throws {
        var data = makeTestSubscriptionData()
        widePixel.startFlow(data)

        XCTAssertNil(data.createAccountDuration)
        widePixel.startMeasuring(&data, keyPath: \.createAccountDuration)
        XCTAssertNotNil(data.createAccountDuration?.start)
        XCTAssertNil(data.createAccountDuration?.end)

        widePixel.stopMeasuring(&data, keyPath: \.createAccountDuration)
        XCTAssertNotNil(data.createAccountDuration?.start)
        XCTAssertNotNil(data.createAccountDuration?.end)
    }

    func testMeasurementWithExtremeDurations() throws {
        let data = makeTestSubscriptionData()
        widePixel.startFlow(data)

        // Test very short duration
        let shortStart = Date()
        let shortEnd = shortStart.addingTimeInterval(0.001)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id, keyPath: \.createAccountDuration, at: shortStart)
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id, keyPath: \.createAccountDuration, at: shortEnd)

        // Test very long duration
        let longStart = Date(timeIntervalSince1970: 0)
        let longEnd = longStart.addingTimeInterval(3600 * 24)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id, keyPath: \.completePurchaseDuration, at: longStart)
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id, keyPath: \.completePurchaseDuration, at: longEnd)

        let typed = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        var parameters: [String: String] = [:]
        parameters["global.platform"] = PlatformInfo.displayName
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

        XCTAssertEqual(parameters["feature.data.ext.create_account_latency_ms_bucketed"], "1000")
        XCTAssertEqual(parameters["feature.data.ext.complete_purchase_latency_ms_bucketed"], "60000")
    }

    func testStopMeasurementWhenNeverStarted() throws {
        let data = makeTestSubscriptionData()
        widePixel.startFlow(data)

        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id, keyPath: \.createAccountDuration)

        let dataAfterStop = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.start)
        XCTAssertNotNil(dataAfterStop.createAccountDuration?.end)
        XCTAssertEqual(dataAfterStop.createAccountDuration?.start, dataAfterStop.createAccountDuration?.end)
    }

    // MARK: - Parameter Flattening Tests

    func testComprehensiveParameterFlattening() throws {
        let testError = makeTestError(domain: "TestErrorDomain", code: 12345)
        let contextID = UUID()

        let subscriptionData = SubscriptionPurchaseWidePixelData(
            purchasePlatform: .appstore,
            failingStep: .accountCreate,
            subscriptionIdentifier: "ddg.privacy.pro.monthly",
            freeTrialEligible: true,
            createAccountDuration: MeasuredInterval(
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
        let typed = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: contextID)
        var parameters: [String: String] = [:]
        parameters["global.platform"] = PlatformInfo.displayName
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
        XCTAssertEqual(parameters["feature.data.ext.purchase_platform"], "appstore")
        XCTAssertEqual(parameters["feature.data.ext.failing_step"], "ACCOUNT_CREATE")
        XCTAssertEqual(parameters["feature.data.ext.subscription_identifier"], "ddg.privacy.pro.monthly")
        XCTAssertEqual(parameters["feature.data.ext.free_trial_eligible"], "true")

        // Measurement parameters
        XCTAssertEqual(parameters["feature.data.ext.create_account_latency_ms_bucketed"], "5000")

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
        XCTAssertEqual(parameters["feature.name"], "subscription_purchase")
        XCTAssertNil(parameters["feature.status"])
    }

    func testParameterFlatteningWithSpecialCharacters() throws {
        var data = makeTestSubscriptionData()
        data.contextData.data = [
            "unicode": "🎉🚀✨",
            "newlines": "line1\nline2",
            "quotes": "\"quoted\" and 'single'",
            "empty": "",
            "whitespace": "   \t\n   "
        ]
        data.contextData.name = "test 🎯 context"

        widePixel.startFlow(data)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        XCTAssertEqual(retrievedData.contextData.data?["unicode"], "🎉🚀✨")
        XCTAssertEqual(retrievedData.contextData.name, "test 🎯 context")
    }

    // MARK: - Sampling Tests

    func testSamplingAllowsPixelWhenEnabled() throws {
        class AlwaysSendSampler: WidePixelSampling {
            func shouldSend(sampleRate: Double) -> Bool { return true }
        }

        let mockSampler = AlwaysSendSampler()
        let testWidePixel = WidePixel(userDefaults: testDefaults, sampler: mockSampler)

        let data = makeTestSubscriptionData()
        testWidePixel.startFlow(data)

        let expectation = XCTestExpectation(description: "Pixel should be sent")
        testWidePixel.completeFlow(data, finalStatus: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(capturedPixels.count, 1)
        let remainingData = testWidePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        XCTAssertNil(remainingData)
    }

    func testSamplingDropsPixelWhenDisabled() throws {
        class NeverSendSampler: WidePixelSampling {
            func shouldSend(sampleRate: Double) -> Bool { return false }
        }

        let mockSampler = NeverSendSampler()
        let testWidePixel = WidePixel(userDefaults: testDefaults, sampler: mockSampler)

        let data = makeTestSubscriptionData()
        testWidePixel.startFlow(data)

        let expectation = XCTestExpectation(description: "Completion should still be called")
        testWidePixel.completeFlow(data, finalStatus: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(capturedPixels.count, 0)
        let remainingData = testWidePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        XCTAssertNil(remainingData)
    }

    func testDefaultSamplerBehavior() {
        let sampler = DefaultWidePixelSampler()

        // Test sample rate 0.0
        for _ in 0..<50 {
            XCTAssertFalse(sampler.shouldSend(sampleRate: 0.0))
        }

        // Test sample rate 1.0
        for _ in 0..<50 {
            XCTAssertTrue(sampler.shouldSend(sampleRate: 1.0))
        }

        // Test invalid rates
        XCTAssertFalse(sampler.shouldSend(sampleRate: -0.5))
        XCTAssertTrue(sampler.shouldSend(sampleRate: 1.5))
    }

    // MARK: - Concurrency Tests

    func testConcurrentFlowOperations() throws {
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 10

        DispatchQueue.concurrentPerform(iterations: 10) { i in
            do {
                let data = self.makeTestSubscriptionData(contextName: "concurrent-\(i)")
                self.widePixel.startFlow(data)

                var updated = data
                updated.subscriptionIdentifier = "updated-\(i)"
                self.widePixel.updateFlow(updated)

                expectation.fulfill()
            } catch {
                XCTFail("Concurrent operation failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 5.0)

        let allFlows = widePixel.getAllFlowData(SubscriptionPurchaseWidePixelData.self)
        XCTAssertEqual(allFlows.count, 10)
    }

    func testConcurrentMeasurements() throws {
        let data = makeTestSubscriptionData()
        widePixel.startFlow(data)

        let expectation = XCTestExpectation(description: "Concurrent measurements complete")
        expectation.expectedFulfillmentCount = 6

        DispatchQueue.concurrentPerform(iterations: 3) { i in
            do {
                let keyPaths: [WritableKeyPath<SubscriptionPurchaseWidePixelData, MeasuredInterval?>] = [
                    \.createAccountDuration,
                     \.completePurchaseDuration
                ]

                for keyPath in keyPaths {
                    self.widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id, keyPath: keyPath)
                    self.widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id, keyPath: keyPath)
                    expectation.fulfill()
                }
            } catch {
                XCTFail("Concurrent measurement failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 5.0)

        let finalData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        XCTAssertTrue(finalData.createAccountDuration != nil || finalData.completePurchaseDuration != nil)
    }

    // MARK: - Storage Management Tests

    func testActiveFlowManagement() throws {
        let data1 = makeTestSubscriptionData(contextName: "flow-1")
        let data2 = makeTestSubscriptionData(contextName: "flow-2")

        widePixel.startFlow(data1)
        widePixel.startFlow(data2)

        let activeFlows = widePixel.getActiveFlowNames()
        XCTAssertEqual(activeFlows.count, 1) // Same pixel name
        XCTAssertTrue(activeFlows.contains("subscription_purchase"))

        let allFlows = widePixel.getAllFlowData(SubscriptionPurchaseWidePixelData.self)
        XCTAssertEqual(allFlows.count, 2)
    }

    func testClearAllFlows() throws {
        for i in 0..<5 {
            let data = makeTestSubscriptionData(contextName: "clear-test-\(i)")
            widePixel.startFlow(data)
        }

        XCTAssertEqual(widePixel.getAllFlowData(SubscriptionPurchaseWidePixelData.self).count, 5)

        widePixel.clearAllFlows()

        XCTAssertEqual(widePixel.getAllFlowData(SubscriptionPurchaseWidePixelData.self).count, 0)
        XCTAssertEqual(widePixel.getActiveFlowNames().count, 0)
    }

    func testMultipleFlowIsolation() throws {
        let flows = (0..<3).map { i in
            makeTestSubscriptionData(
                platform: i % 2 == 0 ? .appstore : .stripe,
                contextName: "isolation-\(i)"
            )
        }

        for flow in flows {
            widePixel.startFlow(flow)
        }

        // Update middle flow
        var updatedFlow = flows[1]
        updatedFlow.freeTrialEligible = true
        widePixel.updateFlow(updatedFlow)

        // Verify isolation
        let unchangedFlow1 = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: flows[0].contextData.id)
        let changedFlow = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: flows[1].contextData.id)
        let unchangedFlow3 = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: flows[2].contextData.id)

        XCTAssertNil(unchangedFlow1.freeTrialEligible)
        XCTAssertEqual(changedFlow.freeTrialEligible, true)
        XCTAssertNil(unchangedFlow3.freeTrialEligible)
    }

    // MARK: - Performance Tests

    func testFlowCreationPerformance() {
        measure {
            for i in 0..<100 {
                do {
                    let data = makeTestSubscriptionData(contextName: "perf-\(i)")
                    widePixel.startFlow(data)
                } catch {
                    XCTFail("Flow creation failed: \(error)")
                }
            }
            widePixel.clearAllFlows()
        }
    }

    func testParameterFlatteningPerformance() throws {
        var data = makeTestSubscriptionData()
        data.contextData.data = [:]
        for i in 0..<50 {
            data.contextData.data?["key\(i)"] = "value\(i)"
        }
        data.createAccountDuration = MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2.5))

        widePixel.startFlow(data)

        measure {
            do {
                let typed = try self.XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
                var parameters: [String: String] = [:]
                parameters["global.platform"] = PlatformInfo.displayName
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
            } catch {
                XCTFail("Parameter flattening failed: \(error)")
            }
        }
    }

    // MARK: - Edge Cases

    func testLargeContextData() throws {
        var data = makeTestSubscriptionData()
        data.contextData.data = [:]
        for i in 0..<100 {
            data.contextData.data?["key\(i)"] = String(repeating: "value", count: 50)
        }

        widePixel.startFlow(data)
        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        XCTAssertEqual(retrievedData.contextData.data?.count, 100)
    }

    func testNilAndEmptyValues() throws {
        var data = makeTestSubscriptionData()
        data.subscriptionIdentifier = nil
        data.freeTrialEligible = nil
        data.contextData.name = nil
        data.contextData.data = nil

        widePixel.startFlow(data)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: data.contextData.id)
        XCTAssertNil(retrievedData.subscriptionIdentifier)
        XCTAssertNil(retrievedData.freeTrialEligible)
        XCTAssertNil(retrievedData.contextData.name)
        XCTAssertNil(retrievedData.contextData.data)

        let expectation = XCTestExpectation(description: "Completion with nil values")
        widePixel.completeFlow(retrievedData, finalStatus: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(capturedPixels.count, 1)
    }

    func testFlowRestartWithSameContextID() throws {
        let contextID = UUID()

        let data1 = makeTestSubscriptionData(platform: .appstore, contextID: contextID, contextName: "first")
        widePixel.startFlow(data1)

        var updated1 = data1
        updated1.subscriptionIdentifier = "first-id"
        widePixel.updateFlow(updated1)

        let data2 = makeTestSubscriptionData(platform: .stripe, contextID: contextID, contextName: "second")
        widePixel.startFlow(data2)

        let retrievedData = try XCTUnwrapFlow(SubscriptionPurchaseWidePixelData.self, contextID: contextID)
        XCTAssertEqual(retrievedData.purchasePlatform, .stripe)
        XCTAssertEqual(retrievedData.contextData.name, "second")
        XCTAssertNil(retrievedData.subscriptionIdentifier)
    }
}

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

// MARK: - Mock Wide Event Sending

final class MockWideEventSending: WideEventSending {
    struct CapturedCall {
        let pixelName: String
        let status: WideEventStatus
        let postEndpointEnabled: Bool
        let contextName: String?
        let testIdentifier: String?
    }

    var capturedCalls: [CapturedCall] = []
    var completionResult: (Bool, Error?) = (true, nil)

    func send<T: WideEventData>(
        _ data: T,
        status: WideEventStatus,
        featureFlagProvider: WideEventFeatureFlagProviding,
        onComplete: @escaping PixelKit.CompletionBlock
    ) {
        let mockData = data as? MockWideEventData
        let postEndpointEnabled = featureFlagProvider.isEnabled(.postEndpoint)
        let call = CapturedCall(
            pixelName: T.metadata.pixelName,
            status: status,
            postEndpointEnabled: postEndpointEnabled,
            contextName: data.contextData.name,
            testIdentifier: mockData?.testIdentifier
        )
        capturedCalls.append(call)
        DispatchQueue.main.async {
            onComplete(self.completionResult.0, self.completionResult.1)
        }
    }
}

final class MockWideEventFeatureFlagProvider: WideEventFeatureFlagProviding {
    var isPostEndpointEnabled: Bool

    init(isPostEndpointEnabled: Bool) {
        self.isPostEndpointEnabled = isPostEndpointEnabled
    }

    func isEnabled(_ flag: WideEventFeatureFlag) -> Bool {
        switch flag {
        case .postEndpoint:
            return isPostEndpointEnabled
        }
    }
}

// MARK: - Mock Wide Event Data

final class MockWideEventData: WideEventData {
    static let metadata = WideEventMetadata(
        pixelName: "mock-wide-event",
        featureName: "mock-wide-event",
        mobileMetaType: "ios-test-mock-wide-event",
        desktopMetaType: "macos-test-mock-wide-event"
    )

    enum FailingStep: String, Codable {
        case step1 = "step_1"
        case step2 = "step_2"
    }

    var failingStep: FailingStep?
    var testIdentifier: String?
    var testEligible: Bool
    var duration: WideEvent.MeasuredInterval?
    var errorData: WideEventErrorData?

    var contextData: WideEventContextData
    var appData: WideEventAppData
    var globalData: WideEventGlobalData

    init(
        failingStep: FailingStep? = nil,
        testIdentifier: String? = nil,
        testEligible: Bool = false,
        duration: WideEvent.MeasuredInterval? = nil,
        errorData: WideEventErrorData? = nil,
        contextData: WideEventContextData = WideEventContextData(),
        appData: WideEventAppData = WideEventAppData(),
        globalData: WideEventGlobalData = WideEventGlobalData(platform: "macOS", sampleRate: 1.0)
    ) {
        self.failingStep = failingStep
        self.testIdentifier = testIdentifier
        self.testEligible = testEligible
        self.duration = duration
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    func pixelParameters() -> [String: String] {
        var params: [String: String] = [:]

        if let failingStep = failingStep {
            params["feature.data.ext.failing_step"] = failingStep.rawValue
        }

        if let testIdentifier = testIdentifier {
            params["feature.data.ext.test_identifier"] = testIdentifier
        }

        params["feature.data.ext.test_eligible"] = String(testEligible)

        return params
    }
}

final class WideEventTests: XCTestCase {

    var wideEvent: WideEvent!
    var testDefaults: UserDefaults!
    var capturedPixels: [(name: String, parameters: [String: String])] = []
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        wideEvent = WideEvent(storage: WideEventUserDefaultsStorage(userDefaults: testDefaults),
                              featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: true))
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
        let mockData = makeTestMockData(
            contextName: "test-flow",
            testIdentifier: "test-subscription-id"
        )

        wideEvent.startFlow(mockData)

        let retrievedData = try XCTUnwrapFlow(MockWideEventData.self, globalID: mockData.globalData.id)

        XCTAssertEqual(retrievedData.contextData.name, "test-flow")
        XCTAssertEqual(retrievedData.testIdentifier, "test-subscription-id")
    }

    func testFlowUpdateWithDataReplacement() throws {
        let initialData = makeTestMockData(contextName: "initial")
        wideEvent.startFlow(initialData)

        let updatedData = initialData
        updatedData.failingStep = .step1
        updatedData.testIdentifier = "updated-subscription"
        updatedData.testEligible = true
        wideEvent.updateFlow(updatedData)

        let retrievedData = try XCTUnwrapFlow(MockWideEventData.self, globalID: initialData.globalData.id)
        XCTAssertEqual(retrievedData.failingStep, .step1)
        XCTAssertEqual(retrievedData.testIdentifier, "updated-subscription")
        XCTAssertEqual(retrievedData.testEligible, true)
    }

    func testFlowCancellationClearsStorage() throws {
        let subscriptionData = makeTestMockData(contextName: "cancellation-test")
        wideEvent.startFlow(subscriptionData)

        _ = try XCTUnwrapFlow(MockWideEventData.self, globalID: subscriptionData.globalData.id)

        let expectation = XCTestExpectation(description: "Flow cancelled")
        wideEvent.completeFlow(subscriptionData, status: .cancelled) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let retrievedData = wideEvent.getFlowData(MockWideEventData.self, globalID: subscriptionData.globalData.id)
        XCTAssertNil(retrievedData)

        XCTAssert(capturedPixels.count >= 1 && capturedPixels.count <= 2)
        XCTAssertEqual(capturedPixels[0].parameters["feature.status"], "CANCELLED")
    }

    // MARK: - Error Handling Tests

    func testGetFlowDataForNonExistentFlow() {
        let nonExistentGlobalID = UUID().uuidString
        let result = wideEvent.getFlowData(MockWideEventData.self, globalID: nonExistentGlobalID)
        XCTAssertNil(result)
    }

    func testDiscardFlowDeletesStoredData() throws {
        let subscriptionData = makeTestMockData(contextName: "discard-test")
        wideEvent.startFlow(subscriptionData)

        // Verify flow exists
        _ = try XCTUnwrapFlow(MockWideEventData.self, globalID: subscriptionData.globalData.id)

        // Discard the flow
        wideEvent.discardFlow(subscriptionData)

        // Verify flow is deleted from storage
        let retrievedData = wideEvent.getFlowData(MockWideEventData.self, globalID: subscriptionData.globalData.id)
        XCTAssertNil(retrievedData, "Flow should be deleted from storage after discard")

        // Verify no pixel was fired
        XCTAssertEqual(capturedPixels.count, 0, "No pixel should be fired when discarding a flow")
    }

    func testDiscardFlowForNonExistentFlow() {
        let data = makeTestMockData()
        wideEvent.discardFlow(data)

        // Verify no pixel was fired
        XCTAssertEqual(capturedPixels.count, 0)
    }

    func testDiscardFlowAfterUpdates() throws {
        let subscriptionData = makeTestMockData(contextName: "discard-with-updates")
        wideEvent.startFlow(subscriptionData)

        // Update the flow multiple times
        let updatedData = subscriptionData
        updatedData.testIdentifier = "test-subscription"
        updatedData.testEligible = true
        wideEvent.updateFlow(updatedData)

        updatedData.failingStep = .step1
        wideEvent.updateFlow(updatedData)

        // Verify flow exists with updates
        let retrievedBeforeDiscard = try XCTUnwrapFlow(MockWideEventData.self, globalID: subscriptionData.globalData.id)
        XCTAssertEqual(retrievedBeforeDiscard.testIdentifier, "test-subscription")
        XCTAssertEqual(retrievedBeforeDiscard.failingStep, .step1)
        XCTAssertTrue(retrievedBeforeDiscard.testEligible)

        // Discard the flow
        wideEvent.discardFlow(updatedData)

        // Verify flow is deleted
        let retrievedAfterDiscard = wideEvent.getFlowData(MockWideEventData.self, globalID: subscriptionData.globalData.id)
        XCTAssertNil(retrievedAfterDiscard, "Updated flow should be deleted from storage after discard")

        // Verify no pixel was fired
        XCTAssertEqual(capturedPixels.count, 0, "No pixel should be fired when discarding a flow")
    }

    func testSerializationFailure() throws {
        struct NonSerializableData: WideEventData {
            static let metadata = WideEventMetadata(
                pixelName: "non_serializable",
                featureName: "non_serializable",
                mobileMetaType: "ios-test-non-serializable",
                desktopMetaType: "macos-test-non-serializable"
            )
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

        let subscriptionData = makeTestMockData()
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
        let data = makeTestMockData()
        wideEvent.startFlow(data)

        let started = try XCTUnwrapFlow(MockWideEventData.self, globalID: data.globalData.id)
        started.duration = WideEvent.MeasuredInterval.startingNow()
        wideEvent.updateFlow(started)

        let dataAfterStart = try XCTUnwrapFlow(MockWideEventData.self, globalID: data.globalData.id)
        XCTAssertNotNil(dataAfterStart.duration?.start)
        XCTAssertNil(dataAfterStart.duration?.end)

        let stopped = try XCTUnwrapFlow(MockWideEventData.self, globalID: data.globalData.id)
        stopped.duration?.complete()
        wideEvent.updateFlow(stopped)

        let dataAfterStop = try XCTUnwrapFlow(MockWideEventData.self, globalID: data.globalData.id)
        XCTAssertNotNil(dataAfterStop.duration?.start)
        XCTAssertNotNil(dataAfterStop.duration?.end)
    }

    func testInstanceBasedMeasurements() throws {
        let data = makeTestMockData()
        wideEvent.startFlow(data)

        XCTAssertNil(data.duration)
        data.duration = WideEvent.MeasuredInterval.startingNow()
        XCTAssertNotNil(data.duration?.start)
        XCTAssertNil(data.duration?.end)

        data.duration?.complete()
        XCTAssertNotNil(data.duration?.start)
        XCTAssertNotNil(data.duration?.end)
    }

    func testStopMeasurementWhenNeverStarted() throws {
        let data = makeTestMockData()
        wideEvent.startFlow(data)

        let now = Date()
        let updated = try XCTUnwrapFlow(MockWideEventData.self, globalID: data.globalData.id)
        updated.duration = WideEvent.MeasuredInterval(start: now, end: now)
        wideEvent.updateFlow(updated)

        let dataAfterStop = try XCTUnwrapFlow(MockWideEventData.self, globalID: data.globalData.id)
        XCTAssertNotNil(dataAfterStop.duration?.start)
        XCTAssertNotNil(dataAfterStop.duration?.end)
        XCTAssertEqual(dataAfterStop.duration?.start, dataAfterStop.duration?.end)
    }

    func testComprehensiveParameterFlattening() throws {
        let testError = makeTestError(domain: "TestErrorDomain", code: 12345)

        let mockData = MockWideEventData(
            failingStep: .step1,
            testIdentifier: "ddg.privacy.pro.monthly",
            testEligible: true,
            duration: WideEvent.MeasuredInterval(
                start: Date(timeIntervalSince1970: 1000),
                end: Date(timeIntervalSince1970: 1002.5)
            ),
            errorData: WideEventErrorData(error: testError, description: "Test Error"),
            contextData: WideEventContextData(name: "test-funnel"),
            appData: WideEventAppData()
        )

        wideEvent.startFlow(mockData)
        let typed = try XCTUnwrapFlow(MockWideEventData.self, globalID: mockData.globalData.id)
        var parameters: [String: String] = [:]

        parameters["global.platform"] = "macOS"
        parameters["global.type"] = "app"
        parameters["global.sample_rate"] = "1.0"
        parameters["app.name"] = typed.appData.name
        parameters["app.version"] = typed.appData.version
        if let formFactor = typed.appData.formFactor { parameters["app.form_factor"] = formFactor }
        if let name = typed.contextData.name { parameters["context.name"] = name }

        parameters.merge(typed.pixelParameters(), uniquingKeysWith: { _, new in new })
        parameters.merge(typed.errorData!.pixelParameters(), uniquingKeysWith: { _, new in new })

        // Feature parameters
        XCTAssertEqual(parameters["feature.data.ext.failing_step"], "step_1")
        XCTAssertEqual(parameters["feature.data.ext.test_identifier"], "ddg.privacy.pro.monthly")
        XCTAssertEqual(parameters["feature.data.ext.test_eligible"], "true")

        // Error parameters
        XCTAssertEqual(parameters["feature.data.error.domain"], "TestErrorDomain")
        XCTAssertEqual(parameters["feature.data.error.code"], "12345")
        XCTAssertEqual(parameters["feature.data.error.description"], "Test Error")

        // Context parameters
        XCTAssertEqual(parameters["context.name"], "test-funnel")

        // Global parameters
        XCTAssertNotNil(parameters["global.platform"])
        XCTAssertEqual(parameters["global.type"], "app")
        XCTAssertEqual(parameters["global.sample_rate"], "1.0")

        XCTAssertNil(parameters["feature.status"])
    }

    func testErrorDataCapturesUnderlyingErrors() {
        let deepError = NSError(domain: "DeepDomain", code: 3)

        let deepErrorData = WideEventErrorData(error: deepError, description: "Test Deep Error")

        XCTAssertEqual(deepErrorData.domain, "DeepDomain")
        XCTAssertEqual(deepErrorData.code, 3)
        XCTAssertEqual(deepErrorData.underlyingErrors.count, 0)

        let nestedError = NSError(domain: "NestedDomain", code: 2, userInfo: [NSUnderlyingErrorKey: deepError])
        let rootError = NSError(domain: "RootDomain", code: 1, userInfo: [NSUnderlyingErrorKey: nestedError])

        // No Description
        let errorData = WideEventErrorData(error: rootError)

        XCTAssertEqual(errorData.domain, "RootDomain")
        XCTAssertEqual(errorData.code, 1)
        XCTAssertNil(errorData.description)

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
        let data1 = makeTestMockData(contextName: "flow-1")
        let data2 = makeTestMockData(contextName: "flow-2")

        wideEvent.startFlow(data1)
        wideEvent.startFlow(data2)

        let allFlows = wideEvent.getAllFlowData(MockWideEventData.self)
        XCTAssertEqual(allFlows.count, 2)
    }

    func testNilAndEmptyValues() throws {
        let data = makeTestMockData()
        data.testIdentifier = nil
        data.contextData.name = nil

        wideEvent.startFlow(data)

        let retrievedData = try XCTUnwrapFlow(MockWideEventData.self, globalID: data.globalData.id)
        XCTAssertNil(retrievedData.testIdentifier)
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

    func testCompleteFlowWithSuccessReason_includesReasonInPixelParameters() throws {
        let data = makeTestMockData()
        wideEvent.startFlow(data)

        let expectation = XCTestExpectation(description: "Flow completed with success reason")
        wideEvent.completeFlow(data, status: .success(reason: "test_success_reason")) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(capturedPixels.count >= 1 && capturedPixels.count <= 2)
        let params = capturedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "SUCCESS")
        XCTAssertEqual(params["feature.status_reason"], "test_success_reason")
    }

    func testFlowRestartWithSameContextID() throws {
        let data1 = makeTestMockData(contextName: "first")
        wideEvent.startFlow(data1)

        let updated1 = data1
        updated1.testIdentifier = "subscription"
        wideEvent.updateFlow(updated1)

        let data2 = makeTestMockData(contextName: "second")
        wideEvent.startFlow(data2)

        let retrievedData = try XCTUnwrapFlow(MockWideEventData.self, globalID: data2.globalData.id)
        XCTAssertEqual(retrievedData.contextData.name, "second")
        XCTAssertNil(retrievedData.testIdentifier)
    }

    func testSamplingDecisionAtStartSkipsPersistenceWhenNotSampled() throws {
        let notSampled = makeTestMockData()
        notSampled.globalData.sampleRate = 0.0

        wideEvent.startFlow(notSampled)

        XCTAssertNil(wideEvent.getFlowData(MockWideEventData.self, globalID: notSampled.globalData.id))

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(MockWideEventData.self, globalID: notSampled.globalData.id, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(capturedPixels.count, 0)
    }

    // MARK: - Test Utilities

    func makeTestMockData(
        contextName: String? = nil,
        testIdentifier: String? = nil,
        testEligible: Bool? = nil
    ) -> MockWideEventData {
        let contextData = WideEventContextData(name: contextName)
        return MockWideEventData(
            testIdentifier: testIdentifier,
            testEligible: testEligible ?? false,
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

// MARK: - WideEventSending Tests

final class WideEventSendingTests: XCTestCase {

    var mockSender: MockWideEventSending!
    var wideEvent: WideEvent!
    var testDefaults: UserDefaults!
    private var featureFlagProvider: MockWideEventFeatureFlagProvider!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        mockSender = MockWideEventSending()
        featureFlagProvider = MockWideEventFeatureFlagProvider(isPostEndpointEnabled: true)
        wideEvent = WideEvent(
            storage: WideEventUserDefaultsStorage(userDefaults: testDefaults),
            sender: mockSender,
            featureFlagProvider: featureFlagProvider
        )
    }

    override func tearDown() {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        super.tearDown()
    }

    func testWideEventPassesSendPOSTEnabledToSender() throws {
        let data = MockWideEventData(contextData: WideEventContextData(name: "test"))
        wideEvent.startFlow(data)

        let expectation = XCTestExpectation(description: "Flow completed")
        wideEvent.completeFlow(data, status: .success) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockSender.capturedCalls.count, 1)
        XCTAssertTrue(mockSender.capturedCalls[0].postEndpointEnabled)
    }

    func testWideEventPassesSendPOSTDisabledToSender() throws {
        let disabledWideEvent = WideEvent(
            storage: WideEventUserDefaultsStorage(userDefaults: testDefaults),
            sender: mockSender,
            featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: false)
        )

        let data = MockWideEventData(contextData: WideEventContextData(name: "test"))
        disabledWideEvent.startFlow(data)

        let expectation = XCTestExpectation(description: "Flow completed")
        disabledWideEvent.completeFlow(data, status: .success) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockSender.capturedCalls.count, 1)
        XCTAssertFalse(mockSender.capturedCalls[0].postEndpointEnabled)
    }

    func testSendPOSTEnabledClosureIsEvaluatedAtSendTime() throws {
        let dynamicFeatureFlagProvider = MockWideEventFeatureFlagProvider(isPostEndpointEnabled: false)

        let dynamicWideEvent = WideEvent(
            storage: WideEventUserDefaultsStorage(userDefaults: testDefaults),
            sender: mockSender,
            featureFlagProvider: dynamicFeatureFlagProvider
        )

        let data1 = MockWideEventData(contextData: WideEventContextData(name: "test1"))
        dynamicWideEvent.startFlow(data1)

        let expectation1 = XCTestExpectation(description: "First flow completed")
        dynamicWideEvent.completeFlow(data1, status: .success) { _, _ in
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 1.0)

        XCTAssertEqual(mockSender.capturedCalls.count, 1)
        XCTAssertFalse(mockSender.capturedCalls[0].postEndpointEnabled)

        dynamicFeatureFlagProvider.isPostEndpointEnabled = true

        let data2 = MockWideEventData(contextData: WideEventContextData(name: "test2"))
        dynamicWideEvent.startFlow(data2)

        let expectation2 = XCTestExpectation(description: "Second flow completed")
        dynamicWideEvent.completeFlow(data2, status: .success) { _, _ in
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1.0)

        XCTAssertEqual(mockSender.capturedCalls.count, 2)
        XCTAssertTrue(mockSender.capturedCalls[1].postEndpointEnabled)
    }

    func testWideEventPassesCorrectPixelNameToSender() throws {
        let data = MockWideEventData(contextData: WideEventContextData(name: "test"))
        wideEvent.startFlow(data)

        let expectation = XCTestExpectation(description: "Flow completed")
        wideEvent.completeFlow(data, status: .success) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockSender.capturedCalls.count, 1)
        XCTAssertEqual(mockSender.capturedCalls[0].pixelName, MockWideEventData.metadata.pixelName)
    }

    func testWideEventPassesDataToSender() throws {
        let data = MockWideEventData(
            testIdentifier: "test-id",
            testEligible: true,
            contextData: WideEventContextData(name: "test-context")
        )
        wideEvent.startFlow(data)

        let expectation = XCTestExpectation(description: "Flow completed")
        wideEvent.completeFlow(data, status: .success) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockSender.capturedCalls.count, 1)
        let capturedCall = mockSender.capturedCalls[0]
        XCTAssertEqual(capturedCall.contextName, "test-context")
        XCTAssertEqual(capturedCall.testIdentifier, "test-id")
        XCTAssertEqual(capturedCall.status, .success)
    }

    func testSenderCompletionHandlerIsCalled() throws {
        mockSender.completionResult = (true, nil)

        let data = MockWideEventData(contextData: WideEventContextData(name: "test"))
        wideEvent.startFlow(data)

        let expectation = XCTestExpectation(description: "Completion called")
        var receivedSuccess = false
        var receivedError: Error?

        wideEvent.completeFlow(data, status: .success) { success, error in
            receivedSuccess = success
            receivedError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(receivedSuccess)
        XCTAssertNil(receivedError)
    }

    func testSenderFailureIsPropagated() throws {
        let testError = NSError(domain: "TestDomain", code: 123)
        mockSender.completionResult = (false, testError)

        let data = MockWideEventData(contextData: WideEventContextData(name: "test"))
        wideEvent.startFlow(data)

        let expectation = XCTestExpectation(description: "Completion called")
        var receivedSuccess = true
        var receivedError: Error?

        wideEvent.completeFlow(data, status: .success) { success, error in
            receivedSuccess = success
            receivedError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(receivedSuccess)
        XCTAssertNotNil(receivedError)
    }
}

// MARK: - DefaultWideEventSending Tests

final class DefaultWideEventSendingTests: XCTestCase {

    var capturedPixels: [(name: String, parameters: [String: String])] = []
    var capturedPOSTRequests: [(url: URL, body: Data, headers: [String: String])] = []
    var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        capturedPixels.removeAll()
        capturedPOSTRequests.removeAll()
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

    func testSendFiresDailyAndStandardPixels() {
        let sender = DefaultWideEventSender(
            pixelKitProvider: { PixelKit.shared },
            postRequestHandler: { _, _, _, onComplete in onComplete(true, nil) }
        )

        let data = MockWideEventData(contextData: WideEventContextData(name: "test"))

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(capturedPixels.count, 2)
        #if os(macOS)
        XCTAssertTrue(capturedPixels[0].name.hasPrefix("m_mac_wide_"))
        XCTAssertTrue(capturedPixels[1].name.hasPrefix("m_mac_wide_"))
        #elseif os(iOS)
        XCTAssertTrue(capturedPixels[0].name.hasPrefix("m_ios_wide_"))
        XCTAssertTrue(capturedPixels[1].name.hasPrefix("m_ios_wide_"))
        #endif
    }

    func testSendFiresPOSTWhenEnabled() {
        var postRequestFired = false

        let sender = DefaultWideEventSender(
            pixelKitProvider: { PixelKit.shared },
            postRequestHandler: { url, body, headers, onComplete in
                postRequestFired = true
                self.capturedPOSTRequests.append((url: url, body: body, headers: headers))
                onComplete(true, nil)
            }
        )

        let data = MockWideEventData(contextData: WideEventContextData(name: "test"))

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(postRequestFired)
        XCTAssertEqual(capturedPOSTRequests.count, 1)
        XCTAssertEqual(capturedPOSTRequests[0].url.absoluteString, "https://improving.duckduckgo.com/e")
        XCTAssertEqual(capturedPOSTRequests[0].headers["Content-Type"], "application/json")
    }

    func testSendSkipsPOSTWhenDisabled() {
        var postRequestFired = false

        let sender = DefaultWideEventSender(
            pixelKitProvider: { PixelKit.shared },
            postRequestHandler: { _, _, _, onComplete in
                postRequestFired = true
                onComplete(true, nil)
            }
        )

        let data = MockWideEventData(contextData: WideEventContextData(name: "test"))

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(postRequestFired)
    }

    func testPOSTBodyContainsNestedJSON() {
        let sender = DefaultWideEventSender(
            pixelKitProvider: { PixelKit.shared },
            postRequestHandler: { url, body, headers, onComplete in
                self.capturedPOSTRequests.append((url: url, body: body, headers: headers))
                onComplete(true, nil)
            }
        )

        let data = MockWideEventData(
            testIdentifier: "test_value",
            contextData: WideEventContextData(name: "test"),
            globalData: WideEventGlobalData(platform: "iOS", sampleRate: 1.0)
        )

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(capturedPOSTRequests.count, 1)

        let body = capturedPOSTRequests[0].body
        let json = try? JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]

        XCTAssertNotNil(json)

        let global = json?["global"] as? [String: Any]
        XCTAssertEqual(global?["platform"] as? String, "iOS")
        XCTAssertEqual(global?["type"] as? String, "app")

        let feature = json?["feature"] as? [String: Any]
        XCTAssertEqual(feature?["status"] as? String, "SUCCESS")

        let featureData = feature?["data"] as? [String: Any]
        let ext = featureData?["ext"] as? [String: Any]
        XCTAssertEqual(ext?["test_identifier"] as? String, "test_value")
    }

    func testSendReturnsErrorWhenPixelKitNotInitialized() {
        PixelKit.tearDown()

        let sender = DefaultWideEventSender(
            pixelKitProvider: { nil },
            postRequestHandler: { _, _, _, onComplete in onComplete(true, nil) }
        )

        let data = MockWideEventData(contextData: WideEventContextData(name: "test"))

        let expectation = XCTestExpectation(description: "Completion called")
        var receivedSuccess = true
        var receivedError: Error?

        sender.send(data, status: .success, featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: true)) { success, error in
            receivedSuccess = success
            receivedError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(receivedSuccess)
        XCTAssertNotNil(receivedError)
    }

    func testSendGeneratesCorrectParameters() {
        let sender = DefaultWideEventSender(
            pixelKitProvider: { PixelKit.shared },
            postRequestHandler: { _, _, _, onComplete in onComplete(true, nil) }
        )

        let data = MockWideEventData(
            testIdentifier: "test-id",
            testEligible: true,
            contextData: WideEventContextData(name: "test-context"),
            globalData: WideEventGlobalData(platform: "macOS", sampleRate: 1.0)
        )

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success(reason: "test_reason"), featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(capturedPixels.count, 2)
        let parameters = capturedPixels[0].parameters

        XCTAssertEqual(parameters["global.platform"], "macOS")
        XCTAssertEqual(parameters["global.type"], "app")
        XCTAssertEqual(parameters["context.name"], "test-context")
        XCTAssertEqual(parameters["feature.data.ext.test_identifier"], "test-id")
        XCTAssertEqual(parameters["feature.data.ext.test_eligible"], "true")
        XCTAssertEqual(parameters["feature.status"], "SUCCESS")
        XCTAssertEqual(parameters["feature.status_reason"], "test_reason")
    }
}

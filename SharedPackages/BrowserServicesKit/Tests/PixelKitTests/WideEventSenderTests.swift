//
//  WideEventSenderTests.swift
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

final class WideEventSenderTests: XCTestCase {

    var capturedPixels: [(name: String, parameters: [String: String])] = []
    var capturedPOSTRequests: [(url: URL, body: Data, headers: [String: String])] = []
    var testDefaults: UserDefaults!

    private var testSuiteName: String!
    private var mockPostRequestHandler: DefaultWideEventSender.POSTRequestHandler!
    private var postRequestSuccess: Bool = true
    private var postRequestError: Error?

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        capturedPixels.removeAll()
        capturedPOSTRequests.removeAll()
        postRequestSuccess = true
        postRequestError = nil

        mockPostRequestHandler = { [weak self] url, body, headers, onComplete in
            self?.capturedPOSTRequests.append((url: url, body: body, headers: headers))
            onComplete(self?.postRequestSuccess ?? true, self?.postRequestError)
        }

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
            appVersion: "1.0.0",
            source: "test-suite",
            defaultHeaders: [:],
            dateGenerator: Date.init,
            defaults: testDefaults,
            fireRequest: mockFireRequest
        )
    }

    private func makeSender(pixelKitProvider: (() -> PixelKit?)? = nil, storage: WideEventStoring? = nil) -> DefaultWideEventSender {
        return DefaultWideEventSender(
            pixelKitProvider: pixelKitProvider ?? { PixelKit.shared },
            postRequestHandler: mockPostRequestHandler,
            storage: storage ?? WideEventUserDefaultsStorage(userDefaults: testDefaults)
        )
    }

    private func makeFeatureFlagProvider(isPostEndpointEnabled: Bool) -> WideEventFeatureFlagProviding {
        return MockWideEventFeatureFlagProvider(isPostEndpointEnabled: isPostEndpointEnabled)
    }

    private func makeTestData(
        contextName: String? = "test-context",
        testIdentifier: String? = nil,
        testEligible: Bool = false,
        platform: String = "macOS",
        sampleRate: Float = 1.0,
        errorData: WideEventErrorData? = nil
    ) -> SenderTestWideEventData {
        return SenderTestWideEventData(
            testIdentifier: testIdentifier,
            testEligible: testEligible,
            errorData: errorData,
            contextData: WideEventContextData(name: contextName),
            appData: WideEventAppData(name: "TestApp", version: "1.0.0", formFactor: "phone"),
            globalData: WideEventGlobalData(platform: platform, sampleRate: sampleRate)
        )
    }

    // MARK: - Initialization Tests

    func testInitializationWithCustomPixelKitProvider() {
        var providerCalled = false
        let sender = DefaultWideEventSender(pixelKitProvider: {
            providerCalled = true
            return PixelKit.shared
        })

        let data = makeTestData()
        let expectation = XCTestExpectation(description: "Send completed")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(providerCalled)
    }

    func testInitializationWithCustomPOSTRequestHandler() {
        var handlerCalled = false
        let sender = DefaultWideEventSender(
            pixelKitProvider: { PixelKit.shared },
            postRequestHandler: { _, _, _, onComplete in
                handlerCalled = true
                onComplete(true, nil)
            }
        )

        let data = makeTestData()
        let expectation = XCTestExpectation(description: "Send completed")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(handlerCalled)
    }

    // MARK: - Pixel Firing Tests

    func testSendFiresBothDailyAndStandardPixels() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPixels.count, 2)
    }

    func testSendGeneratesCorrectPlatformPrefixedPixelName() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPixels.count, 2)
        #if os(macOS)
        XCTAssertTrue(capturedPixels[0].name.hasPrefix("m_mac_wide_"))
        XCTAssertTrue(capturedPixels[0].name.contains(SenderTestWideEventData.metadata.pixelName))
        #elseif os(iOS)
        XCTAssertTrue(capturedPixels[0].name.hasPrefix("m_ios_wide_"))
        XCTAssertTrue(capturedPixels[0].name.contains(SenderTestWideEventData.metadata.pixelName))
        #endif
    }

    func testSendCallsCompletionWithSuccessWhenPixelsFired() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Completion called")
        var receivedSuccess = false
        var receivedError: Error?

        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { success, error in
            receivedSuccess = success
            receivedError = error
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(receivedSuccess)
        XCTAssertNil(receivedError)
    }

    func testSendReturnsErrorWhenPixelKitNotInitialized() {
        PixelKit.tearDown()
        let sender = DefaultWideEventSender(
            pixelKitProvider: { nil },
            postRequestHandler: mockPostRequestHandler
        )

        let data = makeTestData()
        let expectation = XCTestExpectation(description: "Completion called")
        var receivedSuccess = true
        var receivedError: Error?

        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { success, error in
            receivedSuccess = success
            receivedError = error
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertFalse(receivedSuccess)
        XCTAssertNotNil(receivedError)
        if let error = receivedError as? WideEventError {
            if case .invalidFlowState = error {
            } else {
                XCTFail("Expected invalidFlowState error")
            }
        }
    }

    // MARK: - Parameter Generation Tests

    func testSendIncludesGlobalParameters() {
        let sender = makeSender()
        let data = makeTestData(platform: "testPlatform", sampleRate: 0.5)

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["global.platform"], "testPlatform")
        XCTAssertEqual(parameters["global.type"], "app")
        XCTAssertEqual(parameters["global.sample_rate"], "0.5")
    }

    func testSendIncludesAppParameters() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["app.name"], "TestApp")
        XCTAssertEqual(parameters["app.version"], "1.0.0")
        XCTAssertEqual(parameters["app.form_factor"], "phone")
    }

    func testSendIncludesContextParameters() {
        let sender = makeSender()
        let data = makeTestData(contextName: "my-test-context")

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["context.name"], "my-test-context")
    }

    func testSendIncludesFeatureName() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["feature.name"], SenderTestWideEventData.metadata.featureName)
    }

    func testSendIncludesFeatureSpecificParameters() {
        let sender = makeSender()
        let data = makeTestData(testIdentifier: "test-id-123", testEligible: true)

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["feature.data.ext.test_identifier"], "test-id-123")
        XCTAssertEqual(parameters["feature.data.ext.test_eligible"], "true")
    }

    func testSendIncludesErrorDataWhenPresent() {
        let sender = makeSender()
        let error = NSError(domain: "TestErrorDomain", code: 42)
        let errorData = WideEventErrorData(error: error, description: "Test error description")
        let data = makeTestData(errorData: errorData)

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .failure, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["feature.data.error.domain"], "TestErrorDomain")
        XCTAssertEqual(parameters["feature.data.error.code"], "42")
        XCTAssertEqual(parameters["feature.data.error.description"], "Test error description")
    }

    func testSendIncludesUnderlyingErrorsWhenPresent() {
        let sender = makeSender()
        let innerError = NSError(domain: "InnerDomain", code: 100)
        let outerError = NSError(domain: "OuterDomain", code: 200, userInfo: [NSUnderlyingErrorKey: innerError])
        let errorData = WideEventErrorData(error: outerError)
        let data = makeTestData(errorData: errorData)

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .failure, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["feature.data.error.domain"], "OuterDomain")
        XCTAssertEqual(parameters["feature.data.error.code"], "200")
        XCTAssertEqual(parameters["feature.data.error.underlying_domain"], "InnerDomain")
        XCTAssertEqual(parameters["feature.data.error.underlying_code"], "100")
    }

    // MARK: - Status Tests

    func testSendIncludesSuccessStatus() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["feature.status"], "SUCCESS")
        XCTAssertNil(parameters["feature.data.ext.status_reason"])
    }

    func testSendIncludesSuccessStatusWithReason() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success(reason: "completed_successfully"), featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["feature.status"], "SUCCESS")
        XCTAssertEqual(parameters["feature.data.ext.status_reason"], "completed_successfully")
    }

    func testSendIncludesFailureStatus() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .failure, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["feature.status"], "FAILURE")
        XCTAssertNil(parameters["feature.data.ext.status_reason"])
    }

    func testSendIncludesCancelledStatus() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .cancelled, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["feature.status"], "CANCELLED")
        XCTAssertNil(parameters["feature.data.ext.status_reason"])
    }

    func testSendIncludesUnknownStatusWithReason() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .unknown(reason: "unexpected_state"), featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["feature.status"], "UNKNOWN")
        XCTAssertEqual(parameters["feature.data.ext.status_reason"], "unexpected_state")
    }

    // MARK: - POST Request Tests

    func testSendFiresPOSTRequestWhenEnabled() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPOSTRequests.count, 1)
    }

    func testSendSkipsPOSTRequestWhenDisabled() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPOSTRequests.count, 0)
    }

    func testSendPOSTRequestUsesCorrectEndpoint() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPOSTRequests.count, 1)
        XCTAssertEqual(capturedPOSTRequests[0].url.absoluteString, "https://improving.duckduckgo.com/e")
    }

    func testSendPOSTRequestIncludesJSONContentTypeHeader() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPOSTRequests.count, 1)
        XCTAssertEqual(capturedPOSTRequests[0].headers["Content-Type"], "application/json")
    }

    func testSendPOSTRequestBodyIsValidJSON() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPOSTRequests.count, 1)
        let body = capturedPOSTRequests[0].body
        let json = try? JSONSerialization.jsonObject(with: body, options: [])
        XCTAssertNotNil(json)
    }

    func testSendPOSTRequestBodyContainsNestedStructure() {
        let sender = makeSender()
        let data = makeTestData(
            contextName: "nested-test",
            testIdentifier: "nested-id",
            platform: "iOS"
        )

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPOSTRequests.count, 1)
        let body = capturedPOSTRequests[0].body
        let json = try? JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
        XCTAssertNotNil(json)

        let global = json?["global"] as? [String: Any]
        XCTAssertNotNil(global)
        XCTAssertEqual(global?["platform"] as? String, "iOS")
        XCTAssertEqual(global?["type"] as? String, "app")

        let context = json?["context"] as? [String: Any]
        XCTAssertNotNil(context)
        XCTAssertEqual(context?["name"] as? String, "nested-test")

        let feature = json?["feature"] as? [String: Any]
        XCTAssertNotNil(feature)
        XCTAssertEqual(feature?["name"] as? String, SenderTestWideEventData.metadata.featureName)
        XCTAssertEqual(feature?["status"] as? String, "SUCCESS")

        let featureData = feature?["data"] as? [String: Any]
        let ext = featureData?["ext"] as? [String: Any]
        XCTAssertEqual(ext?["test_identifier"] as? String, "nested-id")
    }

    func testSendPOSTRequestPreservesNumericTypesInJSON() {
        let sender = makeSender()
        let data = makeTestData(sampleRate: 0.75)

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let body = capturedPOSTRequests[0].body
        let json = try? JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
        let global = json?["global"] as? [String: Any]
        let sampleRate = global?["sample_rate"]

        XCTAssertTrue(sampleRate is Float || sampleRate is Double || sampleRate is NSNumber)
    }

    func testSendWithNilContextName() {
        let sender = makeSender()
        let data = makeTestData(contextName: nil)

        let expectation = XCTestExpectation(description: "Send completed")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { success, _ in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertNil(parameters["context.name"])
    }

    func testPOSTRequestHandlerCalledWithCorrectParameters() {
        var capturedURL: URL?
        var capturedBody: Data?
        var capturedHeaders: [String: String]?

        let sender = DefaultWideEventSender(
            pixelKitProvider: { PixelKit.shared },
            postRequestHandler: { url, body, headers, onComplete in
                capturedURL = url
                capturedBody = body
                capturedHeaders = headers
                onComplete(true, nil)
            }
        )

        let data = makeTestData()
        let expectation = XCTestExpectation(description: "Send completed")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(capturedURL)
        XCTAssertNotNil(capturedBody)
        XCTAssertNotNil(capturedHeaders)
        XCTAssertEqual(capturedURL?.absoluteString, "https://improving.duckduckgo.com/e")
        XCTAssertEqual(capturedHeaders?["Content-Type"], "application/json")
    }

    func testPOSTRequestFailureDoesNotAffectPixelCompletion() {
        postRequestSuccess = false
        postRequestError = NSError(domain: "TestError", code: 500)

        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Send completed")
        var receivedSuccess = false

        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { success, _ in
            receivedSuccess = success
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(receivedSuccess)
        XCTAssertEqual(capturedPixels.count, 2)
        XCTAssertEqual(capturedPOSTRequests.count, 1)
    }

    // MARK: - First Daily Occurrence Tests

    func testSendIncludesFirstDailyOccurrenceOnFirstFire() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["global.is_first_daily_occurrence"], "true")
    }

    func testSendOmitsFirstDailyOccurrenceOnSubsequentFireSameDay() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation1 = XCTestExpectation(description: "First pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation1.fulfill()
        }

        wait(for: [expectation1], timeout: 5.0)

        capturedPixels.removeAll()

        let expectation2 = XCTestExpectation(description: "Second pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation2.fulfill()
        }

        wait(for: [expectation2], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertNil(parameters["global.is_first_daily_occurrence"])
    }

    func testSendIncludesFirstDailyOccurrenceWhenLastSentYesterday() {
        let mockStorage = MockWideEventStorage()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        mockStorage.timestamps[SenderTestWideEventData.metadata.type] = yesterday

        let sender = makeSender(storage: mockStorage)
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let parameters = capturedPixels[0].parameters
        XCTAssertEqual(parameters["global.is_first_daily_occurrence"], "true")
    }

    func testSendRecordsTimestampAfterFiring() {
        let mockStorage = MockWideEventStorage()
        let sender = makeSender(storage: mockStorage)
        let data = makeTestData()

        XCTAssertNil(mockStorage.timestamps[SenderTestWideEventData.metadata.type])

        let expectation = XCTestExpectation(description: "Pixels fired")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: false)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(mockStorage.timestamps[SenderTestWideEventData.metadata.type])
    }

    func testPOSTRequestIncludesFirstDailyOccurrenceAsBooleanWhenTrue() {
        let sender = makeSender()
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPOSTRequests.count, 1)
        let body = capturedPOSTRequests[0].body
        let json = try? JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
        let global = json?["global"] as? [String: Any]
        XCTAssertEqual(global?["is_first_daily_occurrence"] as? Bool, true)
    }

    func testPOSTRequestOmitsFirstDailyOccurrenceWhenNotFirstToday() {
        let mockStorage = MockWideEventStorage()
        mockStorage.timestamps[SenderTestWideEventData.metadata.type] = Date()

        let sender = makeSender(storage: mockStorage)
        let data = makeTestData()

        let expectation = XCTestExpectation(description: "Request sent")
        sender.send(data, status: .success, featureFlagProvider: makeFeatureFlagProvider(isPostEndpointEnabled: true)) { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(capturedPOSTRequests.count, 1)
        let body = capturedPOSTRequests[0].body
        let json = try? JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
        let global = json?["global"] as? [String: Any]
        XCTAssertNil(global?["is_first_daily_occurrence"])
    }
}

// MARK: - Test Wide Event Data Types

final class SenderTestWideEventData: WideEventData {
    static let metadata = WideEventMetadata(
        pixelName: "sender_test_event",
        featureName: "sender_test_event",
        mobileMetaType: "ios-sender-test-event",
        desktopMetaType: "macos-sender-test-event"
    )

    var testIdentifier: String?
    var testEligible: Bool
    var errorData: WideEventErrorData?
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var globalData: WideEventGlobalData

    init(
        testIdentifier: String? = nil,
        testEligible: Bool = false,
        errorData: WideEventErrorData? = nil,
        contextData: WideEventContextData = WideEventContextData(),
        appData: WideEventAppData = WideEventAppData(),
        globalData: WideEventGlobalData = WideEventGlobalData(platform: "macOS", sampleRate: 1.0)
    ) {
        self.testIdentifier = testIdentifier
        self.testEligible = testEligible
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    func pixelParameters() -> [String: String] {
        var params: [String: String] = [:]

        if let testIdentifier = testIdentifier {
            params["feature.data.ext.test_identifier"] = testIdentifier
        }

        params["feature.data.ext.test_eligible"] = String(testEligible)
        return params
    }

    func jsonParameters() -> [String: Encodable] {
        var params: [String: Encodable] = [:]

        if let testIdentifier = testIdentifier {
            params["feature.data.ext.test_identifier"] = testIdentifier
        }

        params["feature.data.ext.test_eligible"] = testEligible
        return params
    }
}

// MARK: - Mock Wide Event Storage

final class MockWideEventStorage: WideEventStoring {
    var timestamps: [String: Date] = [:]
    var savedData: [String: Data] = [:]

    func save<T: WideEventData>(_ data: T) throws {
        let encoded = try JSONEncoder().encode(data)
        savedData["\(T.metadata.pixelName).\(data.globalData.id)"] = encoded
    }

    func load<T: WideEventData>(globalID: String) throws -> T {
        let key = "\(T.metadata.pixelName).\(globalID)"
        guard let data = savedData[key] else {
            throw WideEventError.flowNotFound(pixelName: T.metadata.pixelName)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func update<T: WideEventData>(_ data: T) throws {
        try save(data)
    }

    func delete<T: WideEventData>(_ data: T) {
        savedData.removeValue(forKey: "\(T.metadata.pixelName).\(data.globalData.id)")
    }

    func allWideEvents<T: WideEventData>(for type: T.Type) -> [T] {
        return []
    }

    func lastSentTimestamp(for eventType: String) -> Date? {
        return timestamps[eventType]
    }

    func recordSentTimestamp(for eventType: String, date: Date) {
        timestamps[eventType] = date
    }
}

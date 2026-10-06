//
//  WideEventStoringTests.swift
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
import PixelKit
@testable import WideEvent
import Foundation

final class WideEventStoringTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var testSuiteName: String!
    private var storage: WideEventUserDefaultsStorage!

    override func setUp() {
        super.setUp()
        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        storage = WideEventUserDefaultsStorage(userDefaults: testDefaults)
    }

    override func tearDown() {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        storage = nil
        super.tearDown()
    }

    func testWhenExistingFlowIsLoadedThenItCompletesWithoutResettingDailyOccurrence() throws {
        XCTAssertEqual(WideEventUserDefaultsStorage.suiteName, "com.duckduckgo.wide-pixel.storage")

        let globalID = "661A7558-48CC-49B0-B70C-C14F258E7D11"
        let flowKey = "storage_test_event.\(globalID)"
#if os(iOS)
        let eventType = "ios-storage-test-event"
#else
        let eventType = "macos-storage-test-event"
#endif
        let timestampKey = "last_sent.\(eventType)"
        let lastSent = Date()
        // Seed the JSON and keys written before extraction, independently of the current encoder.
        let json = """
        {
            "globalData": {
                "id": "661A7558-48CC-49B0-B70C-C14F258E7D11",
                "platform": "macOS",
                "type": "app",
                "sampleRate": 1
            },
            "appData": {"name": "DuckDuckGo", "version": "1.0.0", "internalUser": true},
            "contextData": {"name": "existing-flow"}
        }
        """
        testDefaults.set(Data(json.utf8), forKey: flowKey)
        testDefaults.set(lastSent, forKey: timestampKey)

        let data: StorageTestWideEventData = try storage.load(globalID: globalID)
        XCTAssertEqual(data.globalData.id, globalID)
        XCTAssertEqual(data.contextData.name, "existing-flow")
        XCTAssertEqual(data.appData.internalUser, true)
        XCTAssertEqual(storage.allWideEvents(for: StorageTestWideEventData.self).count, 1)
        XCTAssertEqual(storage.lastSentTimestamp(for: eventType), lastSent)

        var capturedParameters: [[String: String]] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                defaultHeaders: [:],
                                defaults: testDefaults) { _, _, parameters, _, _, onComplete in
            capturedParameters.append(parameters)
            onComplete(true, nil)
        }
        var postBody: Data?
        let sender = DefaultWideEventSender(pixelKitProvider: { pixelKit }, postRequestHandler: { _, body, _, onComplete in
            postBody = body
            onComplete(true, nil)
        }, storage: storage)
        let wideEvent = WideEvent(storage: storage,
                                  sender: sender,
                                  failureEventMapping: nil,
                                  featureFlagProvider: MockWideEventFeatureFlagProvider())
        let completion = expectation(description: "Existing flow completes")

        wideEvent.completeFlow(data, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            completion.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertNil(testDefaults.data(forKey: flowKey))
        XCTAssertTrue(storage.allWideEvents(for: StorageTestWideEventData.self).isEmpty)
        XCTAssertEqual(capturedParameters.count, 2)
        for parameters in capturedParameters {
            XCTAssertNil(parameters["global.is_first_daily_occurrence"])
            XCTAssertEqual(parameters["context.name"], "existing-flow")
            XCTAssertEqual(parameters["feature.status"], "SUCCESS")
        }
        let body = try XCTUnwrap(postBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let global = try XCTUnwrap(payload["global"] as? [String: Any])
        XCTAssertNil(global["is_first_daily_occurrence"])
        let recordedDate = try XCTUnwrap(testDefaults.object(forKey: timestampKey) as? Date)
        XCTAssertGreaterThanOrEqual(recordedDate, lastSent)
    }

    // MARK: - lastSentTimestamp Tests

    func testLastSentTimestampReturnsNilWhenNeverRecorded() {
        let timestamp = storage.lastSentTimestamp(for: "nonexistent_event")
        XCTAssertNil(timestamp)
    }

    func testLastSentTimestampReturnsRecordedDate() {
        let eventType = "test_event"
        let recordedDate = Date(timeIntervalSince1970: 1000000)

        storage.recordSentTimestamp(for: eventType, date: recordedDate)
        let retrievedDate = storage.lastSentTimestamp(for: eventType)

        XCTAssertNotNil(retrievedDate)
        XCTAssertEqual(retrievedDate!.timeIntervalSince1970, recordedDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testRecordSentTimestampOverwritesPreviousValue() {
        let eventType = "test_event"
        let firstDate = Date(timeIntervalSince1970: 1000000)
        let secondDate = Date(timeIntervalSince1970: 2000000)

        storage.recordSentTimestamp(for: eventType, date: firstDate)
        storage.recordSentTimestamp(for: eventType, date: secondDate)

        let retrievedDate = storage.lastSentTimestamp(for: eventType)

        XCTAssertNotNil(retrievedDate)
        XCTAssertEqual(retrievedDate!.timeIntervalSince1970, secondDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testTimestampsAreStoredPerEventType() {
        let eventType1 = "event_one"
        let eventType2 = "event_two"
        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        storage.recordSentTimestamp(for: eventType1, date: date1)
        storage.recordSentTimestamp(for: eventType2, date: date2)

        let retrievedDate1 = storage.lastSentTimestamp(for: eventType1)
        let retrievedDate2 = storage.lastSentTimestamp(for: eventType2)

        XCTAssertNotNil(retrievedDate1)
        XCTAssertNotNil(retrievedDate2)
        XCTAssertEqual(retrievedDate1!.timeIntervalSince1970, date1.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(retrievedDate2!.timeIntervalSince1970, date2.timeIntervalSince1970, accuracy: 1.0)
    }

    func testTimestampStorageDoesNotAffectWideEventDataStorage() throws {
        let eventType = "storage_isolation_test"
        let timestamp = Date()

        storage.recordSentTimestamp(for: eventType, date: timestamp)

        // Verify no wide event data was affected
        XCTAssertThrowsError(try storage.load(globalID: "some-id") as StorageTestWideEventData) { error in
            guard case WideEventError.flowNotFound = error else {
                XCTFail("Expected flowNotFound error")
                return
            }
        }
    }
}

// MARK: - Test Wide Event Data Type

private final class StorageTestWideEventData: WideEventData {
    static let metadata = WideEventMetadata(
        pixelName: "storage_test_event",
        featureName: "storage_test_event",
        mobileMetaType: "ios-storage-test-event",
        desktopMetaType: "macos-storage-test-event",
        version: "1.0.0"
    )

    var errorData: WideEventErrorData?
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var globalData: WideEventGlobalData

    init(globalData: WideEventGlobalData = WideEventGlobalData(platform: "macOS", sampleRate: 1.0)) {
        self.contextData = WideEventContextData()
        self.appData = WideEventAppData()
        self.globalData = globalData
    }

    func jsonParameters() -> [String: Encodable] {
        return [:]
    }
}

//
//  ScanWideEventRecorderTests.swift
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
import PixelKitTestingUtilities
import BrowserServicesKit
@testable import DataBrokerProtectionCore

final class ScanWideEventRecorderTests: XCTestCase {

    private let attemptID = UUID(uuidString: "00000000-1111-2222-3333-444444444444")!
    private let dataBrokerURL = "https://broker.example"
    private let dataBrokerVersion = "1.2"
    private var wideEventMock: WideEventMock!

    override func setUp() {
        super.setUp()
        wideEventMock = WideEventMock()
    }

    override func tearDown() {
        wideEventMock = nil
        super.tearDown()
    }

    // MARK: - Metadata

    func testMetadataForInitialScanUsesReferenceDateAndNewScan() {
        let referenceDate = Date(timeIntervalSince1970: 500)
        let scanJob = ScanJobData(brokerId: 1,
                                  profileQueryId: 1,
                                  historyEvents: [])

        let metadata = ScanWideEventRecorder.Metadata(from: scanJob, referenceDate: referenceDate)

        XCTAssertEqual(metadata.intervalStart, referenceDate)
        XCTAssertEqual(metadata.attemptNumber, 1)
        XCTAssertEqual(metadata.attemptType, .newScan)
    }

    func testMetadataCountsAttemptsSinceLastSuccess() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let historyEvents: [HistoryEvent] = [
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date(timeIntervalSince1970: 1_000)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .matchesFound(count: 2), date: Date(timeIntervalSince1970: 2_000)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date(timeIntervalSince1970: 3_000)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .error(error: .unknown("failed")), date: Date(timeIntervalSince1970: 3_500)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date(timeIntervalSince1970: 4_000))
        ]
        let scanJob = ScanJobData(brokerId: 1,
                                  profileQueryId: 1,
                                  historyEvents: historyEvents)

        let metadata = ScanWideEventRecorder.Metadata(from: scanJob, referenceDate: referenceDate)

        XCTAssertEqual(metadata.attemptNumber, 3, "Two attempts recorded after success plus the new one about to start.")
        XCTAssertEqual(metadata.intervalStart, Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(metadata.attemptType, .maintenanceScan)
    }

    func testMetadataUsesConfirmationAttemptWhenLastEventIsOptOutRequested() {
        let referenceDate = Date(timeIntervalSince1970: 20_000)
        let historyEvents: [HistoryEvent] = [
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date(timeIntervalSince1970: 5_000)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .matchesFound(count: 1), date: Date(timeIntervalSince1970: 5_500)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutRequested, date: Date(timeIntervalSince1970: 6_000))
        ]
        let scanJob = ScanJobData(brokerId: 1,
                                  profileQueryId: 1,
                                  historyEvents: historyEvents)

        let metadata = ScanWideEventRecorder.Metadata(from: scanJob, referenceDate: referenceDate)

        XCTAssertEqual(metadata.attemptType, .confirmOptOutScan)
        XCTAssertEqual(metadata.attemptNumber, 1)
        XCTAssertEqual(metadata.intervalStart, referenceDate)
    }

    // MARK: - Recorder

    func testStartIfPossibleStartsNewFlow() {
        XCTAssertEqual(wideEventMock.started.count, 0)

        let initialMetadata = ScanWideEventRecorder.Metadata(intervalStart: Date(timeIntervalSince1970: 10),
                                                            attemptNumber: 1,
                                                            attemptType: .newScan)

        let recorder = ScanWideEventRecorder.startIfPossible(wideEvent: wideEventMock,
                                                             attemptID: attemptID,
                                                             dataBrokerURL: dataBrokerURL,
                                                             dataBrokerVersion: dataBrokerVersion,
                                                             metadata: initialMetadata)

        XCTAssertNotNil(recorder)
        XCTAssertEqual(wideEventMock.started.count, 1)

        let startedData = wideEventMock.started.first as? ScanWideEventData
        XCTAssertEqual(startedData?.attemptNumber, 1)
        XCTAssertEqual(startedData?.attemptType, .newScan)
        XCTAssertEqual(startedData?.scanInterval?.start, Date(timeIntervalSince1970: 10))
    }

    func testStartIfPossibleReusesExistingFlow() {
        let initialMetadata = ScanWideEventRecorder.Metadata(intervalStart: Date(timeIntervalSince1970: 10),
                                                            attemptNumber: 1,
                                                            attemptType: .newScan)

        _ = ScanWideEventRecorder.startIfPossible(wideEvent: wideEventMock,
                                                  attemptID: attemptID,
                                                  dataBrokerURL: dataBrokerURL,
                                                  dataBrokerVersion: dataBrokerVersion,
                                                  metadata: initialMetadata)

        XCTAssertEqual(wideEventMock.started.count, 1)

        let updatedMetadata = ScanWideEventRecorder.Metadata(intervalStart: Date(timeIntervalSince1970: 5),
                                                             attemptNumber: 2,
                                                             attemptType: .maintenanceScan)

        _ = ScanWideEventRecorder.startIfPossible(wideEvent: wideEventMock,
                                                  attemptID: attemptID,
                                                  dataBrokerURL: dataBrokerURL,
                                                  dataBrokerVersion: dataBrokerVersion,
                                                  metadata: updatedMetadata)

        XCTAssertEqual(wideEventMock.started.count, 1, "Should reuse the existing flow.")
    }
}

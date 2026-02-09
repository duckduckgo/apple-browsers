//
//  WideEventRecorderTests.swift
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
import PixelKitTestingUtilities

final class WideEventRecorderTests: XCTestCase {

    private var wideEventMock: WideEventMock!
    private let identifier = "wide-event-id"

    override func setUp() {
        super.setUp()
        wideEventMock = WideEventMock()
    }

    override func tearDown() {
        wideEventMock = nil
        super.tearDown()
    }

    func testStartIfPossibleCreatesRecorderWithInterval() {
        let startDate = Date(timeIntervalSince1970: 100)

        let recorder = WideEventRecorder<WideEventDataMeasuringMock>.startIfPossible(
            wideEvent: wideEventMock,
            identifier: identifier,
            sampleRate: 0.25,
            intervalStart: startDate,
            makeData: { global, interval in
                WideEventDataMeasuringMock(globalData: global, measuredInterval: interval)
            }
        )

        XCTAssertNotNil(recorder)
        let startedData = wideEventMock.started.first as? WideEventDataMeasuringMock
        XCTAssertEqual(startedData?.globalData.id, "wide-event-id")
        XCTAssertEqual(startedData?.globalData.sampleRate, 0.25)
        XCTAssertEqual(startedData?.measuredInterval?.start, Date(timeIntervalSince1970: 100))
        XCTAssertNil(startedData?.measuredInterval?.end)
    }

    func testResumeIfPossibleReturnsExistingRecorder() {
        let notResumed = WideEventRecorder<WideEventDataMeasuringMock>.resumeIfPossible(
            wideEvent: wideEventMock,
            identifier: identifier
        )

        XCTAssertNil(notResumed)

        let startDate = Date(timeIntervalSince1970: 200)

        XCTAssertNotNil(
            WideEventRecorder<WideEventDataMeasuringMock>.makeIfPossible(
                wideEvent: wideEventMock,
                identifier: identifier,
                sampleRate: 0.5,
                intervalStart: startDate,
                makeData: { global, interval in
                    WideEventDataMeasuringMock(globalData: global, measuredInterval: interval)
                }
            )
        )

        let resumed = WideEventRecorder<WideEventDataMeasuringMock>.resumeIfPossible(
            wideEvent: wideEventMock,
            identifier: identifier
        )

        XCTAssertNotNil(resumed)
        XCTAssertEqual(wideEventMock.started.count, 1)
    }

    func testMarkCompletedUpdatesIntervalAndCompletesFlow() throws {
        let startDate = Date(timeIntervalSince1970: 300)
        let completionDate = Date(timeIntervalSince1970: 500)

        let recorder = try XCTUnwrap(
            WideEventRecorder<WideEventDataMeasuringMock>.makeIfPossible(
                wideEvent: wideEventMock,
                identifier: identifier,
                sampleRate: 1.0,
                intervalStart: startDate,
                makeData: { global, interval in
                    WideEventDataMeasuringMock(globalData: global, measuredInterval: interval)
                }
            )
        )

        let completionExpectation = expectation(description: "flow completed")
        wideEventMock.onComplete = { data, status in
            guard let data = data as? WideEventDataMeasuringMock else { return }
            XCTAssertEqual(status, .success)
            XCTAssertEqual(data.measuredInterval?.end, completionDate)
            completionExpectation.fulfill()
        }

        recorder.markCompleted(at: completionDate)

        wait(for: [completionExpectation], timeout: 1.0)

        let updatedData = wideEventMock.updates.last as? WideEventDataMeasuringMock
        XCTAssertEqual(updatedData?.measuredInterval?.end, completionDate)
        XCTAssertEqual(wideEventMock.completions.count, 1)
    }

    func testMarkCompletedWithInvalidIntervalCompletesFlowWithReason() throws {
        let recorder = try XCTUnwrap(
            WideEventRecorder<WideEventDataMeasuringMock>.makeIfPossible(
                wideEvent: wideEventMock,
                identifier: identifier,
                sampleRate: 1.0,
                intervalStart: nil,
                makeData: { global, interval in
                    WideEventDataMeasuringMock(globalData: global, measuredInterval: interval)
                }
            )
        )

        let completionExpectation = expectation(description: "flow completed")
        wideEventMock.onComplete = { data, status in
            guard let data = data as? WideEventDataMeasuringMock else { return }
            XCTAssertEqual(status, .success(reason: "invalid-interval"))
            XCTAssertNil(data.measuredInterval?.end)
            completionExpectation.fulfill()
        }

        recorder.markCompleted(at: Date(), invalidIntervalReason: "invalid-interval")

        wait(for: [completionExpectation], timeout: 1.0)

        XCTAssertEqual(wideEventMock.updates.count, 0)
    }
}

private final class WideEventDataMeasuringMock: WideEventDataMeasuringInterval {
    static let metadata = WideEventMetadata(
        pixelName: "test-wide-event",
        featureName: "test-wide-event",
        mobileMetaType: "ios-test-wide-event",
        desktopMetaType: "macos-test-wide-event",
        version: "1.0.0"
    )

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var measuredInterval: WideEvent.MeasuredInterval?
    var errorData: WideEventErrorData?

    init(globalData: WideEventGlobalData,
         measuredInterval: WideEvent.MeasuredInterval?) {
        self.globalData = globalData
        self.contextData = WideEventContextData()
        self.appData = WideEventAppData()
        self.measuredInterval = measuredInterval
    }

    func pixelParameters() -> [String: String] { [:] }
}

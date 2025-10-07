//
//  OptOutSubmissionWideEventRecorderTests.swift
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
import PixelKitTestingUtilities
import PixelKit
@testable import DataBrokerProtectionCore

final class OptOutSubmissionWideEventRecorderTests: XCTestCase {

    private var wideEventMock: WideEventMock!
    private let attemptID = UUID()
    private let recordFoundDate = Date(timeIntervalSince1970: 100)

    override func setUp() {
        super.setUp()
        wideEventMock = WideEventMock()
    }

    override func tearDown() {
        wideEventMock.onUpdate = nil
        wideEventMock.onComplete = nil
        wideEventMock = nil
        super.tearDown()
    }

    func testMakeIfPossibleStartsFlow() {
        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEventMock,
                                                                        attemptID: attemptID,
                                                                        dataBrokerURL: "broker.com",
                                                                        dataBrokerVersion: "1.0",
                                                                        recordFoundDate: recordFoundDate)

        XCTAssertNotNil(recorder)
        XCTAssertEqual(wideEventMock.started.count, 1)

        let data = wideEventMock.started.first as? OptOutSubmissionWideEventData
        XCTAssertEqual(data?.globalData.id, attemptID.uuidString)
        XCTAssertEqual(data?.submissionInterval?.start, recordFoundDate)
        XCTAssertNil(data?.submissionInterval?.end)
    }

    func testRecordStageAppendsStageAndUpdatesFlow() {
        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEventMock,
                                                                        attemptID: attemptID,
                                                                        dataBrokerURL: "broker.com",
                                                                        dataBrokerVersion: "1.0",
                                                                        recordFoundDate: recordFoundDate)!

        let updateExpectation = expectation(description: "wide event updated")
        wideEventMock.onUpdate = { _ in updateExpectation.fulfill() }

        recorder.recordStage(.submit, duration: -5, tries: 2, actionID: "action")

        wait(for: [updateExpectation], timeout: 1)

        guard let data = wideEventMock.updates.last as? OptOutSubmissionWideEventData,
              let stage = data.stages.last else {
            return XCTFail("Stage not recorded")
        }

        XCTAssertEqual(stage.name, .submit)
        XCTAssertEqual(stage.duration, 0)
        XCTAssertEqual(stage.tries, 2)
        XCTAssertEqual(stage.actionID, "action")
    }

    func testCompleteWithErrorSetsErrorDataAndCompletesOnce() {
        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEventMock,
                                                                        attemptID: attemptID,
                                                                        dataBrokerURL: "broker.com",
                                                                        dataBrokerVersion: "1.0",
                                                                        recordFoundDate: recordFoundDate)!

        let error = NSError(domain: "test", code: 9)
        let completionExpectation = expectation(description: "wide event completed")
        wideEventMock.onComplete = { _, _ in completionExpectation.fulfill() }

        recorder.complete(status: .failure, with: error)
        recorder.complete(status: .failure, with: error)

        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(wideEventMock.completions.count, 1)

        guard let completedData = wideEventMock.completions.last?.0 as? OptOutSubmissionWideEventData else {
            return XCTFail("Expected OptOutSubmissionWideEventData in completion")
        }

        XCTAssertEqual(wideEventMock.completions.last?.1, .failure)
        XCTAssertEqual(completedData.errorData?.domain, error.domain)
        XCTAssertEqual(completedData.errorData?.code, error.code)
        XCTAssertEqual(completedData.errorData?.underlyingErrors.count, 0)
    }

    func testCancelWithErrorMarksFlowCancelled() {
        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEventMock,
                                                                        attemptID: attemptID,
                                                                        dataBrokerURL: "broker.com",
                                                                        dataBrokerVersion: "1.0",
                                                                        recordFoundDate: recordFoundDate)!

        let error = NSError(domain: "cancelled", code: 1)
        let completionExpectation = expectation(description: "wide event cancelled")
        wideEventMock.onComplete = { _, _ in completionExpectation.fulfill() }

        recorder.cancel(with: error)

        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(wideEventMock.completions.count, 1)

        guard let completedData = wideEventMock.completions.last?.0 as? OptOutSubmissionWideEventData else {
            return XCTFail("Expected OptOutSubmissionWideEventData in completion")
        }

        XCTAssertEqual(wideEventMock.completions.last?.1, .cancelled)
        XCTAssertEqual(completedData.errorData?.domain, error.domain)
        XCTAssertEqual(completedData.errorData?.code, error.code)
        XCTAssertEqual(completedData.errorData?.underlyingErrors.count, 0)
    }

    func testResumeIfPossibleReturnsExistingFlow() {
        XCTAssertNotNil(OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEventMock,
                                                                         attemptID: attemptID,
                                                                         dataBrokerURL: "broker.com",
                                                                         dataBrokerVersion: "1.0",
                                                                         recordFoundDate: recordFoundDate))
        XCTAssertEqual(wideEventMock.started.count, 1)

        let notResumed = OptOutSubmissionWideEventRecorder.resumeIfPossible(wideEvent: wideEventMock,
                                                                            attemptID: UUID())
        XCTAssertNil(notResumed)

        let resumed = OptOutSubmissionWideEventRecorder.resumeIfPossible(wideEvent: wideEventMock,
                                                                         attemptID: attemptID)

        XCTAssertNotNil(resumed)
        XCTAssertEqual(wideEventMock.started.count, 1)
    }
}

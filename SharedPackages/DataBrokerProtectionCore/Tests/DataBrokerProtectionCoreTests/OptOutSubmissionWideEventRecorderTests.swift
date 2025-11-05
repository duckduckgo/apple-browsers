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
import PixelKitTestingUtilities
import PixelKit
import BrowserServicesKit
@testable import DataBrokerProtectionCore

final class OptOutSubmissionWideEventRecorderTests: XCTestCase {

    private var wideEventMock: WideEventMock!
    private let profileIdentifier = "profile-id"
    private let brokerId: Int64 = 42
    private let profileQueryId: Int64 = 13
    private let extractedProfileId: Int64 = 99
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
        let recorderIdentifier = OptOutWideEventIdentifier(
            profileIdentifier: profileIdentifier,
            brokerId: brokerId,
            profileQueryId: profileQueryId,
            extractedProfileId: extractedProfileId
        )
        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(
            wideEvent: wideEventMock,
            identifier: recorderIdentifier,
            dataBrokerURL: "broker.com",
            dataBrokerVersion: "1.0",
            recordFoundDate: recordFoundDate
        )

        XCTAssertNotNil(recorder)
        XCTAssertEqual(wideEventMock.started.count, 1)

        let data = wideEventMock.started.first as? OptOutSubmissionWideEventData
        XCTAssertEqual(data?.globalData.id, "profile-id".sha256)
        XCTAssertEqual(data?.submissionInterval?.start, recordFoundDate)
        XCTAssertNil(data?.submissionInterval?.end)
    }

    func testResumeIfPossibleReturnsExistingFlow() {
        let identifier = OptOutWideEventIdentifier(
            profileIdentifier: profileIdentifier,
            brokerId: brokerId,
            profileQueryId: profileQueryId,
            extractedProfileId: extractedProfileId
        )
        XCTAssertNotNil(
            OptOutSubmissionWideEventRecorder.makeIfPossible(
                wideEvent: wideEventMock,
                identifier: identifier,
                dataBrokerURL: "broker.com",
                dataBrokerVersion: "1.0",
                recordFoundDate: recordFoundDate
            )
        )
        XCTAssertEqual(wideEventMock.started.count, 1)

        let otherIdentifier = OptOutWideEventIdentifier(
            profileIdentifier: "other-profile",
            brokerId: brokerId,
            profileQueryId: profileQueryId,
            extractedProfileId: extractedProfileId
        )
        XCTAssertNil(
            OptOutSubmissionWideEventRecorder.resumeIfPossible(
                wideEvent: wideEventMock,
                identifier: otherIdentifier
            )
        )

        let completionExpectation = expectation(description: "wide event completed")
        wideEventMock.onComplete = { data, status in
            guard let data = data as? OptOutSubmissionWideEventData else {
                XCTFail("Unexpected data type")
                return
            }

            XCTAssertEqual(status, .success)
            XCTAssertEqual(data.submissionInterval?.start, self.recordFoundDate)
            completionExpectation.fulfill()
        }

        let resumedRecorder = OptOutSubmissionWideEventRecorder.startIfPossible(
            wideEvent: wideEventMock,
            identifier: identifier,
            dataBrokerURL: "broker.com",
            dataBrokerVersion: "1.0",
            recordFoundDate: recordFoundDate.addingTimeInterval(50) // this won't affect the stored interval
        )

        XCTAssertNotNil(resumedRecorder)
        resumedRecorder?.markCompleted(at: Date(timeIntervalSince1970: 200))

        wait(for: [completionExpectation], timeout: 1.0)

        let updatedData = wideEventMock.updates.last as? OptOutSubmissionWideEventData
        XCTAssertEqual(updatedData?.submissionInterval?.start, recordFoundDate)
        XCTAssertEqual(updatedData?.submissionInterval?.end, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(wideEventMock.started.count, 1)
    }

    func testMakeIfPossibleUsesFallbackIdentifierWhenProfileIdentifierMissing() {
        let identifierWithoutProfile = OptOutWideEventIdentifier(
            profileIdentifier: nil,
            brokerId: brokerId,
            profileQueryId: profileQueryId,
            extractedProfileId: extractedProfileId
        )

        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(
            wideEvent: wideEventMock,
            identifier: identifierWithoutProfile,
            dataBrokerURL: "broker.com",
            dataBrokerVersion: "1.0",
            recordFoundDate: recordFoundDate
        )

        XCTAssertNotNil(recorder)
        XCTAssertEqual(wideEventMock.started.count, 1)

        let data = wideEventMock.started.first as? OptOutSubmissionWideEventData
        XCTAssertEqual(data?.globalData.id, "42-13-99")
    }

    func testStartIfPossibleCreatesRecorderWhenNoneExists() {
        let identifier = OptOutWideEventIdentifier(
            profileIdentifier: profileIdentifier,
            brokerId: brokerId,
            profileQueryId: profileQueryId,
            extractedProfileId: extractedProfileId
        )

        let recorder = OptOutSubmissionWideEventRecorder.startIfPossible(
            wideEvent: wideEventMock,
            identifier: identifier,
            dataBrokerURL: "broker.com",
            dataBrokerVersion: "1.0",
            recordFoundDate: recordFoundDate
        )

        XCTAssertNotNil(recorder)
        let data = wideEventMock.started.first as? OptOutSubmissionWideEventData
        XCTAssertEqual(data?.submissionInterval?.start, recordFoundDate)
    }
}

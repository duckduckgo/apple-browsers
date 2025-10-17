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
                                                                        identifier: profileIdentifier,
                                                                        dataBrokerURL: "broker.com",
                                                                        dataBrokerVersion: "1.0",
                                                                        recordFoundDate: recordFoundDate)

        XCTAssertNotNil(recorder)
        XCTAssertEqual(wideEventMock.started.count, 1)

        let data = wideEventMock.started.first as? OptOutSubmissionWideEventData
        XCTAssertEqual(data?.globalData.id, profileIdentifier.sha256)
        XCTAssertEqual(data?.submissionInterval?.start, recordFoundDate)
        XCTAssertNil(data?.submissionInterval?.end)
    }

    func testResumeIfPossibleReturnsExistingFlow() {
        XCTAssertNotNil(OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEventMock,
                                                                         identifier: profileIdentifier,
                                                                         dataBrokerURL: "broker.com",
                                                                         dataBrokerVersion: "1.0",
                                                                         recordFoundDate: recordFoundDate))
        XCTAssertEqual(wideEventMock.started.count, 1)

        let notResumed = OptOutSubmissionWideEventRecorder.resumeIfPossible(wideEvent: wideEventMock,
                                                                            identifier: "other-profile")
        XCTAssertNil(notResumed)

        let resumed = OptOutSubmissionWideEventRecorder.resumeIfPossible(wideEvent: wideEventMock,
                                                                         identifier: profileIdentifier)

        XCTAssertNotNil(resumed)
        XCTAssertEqual(wideEventMock.started.count, 1)
    }
}

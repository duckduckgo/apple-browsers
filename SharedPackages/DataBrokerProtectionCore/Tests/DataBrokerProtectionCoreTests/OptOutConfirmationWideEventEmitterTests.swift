//
//  OptOutConfirmationWideEventEmitterTests.swift
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

final class OptOutConfirmationWideEventEmitterTests: XCTestCase {

    private var wideEventMock: WideEventMock!
    private let profileIdentifier = "profile-identifier"
    private let recordFoundDate = Date(timeIntervalSince1970: 1_000)
    private let confirmationDate = Date(timeIntervalSince1970: 2_000)

    override func setUp() {
        super.setUp()
        wideEventMock = WideEventMock()
    }

    override func tearDown() {
        wideEventMock = nil
        super.tearDown()
    }

    func testEmitSuccessStartsAndCompletesFlow() {
        OptOutConfirmationWideEventEmitter.emitSuccess(wideEvent: wideEventMock,
                                                       profileIdentifier: profileIdentifier,
                                                       recordFoundDate: recordFoundDate,
                                                       confirmationDate: confirmationDate,
                                                       dataBrokerURL: "broker.com",
                                                       dataBrokerVersion: "1.0")

        XCTAssertEqual(wideEventMock.started.count, 1)
        XCTAssertEqual(wideEventMock.completions.count, 1)
        XCTAssertEqual(wideEventMock.completions.last?.1, .success)

        guard let data = wideEventMock.completions.last?.0 as? OptOutConfirmationWideEventData else {
            return XCTFail("Expected OptOutConfirmationWideEventData")
        }

        XCTAssertEqual(data.globalData.id, profileIdentifier.sha256)
        XCTAssertEqual(data.dataBrokerURL, "broker.com")
        XCTAssertEqual(data.dataBrokerVersion, "1.0")
        XCTAssertEqual(data.confirmationInterval?.start, recordFoundDate)
        XCTAssertEqual(data.confirmationInterval?.end, confirmationDate)
    }
}

//
//  AdClickAttributionCounterTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Persistence
import PersistenceTestingUtils
@testable import BrowserServicesKit

class AdClickAttributionCounterTests: XCTestCase {

    func testWhenEventIsDetectedCounterIsIncremented() {
        let mockStore = MockKeyValueStore()
        let counter = AdClickAttributionCounter(store: mockStore, onSendRequest: { _ in
            XCTFail("Should not send anything")
        })

        let date = Date()
        // First use saves date if not present in store
        counter.onAttributionActive(currentTime: date)

        // Second use, later, but before sync interval
        counter.onAttributionActive(currentTime: date + 1)

        let count = mockStore.object(forKey: AdClickAttributionCounter.Constant.pageLoadsCountKey) as? Int
        XCTAssertEqual(count, 2)

        let storedDate = mockStore.object(forKey: AdClickAttributionCounter.Constant.lastSendAtKey) as? Date
        XCTAssertEqual(date, storedDate)
    }

    var onSend: (Int) -> Void = { _ in }

    func testWhenTimeIntervalHasPassedThenDataIsSent() {
        let interval: Double = 60 * 60

        let expectation = expectation(description: "Data sent")
        expectation.expectedFulfillmentCount = 2

        let mockStore = MockKeyValueStore()
        let counter = AdClickAttributionCounter(store: mockStore, sendInterval: interval) { count in
            self.onSend(count)
        }

        onSend = { _ in XCTFail("Send not expected") }

        counter.onAttributionActive()
        counter.onAttributionActive()
        counter.onAttributionActive(currentTime: Date() + interval - 1)

        counter.sendEventsIfNeeded()

        onSend = { count in
            expectation.fulfill()
            XCTAssertEqual(count, 3)
        }

        // timestamp in counter will become now + interval
        counter.sendEventsIfNeeded(currentTime: Date() + interval + 1)

        onSend = { _ in XCTFail("Send not expected") }

        counter.onAttributionActive(currentTime: Date() + interval + 1)

        onSend = { count in
            expectation.fulfill()
            XCTAssertEqual(count, 2)
        }

        // Add another interval to trigger sync
        counter.onAttributionActive(currentTime: Date() + 2*interval + 1)

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenTimeIntervalHasPassedAndCounterIsZeroThenCurrentTimeIsReset() {
        let interval: Double = 60 * 60
        let mockStore = MockKeyValueStore()
        let counter = AdClickAttributionCounter(store: mockStore, sendInterval: interval) {_ in }

        var storedDate: Date? { mockStore.object(forKey: AdClickAttributionCounter.Constant.lastSendAtKey) as? Date }

        let date = Date()
        counter.onAttributionActive(currentTime: date)
        XCTAssertEqual(date, storedDate)

        let sendDate = date + interval + 1
        counter.sendEventsIfNeeded(currentTime: sendDate)
        XCTAssertEqual(sendDate, storedDate)

        let nextSendDate = sendDate + interval + 1
        counter.sendEventsIfNeeded(currentTime: nextSendDate)
        XCTAssertEqual(nextSendDate, storedDate)
    }

}

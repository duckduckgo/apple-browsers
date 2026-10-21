//
//  PromoHistoryRecordTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PromoHistoryRecordTests: XCTestCase {

    func testIsEligible_WhenActioned_ReturnsFalse_EvenWithNilNextEligibleDate() {
        var record = PromoHistoryRecord(id: "test")
        record.actioned = true
        record.nextEligibleDate = nil

        XCTAssertFalse(record.isEligible(asOf: Date()))
    }

    func testIsEligible_WhenActioned_ReturnsFalse_EvenWhenNextEligibleDateIsInPast() {
        var record = PromoHistoryRecord(id: "test")
        record.actioned = true
        record.nextEligibleDate = Date().addingTimeInterval(-3600)

        XCTAssertFalse(record.isEligible(asOf: Date()))
    }

    func testIsEligible_WhenNotActionedAndNextEligibleDateNil_ReturnsTrue() {
        var record = PromoHistoryRecord(id: "test")
        record.actioned = false
        record.nextEligibleDate = nil

        XCTAssertTrue(record.isEligible(asOf: Date()))
    }

    func testIsEligible_WhenNotActionedAndNextEligibleDateInPast_ReturnsTrue() {
        let asOf = Date()
        var record = PromoHistoryRecord(id: "test")
        record.actioned = false
        record.nextEligibleDate = asOf.addingTimeInterval(-3600)

        XCTAssertTrue(record.isEligible(asOf: asOf))
    }

    func testIsEligible_WhenNotActionedAndNextEligibleDateEqualsAsOf_ReturnsTrue() {
        let asOf = Date()
        var record = PromoHistoryRecord(id: "test")
        record.actioned = false
        record.nextEligibleDate = asOf

        XCTAssertTrue(record.isEligible(asOf: asOf))
    }

    func testIsEligible_WhenNotActionedAndNextEligibleDateInFuture_ReturnsFalse() {
        let asOf = Date()
        var record = PromoHistoryRecord(id: "test")
        record.actioned = false
        record.nextEligibleDate = asOf.addingTimeInterval(3600)

        XCTAssertFalse(record.isEligible(asOf: asOf))
    }
}

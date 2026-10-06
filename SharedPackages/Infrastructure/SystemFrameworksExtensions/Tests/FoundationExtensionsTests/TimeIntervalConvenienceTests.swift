//
//  TimeIntervalConvenienceTests.swift
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

import Foundation
import XCTest
@testable import FoundationExtensions

final class TimeIntervalConvenienceTests: XCTestCase {

    func testWhenCreatingSecondsThenReturnsExpectedInterval() {
        XCTAssertEqual(TimeInterval.seconds(5), 5)
    }

    func testWhenCreatingMillisecondsThenReturnsExpectedInterval() {
        XCTAssertEqual(TimeInterval.milliseconds(5), 0.005)
    }

    func testWhenCreatingMinutesThenReturnsExpectedInterval() {
        XCTAssertEqual(TimeInterval.minutes(5), 5 * 60)
    }

    func testWhenCreatingHoursThenReturnsExpectedInterval() {
        XCTAssertEqual(TimeInterval.hours(5), 5 * 60 * 60)
    }

    func testWhenCreatingDaysThenReturnsExpectedInterval() {
        XCTAssertEqual(TimeInterval.days(5), 5 * 24 * 60 * 60)
    }

    func testWhenUsingDayConstantThenReturnsExpectedInterval() {
        XCTAssertEqual(TimeInterval.day, 24 * 60 * 60)
    }
}

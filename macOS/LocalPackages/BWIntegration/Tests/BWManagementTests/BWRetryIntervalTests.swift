//
//  BWRetryIntervalTests.swift
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

import XCTest
@testable import BWManagement

final class BWRetryIntervalTests: XCTestCase {

    func testWhenNextIsCalledRepeatedlyThenIntervalDoublesUpToMaximum() {
        var interval = BWRetryInterval()

        XCTAssertEqual(interval.next(), 1)
        XCTAssertEqual(interval.next(), 2)
        XCTAssertEqual(interval.next(), 4)
        XCTAssertEqual(interval.next(), 8)
        XCTAssertEqual(interval.next(), 16)
        XCTAssertEqual(interval.next(), 16)
    }

    func testWhenResetThenIntervalRestartsFromInitialInterval() {
        var interval = BWRetryInterval()
        _ = interval.next()
        _ = interval.next()

        interval.reset()

        XCTAssertEqual(interval.next(), BWRetryInterval.initialInterval)
    }

}

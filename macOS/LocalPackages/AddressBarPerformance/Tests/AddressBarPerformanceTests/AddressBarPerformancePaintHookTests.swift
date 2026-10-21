//
//  AddressBarPerformancePaintHookTests.swift
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

import Darwin
import XCTest
@testable import AddressBarPerformance

final class AddressBarPerformancePaintHookTests: XCTestCase {

    // MARK: - hostTimeToSeconds

    func test_hostTimeToSeconds_zeroInputProducesZero() {
        XCTAssertEqual(AddressBarPerformancePaintHook.hostTimeToSeconds(0), 0)
    }

    func test_hostTimeToSeconds_appliesHostTimebase() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let hostTime: UInt64 = 1_000_000_000
        let expected = Double(hostTime) * Double(info.numer) / Double(info.denom) / 1_000_000_000

        XCTAssertEqual(AddressBarPerformancePaintHook.hostTimeToSeconds(hostTime), expected, accuracy: 1e-9)
    }

    func test_hostTimeToSeconds_isMonotonic() {
        let a = AddressBarPerformancePaintHook.hostTimeToSeconds(1_000)
        let b = AddressBarPerformancePaintHook.hostTimeToSeconds(2_000)
        let c = AddressBarPerformancePaintHook.hostTimeToSeconds(3_000)

        XCTAssertLessThan(a, b)
        XCTAssertLessThan(b, c)
    }
}

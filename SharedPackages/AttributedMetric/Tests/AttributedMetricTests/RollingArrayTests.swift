//
//  RollingArrayTests.swift
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
@testable import AttributedMetric

final class RollingArrayTests: XCTestCase {

    private var rollingBool: RollingArray<Bool>!
    private var rollingInt: RollingArray<Int>!

    override func setUp() {
        super.setUp()
        rollingBool = RollingArray<Bool>(capacity: 7)
        rollingInt = RollingArray<Int>(capacity: 7)
    }

    override func tearDown() {
        rollingBool = nil
        rollingInt = nil
        super.tearDown()
    }

    func testInitialization() {
        // Both types should start empty
        XCTAssertEqual(rollingBool.allValues, [])
        XCTAssertEqual(rollingInt.allValues, [])
        XCTAssertEqual(rollingBool.count, 0)
        XCTAssertEqual(rollingInt.count, 0)

        // All subscripts should return nil
        for i in 0..<7 {
            XCTAssertNil(rollingBool[i])
            XCTAssertNil(rollingInt[i])
        }
    }

    func testAppendBasicValues() {
        // Test Bool values
        rollingBool.append(true)
        XCTAssertEqual(rollingBool.allValues, [true])
        XCTAssertEqual(rollingBool.count, 1)
        XCTAssertEqual(rollingBool[6], true)

        rollingBool.append(false)
        XCTAssertEqual(rollingBool.allValues, [true, false])
        XCTAssertEqual(rollingBool.count, 2)

        // Test Int values (including zero)
        rollingInt.append(5)
        XCTAssertEqual(rollingInt.allValues, [5])
        XCTAssertEqual(rollingInt.count, 1)

        rollingInt.append(0)
        XCTAssertEqual(rollingInt.allValues, [5, 0])
        XCTAssertEqual(rollingInt.count, 2)
    }

    func testRollingBehavior() {
        // Fill all 7 slots
        for i in 1...7 {
            rollingInt.append(i)
        }
        XCTAssertEqual(rollingInt.allValues, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(rollingInt.count, 7)

        // Add 8th value - should roll over
        rollingInt.append(8)
        XCTAssertEqual(rollingInt.allValues, [2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(rollingInt.count, 7)

        // Add 9th value - should continue rolling
        rollingInt.append(9)
        XCTAssertEqual(rollingInt.allValues, [3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(rollingInt.count, 7)
    }

    func testSubscriptAccess() {
        // Test valid indices
        rollingBool.append(true)
        rollingBool.append(false)
        rollingBool.append(true)

        XCTAssertEqual(rollingBool[4], true)   // First appended
        XCTAssertEqual(rollingBool[5], false)  // Second appended
        XCTAssertEqual(rollingBool[6], true)   // Third appended
        XCTAssertNil(rollingBool[0])           // Empty slot
        XCTAssertNil(rollingBool[1])           // Empty slot

        // Test invalid indices
        XCTAssertNil(rollingBool[-1])
        XCTAssertNil(rollingBool[7])
        XCTAssertNil(rollingBool[100])
    }

    func testLargeNumberOfAppends() {
        // Test with alternating pattern
        let pattern = [true, false, true, false, true, false, true, false, true, false]
        for value in pattern {
            rollingBool.append(value)
        }

        // Should contain last 7 values: [false, true, false, true, false, true, false]
        let expected = [false, true, false, true, false, true, false]
        XCTAssertEqual(rollingBool.allValues, expected)
        XCTAssertEqual(rollingBool.count, 7)
    }

    func testMixedValueTypes() {
        // Test with mixed positive, negative, and zero
        let values = [-5, 0, 10, -2, 100, 0, 7]
        for value in values {
            rollingInt.append(value)
        }

        XCTAssertEqual(rollingInt.allValues, values)
        XCTAssertEqual(rollingInt.count, 7)
    }

    func testCodableRoundTrip() throws {
        // Test empty state
        let emptyData = try JSONEncoder().encode(rollingBool)
        let decodedEmpty = try JSONDecoder().decode(RollingArray<Bool>.self, from: emptyData)
        XCTAssertEqual(decodedEmpty.allValues, [])
        XCTAssertEqual(decodedEmpty.count, 0)

        // Test with data
        rollingInt.append(1)
        rollingInt.append(0)
        rollingInt.append(-5)

        let data = try JSONEncoder().encode(rollingInt)
        let decoded = try JSONDecoder().decode(RollingArray<Int>.self, from: data)

        XCTAssertEqual(decoded.allValues, rollingInt.allValues)
        XCTAssertEqual(decoded.count, rollingInt.count)
    }

    func testDifferentCapacities() {
        // Test capacity 3
        let rolling3 = RollingArray<Int>(capacity: 3)
        XCTAssertEqual(rolling3.count, 0)

        rolling3.append(1)
        rolling3.append(2)
        rolling3.append(3)
        XCTAssertEqual(rolling3.allValues, [1, 2, 3])
        XCTAssertEqual(rolling3.count, 3)

        // Roll over
        rolling3.append(4)
        XCTAssertEqual(rolling3.allValues, [2, 3, 4])
        XCTAssertEqual(rolling3.count, 3)

        // Test capacity 10
        let rolling10 = RollingArray<String>(capacity: 10)
        for i in 1...12 {
            rolling10.append("item\(i)")
        }
        XCTAssertEqual(rolling10.count, 10)
        XCTAssertEqual(rolling10.allValues, ["item3", "item4", "item5", "item6", "item7", "item8", "item9", "item10", "item11", "item12"])

        // Test minimum capacity of 1
        let rolling1 = RollingArray<Bool>(capacity: 1)
        rolling1.append(true)
        rolling1.append(false)
        XCTAssertEqual(rolling1.allValues, [false])
        XCTAssertEqual(rolling1.count, 1)
        rolling1.append(true)
        rolling1.append(true)
        XCTAssertEqual(rolling1.count, 1)
    }

    func testEmptyArrayAllFunctions() {
        let emptyRollingInt = RollingArray<Int>(capacity: 5)
        let emptyRollingBool = RollingArray<Bool>(capacity: 3)

        // Test count property
        XCTAssertEqual(emptyRollingInt.count, 0)
        XCTAssertEqual(emptyRollingBool.count, 0)

        // Test allValues property
        XCTAssertEqual(emptyRollingInt.allValues, [])
        XCTAssertEqual(emptyRollingBool.allValues, [])

        // Test last property
        XCTAssertNil(emptyRollingInt.last)
        XCTAssertNil(emptyRollingBool.last)

        // Test lastIndex property
        XCTAssertEqual(emptyRollingInt.lastIndex, 4) // capacity - 1
        XCTAssertEqual(emptyRollingBool.lastIndex, 2) // capacity - 1

        // Test subscript access for all valid indices
        for i in 0..<5 {
            XCTAssertNil(emptyRollingInt[i])
        }
        for i in 0..<3 {
            XCTAssertNil(emptyRollingBool[i])
        }

        // Test subscript access for invalid indices
        XCTAssertNil(emptyRollingInt[-1])
        XCTAssertNil(emptyRollingInt[5])
        XCTAssertNil(emptyRollingInt[100])
        XCTAssertNil(emptyRollingBool[-1])
        XCTAssertNil(emptyRollingBool[3])
        XCTAssertNil(emptyRollingBool[100])

        // Test subscript setter with nil
        emptyRollingInt[0] = nil
        XCTAssertNil(emptyRollingInt[0])
        XCTAssertEqual(emptyRollingInt.count, 0)

        // Test subscript setter with value
        emptyRollingInt[2] = 42
        XCTAssertEqual(emptyRollingInt[2], 42)
        XCTAssertEqual(emptyRollingInt.count, 1)
        XCTAssertEqual(emptyRollingInt.allValues, [42])

        // Test that values array maintains correct structure
        XCTAssertEqual(emptyRollingBool.values.count, 3)
        for value in emptyRollingBool.values {
            XCTAssertEqual(value, .unknown)
        }
    }

    func testZeroCapacityArray() {
        let zeroCapacityArray = RollingArray<Int>(capacity: 0)

        // Test count property
        XCTAssertEqual(zeroCapacityArray.count, 0)

        // Test allValues property
        XCTAssertEqual(zeroCapacityArray.allValues, [])

        // Test last property
        XCTAssertNil(zeroCapacityArray.last)

        // Test lastIndex property (should be -1 for empty array)
        XCTAssertEqual(zeroCapacityArray.lastIndex, -1)

        // Test values array is empty
        XCTAssertEqual(zeroCapacityArray.values.count, 0)
        XCTAssertEqual(zeroCapacityArray.values, [])

        // Test subscript access - all indices should return nil
        XCTAssertNil(zeroCapacityArray[0])
        XCTAssertNil(zeroCapacityArray[-1])
        XCTAssertNil(zeroCapacityArray[1])

        // Test subscript setter - should not crash but have no effect
        zeroCapacityArray[0] = 42
        XCTAssertEqual(zeroCapacityArray.count, 0)
        XCTAssertEqual(zeroCapacityArray.allValues, [])
        XCTAssertNil(zeroCapacityArray[0])

        // Test append function - should not crash
        zeroCapacityArray.append(100)
        XCTAssertEqual(zeroCapacityArray.count, 1)
        XCTAssertEqual(zeroCapacityArray.allValues, [100])
        XCTAssertEqual(zeroCapacityArray.values.count, 1)
        XCTAssertEqual(zeroCapacityArray.lastIndex, 0)

        // Test append again to verify rolling behavior with single slot
        zeroCapacityArray.append(200)
        XCTAssertEqual(zeroCapacityArray.count, 1)
        XCTAssertEqual(zeroCapacityArray.allValues, [200])
        XCTAssertEqual(zeroCapacityArray.values.count, 1)
        XCTAssertEqual(zeroCapacityArray[0], 200)
    }
}

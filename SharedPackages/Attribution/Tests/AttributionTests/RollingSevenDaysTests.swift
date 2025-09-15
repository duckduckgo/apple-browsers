//
//  RollingSevenDaysTests.swift
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
@testable import Attribution

final class RollingSevenDaysTests: XCTestCase {
    
    private var rollingBool: RollingSevenDaysBool!
    private var rollingInt: RollingSevenDaysInt!
    
    override func setUp() {
        super.setUp()
        rollingBool = RollingSevenDaysBool()
        rollingInt = RollingSevenDaysInt()
    }
    
    override func tearDown() {
        rollingBool = nil
        rollingInt = nil
        super.tearDown()
    }
}

// MARK: - Core Functionality Tests

extension RollingSevenDaysTests {
    
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
}

// MARK: - Advanced Behavior Tests

extension RollingSevenDaysTests {
    
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
}

// MARK: - Codable Tests

extension RollingSevenDaysTests {
    
    func testCodableRoundTrip() throws {
        // Test empty state
        let emptyData = try JSONEncoder().encode(rollingBool)
        let decodedEmpty = try JSONDecoder().decode(RollingSevenDaysBool.self, from: emptyData)
        XCTAssertEqual(decodedEmpty.allValues, [])
        XCTAssertEqual(decodedEmpty.count, 0)
        
        // Test with data
        rollingInt.append(1)
        rollingInt.append(0)
        rollingInt.append(-5)
        
        let data = try JSONEncoder().encode(rollingInt)
        let decoded = try JSONDecoder().decode(RollingSevenDaysInt.self, from: data)
        
        XCTAssertEqual(decoded.allValues, rollingInt.allValues)
        XCTAssertEqual(decoded.count, rollingInt.count)
    }
}
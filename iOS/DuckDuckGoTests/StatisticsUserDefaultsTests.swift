//
//  StatisticsUserDefaultsTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
@testable import Core

class StatisticsUserDefaultsTests: XCTestCase {

    struct Constants {
        static let userDefaultsSuit = "StatisticsUserDefaultsTestSuit"
        static let atb = "atb"
        static let appRetentionAtb = "appAtb"
        static let searchRetentionAtb = "searchAtb"
        static let variant = "testVariant"
    }

    var testee: StatisticsUserDefaults!

    override func setUp() {
        super.setUp()
        
        UserDefaults().removePersistentDomain(forName: Constants.userDefaultsSuit)
        testee = StatisticsUserDefaults(groupName: Constants.userDefaultsSuit)
    }

    func testWhenNoInstallDateSetThenReturnsNil() {
        XCTAssertNil(testee.installDate)
    }

    func testWhenAtbAndVariantThenAtbWithVariantReturnsAtbWithVariant() {
        testee.atb = Constants.atb
        testee.variant = Constants.variant
        XCTAssertEqual(testee.atbWithVariant, "\(Constants.atb)\(Constants.variant)")
    }

    func testWhenAtbAndNoVariantThenAtbWithVariantReturnsAtb() {
        testee.atb = Constants.atb
        testee.variant = nil
        XCTAssertEqual(testee.atbWithVariant, Constants.atb)
    }

    func testWhenVariantSetThenDefaultsIsUpdated() {
        testee.variant = Constants.variant
        XCTAssertEqual(testee.variant, Constants.variant)
    }

    func testWhenFirstInitialisedThenHasStatisticsIsFalseAndAtbNil() {
        XCTAssertNil(testee.atb)
        XCTAssertFalse(testee.hasInstallStatistics)
        XCTAssertNil(testee.variant)
    }

    func testWhenAtbValueSetThenHasStatisticsIsTrue() {
        testee.atb = Constants.atb
        XCTAssertTrue(testee.hasInstallStatistics)
    }

    func testWhenAtbNotSetThenHasStatisticsIsFalse() {
        XCTAssertFalse(testee.hasInstallStatistics)
    }
    
    func testWhenAtbValueSetThenDefaultsUpdated() {
        testee.atb = Constants.atb
        XCTAssertEqual(testee.atb, Constants.atb)
    }
    
    func testWhenAppRetentionAtbValueSetThenDefaultsUpdated() {
        testee.appRetentionAtb = Constants.appRetentionAtb
        XCTAssertEqual(testee.appRetentionAtb, Constants.appRetentionAtb)
    }
    
    func testWhenAppRetentionAtbNotSetThenAtbDefaultReturned() {
        testee.atb = Constants.atb
        XCTAssertEqual(testee.appRetentionAtb, Constants.atb)
    }
    
    func testWhenSearchRetentionAtbValueSetThenDefaultsUpdated() {
        testee.searchRetentionAtb = Constants.searchRetentionAtb
        XCTAssertEqual(testee.searchRetentionAtb, Constants.searchRetentionAtb)
    }
    
    func testWhenSearchRetentionAtbNotSetThenAtbDefaultIsReturned() {
        testee.atb = Constants.atb
        XCTAssertEqual(testee.searchRetentionAtb, Constants.atb)
    }
    
    func testLastAppRetentionRequestDateDefaultsAndSetting() throws {
        // Initially should be nil
        XCTAssertNil(testee.lastAppRetentionRequestDate)
        
        // Set a date and verify it's stored
        let testDate = Date()
        testee.lastAppRetentionRequestDate = testDate
        let storedTimeInterval = try XCTUnwrap(testee.lastAppRetentionRequestDate?.timeIntervalSince1970)
        XCTAssertEqual(storedTimeInterval, testDate.timeIntervalSince1970, accuracy: 0.1)
        
        // Clear and verify it's nil again
        testee.lastAppRetentionRequestDate = nil
        XCTAssertNil(testee.lastAppRetentionRequestDate)
    }
    
    func testIsAppRetentionFiredToday() {
        // Initially should be false
        XCTAssertFalse(testee.isAppRetentionFiredToday)
        
        // Set today's date and verify it returns true
        testee.lastAppRetentionRequestDate = Date()
        XCTAssertTrue(testee.isAppRetentionFiredToday)
        
        // Set yesterday's date and verify it returns false
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        testee.lastAppRetentionRequestDate = yesterday
        XCTAssertFalse(testee.isAppRetentionFiredToday)
        
        // Set nil date and verify it returns false
        testee.lastAppRetentionRequestDate = nil
        XCTAssertFalse(testee.isAppRetentionFiredToday)
    }

}

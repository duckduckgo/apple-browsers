//
//  AppStartsTests.swift
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

final class AppStartsTests: XCTestCase {
    
    private var userDefaults: UserDefaults!
    private var uuid: UUID!
    let testDate = Date(timeIntervalSince1970: 434720061)

    override func setUp() {
        super.setUp()
        uuid = UUID()
        userDefaults = UserDefaults(suiteName: "AppStartsTestSuite.\(uuid.uuidString)")!
    }
    
    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "AppStartsTestSuite.\(uuid.uuidString)")
        userDefaults = nil
        uuid = nil
        super.tearDown()
    }
}

// MARK: - TimePast Tests

extension AppStartsTests {

    func testTimePastFromInstallation_noTimestamps_returnsNone() {
        let appStarts = AppStarts(timestamps: [])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .none)
    }
    
    func testTimePastFromInstallation_singleTimestamp_returnsNone() {
        let appStarts = AppStarts(timestamps: [testDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .none)
    }
    
    func testTimePastFromInstallation_lessThanOneWeek_returnsNone() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 3, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .none)
    }
    
    func testTimePastFromInstallation_oneWeek_returnsWeek1() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 7, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .weeks(1))
    }

    func testTimePastFromInstallation_8Days_returnsWeek1() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 8, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .weeks(1))
    }

    func testTimePastFromInstallation_twoWeeks_returnsWeek2() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 14, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .weeks(2))
    }

    func testTimePastFromInstallation_15Days_returnsWeek2() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 15, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .weeks(2))
    }

    func testTimePastFromInstallation_threeWeeks_returnsWeek3() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 21, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .weeks(3))
    }
    
    func testTimePastFromInstallation_fourWeeks_returnsMonth1() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 28, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .months(1))
    }
    
    func testTimePastFromInstallation_eightWeeks_returnsMonth2() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 56, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .months(2))
    }
    
    func testTimePastFromInstallation_twentyWeeks_returnsMonth5() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 140, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .months(5))
    }
}

// MARK: - Time Period Logic Tests

extension AppStartsTests {
    
    func testTimePeriodLogic_allWeekGaps() {
        let installDate = testDate
        
        // Less than 1 week - should return .none
        let day2 = Calendar.current.date(byAdding: .day, value: 2, to: installDate)!
        let appStarts2Days = AppStarts(timestamps: [installDate, day2])
        XCTAssertEqual(appStarts2Days.timePastFromInstallation(), .none)
        
        let day3 = Calendar.current.date(byAdding: .day, value: 3, to: installDate)!
        let appStarts3Days = AppStarts(timestamps: [installDate, day3])
        XCTAssertEqual(appStarts3Days.timePastFromInstallation(), .none)
        
        let day4 = Calendar.current.date(byAdding: .day, value: 4, to: installDate)!
        let appStarts4Days = AppStarts(timestamps: [installDate, day4])
        XCTAssertEqual(appStarts4Days.timePastFromInstallation(), .none)
        
        // Week 1 boundary tests
        let day6 = Calendar.current.date(byAdding: .day, value: 6, to: installDate)!
        let appStarts6Days = AppStarts(timestamps: [installDate, day6])
        XCTAssertEqual(appStarts6Days.timePastFromInstallation(), .none)
        
        let week1Date = Calendar.current.date(byAdding: .day, value: 7, to: installDate)!
        let appStarts1Week = AppStarts(timestamps: [installDate, week1Date])
        XCTAssertEqual(appStarts1Week.timePastFromInstallation(), .weeks(1))
        
        let day8 = Calendar.current.date(byAdding: .day, value: 8, to: installDate)!
        let appStarts8Days = AppStarts(timestamps: [installDate, day8])
        XCTAssertEqual(appStarts8Days.timePastFromInstallation(), .weeks(1))
        
        // Week 2 boundary tests
        let day13 = Calendar.current.date(byAdding: .day, value: 13, to: installDate)!
        let appStarts13Days = AppStarts(timestamps: [installDate, day13])
        XCTAssertEqual(appStarts13Days.timePastFromInstallation(), .weeks(1))
        
        let week2Date = Calendar.current.date(byAdding: .day, value: 14, to: installDate)!
        let appStarts2Weeks = AppStarts(timestamps: [installDate, week2Date])
        XCTAssertEqual(appStarts2Weeks.timePastFromInstallation(), .weeks(2))
        
        let day15 = Calendar.current.date(byAdding: .day, value: 15, to: installDate)!
        let appStarts15Days = AppStarts(timestamps: [installDate, day15])
        XCTAssertEqual(appStarts15Days.timePastFromInstallation(), .weeks(2))
        
        // Week 3 boundary tests
        let day20 = Calendar.current.date(byAdding: .day, value: 20, to: installDate)!
        let appStarts20Days = AppStarts(timestamps: [installDate, day20])
        XCTAssertEqual(appStarts20Days.timePastFromInstallation(), .weeks(2))
        
        let week3Date = Calendar.current.date(byAdding: .day, value: 21, to: installDate)!
        let appStarts3Weeks = AppStarts(timestamps: [installDate, week3Date])
        XCTAssertEqual(appStarts3Weeks.timePastFromInstallation(), .weeks(3))
        
        let day22 = Calendar.current.date(byAdding: .day, value: 22, to: installDate)!
        let appStarts22Days = AppStarts(timestamps: [installDate, day22])
        XCTAssertEqual(appStarts22Days.timePastFromInstallation(), .weeks(3))
        
        // Week 4 = Month 1 boundary tests (28 days)
        let day27 = Calendar.current.date(byAdding: .day, value: 27, to: installDate)!
        let appStarts27Days = AppStarts(timestamps: [installDate, day27])
        XCTAssertEqual(appStarts27Days.timePastFromInstallation(), .weeks(3))
        
        let month1Date = Calendar.current.date(byAdding: .day, value: 28, to: installDate)!
        let appStarts1Month = AppStarts(timestamps: [installDate, month1Date])
        XCTAssertEqual(appStarts1Month.timePastFromInstallation(), .months(1))
        
        let day29 = Calendar.current.date(byAdding: .day, value: 29, to: installDate)!
        let appStarts29Days = AppStarts(timestamps: [installDate, day29])
        XCTAssertEqual(appStarts29Days.timePastFromInstallation(), .months(1))

        // Month 2 boundary tests (56 days)
        let day55 = Calendar.current.date(byAdding: .day, value: 55, to: installDate)!
        let appStarts55Days = AppStarts(timestamps: [installDate, day55])
        XCTAssertEqual(appStarts55Days.timePastFromInstallation(), .months(1))

        let week8Date = Calendar.current.date(byAdding: .day, value: 56, to: installDate)!
        let appStarts8Weeks = AppStarts(timestamps: [installDate, week8Date])
        XCTAssertEqual(appStarts8Weeks.timePastFromInstallation(), .months(2))
        
        let day57 = Calendar.current.date(byAdding: .day, value: 57, to: installDate)!
        let appStarts57Days = AppStarts(timestamps: [installDate, day57])
        XCTAssertEqual(appStarts57Days.timePastFromInstallation(), .months(2))
        
        // Week 16 = Month 4 boundary tests (112 days)
        let day111 = Calendar.current.date(byAdding: .day, value: 111, to: installDate)!
        let appStarts111Days = AppStarts(timestamps: [installDate, day111])
        XCTAssertEqual(appStarts111Days.timePastFromInstallation(), .months(3))
        
        let month4Date = Calendar.current.date(byAdding: .day, value: 112, to: installDate)!
        let appStarts4Months = AppStarts(timestamps: [installDate, month4Date])
        XCTAssertEqual(appStarts4Months.timePastFromInstallation(), .months(4))
        
        let day113 = Calendar.current.date(byAdding: .day, value: 113, to: installDate)!
        let appStarts113Days = AppStarts(timestamps: [installDate, day113])
        XCTAssertEqual(appStarts113Days.timePastFromInstallation(), .months(4))
    }
}

// MARK: - AttributionDataStorage Tests

extension AppStartsTests {
    
    func testAttributionDataStorage_setAndGet_emptyAppStarts() {
        let storage = AttributionDataStorage(userDefaults: userDefaults)
        let appStarts = AppStarts(timestamps: [])
        
        storage.appStarts = appStarts
        
        let retrieved = storage.appStarts
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.timestamps.count, 0)
    }
    
    func testAttributionDataStorage_setAndGet_withTimestamps() {
        let storage = AttributionDataStorage(userDefaults: userDefaults)
        let date1 = testDate
        let date2 = Calendar.current.date(byAdding: .day, value: 7, to: date1)!
        let appStarts = AppStarts(timestamps: [date1, date2])
        
        storage.appStarts = appStarts
        
        let retrieved = storage.appStarts
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved!.timestamps.count, 2)
        XCTAssertEqual(retrieved!.timestamps[0].timeIntervalSince1970, date1.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(retrieved!.timestamps[1].timeIntervalSince1970, date2.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testAttributionDataStorage_get_nonExistentData_returnsNil() {
        let storage = AttributionDataStorage(userDefaults: userDefaults)
        XCTAssertNil(storage.appStarts)
    }
    
    func testAttributionDataStorage_setNil() {
        let storage = AttributionDataStorage(userDefaults: userDefaults)
        let appStarts = AppStarts(timestamps: [testDate])
        
        storage.appStarts = appStarts
        XCTAssertNotNil(storage.appStarts)
        
        storage.appStarts = nil
        XCTAssertNil(storage.appStarts)
    }
    
    func testAttributionDataStorage_storageKeyRawValue() {
        XCTAssertEqual(AttributionDataStorage.StorageKey.startTimeStamps.rawValue, "startTimeStamps")
    }
}

// MARK: - AttributionDataStorage Encoding/Decoding Tests

extension AppStartsTests {
    
    func testAttributionDataStorage_encode_decode_emptyAppStarts() {
        let storage = AttributionDataStorage(userDefaults: userDefaults)
        let appStarts = AppStarts(timestamps: [])
        
        storage.encode(appStarts, to: userDefaults, key: .startTimeStamps)
        
        let decoded: AppStarts? = storage.decode(from: userDefaults, key: .startTimeStamps)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.timestamps.count, 0)
    }
    
    func testAttributionDataStorage_encode_decode_withTimestamps() {
        let storage = AttributionDataStorage(userDefaults: userDefaults)
        let date1 = testDate
        let date2 = Calendar.current.date(byAdding: .day, value: 7, to: date1)!
        let appStarts = AppStarts(timestamps: [date1, date2])
        
        storage.encode(appStarts, to: userDefaults, key: .startTimeStamps)
        
        let decoded: AppStarts? = storage.decode(from: userDefaults, key: .startTimeStamps)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.timestamps.count, 2)
        XCTAssertEqual(decoded!.timestamps[0].timeIntervalSince1970, date1.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(decoded!.timestamps[1].timeIntervalSince1970, date2.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testAttributionDataStorage_decode_nonExistentKey_returnsNil() {
        let storage = AttributionDataStorage(userDefaults: userDefaults)
        let decoded: AppStarts? = storage.decode(from: userDefaults, key: .startTimeStamps)
        XCTAssertNil(decoded)
    }
    
    func testAttributionDataStorage_decode_invalidData_returnsNil() {
        let storage = AttributionDataStorage(userDefaults: userDefaults)
        userDefaults.set("invalid_data", forKey: AttributionDataStorage.StorageKey.startTimeStamps.rawValue)
        let decoded: AppStarts? = storage.decode(from: userDefaults, key: .startTimeStamps)
        XCTAssertNil(decoded)
    }
}

// MARK: - AppStarts Functionality Tests

extension AppStartsTests {
    
    func testAppendTimestamp() {
        var appStarts = AppStarts(timestamps: [])
        let date = testDate
        
        appStarts.append(timestamp: date)
        
        XCTAssertEqual(appStarts.timestamps.count, 1)
        XCTAssertEqual(appStarts.timestamps[0].timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testMultipleTimestamps_usesFirstAndLast() {
        let installDate = testDate
        let middleDate = Calendar.current.date(byAdding: .day, value: 10, to: installDate)!
        let lastDate = Calendar.current.date(byAdding: .day, value: 21, to: installDate)!
        
        let appStarts = AppStarts(timestamps: [installDate, middleDate, lastDate])
        
        XCTAssertEqual(appStarts.timePastFromInstallation(), .weeks(3))
    }
}

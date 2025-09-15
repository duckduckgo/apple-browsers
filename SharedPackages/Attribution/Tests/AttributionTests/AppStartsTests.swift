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
    
    func testTimePeriodLogic_installWeek() {
        let installDate = testDate
        let appStartDate = Calendar.current.date(byAdding: .day, value: 3, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, appStartDate])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .none)
    }
    
    func testTimePeriodLogic_week1() {
        let installDate = testDate
        let week1Date = Calendar.current.date(byAdding: .day, value: 7, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, week1Date])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .weeks(1))
    }
    
    func testTimePeriodLogic_week2() {
        let installDate = testDate
        let week2Date = Calendar.current.date(byAdding: .day, value: 14, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, week2Date])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .weeks(2))
    }
    
    func testTimePeriodLogic_week3() {
        let installDate = testDate
        let week3Date = Calendar.current.date(byAdding: .day, value: 21, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, week3Date])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .weeks(3))
    }
    
    func testTimePeriodLogic_week4_returnsMonth1() {
        let installDate = testDate
        let week4Date = Calendar.current.date(byAdding: .day, value: 28, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, week4Date])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .months(1))
    }
    
    func testTimePeriodLogic_week5to7_returnsMonth2() {
        let installDate = testDate
        
        let week5Date = Calendar.current.date(byAdding: .day, value: 35, to: installDate)!
        let appStarts5 = AppStarts(timestamps: [installDate, week5Date])
        XCTAssertEqual(appStarts5.timePastFromInstallation(), .months(2))

        let week6Date = Calendar.current.date(byAdding: .day, value: 42, to: installDate)!
        let appStarts6 = AppStarts(timestamps: [installDate, week6Date])
        XCTAssertEqual(appStarts6.timePastFromInstallation(), .months(2))

        let week7Date = Calendar.current.date(byAdding: .day, value: 49, to: installDate)!
        let appStarts7 = AppStarts(timestamps: [installDate, week7Date])
        XCTAssertEqual(appStarts7.timePastFromInstallation(), .months(2))
    }
    
    func testTimePeriodLogic_week8_returnsMonth2() {
        let installDate = testDate
        let week8Date = Calendar.current.date(byAdding: .day, value: 56, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, week8Date])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .months(2))
    }
    
    func testTimePeriodLogic_week20_returnsMonth5() {
        let installDate = testDate
        let week20Date = Calendar.current.date(byAdding: .day, value: 140, to: installDate)!
        let appStarts = AppStarts(timestamps: [installDate, week20Date])
        XCTAssertEqual(appStarts.timePastFromInstallation(), .months(5))
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

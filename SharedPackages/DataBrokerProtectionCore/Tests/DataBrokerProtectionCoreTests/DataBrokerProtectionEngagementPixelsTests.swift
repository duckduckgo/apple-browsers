//
//  DataBrokerProtectionEngagementPixelsTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Foundation
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class DataBrokerProtectionEngagementPixelsTests: XCTestCase {

    private let database = MockDatabase()
    private let repository = MockDataBrokerProtectionEngagementPixelsRepository()
    private let handler = MockDataBrokerProtectionPixelsHandler()

    private var fakeProfile: DataBrokerProtectionProfile {
        let name = DataBrokerProtectionProfile.Name(firstName: "John", lastName: "Doe")
        let address = DataBrokerProtectionProfile.Address(city: "City", state: "State")

        return DataBrokerProtectionProfile(names: [name], addresses: [address], phones: [String](), birthYear: 1900)
    }

    override func tearDown() {
        database.clear()
        repository.clear()
        handler.clear()
    }

    // MARK: - Activity gate

    func testWhenThereIsNoProfile_thenNoEngagementPixelIsFired() {
        seedScanCompletedDaysAgo(0, currentDate: Date())
        database.setFetchedProfile(nil)
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: Date())

        XCTAssertFalse(repository.wasDailyPixelSent)
        XCTAssertFalse(repository.wasWeeklyPixelSent)
        XCTAssertFalse(repository.wasMonthlyPixelSent)
        XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.isEmpty)
    }

    func testWhenNoScanHasFinished_thenNoEngagementPixelIsFired() {
        seedScanCompletedDaysAgo(nil, currentDate: Date())
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: Date())

        XCTAssertFalse(repository.wasDailyPixelSent)
        XCTAssertFalse(repository.wasWeeklyPixelSent)
        XCTAssertFalse(repository.wasMonthlyPixelSent)
        XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.isEmpty)
    }

    // MARK: - DAU

    func testWhenLatestDailyPixelIsNilAndScanFinishedToday_thenWeFireDailyPixel() {
        let now = dateFromString("2024-02-21")
        seedScanCompletedDaysAgo(0, currentDate: now)
        repository.setLatestDailyPixel = nil
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertTrue(wasPixelFired(.dailyActiveUser(isAuthenticated: true, needBackgroundAppRefresh: nil, isFreeScan: false)))
        XCTAssertTrue(repository.wasDailyPixelSent)
    }

    func testWhenCurrentDayIsDifferentToLatestDailyPixelAndScanFinishedRecently_thenWeFireDailyPixel() {
        let now = dateFromString("2024-02-21")
        seedScanCompletedDaysAgo(0, currentDate: now)
        repository.setLatestDailyPixel = dateFromString("2024-02-20")
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertTrue(wasPixelFired(.dailyActiveUser(isAuthenticated: true, needBackgroundAppRefresh: nil, isFreeScan: false)))
        XCTAssertTrue(repository.wasDailyPixelSent)
    }

    func testWhenCurrentDayIsEqualToLatestDailyPixel_thenWeDoNotFireDailyPixel() {
        let now = Date()
        seedScanCompletedDaysAgo(0, currentDate: now)
        repository.setLatestDailyPixel = now
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertFalse(wasPixelFired(.dailyActiveUser(isAuthenticated: true, needBackgroundAppRefresh: nil, isFreeScan: false)))
        XCTAssertFalse(repository.wasDailyPixelSent)
    }

    func testWhenTimeElapsedButLastScanFinishedTooLongAgo_thenWeDoNotFireDailyPixel() {
        let now = dateFromString("2024-02-21")
        seedScanCompletedDaysAgo(2, currentDate: now)
        repository.setLatestDailyPixel = nil
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertFalse(wasPixelFired(.dailyActiveUser(isAuthenticated: true, needBackgroundAppRefresh: nil, isFreeScan: false)))
        XCTAssertFalse(repository.wasDailyPixelSent)
    }

    // MARK: - WAU

    func testWhenLatestWeeklyPixelIsNilAndScanFinishedThisWeek_thenWeFireWeeklyPixel() {
        let now = dateFromString("2024-02-21")
        seedScanCompletedDaysAgo(3, currentDate: now)
        repository.setLatestWeeklyPixel = nil
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertTrue(wasPixelFired(.weeklyActiveUser(isAuthenticated: true, isFreeScan: false)))
        XCTAssertTrue(repository.wasWeeklyPixelSent)
    }

    func testWhenCurrentDayIsSevenDatesEqualOrGreaterThanLatestWeeklyAndScanFinishedRecently_thenWeFireWeeklyPixel() {
        let now = dateFromString("2024-02-27")
        seedScanCompletedDaysAgo(1, currentDate: now)
        repository.setLatestWeeklyPixel = dateFromString("2024-02-20")
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertTrue(wasPixelFired(.weeklyActiveUser(isAuthenticated: true, isFreeScan: false)))
        XCTAssertTrue(repository.wasWeeklyPixelSent)
    }

    func testWhenCurrentDayIsSevenDatesLessThanLatestWeekly_thenWeDoNotFireWeeklyPixel() {
        let now = dateFromString("2024-02-26")
        seedScanCompletedDaysAgo(0, currentDate: now)
        repository.setLatestWeeklyPixel = dateFromString("2024-02-20")
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertFalse(wasPixelFired(.weeklyActiveUser(isAuthenticated: true, isFreeScan: false)))
        XCTAssertFalse(repository.wasWeeklyPixelSent)
    }

    func testWhenTimeElapsedButLastScanFinishedMoreThan7DaysAgo_thenWeDoNotFireWeeklyPixel() {
        let now = dateFromString("2024-02-27")
        seedScanCompletedDaysAgo(8, currentDate: now)
        repository.setLatestWeeklyPixel = dateFromString("2024-02-20")
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertFalse(wasPixelFired(.weeklyActiveUser(isAuthenticated: true, isFreeScan: false)))
        XCTAssertFalse(repository.wasWeeklyPixelSent)
    }

    // MARK: - MAU

    func testWhenLatestMonthlyPixelIsNilAndScanFinishedThisMonth_thenWeFireMonthlyPixel() {
        let now = dateFromString("2024-02-21")
        seedScanCompletedDaysAgo(10, currentDate: now)
        repository.setLatestMonthlyPixel = nil
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertTrue(wasPixelFired(.monthlyActiveUser(isAuthenticated: true, isFreeScan: false)))
        XCTAssertTrue(repository.wasMonthlyPixelSent)
    }

    func testWhenCurrentMonthIs28DatesGreaterOrEqualThanLatestMonthlyPixelAndScanFinishedRecently_thenWeFireMonthlyPixel() {
        let now = dateFromString("2024-03-19")
        seedScanCompletedDaysAgo(1, currentDate: now)
        repository.setLatestMonthlyPixel = dateFromString("2024-02-20")
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertTrue(wasPixelFired(.monthlyActiveUser(isAuthenticated: true, isFreeScan: false)))
        XCTAssertTrue(repository.wasMonthlyPixelSent)
    }

    func testWhenCurrentIsNot28DatesGreaterOrEqualToLatestMonthlyPixel_thenWeDoNotFireMonthlyPixel() {
        let now = dateFromString("2024-03-18")
        seedScanCompletedDaysAgo(0, currentDate: now)
        repository.setLatestMonthlyPixel = dateFromString("2024-02-20")
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertFalse(wasPixelFired(.monthlyActiveUser(isAuthenticated: true, isFreeScan: false)))
        XCTAssertFalse(repository.wasMonthlyPixelSent)
    }

    func testWhenTimeElapsedButLastScanFinishedMoreThan28DaysAgo_thenWeDoNotFireMonthlyPixel() {
        let now = dateFromString("2024-03-19")
        seedScanCompletedDaysAgo(29, currentDate: now)
        repository.setLatestMonthlyPixel = dateFromString("2024-02-20")
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        XCTAssertFalse(wasPixelFired(.monthlyActiveUser(isAuthenticated: true, isFreeScan: false)))
        XCTAssertFalse(repository.wasMonthlyPixelSent)
    }

    // MARK: - Free scan parameter

    func testWhenUserIsAuthenticated_thenEngagementPixelsIncludeFreeScanFalse() {
        let now = Date()
        seedScanCompletedDaysAgo(0, currentDate: now)
        repository.setLatestDailyPixel = nil
        repository.setLatestWeeklyPixel = nil
        repository.setLatestMonthlyPixel = nil
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: true, currentDate: now)

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        XCTAssertFalse(firedPixels.isEmpty)
        for pixel in firedPixels {
            XCTAssertEqual(pixel.parameters?["free_scan"], "false", "Expected free_scan=false for authenticated user on pixel \(pixel.name)")
        }
    }

    func testWhenUserIsNotAuthenticated_thenEngagementPixelsIncludeFreeScanTrue() {
        let now = Date()
        seedScanCompletedDaysAgo(0, currentDate: now)
        repository.setLatestDailyPixel = nil
        repository.setLatestWeeklyPixel = nil
        repository.setLatestMonthlyPixel = nil
        let sut = DataBrokerProtectionEngagementPixels(database: database, handler: handler, repository: repository)

        sut.fireEngagementPixel(isAuthenticated: false, currentDate: now)

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        XCTAssertFalse(firedPixels.isEmpty)
        for pixel in firedPixels {
            XCTAssertEqual(pixel.parameters?["free_scan"], "true", "Expected free_scan=true for unauthenticated user on pixel \(pixel.name)")
        }
    }

    // MARK: - Helpers

    private func seedScanCompletedDaysAgo(_ daysAgo: Int?, currentDate: Date) {
        database.setFetchedProfile(fakeProfile)
        if let daysAgo {
            database.mostRecentFinishedScanEventDateToReturn = Calendar.current.date(byAdding: .day, value: -daysAgo, to: currentDate)!
        } else {
            database.mostRecentFinishedScanEventDateToReturn = nil
        }
    }

    private func wasPixelFired(_ pixel: DataBrokerProtectionSharedPixels) -> Bool {
        MockDataBrokerProtectionPixelsHandler.lastPixelsFired.contains(where: { $0.name == pixel.name })
    }

    private func dateFromString(_ string: String) -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: string)!
    }
}

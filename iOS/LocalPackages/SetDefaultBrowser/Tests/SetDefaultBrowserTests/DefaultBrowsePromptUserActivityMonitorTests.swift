//
//  DefaultBrowsePromptUserActivityMonitor.swift
//  DuckDuckGo
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

import Foundation
import XCTest
import SetDefaultBrowserTestSupport
@testable import SetDefaultBrowserCore

@MainActor
// https://github.com/swiftlang/swift/issues/75815
final class DefaultBrowsePromptUserActivityMonitorTests: XCTestCase, Sendable {
    private static let today = Date(timeIntervalSince1970: 1750845600) // Wednesday, 25 June 2025 10:00:00 AM
    private static let maxDaysToKeep: Int = 10

    private var storeMock: MockDefaultBrowsePromptUserActivityStore!
    private var dateProvideMock: MockDateProvider!
    private var sut: DefaultBrowsePromptUserActivityMonitor!

    override func setUp() async throws {
        try await super.setUp()

        storeMock = MockDefaultBrowsePromptUserActivityStore()
        dateProvideMock = MockDateProvider()
        sut = DefaultBrowsePromptUserActivityMonitor(store: storeMock, maxDaysToKeep: Self.maxDaysToKeep, dateProvider: dateProvideMock.getDate)
    }

    override func tearDown() async throws {
        storeMock = nil
        dateProvideMock = nil
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Did Become Active Notification

    func testWhenDidBecomeActiveIsCalled_AndTodayActivityIsNotRecorded_ThenAskStoreToUpdateActivity() {
        // GIVEN
        let expectation = self.expectation(forNotification: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(storeMock.didCallSaveActivity)

        // WHEN
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        // THEN
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(storeMock.didCallSaveActivity)
    }

    func testWhenDidBecomeActiveIsCalled_AndTodayActivityIsNotRecorded_ThenAddTodayToActiveDates() {
        // GIVEN
        storeMock.activityToReturn = .init(activeDates: [Self.today], lastActiveDate: Self.today)
        let tomorrow = Self.today.advanced(by: .days(1))
        dateProvideMock.setNowDate(tomorrow)
        let expectation = self.expectation(forNotification: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(storeMock.didCallSaveActivity)
        XCTAssertNil(storeMock.capturedSaveActivity)

        // WHEN
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        // THEN
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(storeMock.didCallSaveActivity)
        XCTAssertEqual(storeMock.capturedSaveActivity?.activeDates.sorted(by: <), [Self.today, tomorrow])
        XCTAssertEqual(storeMock.capturedSaveActivity?.lastActiveDate, tomorrow)
    }

    func testWhenDidBecomeActiveIsCalled_AndTodayActivityIsRecorded_ThenDoNotAskStoreToUpdateActivity() {
        // GIVEN
        dateProvideMock.setNowDate(Self.today)
        dateProvideMock.advanceBy(2 * 60 * 60) // Advance by two hours
        storeMock.activityToReturn = .init(lastActiveDate: Self.today)
        let expectation = self.expectation(forNotification: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(storeMock.didCallSaveActivity)
        XCTAssertNil(storeMock.capturedSaveActivity)

        // WHEN
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        // THEN
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(storeMock.didCallSaveActivity)
        XCTAssertNil(storeMock.capturedSaveActivity)
    }

    func testWhenMaxNumberOfActiveDaysIsReached_ThenRemoveExtraOldDates() throws {
        // GIVEN
        let expectation = self.expectation(forNotification: UIApplication.didBecomeActiveNotification, object: nil)
        // Creates 10 days in the future
        let dates = (0..<Self.maxDaysToKeep).map { index in
            Self.today.advanced(by: .days(index))
        }
        let lastActivityDate = try XCTUnwrap(dates.last)
        // Advance to 11th days so that when we record the activity the recorded activity is now 11 and the logic should cap the array to `maxDaysToKeep` value.
        dateProvideMock.setNowDate(lastActivityDate.advanced(by: .days(1)))
        storeMock.activityToReturn = .init(activeDates: Set(dates), lastActiveDate: lastActivityDate)
        XCTAssertFalse(storeMock.didCallSaveActivity)

        // WHEN
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        // THEN
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(storeMock.didCallSaveActivity)
        XCTAssertEqual(storeMock.capturedSaveActivity?.activeDates.count, Self.maxDaysToKeep)
        XCTAssertEqual(storeMock.capturedSaveActivity?.activeDates.sorted(by: <).first, Self.today.advanced(by: .days(1)))
    }

    // MARK: - Number of Active Days

    func testWhenNumberOfActiveDaysIsCalledThenReturnNumberOfActiveDaysSinceToday() throws {
        // GIVEN
        let dates = (0..<Self.maxDaysToKeep).map { index in
            Self.today.advanced(by: .days(index))
        }
        let lastActivityDate = try XCTUnwrap(dates.last)
        storeMock.activityToReturn = .init(activeDates: Set(dates), lastActiveDate: lastActivityDate)

        // Sort the dates from the greatest to lowest. Checking the number of active days to the greatest to the lowest is equal to index + 1
        dates.sorted(by: >).enumerated().forEach { index, date in
            // WHEN
            let result = sut.numberOfActiveDays(since: date)

            // THEN
            XCTAssertEqual(result, index+1)
        }
    }

    // MARK: - Reset Number of Active Days

    func testWhenResetNumberOfActiveDaysIsCalledThenAskStoreToDeleteActivity() {
        // GIVEN
        XCTAssertFalse(storeMock.didCallDeleteActivity)

        // WHEN
        sut.resetNumberOfActiveDays()

        // THEN
        XCTAssertTrue(storeMock.didCallDeleteActivity)
    }

}

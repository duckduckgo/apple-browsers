//
//  DefaultBrowsePromptUserActivityMonitorTests.swift
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
        sut = DefaultBrowsePromptUserActivityMonitor(store: storeMock, dateProvider: dateProvideMock.getDate)
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

    func testWhenDidBecomeActiveIsCalled_AndTodayActivityIsNotRecorded_ThenIncrementNumberOfActiveDays() {
        // GIVEN
        storeMock.activityToReturn = .init(numberOfActiveDays: 1, lastActiveDate: Self.today)
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
        XCTAssertEqual(storeMock.capturedSaveActivity?.numberOfActiveDays, 2)
        XCTAssertEqual(storeMock.capturedSaveActivity?.lastActiveDate, Calendar.current.startOfDay(for: tomorrow))
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

    // MARK: - Number of Active Days

    func testWhenNumberOfActiveDaysIsCalledThenReturnNumberOfActiveDays() throws {
        // GIVEN
        let lastActivityDate = Self.today.advanced(by: .days(10))
        storeMock.activityToReturn = .init(numberOfActiveDays: 10, lastActiveDate: lastActivityDate)

        // WHEN
        let result = sut.numberOfActiveDays()

        // THEN
        XCTAssertEqual(result, 10)
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

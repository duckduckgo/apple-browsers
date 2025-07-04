//
//  DefaultBrowserPromptUserActivityManagerTests.swift
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
import Testing
import SetDefaultBrowserTestSupport
import SetDefaultBrowserCore
@testable import DuckDuckGo

@MainActor
@Suite("Default Browser Prompt - User Activity Manager")
struct DefaultBrowserPromptUserActivityMonitorTests {
    private static let today = Date(timeIntervalSince1970: 1750845600) // Wednesday, 25 June 2025 10:00:00 AM
    private static let maxDaysToKeep: Int = 10

    private var storeMock: MockDefaultBrowserPromptUserActivityStore
    private var dateProviderMock: TimeTraveller
    private var sut: DefaultBrowserPromptUserActivityManager

    init() {
        storeMock = MockDefaultBrowserPromptUserActivityStore()
        dateProviderMock = TimeTraveller()
        sut = DefaultBrowserPromptUserActivityManager(store: storeMock, dateProvider: dateProviderMock.getDate)
    }

    // MARK: - Record Activity

    @Test("Check Activity Is Stored")
    func testWhenRecordActivityIsCalled_AndTodayActivityIsNotRecorded_ThenAskStoreToUpdateActivity() {
        // GIVEN
        #expect(!storeMock.didCallSaveActivity)

        // WHEN
        sut.recordActivity()

        // THEN
        #expect(storeMock.didCallSaveActivity)
    }

    @Test("Check Activity Counter Is Increased And Last Activity Date Is Updated When Activity Is Stored")
    func testWhenRecordActivityIsCalled_AndTodayActivityIsNotRecorded_ThenIncrementNumberOfActiveDays() {
        // GIVEN
        storeMock.activityToReturn = .init(numberOfActiveDays: 1, lastActiveDate: Self.today)
        let tomorrow = Self.today.advanced(by: .days(1))
        dateProviderMock.setNowDate(tomorrow)
        #expect(!storeMock.didCallSaveActivity)
        #expect(storeMock.capturedSaveActivity == nil)

        // WHEN
        sut.recordActivity()

        // THEN
        #expect(storeMock.didCallSaveActivity)
        #expect(storeMock.capturedSaveActivity?.numberOfActiveDays == 2)
        #expect(storeMock.capturedSaveActivity?.lastActiveDate == Calendar.current.startOfDay(for: tomorrow))
    }

    @Test("Check Activity Is Not Updated When a Record For The Same Day Already Exists")
    func testWhenRecordActivityIsCalled_AndTodayActivityIsRecorded_ThenDoNotAskStoreToUpdateActivity() {
        // GIVEN
        dateProviderMock.setNowDate(Self.today)
        dateProviderMock.advanceBy(2 * 60 * 60) // Advance by two hours
        storeMock.activityToReturn = .init(lastActiveDate: Self.today)
        #expect(!storeMock.didCallSaveActivity)
        #expect(storeMock.capturedSaveActivity == nil)

        // WHEN
        sut.recordActivity()

        // THEN
        #expect(!storeMock.didCallSaveActivity)
        #expect(storeMock.capturedSaveActivity == nil)
    }

    // MARK: - Number of Active Days

    @Test("Check Correct Number Of Active Days Is Returned")
    func testWhenNumberOfActiveDaysIsCalledThenReturnNumberOfActiveDays() {
        // GIVEN
        let lastActivityDate = Self.today.advanced(by: .days(10))
        storeMock.activityToReturn = .init(numberOfActiveDays: 10, lastActiveDate: lastActivityDate)

        // WHEN
        let result = sut.numberOfActiveDays()

        // THEN
        #expect(result == 10)
    }

    // MARK: - Reset Number of Active Days

    @Test("Check Number Of Active Days Is Reset")
    func testWhenResetNumberOfActiveDaysIsCalledThenAskStoreToDeleteActivity() {
        // GIVEN
        storeMock.activityToReturn = .init(numberOfActiveDays: 10, lastActiveDate: Self.today)
        #expect(!storeMock.didCallSaveActivity)

        // WHEN
        sut.resetNumberOfActiveDays()

        // THEN
        #expect(storeMock.didCallSaveActivity)
        #expect(storeMock.capturedSaveActivity?.lastActiveDate == Self.today)
        #expect(storeMock.capturedSaveActivity?.numberOfActiveDays == 0)
    }

}

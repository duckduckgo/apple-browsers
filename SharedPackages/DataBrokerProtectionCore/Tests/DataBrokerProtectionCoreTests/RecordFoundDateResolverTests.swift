//
//  RecordFoundDateResolverTests.swift
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
@testable import DataBrokerProtectionCore
@testable import DataBrokerProtectionCoreTestsUtils

final class RecordFoundDateResolverTests: XCTestCase {

    private var mockDatabase: MockDatabase!

    override func setUp() {
        super.setUp()
        mockDatabase = MockDatabase()
    }

    override func tearDown() {
        mockDatabase = nil
        super.tearDown()
    }

    func testUsesBrokerProfileQueryDataWhenProvided() {
        let now = Date()
        let historyEvents = [
            HistoryEvent(extractedProfileId: 1, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: now)
        ]
        mockDatabase.optOutToReturn = nil

        let brokerQueryData = BrokerProfileQueryData.mock(
            optOutJobData: [OptOutJobData(
                brokerId: 1,
                profileQueryId: 2,
                createdDate: .distantPast,
                preferredRunDate: nil,
                historyEvents: historyEvents,
                lastRunDate: nil,
                attemptCount: 0,
                submittedSuccessfullyDate: nil,
                extractedProfile: .mockWithoutRemovedDate
            )]
        )

        let result = RecordFoundDateResolver.resolve(brokerQueryProfileData: brokerQueryData,
                                                     repository: mockDatabase,
                                                     brokerId: 1,
                                                     profileQueryId: 2,
                                                     extractedProfileId: 1)
        XCTAssertEqual(result, now)
    }

    func testUsesFetchedOptOutOtherwise() {
        let now = Date()
        let historyEvents = [
            HistoryEvent(extractedProfileId: 1, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: now)
        ]
        mockDatabase.optOutToReturn = OptOutJobData(
            brokerId: 1,
            profileQueryId: 2,
            createdDate: .distantPast,
            preferredRunDate: nil,
            historyEvents: historyEvents,
            lastRunDate: nil,
            attemptCount: 0,
            submittedSuccessfullyDate: nil,
            extractedProfile: .mockWithoutRemovedDate
        )

        let result = RecordFoundDateResolver.resolve(repository: mockDatabase,
                                                     brokerId: 1,
                                                     profileQueryId: 2,
                                                     extractedProfileId: 1)

        XCTAssertEqual(result, now)
    }

    func testFallsBackToFirstFoundDateInHistoryEvents() {
        let invalidDate = Date(timeIntervalSince1970: 0)
        let matchDate = Date(timeIntervalSince1970: 5_000)
        let laterMatchDate = Date(timeIntervalSince1970: 10_000)

        let events = [
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: laterMatchDate),
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: matchDate)
        ]

        mockDatabase.optOutToReturn = OptOutJobData(
            brokerId: 1,
            profileQueryId: 2,
            createdDate: invalidDate,
            preferredRunDate: nil,
            historyEvents: events,
            lastRunDate: nil,
            attemptCount: 0,
            submittedSuccessfullyDate: nil,
            extractedProfile: .mockWithoutRemovedDate
        )

        let result = RecordFoundDateResolver.resolve(repository: mockDatabase,
                                                     brokerId: 1,
                                                     profileQueryId: 2,
                                                     extractedProfileId: 3)

        XCTAssertEqual(result, matchDate)
    }

    func testFallsBackToFirstFoundDateInRepository() throws {
        let events = [
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .reAppearence, date: .now)
        ]
        mockDatabase.optOutToReturn = OptOutJobData(
            brokerId: 1,
            profileQueryId: 2,
            createdDate: Date(timeIntervalSince1970: 0),
            preferredRunDate: nil,
            historyEvents: events,
            lastRunDate: nil,
            attemptCount: 0,
            submittedSuccessfullyDate: nil,
            extractedProfile: .mockWithoutRemovedDate
        )

        let repositoryDate = Date(timeIntervalSince1970: 20_000)
        try mockDatabase.add(
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: repositoryDate)
        )

        let result = RecordFoundDateResolver.resolve(repository: mockDatabase,
                                                     brokerId: 1,
                                                     profileQueryId: 2,
                                                     extractedProfileId: 3)

        XCTAssertEqual(result, repositoryDate)
    }

    func testWhenRecordReappearsAfterClearEventUsesSubsequentMatchDate() {
        let initialMatchDate = Date(timeIntervalSince1970: 1_000)
        let clearDate = Date(timeIntervalSince1970: 2_000)
        let reappearanceMatchDate = Date(timeIntervalSince1970: 3_000)

        let events = [
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: initialMatchDate),
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .optOutConfirmed, date: clearDate),
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: reappearanceMatchDate)
        ]

        mockDatabase.optOutToReturn = OptOutJobData(
            brokerId: 1,
            profileQueryId: 2,
            createdDate: Date(timeIntervalSince1970: 0),
            preferredRunDate: nil,
            historyEvents: events,
            lastRunDate: nil,
            attemptCount: 0,
            submittedSuccessfullyDate: nil,
            extractedProfile: .mockWithoutRemovedDate
        )

        let result = RecordFoundDateResolver.resolve(repository: mockDatabase,
                                                     brokerId: 1,
                                                     profileQueryId: 2,
                                                     extractedProfileId: 3)

        XCTAssertEqual(result, reappearanceMatchDate)
    }

    func testWhenClearEventWithoutSubsequentMatchReturnsFallback() {
        let initialMatchDate = Date(timeIntervalSince1970: 1_000)
        let clearDate = Date(timeIntervalSince1970: 2_000)
        let fallback = Date(timeIntervalSince1970: 9_999)

        let events = [
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: initialMatchDate),
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchRemovedByUser, date: clearDate)
        ]

        mockDatabase.optOutToReturn = OptOutJobData(
            brokerId: 1,
            profileQueryId: 2,
            createdDate: Date(timeIntervalSince1970: 0),
            preferredRunDate: nil,
            historyEvents: events,
            lastRunDate: nil,
            attemptCount: 0,
            submittedSuccessfullyDate: nil,
            extractedProfile: .mockWithoutRemovedDate
        )

        let result = RecordFoundDateResolver.resolve(repository: mockDatabase,
                                                     brokerId: 1,
                                                     profileQueryId: 2,
                                                     extractedProfileId: 3,
                                                     fallback: fallback)

        XCTAssertEqual(result, fallback)
    }

    func testWhenMultipleClearEventsUsesMatchAfterLatestClear() {
        let firstMatch = Date(timeIntervalSince1970: 1_000)
        let firstClear = Date(timeIntervalSince1970: 2_000)
        let secondMatch = Date(timeIntervalSince1970: 3_000)
        let secondClear = Date(timeIntervalSince1970: 4_000)
        let thirdMatch = Date(timeIntervalSince1970: 5_000)

        let events = [
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: firstMatch),
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .optOutConfirmed, date: firstClear),
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: secondMatch),
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchRemovedByUser, date: secondClear),
            HistoryEvent(extractedProfileId: 3, brokerId: 1, profileQueryId: 2, type: .matchesFound(count: 1), date: thirdMatch)
        ]

        mockDatabase.optOutToReturn = OptOutJobData(
            brokerId: 1,
            profileQueryId: 2,
            createdDate: Date(timeIntervalSince1970: 0),
            preferredRunDate: nil,
            historyEvents: events,
            lastRunDate: nil,
            attemptCount: 0,
            submittedSuccessfullyDate: nil,
            extractedProfile: .mockWithoutRemovedDate
        )

        let result = RecordFoundDateResolver.resolve(repository: mockDatabase,
                                                     brokerId: 1,
                                                     profileQueryId: 2,
                                                     extractedProfileId: 3)

        XCTAssertEqual(result, thirdMatch)
    }

    func testReturnsFallbackWhenNoDataAvailable() {
        mockDatabase.optOutToReturn = nil

        let fallback = Date(timeIntervalSince1970: 99_999)

        let result = RecordFoundDateResolver.resolve(repository: mockDatabase,
                                                     brokerId: 1,
                                                     profileQueryId: 2,
                                                     extractedProfileId: 3,
                                                     fallback: fallback)

        XCTAssertEqual(result, fallback)
    }
}

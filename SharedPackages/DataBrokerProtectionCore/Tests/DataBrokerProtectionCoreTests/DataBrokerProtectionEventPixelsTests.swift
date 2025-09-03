//
//  DataBrokerProtectionEventPixelsTests.swift
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

final class DataBrokerProtectionEventPixelsTests: XCTestCase {

    let database = MockDatabase()
    let repository = MockDataBrokerProtectionEventPixelsRepository()
    let handler = MockDataBrokerProtectionPixelsHandler()
    let calendar = Calendar.current
    let eightDaysSinceToday = Calendar.current.date(byAdding: .day, value: -8, to: Date())!

    override func tearDown() {
        handler.clear()
        repository.clear()
    }

    func testWhenFireNewMatchEventPixelIsCalled_thenCorrectPixelIsFired() {
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        sut.fireNewMatchEventPixel()

        XCTAssertEqual(
            MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last!.name,
            DataBrokerProtectionSharedPixels.scanningEventNewMatch.name
        )
    }

    func testWhenFireReappeareanceEventPixelIsCalled_thenCorrectPixelIsFired() {
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        sut.fireReappeareanceEventPixel()

        XCTAssertEqual(
            MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last!.name,
            DataBrokerProtectionSharedPixels.scanningEventReAppearance.name
        )
    }

    func testWhenReportWasFiredInTheLastWeek_thenWeDoNotFireWeeklyPixels() {
        repository.customGetLatestWeeklyPixel = Date().yesterday
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        sut.tryToFireWeeklyPixels()

        XCTAssertFalse(repository.wasMarkWeeklyPixelSentCalled)
    }

    func testWhenReportWasNotFiredInTheLastWeek_thenWeFireWeeklyPixels() {
        guard let eightDaysSinceToday = Calendar.current.date(byAdding: .day, value: -8, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        repository.customGetLatestWeeklyPixel = eightDaysSinceToday
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        sut.tryToFireWeeklyPixels()

        XCTAssertTrue(repository.wasMarkWeeklyPixelSentCalled)
    }

    func testWhenLastWeeklyPixelIsNil_thenWeFireWeeklyPixels() {
        repository.customGetLatestWeeklyPixel = nil
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        sut.tryToFireWeeklyPixels()

        XCTAssertTrue(repository.wasMarkWeeklyPixelSentCalled)
    }

    func testWhenReAppereanceOcurredInTheLastWeek_thenReAppereanceFlagIsTrue() {
        guard let sixDaysSinceToday = Calendar.current.date(byAdding: .day, value: -6, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        let reAppereanceThisWeekEvent = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .reAppearence, date: sixDaysSinceToday)
        let dataBrokerProfileQueryWithReAppereance: [BrokerProfileQueryData] = [
            .init(dataBroker: .mock,
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [reAppereanceThisWeekEvent]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueryWithReAppereance
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first!
        let hadReAppereance = weeklyReportScanningPixel.params!["had_re-appearance"]!

        XCTAssertEqual(hadReAppereance, "1")
    }

    func testWhenReAppereanceDidNotOcurrInTheLastWeek_thenReAppereanceFlagIsFalse() {
        guard let eighDaysSinceToday = Calendar.current.date(byAdding: .day, value: -8, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        let reAppereanceThisWeekEvent = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .reAppearence, date: eighDaysSinceToday)
        let dataBrokerProfileQueryWithReAppereance: [BrokerProfileQueryData] = [
            .init(dataBroker: .mock,
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [reAppereanceThisWeekEvent]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueryWithReAppereance
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first!
        let hadReAppereance = weeklyReportScanningPixel.params!["had_re-appearance"]!

        XCTAssertEqual(hadReAppereance, "0")
    }

    func testWhenNoMatchesHappendInTheLastWeek_thenHadNewMatchFlagIsFalse() {
        guard let eighDaysSinceToday = Calendar.current.date(byAdding: .day, value: -8, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        let newMatchesPriorToThisWeekEvent = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .matchesFound(count: 2), date: eighDaysSinceToday)
        let dataBrokerProfileQueryWithMatches: [BrokerProfileQueryData] = [
            .init(dataBroker: .mock,
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [newMatchesPriorToThisWeekEvent]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueryWithMatches
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first!
        let hadNewMatch = weeklyReportScanningPixel.params!["had_new_match"]!

        XCTAssertEqual(hadNewMatch, "0")
    }

    func testWhenMatchesHappendInTheLastWeek_thenHadNewMatchFlagIsTrue() {
        guard let sixDaysSinceToday = Calendar.current.date(byAdding: .day, value: -6, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        let newMatchesThisWeekEvent = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .matchesFound(count: 2), date: sixDaysSinceToday)
        let dataBrokerProfileQueryWithMatches: [BrokerProfileQueryData] = [
            .init(dataBroker: .mock,
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [newMatchesThisWeekEvent]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueryWithMatches
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first!
        let hadNewMatch = weeklyReportScanningPixel.params!["had_new_match"]!

        XCTAssertEqual(hadNewMatch, "1")
    }

    func testWhenNoRemovalsHappendInTheLastWeek_thenRemovalsCountIsZero() {
        guard let eighDaysSinceToday = Calendar.current.date(byAdding: .day, value: -8, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        let removalsPriorToThisWeekEvent = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutConfirmed, date: eighDaysSinceToday)
        let dataBrokerProfileQueryWithRemovals: [BrokerProfileQueryData] = [
            .init(dataBroker: .mock,
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [removalsPriorToThisWeekEvent]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueryWithRemovals
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first(where: { $0.name.contains("weekly-report_removals") })!
        let removals = weeklyReportScanningPixel.params!["removals"]!

        XCTAssertEqual("0", removals)
    }

    func testWhenRemovalsHappendInTheLastWeek_thenRemovalsCountIsCorrect() {
        guard let sixDaysSinceToday = Calendar.current.date(byAdding: .day, value: -6, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        let removalThisWeekEventOne = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutConfirmed, date: sixDaysSinceToday)
        let removalThisWeekEventTwo = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutConfirmed, date: sixDaysSinceToday)
        let dataBrokerProfileQueryWithRemovals: [BrokerProfileQueryData] = [
            .init(dataBroker: .mock,
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [removalThisWeekEventOne, removalThisWeekEventTwo]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueryWithRemovals
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first(where: { $0.name.contains("weekly-report_removals") })!
        let removals = weeklyReportScanningPixel.params!["removals"]!

        XCTAssertEqual("2", removals)
    }

    func testWhenNoHistoryEventsHappenedInTheLastWeek_thenBrokersScannedIsZero25Range() {
        guard let eighDaysSinceToday = Calendar.current.date(byAdding: .day, value: -8, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        let eventOne = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutStarted, date: eighDaysSinceToday)
        let eventTwo = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .error(error: .cancelled), date: eighDaysSinceToday)
        let eventThree = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: eighDaysSinceToday)
        let eventFour = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .noMatchFound, date: eighDaysSinceToday)
        let dataBrokerProfileQueries: [BrokerProfileQueryData] = [
            .init(dataBroker: .mock,
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventOne, eventTwo, eventThree, eventFour]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueries
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first!
        let scanCoverage = weeklyReportScanningPixel.params!["scan_coverage"]!

        XCTAssertEqual("0-25", scanCoverage)
    }

    func testWhenHistoryEventsHappenedInTheLastWeek_thenBrokersScannedIs2550Range() {
        guard let eighDaysSinceToday = Calendar.current.date(byAdding: .day, value: -8, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        guard let sixDaysSinceToday = Calendar.current.date(byAdding: .day, value: -6, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        let eventOne = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: eighDaysSinceToday)
        let eventTwo = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: sixDaysSinceToday)
        let dataBrokerProfileQueries: [BrokerProfileQueryData] = [
            .init(dataBroker: .mockWithURL("www.brokerone.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventOne])),
            .init(dataBroker: .mockWithURL("www.brokertwo.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventOne])),
            .init(dataBroker: .mockWithURL("www.brokerthree.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventOne])),
            .init(dataBroker: .mockWithURL("www.brokerfour.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventTwo]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueries
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first!
        let scanCoverage = weeklyReportScanningPixel.params!["scan_coverage"]!

        XCTAssertEqual("25-50", scanCoverage)
    }

    func testWhenHistoryEventsHappenedInTheLastWeek_thenBrokersScannedIs5075Range() {
        guard let eighDaysSinceToday = Calendar.current.date(byAdding: .day, value: -8, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        guard let sixDaysSinceToday = Calendar.current.date(byAdding: .day, value: -6, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        let eventOne = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: eighDaysSinceToday)
        let eventTwo = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: sixDaysSinceToday)
        let dataBrokerProfileQueries: [BrokerProfileQueryData] = [
            .init(dataBroker: .mockWithURL("www.brokerone.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventOne])),
            .init(dataBroker: .mockWithURL("www.brokertwo.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventOne])),
            .init(dataBroker: .mockWithURL("www.brokerthree.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventTwo])),
            .init(dataBroker: .mockWithURL("www.brokerfour.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventTwo]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueries
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first!
        let scanCoverage = weeklyReportScanningPixel.params!["scan_coverage"]!

        XCTAssertEqual("50-75", scanCoverage)
    }

    func testWhenHistoryEventsHappenedInTheLastWeek_thenBrokersScannedIs75100Range() {
        guard let eighDaysSinceToday = Calendar.current.date(byAdding: .day, value: -8, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        guard let sixDaysSinceToday = Calendar.current.date(byAdding: .day, value: -6, to: Date()) else {
            XCTFail("This should no throw")
            return
        }

        /*let eventOne*/ _ = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: eighDaysSinceToday)
        let eventTwo = HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: sixDaysSinceToday)
        let dataBrokerProfileQueries: [BrokerProfileQueryData] = [
            .init(dataBroker: .mockWithURL("www.brokerone.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventTwo])),
            .init(dataBroker: .mockWithURL("www.brokertwo.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventTwo])),
            .init(dataBroker: .mockWithURL("www.brokerthree.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventTwo])),
            .init(dataBroker: .mockWithURL("www.brokerfour.com"),
                  profileQuery: .mock,
                  scanJobData: .mockWith(historyEvents: [eventTwo]))
        ]
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        database.brokerProfileQueryDataToReturn = dataBrokerProfileQueries
        repository.customGetLatestWeeklyPixel = nil

        sut.tryToFireWeeklyPixels()

        let weeklyReportScanningPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first!
        let scanCoverage = weeklyReportScanningPixel.params!["scan_coverage"]!

        XCTAssertEqual("75-100", scanCoverage)
    }

    func testWeeklyOptOuts_whenBrokerProfileQueriesHasMixedCreatedDates_thenFilteredCorrectly() {
        // Given
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)
        let extractedProfile = ExtractedProfile.mockWithoutRemovedDate

        let optOutShouldNotInclude1 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -14, to: Date.now)!)
        let optOutShouldNotInclude2 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -21, to: Date.now)!)
        let optOutShouldNotInclude3 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -8, to: Date.now)!)
        let optOutShouldNotInclude4 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -17, to: Date.now)!)
        let optOutShouldNotInclude5 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -10, to: Date.now)!)
        let optOutShouldInclude1 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -6, to: Date.now)!)
        let optOutShouldInclude2 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -3, to: Date.now)!)
        let optOutShouldInclude3 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -1, to: Date.now)!)
        let optOutShouldInclude4 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -5, to: Date.now)!)
        let optOutShouldInclude5 = OptOutJobData.mock(with: Calendar.current.date(byAdding: .day, value: -2, to: Date.now)!)
        let brokerProfileQueryData = [BrokerProfileQueryData.mock(extractedProfile: extractedProfile,
                                                                 optOutJobData: [optOutShouldNotInclude1,
                                                                                 optOutShouldNotInclude2,
                                                                                 optOutShouldInclude1,
                                                                                 optOutShouldInclude2]),
                                      BrokerProfileQueryData.mock(extractedProfile: extractedProfile,
                                                                  optOutJobData: []),
                                      BrokerProfileQueryData.mock(extractedProfile: extractedProfile,
                                                                  optOutJobData: [optOutShouldNotInclude3,
                                                                                  optOutShouldNotInclude4]),
                                      BrokerProfileQueryData.mock(extractedProfile: extractedProfile,
                                                                  optOutJobData: [optOutShouldInclude3]),
                                      BrokerProfileQueryData.mock(extractedProfile: extractedProfile,
                                                                  optOutJobData: [optOutShouldInclude4,
                                                                                  optOutShouldNotInclude5,
                                                                                  optOutShouldInclude5])]

        // When
        let weeklyOptOuts = sut.weeklyOptOuts(for: brokerProfileQueryData)

        // Then
        XCTAssertEqual(weeklyOptOuts.count, 5)
        XCTAssertTrue(weeklyOptOuts.contains { $0.createdDate == optOutShouldInclude1.createdDate })
        XCTAssertTrue(weeklyOptOuts.contains { $0.createdDate == optOutShouldInclude2.createdDate })
        XCTAssertTrue(weeklyOptOuts.contains { $0.createdDate == optOutShouldInclude3.createdDate })
        XCTAssertTrue(weeklyOptOuts.contains { $0.createdDate == optOutShouldInclude4.createdDate })
        XCTAssertTrue(weeklyOptOuts.contains { $0.createdDate == optOutShouldInclude5.createdDate })
    }

    let extractedProfile1 = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
    let extractedProfile2 = ExtractedProfile.mockWithName("The Crock Jock", age: "24", addresses: [AddressCityState(city: "New York", state: "NY")])
    let extractedProfile3 = ExtractedProfile.mockWithName("Wolfy Wolfgang", age: "40", addresses: [AddressCityState(city: "New York", state: "NY")])
    let extractedProfile4 = ExtractedProfile.mockWithName("Pigeon Boy", age: "73", addresses: [AddressCityState(city: "Miami", state: "FL")])
    let extractedProfile5 = ExtractedProfile.mockWithName("Definitely Not 20 Birds in a Trenchcoat", age: "7", addresses: [AddressCityState(city: "New York", state: "NY")])

    let parentProfileMatching1 = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
    let parentProfileMatching2 = ExtractedProfile.mockWithName("The Crock Jock", age: "24", addresses: [AddressCityState(city: "New York", state: "NY")])
    let parentProfileMatching3 = ExtractedProfile.mockWithName("Wolfy Wolfgang", age: "40", addresses: [AddressCityState(city: "New York", state: "NY")])
    let parentProfileMatching4 = ExtractedProfile.mockWithName("Pigeon Boy", age: "73", addresses: [AddressCityState(city: "Miami", state: "FL")])
    let parentProfileMatching5 = ExtractedProfile.mockWithName("Definitely Not 20 Birds in a Trenchcoat", age: "7", addresses: [AddressCityState(city: "New York", state: "NY")])

    let parentProfileNotMatching1 = ExtractedProfile.mockWithName("The Phantom Oinker", age: "12", addresses: [AddressCityState(city: "New York", state: "NY")])
    let parentProfileNotMatching2 = ExtractedProfile.mockWithName("Husky Sausage Dog", age: "4", addresses: [AddressCityState(city: "Miami", state: "FL")])
    let parentProfileNotMatching3 = ExtractedProfile.mockWithName("Actually definitely 20 Birds in a Trenchcoat", age: "7", addresses: [AddressCityState(city: "New York", state: "NY")])

    func testOrphanedProfilesCount_whenChildAndParentHaveSameProfiles_thenCountIsZero() {
        // Given
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        let optOuts = [OptOutJobData.mock(with: extractedProfile1),
                       OptOutJobData.mock(with: extractedProfile2),
                       OptOutJobData.mock(with: extractedProfile3),
                       OptOutJobData.mock(with: extractedProfile4),
                       OptOutJobData.mock(with: extractedProfile5)]
        let parentOptOuts = [OptOutJobData.mock(with: parentProfileMatching4),
                             OptOutJobData.mock(with: parentProfileMatching2),
                             OptOutJobData.mock(with: parentProfileMatching1),
                             OptOutJobData.mock(with: parentProfileMatching3),
                             OptOutJobData.mock(with: parentProfileMatching5)]

        // When
        let count = sut.orphanedProfilesCount(with: optOuts, parentOptOuts: parentOptOuts)

        // Then
        XCTAssertEqual(count, 0)
    }

    func testOrphanedProfilesCount_whenChildAndParentHaveDifferentProfiles_thenCountIsCorrect() {
        // Given
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        let optOuts = [OptOutJobData.mock(with: extractedProfile1),
                       OptOutJobData.mock(with: extractedProfile2),
                       OptOutJobData.mock(with: extractedProfile3),
                       OptOutJobData.mock(with: extractedProfile4),
                       OptOutJobData.mock(with: extractedProfile5)]
        let parentOptOuts = [OptOutJobData.mock(with: parentProfileNotMatching1),
                             OptOutJobData.mock(with: parentProfileMatching2),
                             OptOutJobData.mock(with: parentProfileMatching1),
                             OptOutJobData.mock(with: parentProfileNotMatching2),
                             OptOutJobData.mock(with: parentProfileNotMatching3)]

        // When
        let count = sut.orphanedProfilesCount(with: optOuts, parentOptOuts: parentOptOuts)

        // Then
        XCTAssertEqual(count, 3)
    }

    func testOrphanedProfilesCount_whenChildHasMoreProfiles_thenCountIsCorrect() {
        // Given
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        let optOuts = [OptOutJobData.mock(with: extractedProfile1),
                       OptOutJobData.mock(with: extractedProfile2),
                       OptOutJobData.mock(with: extractedProfile3),
                       OptOutJobData.mock(with: extractedProfile4),
                       OptOutJobData.mock(with: extractedProfile5)]
        let parentOptOuts = [OptOutJobData.mock(with: parentProfileMatching2),
                             OptOutJobData.mock(with: parentProfileMatching1)]

        // When
        let count = sut.orphanedProfilesCount(with: optOuts, parentOptOuts: parentOptOuts)

        // Then
        XCTAssertEqual(count, 3)
    }

    func testChildBrokerURLsToOrphanedProfilesCount_whenChildAndParentHaveDifferentProfiles_thenCountIsCorrect() {
        // Given
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        let childURL = "child.com"
        let parentURL = "parent.com"

        let brokerProfileQueryData = [BrokerProfileQueryData.mock(url: childURL,
                                                                  parentURL: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: extractedProfile1),
                                                                                  OptOutJobData.mock(with: extractedProfile2),
                                                                                  OptOutJobData.mock(with: extractedProfile3)]),
                                      BrokerProfileQueryData.mock(url: childURL,
                                                                  parentURL: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: extractedProfile4),
                                                                                  OptOutJobData.mock(with: extractedProfile5)]),
                                      BrokerProfileQueryData.mock(url: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: parentProfileMatching1),
                                                                                  OptOutJobData.mock(with: parentProfileNotMatching1)]),
                                      BrokerProfileQueryData.mock(url: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: parentProfileMatching2),
                                                                                  OptOutJobData.mock(with: parentProfileNotMatching2),
                                                                                  OptOutJobData.mock(with: parentProfileNotMatching3)])]

        // When
        let brokerURLsToCounts = sut.childBrokerURLsToOrphanedProfilesWeeklyCount(for: brokerProfileQueryData)

        // Then
        XCTAssertEqual(brokerURLsToCounts, ["child.com": 3])
    }

    /*
     fireWeeklyChildBrokerOrphanedOptOutsPixels
     Test cases:
     - Does fire for every child broker once (and _only_ child brokers)
     */

    let pixelName = DataBrokerProtectionSharedPixels.weeklyChildBrokerOrphanedOptOuts(dataBrokerName: "",
                                                                                      childParentRecordDifference: 0,
                                                                                      calculatedOrphanedRecords: 0).name

    func testFireWeeklyChildBrokerOrphanedOptOutsPixels_whenChildAndParentHaveSameProfiles_thenDoesNotFire() {
        // Given
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        let childURL = "child.com"
        let parentURL = "parent.com"

        let brokerProfileQueryData = [BrokerProfileQueryData.mock(url: childURL,
                                                                  parentURL: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: extractedProfile1),
                                                                                  OptOutJobData.mock(with: extractedProfile2),
                                                                                  OptOutJobData.mock(with: extractedProfile3)]),
                                      BrokerProfileQueryData.mock(url: childURL,
                                                                  parentURL: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: extractedProfile4),
                                                                                  OptOutJobData.mock(with: extractedProfile5)]),
                                      BrokerProfileQueryData.mock(url: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: parentProfileMatching1),
                                                                                  OptOutJobData.mock(with: parentProfileMatching4)]),
                                      BrokerProfileQueryData.mock(url: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: parentProfileMatching2),
                                                                                  OptOutJobData.mock(with: parentProfileMatching3),
                                                                                  OptOutJobData.mock(with: parentProfileMatching5)])]

        database.brokerProfileQueryDataToReturn = brokerProfileQueryData
        repository.customGetLatestWeeklyPixel = nil

        // When
        sut.tryToFireWeeklyPixels()

        // Then
        let pixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        XCTAssertFalse(pixels.contains { $0.name == pixelName })
    }

    func testFireWeeklyChildBrokerOrphanedOptOutsPixels_whenChildAndParentHaveDifferentProfiles_thenFiresCorrectly() {
        // Given
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        let childName = "child"
        let childURL = "child.com"
        let parentURL = "parent.com"

        let brokerProfileQueryData = [BrokerProfileQueryData.mock(dataBrokerName: childName,
                                                                  url: childURL,
                                                                  parentURL: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: extractedProfile1),
                                                                                  OptOutJobData.mock(with: extractedProfile2),
                                                                                  OptOutJobData.mock(with: extractedProfile3)]),
                                      BrokerProfileQueryData.mock(dataBrokerName: childName,
                                                                  url: childURL,
                                                                  parentURL: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: extractedProfile4),
                                                                                  OptOutJobData.mock(with: extractedProfile5)]),
                                      BrokerProfileQueryData.mock(url: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: parentProfileMatching1),
                                                                                  OptOutJobData.mock(with: parentProfileNotMatching1)]),
                                      BrokerProfileQueryData.mock(url: parentURL,
                                                                  optOutJobData: [OptOutJobData.mock(with: parentProfileMatching2),
                                                                                  OptOutJobData.mock(with: parentProfileNotMatching2),
                                                                                  OptOutJobData.mock(with: parentProfileNotMatching3)])]

        database.brokerProfileQueryDataToReturn = brokerProfileQueryData
        repository.customGetLatestWeeklyPixel = nil

        // When
        sut.tryToFireWeeklyPixels()

        // Then
        let pixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let firedPixel = pixels.first { $0.name == pixelName }!
        let parameters = firedPixel.params
        XCTAssertEqual(parameters, [DataBrokerProtectionSharedPixels.Consts.dataBrokerParamKey: childName,
                                    DataBrokerProtectionSharedPixels.Consts.calculatedOrphanedRecords: "3",
                                    DataBrokerProtectionSharedPixels.Consts.childParentRecordDifference: "0"])
    }

    func testFireWeeklyChildBrokerOrphanedOptOutsPixels_whenThereAreMultipleChildBrokers_thenFiresOnceForEach() {
        // Given
        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        let childName1 = "child1"
        let childURL1 = "child1.com"
        let parentURL1 = "parent1.com"

        let childName2 = "child2"
        let childURL2 = "child2.com"

        let childName3 = "child3"
        let childURL3 = "child3.com"
        let parentURL3 = "parent3.com"

        let brokerProfileQueryData = [BrokerProfileQueryData.mock(dataBrokerName: childName1,
                                                                  url: childURL1,
                                                                  parentURL: parentURL1,
                                                                  optOutJobData: [OptOutJobData.mock(with: extractedProfile1),
                                                                                  OptOutJobData.mock(with: extractedProfile2)]),
                                      BrokerProfileQueryData.mock(url: parentURL1,
                                                                  optOutJobData: [OptOutJobData.mock(with: parentProfileMatching1)]),
                                      BrokerProfileQueryData.mock(dataBrokerName: childName2,
                                                                  url: childURL2,
                                                                  parentURL: parentURL1,
                                                                  optOutJobData: [OptOutJobData.mock(with: extractedProfile5),
                                                                                  OptOutJobData.mock(with: extractedProfile3)]),
                                      BrokerProfileQueryData.mock(dataBrokerName: childName3,
                                                                  url: childURL3,
                                                                  parentURL: parentURL3,
                                                                  optOutJobData: [OptOutJobData.mock(with: extractedProfile4)]),
                                      BrokerProfileQueryData.mock(url: parentURL3,
                                                                  optOutJobData: [OptOutJobData.mock(with: parentProfileNotMatching3),
                                                                                  OptOutJobData.mock(with: parentProfileMatching5)])]

        database.brokerProfileQueryDataToReturn = brokerProfileQueryData
        repository.customGetLatestWeeklyPixel = nil

        // When
        sut.tryToFireWeeklyPixels()

        // Then
        let pixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let firedPixels = pixels.filter { $0.name == pixelName }

        XCTAssertEqual(firedPixels.count, 3)

        let child1Pixel = firedPixels.filter { $0.params![DataBrokerProtectionSharedPixels.Consts.dataBrokerParamKey] == childName1 }.first!
        XCTAssertEqual(child1Pixel.params, [DataBrokerProtectionSharedPixels.Consts.dataBrokerParamKey: childName1,
                                            DataBrokerProtectionSharedPixels.Consts.calculatedOrphanedRecords: "1",
                                            DataBrokerProtectionSharedPixels.Consts.childParentRecordDifference: "1"])

        let child2Pixel = firedPixels.filter { $0.params![DataBrokerProtectionSharedPixels.Consts.dataBrokerParamKey] == childName2 }.first!
        XCTAssertEqual(child2Pixel.params, [DataBrokerProtectionSharedPixels.Consts.dataBrokerParamKey: childName2,
                                            DataBrokerProtectionSharedPixels.Consts.calculatedOrphanedRecords: "2",
                                            DataBrokerProtectionSharedPixels.Consts.childParentRecordDifference: "1"])

        let child3Pixel = firedPixels.filter { $0.params![DataBrokerProtectionSharedPixels.Consts.dataBrokerParamKey] == childName3 }.first!
        XCTAssertEqual(child3Pixel.params, [DataBrokerProtectionSharedPixels.Consts.dataBrokerParamKey: childName3,
                                            DataBrokerProtectionSharedPixels.Consts.calculatedOrphanedRecords: "1",
                                            DataBrokerProtectionSharedPixels.Consts.childParentRecordDifference: "-1"])
    }

    #if os(iOS)
    func testTryToFireWeeklyPixels_includesBackgroundTaskSessionMetrics() {
        // Create test events with different session types
        let events = [
            // Session 1: completed
            BackgroundTaskEvent(sessionId: "session1", eventType: .started, timestamp: .daysAgo(3)),
            BackgroundTaskEvent(sessionId: "session1", eventType: .completed, timestamp: .daysAgo(3), metadata: BackgroundTaskEvent.Metadata(durationInMs: 30000)),
            // Session 2: terminated
            BackgroundTaskEvent(sessionId: "session2", eventType: .started, timestamp: .daysAgo(2)),
            BackgroundTaskEvent(sessionId: "session2", eventType: .terminated, timestamp: .daysAgo(2), metadata: BackgroundTaskEvent.Metadata(durationInMs: 45000)),
            // Session 3: completed
            BackgroundTaskEvent(sessionId: "session3", eventType: .started, timestamp: .daysAgo(1)),
            BackgroundTaskEvent(sessionId: "session3", eventType: .completed, timestamp: .daysAgo(1), metadata: BackgroundTaskEvent.Metadata(durationInMs: 60000)),
            // Session 4: completed (with invalid negative duration - should be ignored in min/max/median calculation)
            BackgroundTaskEvent(sessionId: "session4", eventType: .started, timestamp: .daysAgo(4)),
            BackgroundTaskEvent(sessionId: "session4", eventType: .completed, timestamp: .daysAgo(4), metadata: BackgroundTaskEvent.Metadata(durationInMs: -1000)),
            // Session 5: terminated (with too long duration - should be ignored in min/max/median calculation)
            BackgroundTaskEvent(sessionId: "session5", eventType: .started, timestamp: .daysAgo(5)),
            BackgroundTaskEvent(sessionId: "session5", eventType: .terminated, timestamp: .daysAgo(5), metadata: BackgroundTaskEvent.Metadata(durationInMs: 90000000)),
            // Session 6: completed
            BackgroundTaskEvent(sessionId: "session6", eventType: .started, timestamp: .daysAgo(6)),
            BackgroundTaskEvent(sessionId: "session6", eventType: .completed, timestamp: .daysAgo(6), metadata: BackgroundTaskEvent.Metadata(durationInMs: 15000)),
            // Session 7: terminated (outside 7-day window  - should be ignored from all calculations)
            BackgroundTaskEvent(sessionId: "session7", eventType: .started, timestamp: .daysAgo(20)),
            BackgroundTaskEvent(sessionId: "session7", eventType: .terminated, timestamp: .daysAgo(20), metadata: BackgroundTaskEvent.Metadata(durationInMs: 50000)),
            // Session 8: completed
            BackgroundTaskEvent(sessionId: "session8", eventType: .started, timestamp: .daysAgo(2)),
            BackgroundTaskEvent(sessionId: "session8", eventType: .completed, timestamp: .daysAgo(2), metadata: BackgroundTaskEvent.Metadata(durationInMs: 35000)),
            // Session 9: orphaned (started but never completed/terminated)
            BackgroundTaskEvent(sessionId: "session9", eventType: .started, timestamp: .daysAgo(3))
        ]

        database.backgroundTaskEventsToReturn = events
        repository.customGetLatestWeeklyPixel = nil

        let sut = DataBrokerProtectionEventPixels(database: database, repository: repository, handler: handler)

        sut.tryToFireWeeklyPixels()

        let sessionPixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
            .first { $0.name.contains("weekly-report_background-task_session") }
        XCTAssertNotNil(sessionPixel)
        XCTAssertEqual(sessionPixel?.params?["num_started"], "8")    // Sessions 1-6, 8, 9
        XCTAssertEqual(sessionPixel?.params?["num_orphaned"], "1")   // Session 9
        XCTAssertEqual(sessionPixel?.params?["num_completed"], "5")  // Sessions 1, 3, 4, 6, 8
        XCTAssertEqual(sessionPixel?.params?["num_terminated"], "2") // Session 2, 5
        XCTAssertEqual(sessionPixel?.params?["duration_min_ms"], "15000.0")
        XCTAssertEqual(sessionPixel?.params?["duration_max_ms"], "60000.0")
        XCTAssertEqual(sessionPixel?.params?["duration_median_ms"], "35000.0")
    }
    #endif

    func testWhenFireWeeklyReportPixels_thenExcludesRemovedBrokersFromReport() {
        // Given
        let activeBrokerData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWithRecentScan,
            optOutJobData: [.mockWithSuccessfulOptOut]
        )

        let removedBroker = DataBroker(
            id: 2,
            name: "RemovedBroker",
            url: "https://removed.com",
            steps: [],
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig.mock,
            mirrorSites: [],
            optOutUrl: "",
            eTag: "",
            removedAt: Date()
        )
        let removedBrokerData = BrokerProfileQueryData(
            dataBroker: removedBroker,
            profileQuery: .mock,
            scanJobData: .mockWithRecentScan,
            optOutJobData: [.mockWithSuccessfulOptOut, .mockWithSuccessfulOptOut]
        )

        database.brokerProfileQueryDataToReturn = [activeBrokerData, removedBrokerData]

        let sut = DataBrokerProtectionEventPixels(database: database,
                                                  repository: repository,
                                                  handler: handler)

        // When
        sut.fireWeeklyReportPixels()

        // Then
        XCTAssertTrue(database.wasFetchAllBrokerProfileQueryDataCalled, "Should call fetchAllBrokerProfileQueryData")
        XCTAssertEqual(database.lastShouldFilterRemovedBrokers, true, "Should request filtering of removed brokers for event pixels")

        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired

        // Weekly report should only reflect active broker data
        let scanningPixels = firedPixels.filter { $0.name == "dbp_event_weekly-report_scanning" }
        let removalPixels = firedPixels.filter { $0.name == "dbp_event_weekly-report_removals" }

        XCTAssertFalse(scanningPixels.isEmpty, "Should fire scanning report pixels")
        XCTAssertFalse(removalPixels.isEmpty, "Should fire removal report pixels")

        // Should only count removals from active broker (1), not removed broker (2)
        if let removalPixel = removalPixels.first,
           let removalsParam = removalPixel.params?["removals"] {
            XCTAssertEqual(removalsParam, "1", "Should only count removals from active brokers")
        }
    }

    func testWhenWeeklyReportPixels_thenExcludesRemovedBrokersFromCoverage() {
        // Given
        let activeBroker1 = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWithRecentScan,
            optOutJobData: []
        )

        let activeBroker2 = BrokerProfileQueryData(
            dataBroker: .mockWithURL("https://active2.com"),
            profileQuery: .mock,
            scanJobData: .mockWithOldScan, // Not scanned this week
            optOutJobData: []
        )

        let removedBroker = BrokerProfileQueryData(
            dataBroker: .removedMock,
            profileQuery: .mock,
            scanJobData: .mockWithRecentScan,
            optOutJobData: []
        )

        database.brokerProfileQueryDataToReturn = [activeBroker1, activeBroker2, removedBroker]

        let sut = DataBrokerProtectionEventPixels(database: database,
                                                  repository: repository,
                                                  handler: handler)

        // When
        sut.fireWeeklyReportPixels()

        // Then
        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let scanningPixels = firedPixels.filter { $0.name == "dbp_event_weekly-report_scanning" }

        XCTAssertFalse(scanningPixels.isEmpty, "Should fire scanning report pixels")

        // Scan coverage should be calculated as: 1 scanned out of 2 active brokers = 50%
        // (excluding the removed broker from both numerator and denominator)
        if let scanningPixel = scanningPixels.first,
           let scanCoverage = scanningPixel.params?["scan_coverage"] {
            XCTAssertEqual(scanCoverage, "50-75", "Scan coverage should exclude removed brokers from calculation")
        }
    }

    func testWhenWeeklyReportPixels_withOnlyRemovedBrokers_thenFiresZeroStats() {
        // Given
        // Create removed broker mocks (using manually created DataBroker since we need removedAt)
        let removedDataBroker1 = DataBroker(
            id: 1,
            name: "RemovedBroker1",
            url: "https://removed1.com",
            steps: [],
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig.mock,
            mirrorSites: [],
            optOutUrl: "",
            eTag: "",
            removedAt: Date()
        )
        let removedBroker1 = BrokerProfileQueryData(
            dataBroker: removedDataBroker1,
            profileQuery: .mock,
            scanJobData: .mockWithRecentScan,
            optOutJobData: [.mockWithSuccessfulOptOut]
        )

        let removedDataBroker2 = DataBroker(
            id: 2,
            name: "RemovedBroker2",
            url: "https://removed2.com",
            steps: [],
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig.mock,
            mirrorSites: [],
            optOutUrl: "",
            eTag: "",
            removedAt: Date()
        )
        let removedBroker2 = BrokerProfileQueryData(
            dataBroker: removedDataBroker2,
            profileQuery: .mock,
            scanJobData: .mockWithRecentScan,
            optOutJobData: [.mockWithSuccessfulOptOut]
        )

        database.brokerProfileQueryDataToReturn = [removedBroker1, removedBroker2]

        let sut = DataBrokerProtectionEventPixels(database: database,
                                                  repository: repository,
                                                  handler: handler)

        // When
        sut.fireWeeklyReportPixels()

        // Then
        let firedPixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        let scanningPixels = firedPixels.filter { $0.name == "dbp_event_weekly-report_scanning" }
        let removalPixels = firedPixels.filter { $0.name == "dbp_event_weekly-report_removals" }

        // Should still fire pixels but with zero counts since all brokers are filtered out
        XCTAssertFalse(scanningPixels.isEmpty, "Should fire scanning report pixels even with no active brokers")
        XCTAssertFalse(removalPixels.isEmpty, "Should fire removal report pixels even with no active brokers")

        if let removalPixel = removalPixels.first,
           let removalsParam = removalPixel.params?["removals"] {
            XCTAssertEqual(removalsParam, "0", "Should show zero removals when all brokers are removed")
        }
    }
}

final class MockDataBrokerProtectionEventPixelsRepository: DataBrokerProtectionEventPixelsRepository {

    var wasMarkWeeklyPixelSentCalled = false
    var customGetLatestWeeklyPixel: Date?

    func markWeeklyPixelSent() {
        wasMarkWeeklyPixelSentCalled = true
    }

    func getLatestWeeklyPixel() -> Date? {
        return customGetLatestWeeklyPixel
    }

    func clear() {
        wasMarkWeeklyPixelSentCalled = false
        customGetLatestWeeklyPixel = nil
    }
}

//
//  BrokerProfileQueryDataTests.swift
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

@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
import XCTest

final class BrokerProfileQueryDataTests: XCTestCase {

    // namesOfBrokersScannedIncludingMirrorSites tests

    func test_namesOfBrokersScannedIncludingMirrorSites_whenNoLastRunDate_thenReturnsEmptyArray() {
        let queryData = BrokerProfileQueryData.mock(lastRunDate: nil)

        let result = queryData.namesOfBrokersScannedIncludingMirrorSites()
        XCTAssertTrue(result.isEmpty)
    }

    func test_namesOfBrokersScannedIncludingMirrorSites_whenNoMirrorSites_ThenReturnsOnlyMainBrokerName() {
        let scanEvent = HistoryEvent.mockScanEvent(with: Date())
        let queryData = BrokerProfileQueryData.mock(dataBrokerName: "testBroker", lastRunDate: Date(), scanHistoryEvents: [scanEvent], mirrorSites: [])

        let result = queryData.namesOfBrokersScannedIncludingMirrorSites()
        XCTAssertEqual(result, ["testBroker"])
    }

    func test_namesOfBrokersScannedIncludingMirrorSites_whenMirrorSitesExistAndExtant_ThenReturnsAllNames() {
        let currentDate = Date()
        let scanEvent = HistoryEvent.mockScanEvent(with: currentDate)
        let mirrorSite1 = MirrorSite(name: "mirror1", url: "mirror1.url", addedAt: Date(timeInterval: -1000, since: currentDate), removedAt: nil)
        let mirrorSite2 = MirrorSite(name: "mirror2", url: "mirror2.url", addedAt: Date(timeInterval: -10, since: currentDate), removedAt: nil)
        let mirrorSite3 = MirrorSite(name: "mirror3", url: "mirror3.url", addedAt: Date(timeInterval: -10000, since: currentDate), removedAt: nil)

        let queryData = BrokerProfileQueryData.mock(dataBrokerName: "testBroker", lastRunDate: currentDate, scanHistoryEvents: [scanEvent], mirrorSites: [mirrorSite1, mirrorSite2, mirrorSite3])

        let result = queryData.namesOfBrokersScannedIncludingMirrorSites()
        XCTAssertEqual(result, ["testBroker", "mirror1", "mirror2", "mirror3"])
    }

    func test_namesOfBrokersScannedIncludingMirrorSites_whenMirrorSitesExistButNotAllWereExtantAtScanTime_ThenReturnsOnlyScannedNames() {
        let currentDate = Date()
        let scanEvent = HistoryEvent.mockScanEvent(with: currentDate)
        let mirrorSite1 = MirrorSite(name: "mirror1", url: "mirror1.url", addedAt: Date(timeInterval: -1000, since: currentDate), removedAt: nil) // This one existed
        let mirrorSite2 = MirrorSite(name: "mirror2", url: "mirror2.url", addedAt: Date(timeInterval: 100, since: currentDate), removedAt: nil) // This one was added too late
        let mirrorSite3 = MirrorSite(name: "mirror3", url: "mirror3.url", addedAt: Date(timeInterval: -10000, since: currentDate), removedAt: Date(timeInterval: -5000, since: currentDate)) // This one was removed before the date

        let queryData = BrokerProfileQueryData.mock(dataBrokerName: "testBroker", lastRunDate: currentDate, scanHistoryEvents: [scanEvent], mirrorSites: [mirrorSite1, mirrorSite2, mirrorSite3])

        let result = queryData.namesOfBrokersScannedIncludingMirrorSites()
        XCTAssertEqual(result, ["testBroker", "mirror1"])
    }

    // [BrokerProfileQueryData] tests

    // elementsSortedByScanLastRunDateWhereScansRanBetween tests

    func test_elementsSortedByScanLastRunDateWhereScansRanBetween_whenNoDatesBetweenDates_ThenReturnsEmptyArray() {
        let queryData1 = BrokerProfileQueryData.mock(dataBrokerName: "1", lastRunDate: Date(timeIntervalSince1970: 0))
        let queryData2 = BrokerProfileQueryData.mock(dataBrokerName: "2", lastRunDate: Date(timeIntervalSince1970: 1000))
        let queryData3 = BrokerProfileQueryData.mock(dataBrokerName: "3", lastRunDate: Date(timeIntervalSince1970: 500))
        let array = [queryData1, queryData2, queryData3]

        let result = array.elementsSortedByScanLastRunDateWhereScansRanBetween(earlierDate: Date(timeIntervalSince1970: 2000), laterDate: Date(timeIntervalSince1970: 20000))
        XCTAssertEqual(result.count, 0)
    }

    func test_elementsSortedByScanLastRunDateWhereScansRanBetween_whenSomeDatesBetweenDates_ThenReturnsSortedArray() {
        let queryData1 = BrokerProfileQueryData.mock(dataBrokerName: "1", lastRunDate: Date(timeIntervalSince1970: 0))
        let queryData2 = BrokerProfileQueryData.mock(dataBrokerName: "2", lastRunDate: Date(timeIntervalSince1970: 1000))
        let queryData3 = BrokerProfileQueryData.mock(dataBrokerName: "3", lastRunDate: Date(timeIntervalSince1970: 500))
        let array = [queryData1, queryData2, queryData3]

        let result = array.elementsSortedByScanLastRunDateWhereScansRanBetween(earlierDate: Date(timeIntervalSince1970: 400), laterDate: Date(timeIntervalSince1970: 20000))
        XCTAssertEqual(result.map { $0.dataBroker.name }, ["3", "2"])
    }

    // elementsSortedByScanPreferredRunDateWhereDateIsBetween tests

    func test_elementsSortedByScanPreferredRunDateWhereDateIsBetween_whenNoDatesBetweenDates_ThenReturnsEmptyArray() {
        let queryData1 = BrokerProfileQueryData.mock(dataBrokerName: "1", preferredRunDate: Date(timeIntervalSince1970: 0))
        let queryData2 = BrokerProfileQueryData.mock(dataBrokerName: "2", preferredRunDate: Date(timeIntervalSince1970: 1000))
        let queryData3 = BrokerProfileQueryData.mock(dataBrokerName: "3", preferredRunDate: Date(timeIntervalSince1970: 500))
        let array = [queryData1, queryData2, queryData3]

        let result = array.elementsSortedByScanPreferredRunDateWhereDateIsBetween(earlierDate: Date(timeIntervalSince1970: 2000), laterDate: Date(timeIntervalSince1970: 20000))
        XCTAssertEqual(result.count, 0)
    }

    func test_elementsSortedByScanPreferredRunDateWhereDateIsBetween_whenSomeDatesBetweenDates_ThenReturnsSortedArray() {
        let queryData1 = BrokerProfileQueryData.mock(dataBrokerName: "1", preferredRunDate: Date(timeIntervalSince1970: 0))
        let queryData2 = BrokerProfileQueryData.mock(dataBrokerName: "2", preferredRunDate: Date(timeIntervalSince1970: 1000))
        let queryData3 = BrokerProfileQueryData.mock(dataBrokerName: "3", preferredRunDate: Date(timeIntervalSince1970: 500))
        let array = [queryData1, queryData2, queryData3]

        let result = array.elementsSortedByScanPreferredRunDateWhereDateIsBetween(earlierDate: Date(timeIntervalSince1970: 400), laterDate: Date(timeIntervalSince1970: 20000))
        XCTAssertEqual(result.map { $0.dataBroker.name }, ["3", "2"])
    }
}

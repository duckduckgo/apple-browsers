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
    lazy var mockOptOutQueryData: [BrokerProfileQueryData] = {
        let brokerId: Int64 = 1

        let mockNilPreferredRunDateQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: nil, optOutJobData: [BrokerProfileQueryData.createOptOutJobData(extractedProfileId: Int64($0), brokerId: brokerId, profileQueryId: Int64($0), preferredRunDate: nil)])
        }
        let mockPastQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowMinus(hours: $0), optOutJobData: [BrokerProfileQueryData.createOptOutJobData(extractedProfileId: Int64($0), brokerId: brokerId, profileQueryId: Int64($0), preferredRunDate: .nowMinus(hours: $0))])
        }
        let mockFutureQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowPlus(hours: $0), optOutJobData: [BrokerProfileQueryData.createOptOutJobData(extractedProfileId: Int64($0), brokerId: brokerId, profileQueryId: Int64($0), preferredRunDate: .nowPlus(hours: $0))])
        }

        return mockNilPreferredRunDateQueryData + mockPastQueryData + mockFutureQueryData
    }()

    lazy var mockScanQueryData: [BrokerProfileQueryData] = {
        let mockNilPreferredRunDateQueryData = Array(1...10).map { _ in
            BrokerProfileQueryData.mock(preferredRunDate: nil)
        }
        let mockPastQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowMinus(hours: $0))
        }
        let mockFutureQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowPlus(hours: $0))
        }

        return mockNilPreferredRunDateQueryData + mockPastQueryData + mockFutureQueryData
    }()

    // namesOfBrokersScannedIncludingMirrorSites tests

    func testNamesOfBrokersScannedIncludingMirrorSites_whenNoLastRunDate_thenReturnsEmptyArray() {
        let queryData = BrokerProfileQueryData.mock(lastRunDate: nil)

        let result = queryData.namesOfBrokersScannedIncludingMirrorSites()
        XCTAssertTrue(result.isEmpty)
    }

    func testNamesOfBrokersScannedIncludingMirrorSites_whenNoMirrorSites_ThenReturnsOnlyMainBrokerName() {
        let scanEvent = HistoryEvent.mockScanEvent(with: Date())
        let queryData = BrokerProfileQueryData.mock(dataBrokerName: "testBroker", lastRunDate: Date(), scanHistoryEvents: [scanEvent], mirrorSites: [])

        let result = queryData.namesOfBrokersScannedIncludingMirrorSites()
        XCTAssertEqual(result, ["testBroker"])
    }

    func testNamesOfBrokersScannedIncludingMirrorSites_whenMirrorSitesExistAndExtant_ThenReturnsAllNames() {
        let currentDate = Date()
        let scanEvent = HistoryEvent.mockScanEvent(with: currentDate)
        let mirrorSite1 = MirrorSite(name: "mirror1", url: "mirror1.url", addedAt: Date(timeInterval: -1000, since: currentDate), removedAt: nil)
        let mirrorSite2 = MirrorSite(name: "mirror2", url: "mirror2.url", addedAt: Date(timeInterval: -10, since: currentDate), removedAt: nil)
        let mirrorSite3 = MirrorSite(name: "mirror3", url: "mirror3.url", addedAt: Date(timeInterval: -10000, since: currentDate), removedAt: nil)

        let queryData = BrokerProfileQueryData.mock(dataBrokerName: "testBroker", lastRunDate: currentDate, scanHistoryEvents: [scanEvent], mirrorSites: [mirrorSite1, mirrorSite2, mirrorSite3])

        let result = queryData.namesOfBrokersScannedIncludingMirrorSites()
        XCTAssertEqual(result, ["testBroker", "mirror1", "mirror2", "mirror3"])
    }

    func testNamesOfBrokersScannedIncludingMirrorSites_whenMirrorSitesExistButNotAllWereExtantAtScanTime_ThenReturnsOnlyScannedNames() {
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

    /*
     func elementsSortedByScanLastRunDateWhereScansRanBetween(earlierDate: Date, laterDate: Date) -> [BrokerProfileQueryData] {
         guard earlierDate < laterDate else {
             assertionFailure()
             return []
         }

         let unsortedElementsBetweenDates = self.filter {
             $0.scanJobData.lastRunDate != nil &&
             $0.scanJobData.lastRunDate! >= earlierDate &&
             $0.scanJobData.lastRunDate! <= laterDate
         }

         let sortedElements = unsortedElementsBetweenDates.sorted {
             $0.scanJobData.lastRunDate! < $1.scanJobData.lastRunDate!
             // At this point they are guaranteed to have a lastRunDate due to the previous filter
         }

         return sortedElements
     }

     func elementsSortedByScanPreferredRunDateWhereDateIsBetween(earlierDate: Date, laterDate: Date) -> [BrokerProfileQueryData] {
         guard earlierDate < laterDate else {
             assertionFailure()
             return []
         }

         let unsortedElementsBetweenDates = self.filter {
             $0.scanJobData.preferredRunDate != nil &&
             $0.scanJobData.preferredRunDate! >= earlierDate &&
             $0.scanJobData.preferredRunDate! <= laterDate
         }

         let sortedElements = unsortedElementsBetweenDates.sorted {
             $0.scanJobData.preferredRunDate! < $1.scanJobData.preferredRunDate!
         }

         return sortedElements
     }
     */
}

//
//  BrokerProfileQueryData.swift
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

import Foundation
import Common

public struct BrokerProfileQueryData: Sendable {
    public let dataBroker: DataBroker
    public let profileQuery: ProfileQuery
    public let scanJobData: ScanJobData
    public let optOutJobData: [OptOutJobData]

    public var jobsData: [BrokerJobData] {
        optOutJobData + [scanJobData]
    }

    public var extractedProfiles: [ExtractedProfile] {
        optOutJobData.map { $0.extractedProfile }
    }

    public var events: [HistoryEvent] {
        jobsData.flatMap { $0.historyEvents }.sorted { $0.date < $1.date }
    }

    public var hasMatches: Bool {
        !optOutJobData.isEmpty
    }

    public var optOutJobDataExcludingUserRemoved: [OptOutJobData] {
        optOutJobData.filter { !$0.isRemovedByUser }
    }

    public init(dataBroker: DataBroker,
                profileQuery: ProfileQuery,
                scanJobData: ScanJobData,
                optOutJobData: [OptOutJobData] = [OptOutJobData]()) {
        self.profileQuery = profileQuery
        self.dataBroker = dataBroker
        self.scanJobData = scanJobData
        self.optOutJobData = optOutJobData
    }
}

extension BrokerProfileQueryData: SubJobContextProviding {}

public extension BrokerProfileQueryData {
    func namesOfBrokersScannedIncludingMirrorSites() -> [String] {
        guard scanJobData.lastRunDate != nil else {
            return []
        }

        let scanEvents = scanJobData.scanStartedEvents()

        let namesOfMirrorSitesScanned = dataBroker.mirrorSites.compactMap { mirrorSite in
            let wasMirrorSiteScanned = scanEvents.contains { event in
                mirrorSite.wasExtant(on: event.date)
            }

            return wasMirrorSiteScanned ? mirrorSite.name : nil
        }

        return [dataBroker.name] + namesOfMirrorSitesScanned
    }

    var numberOfCurrentlyExtantMirrorSites: Int {
        return dataBroker.mirrorSites.filter { $0.isExtant() }.count
    }
}

public extension Array where Element == BrokerProfileQueryData {

    func latestScanLastRunDate() -> Date? {
        self.lazy.compactMap { $0.scanJobData.lastRunDate }.max()
    }

    func earliestScanPreferredRunDate() -> Date? {
        self.lazy.compactMap { $0.scanJobData.preferredRunDate }.min()
    }

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
}

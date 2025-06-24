//
//  DBPUICommunicationModelScanStateExtensions.swift
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
import Algorithms

public extension DBPUIInitialScanState {

    init(from brokerProfileQueryData: [BrokerProfileQueryData]) {
        let withoutDeprecated = brokerProfileQueryData.filter { !$0.profileQuery.deprecated }

        let groupedByBroker = Dictionary(grouping: withoutDeprecated, by: { $0.dataBroker.name }).values

        // totalScans is the overall number of brokers (including only currently extant mirrorSites)
        let totalScans = groupedByBroker.reduce(0) { accumulator, brokerQueryDataArray in
            guard let brokerQueryData = brokerQueryDataArray.first else {
                return accumulator
            }
            return accumulator + brokerQueryData.numberOfCurrentlyExtantMirrorSites + 1
        }

        let withSortedGroups = groupedByBroker.map { $0.sortedByLastRunDate() }

        let sorted = withSortedGroups.sortedByLastRunDateOfFirstElement()

        let partiallyScannedBrokers = sorted.flatMap { brokerQueryGroup in
            brokerQueryGroup.fullyAndPartiallyScannedBrokersForFirstElement
        }

        // currentScans is the number that have been fully or partially scanned
        self.scanProgress = DBPUIScanProgress(currentScans: partiallyScannedBrokers.completeBrokerScansCount,
                                              totalScans: totalScans,
                                              scannedBrokers: partiallyScannedBrokers)

        self.resultsFound = DBPUIDataBrokerProfileMatch.profileMatches(from: withoutDeprecated)
    }
}

public extension DBPUIScanAndOptOutMaintenanceState {

    init(from brokerProfileQueryData: [BrokerProfileQueryData]) {
        var inProgressOptOuts = [DBPUIDataBrokerProfileMatch]()
        var removedProfiles = [DBPUIDataBrokerProfileMatch]()

        let scansThatRanAtLeastOnce = brokerProfileQueryData.flatMap { $0.namesOfBrokersScannedIncludingMirrorSites() }
        let sitesScanned = Dictionary(grouping: scansThatRanAtLeastOnce, by: { $0 }).count

        // Used to find opt outs on the parent
        let brokerURLsToQueryData =  Dictionary(grouping: brokerProfileQueryData, by: { $0.dataBroker.url })

        brokerProfileQueryData.forEach {
            let dataBroker = $0.dataBroker
            let scanJob = $0.scanJobData
            for optOutJob in $0.optOutJobDataExcludingUserRemoved {
                let extractedProfile = optOutJob.extractedProfile

                var parentBrokerOptOutJobData: [OptOutJobData]?
                if let parent = $0.dataBroker.parent,
                   let parentsQueryData = brokerURLsToQueryData[parent] {
                    parentBrokerOptOutJobData = parentsQueryData.flatMap { $0.optOutJobDataExcludingUserRemoved }
                }

                let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOutJob,
                                                               dataBroker: dataBroker,
                                                               parentBrokerOptOutJobData: parentBrokerOptOutJobData,
                                                               optOutUrl: dataBroker.optOutUrl)

                if extractedProfile.removedDate == nil {
                    inProgressOptOuts.append(profileMatch)
                } else {
                    removedProfiles.append(profileMatch)
                }

                if let closestMatchesFoundEvent = scanJob.closestMatchesFoundEvent() {
                    for mirrorSite in dataBroker.mirrorSites where mirrorSite.wasExtant(on: closestMatchesFoundEvent.date) {
                        let mirrorSiteMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOutJob,
                                                                          dataBrokerName: mirrorSite.name,
                                                                          dataBrokerURL: mirrorSite.url,
                                                                          dataBrokerParentURL: dataBroker.parent,
                                                                          parentBrokerOptOutJobData: parentBrokerOptOutJobData,
                                                                          optOutUrl: dataBroker.optOutUrl)

                        if let extractedProfileRemovedDate = extractedProfile.removedDate,
                           mirrorSite.wasExtant(on: extractedProfileRemovedDate) {
                            removedProfiles.append(mirrorSiteMatch)
                        } else {
                            inProgressOptOuts.append(mirrorSiteMatch)
                        }
                    }
                }
            }
        }

        let completedOptOutsDictionary = Dictionary(grouping: removedProfiles, by: { $0.dataBroker })
        let completedOptOuts: [DBPUIOptOutMatch] = completedOptOutsDictionary.compactMap { (_, value: [DBPUIDataBrokerProfileMatch]) in
            value.compactMap { match in
                return DBPUIOptOutMatch(profileMatch: match, matches: value.count)
            }
        }.flatMap { $0 }

        let lastScans = Self.getLastScansInformation(brokerProfileQueryData: brokerProfileQueryData)
        let nextScans = Self.getNextScansInformation(brokerProfileQueryData: brokerProfileQueryData)

        self.inProgressOptOuts = inProgressOptOuts
        self.completedOptOuts = completedOptOuts
        self.scanSchedule = DBPUIScanSchedule(lastScan: lastScans, nextScan: nextScans)
        self.scanHistory = DBPUIScanHistory(sitesScanned: sitesScanned)
    }

    private static func getLastScansInformation(brokerProfileQueryData: [BrokerProfileQueryData],
                                                currentDate: Date = Date()) -> DBPUIScanDate {
        let eightDaysBeforeToday = currentDate.addingTimeInterval(-8 * 24 * 60 * 60)
        let brokers = brokerProfileQueryData.uiBrokersSortedByScanLastRunDateWhereScansRanBetween(earlierDate: eightDaysBeforeToday,
                                                                                                  laterDate: currentDate)

        let latestScanLastRunDate = brokerProfileQueryData.latestScanLastRunDate() ?? currentDate

        return DBPUIScanDate(date: latestScanLastRunDate.timeIntervalSince1970, dataBrokers: brokers)
    }

    private static func getNextScansInformation(brokerProfileQueryData: [BrokerProfileQueryData],
                                                currentDate: Date = Date()) -> DBPUIScanDate {
        let eightDaysAfterToday = currentDate.addingTimeInterval(8 * 24 * 60 * 60)
        let brokers = brokerProfileQueryData.uiBrokersSortedByScanPreferredRunDateWhereDateIsBetween(earlierDate: currentDate,
                                                                                                     laterDate: eightDaysAfterToday)

        let earliestScanPreferredRunDate = brokerProfileQueryData.earliestScanPreferredRunDate() ?? currentDate

        return DBPUIScanDate(date: earliestScanPreferredRunDate.timeIntervalSince1970, dataBrokers: brokers)
    }
}

/// Extension on `Optional` which provides comparison abilities when the wrapped type is `Date`
private extension Optional where Wrapped == Date {

    static func < (lhs: Date?, rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (lhsDate?, rhsDate?):
            return lhsDate < rhsDate
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case (nil, nil):
            return false
        }
    }

    static func == (lhs: Date?, rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs == rhs
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}

private extension Array where Element == [BrokerProfileQueryData] {

    /// Sorts the 2-dimensional array in ascending order based on the `lastRunDate` value of the first element of each internal array
    ///
    /// - Returns: An array of `[BrokerProfileQueryData]` values sorted by the first `lastRunDate` of each element
    func sortedByLastRunDateOfFirstElement() -> Self {
        self.sorted { lhs, rhs in
            let lhsDate = lhs.first?.scanJobData.lastRunDate
            let rhsDate = rhs.first?.scanJobData.lastRunDate

            if lhsDate == rhsDate {
                return lhs.first?.dataBroker.name ?? "" < rhs.first?.dataBroker.name ?? ""
            } else {
                return lhsDate < rhsDate
            }
        }
    }
}

private extension Array where Element == BrokerProfileQueryData {

    func uiBrokersSortedByScanLastRunDateWhereScansRanBetween(earlierDate: Date, laterDate: Date) -> [DBPUIDataBroker] {
        let sortedElements = elementsSortedByScanLastRunDateWhereScansRanBetween(earlierDate: earlierDate,
                                                                                 laterDate: laterDate)

        // Filter down to brokers and relevant mirror sites
        let brokers = sortedElements.flatMap { queryData in
            let dataBroker = queryData.dataBroker
            let lastRunDate = queryData.scanJobData.lastRunDate!

            // Don't include any mirror sites that were added after the parent's last scan date
            // Since if the mirror site was added after, we can't really be said to have scanned them
            let mirrorSitesAddedBeforeLastRunDate = dataBroker.mirrorSites.filter {
                $0.wasExtant(on: lastRunDate)
            }

            let uiDataBroker = DBPUIDataBroker(from: dataBroker, withDate: lastRunDate)
            let uiMirrorSites = mirrorSitesAddedBeforeLastRunDate.map {
                DBPUIDataBroker(from: $0, parentBroker: dataBroker, withDate: lastRunDate)
            }

            return [uiDataBroker] + uiMirrorSites
        }

        let uniqued = brokers.uniqued()
        return uniqued.map { $0 }
    }

    func uiBrokersSortedByScanPreferredRunDateWhereDateIsBetween(earlierDate: Date, laterDate: Date) -> [DBPUIDataBroker] {
        let sortedElements = elementsSortedByScanPreferredRunDateWhereDateIsBetween(earlierDate: earlierDate,
                                                                                    laterDate: laterDate)

        // Filter down to brokers and relevent mirror sites
        let brokers = sortedElements.flatMap { queryData in
            let dataBroker = queryData.dataBroker
            let preferredRunDate = queryData.scanJobData.preferredRunDate!

            // Don't include any mirror sites removed before the preferred run date
            let mirrorSitesStillExtantByPreferredRunDate = dataBroker.mirrorSites.filter {
                $0.wasExtant(on: preferredRunDate)
            }

            let uiDataBroker = DBPUIDataBroker(from: dataBroker, withDate: preferredRunDate)
            let uiMirrorSites = mirrorSitesStillExtantByPreferredRunDate.map {
                DBPUIDataBroker(from: $0, parentBroker: dataBroker, withDate: preferredRunDate)
            }

            return [uiDataBroker] + uiMirrorSites
        }

        let uniqued = brokers.uniqued()
        return uniqued.map { $0 }
    }

    typealias ScannedBroker = DBPUIScanProgress.ScannedBroker

    /// Returns an array of brokers which have been either fully or partially scanned
    ///
    /// A broker is considered fully scanned is all scan jobs for that broker have completed.
    /// A broker is considered partially scanned if at least one scan job for that broker has completed
    var fullyAndPartiallyScannedBrokersForFirstElement: [ScannedBroker] {
        guard let broker = self.first?.dataBroker else { return [] }

        var completedScans = 0
        self.forEach {
            if $0.dataBroker.name != broker.name { return }
            completedScans += ($0.scanJobData.lastRunDate == nil) ? 0 : 1
        }

        guard completedScans != 0 else { return [] }

        var status: ScannedBroker.Status = .inProgress
        if completedScans == self.count {
            status = .completed
        }

        let mirrorBrokers = broker.mirrorSites.compactMap {
            $0.isExtant() ? $0.scannedBroker(withStatus: status) : nil
        }

        return [ScannedBroker(name: broker.name, url: broker.url, status: status)] + mirrorBrokers
    }

    /// Sorts the array in ascending order based on `lastRunDate`
    ///
    /// - Returns: An array of `BrokerProfileQueryData` sorted by `lastRunDate`
    func sortedByLastRunDate() -> Self {
        self.sorted { lhs, rhs in
            lhs.scanJobData.lastRunDate < rhs.scanJobData.lastRunDate
        }
    }
}

extension Array where Element == DBPUIScanProgress.ScannedBroker {
    var completeBrokerScansCount: Int {
        reduce(0) { accumulator, scannedBrokers in
            scannedBrokers.status == .completed ? accumulator + 1 : accumulator
        }
    }
}

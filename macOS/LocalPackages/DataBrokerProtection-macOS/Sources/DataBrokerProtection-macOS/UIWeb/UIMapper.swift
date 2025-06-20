//
//  UIMapper.swift
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
import os.log
import DataBrokerProtectionCore

struct MapperToUI {

    func mapToUIDebugMetadata(metadata: DBPBackgroundAgentMetadata?, brokerProfileQueryData: [BrokerProfileQueryData]) -> DBPUIDebugMetadata {
        let currentAppVersion = Bundle.main.fullVersionNumber ?? "ERROR: Error fetching app version"

        guard let metadata = metadata else {
            return DBPUIDebugMetadata(lastRunAppVersion: currentAppVersion, isAgentRunning: false)
        }

        let lastOperation = brokerProfileQueryData.lastOperation
        let lastStartedOperation = brokerProfileQueryData.lastStartedOperation
        let lastError = brokerProfileQueryData.lastOperationThatErrored

        let lastOperationBrokerURL = brokerProfileQueryData.filter { $0.dataBroker.id == lastOperation?.brokerId }.first?.dataBroker.url
        let lastStartedOperationBrokerURL = brokerProfileQueryData.filter { $0.dataBroker.id == lastStartedOperation?.brokerId }.first?.dataBroker.url

        let metadataUI = DBPUIDebugMetadata(lastRunAppVersion: currentAppVersion,
                                            lastRunAgentVersion: metadata.backgroundAgentVersion,
                                            isAgentRunning: true,
                                            lastSchedulerOperationType: lastOperation?.toString,
                                            lastSchedulerOperationTimestamp: lastOperation?.lastRunDate?.timeIntervalSince1970.withoutDecimals,
                                            lastSchedulerOperationBrokerUrl: lastOperationBrokerURL,
                                            lastSchedulerErrorMessage: lastError?.error,
                                            lastSchedulerErrorTimestamp: lastError?.date.timeIntervalSince1970.withoutDecimals,
                                            lastSchedulerSessionStartTimestamp: metadata.lastSchedulerSessionStartTimestamp,
                                            agentSchedulerState: metadata.agentSchedulerState,
                                            lastStartedSchedulerOperationType: lastStartedOperation?.toString,
                                            lastStartedSchedulerOperationTimestamp: lastStartedOperation?.historyEvents.closestHistoryEvent?.date.timeIntervalSince1970.withoutDecimals,
                                            lastStartedSchedulerOperationBrokerUrl: lastStartedOperationBrokerURL)

#if DEBUG
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.outputFormatting = .sortedKeys
            let jsonData = try encoder.encode(metadataUI)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Logger.dataBrokerProtection.log("Metadata: \(jsonString, privacy: .public)")
            }
        } catch {
            Logger.dataBrokerProtection.error("Error encoding struct to JSON: \(error.localizedDescription, privacy: .public)")
        }
#endif

        return metadataUI
    }
}

extension Bundle {
    var fullVersionNumber: String? {
        guard let appVersion = self.releaseVersionNumber,
              let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return nil
        }

        return appVersion + " (build: \(buildNumber))"
    }
}

extension TimeInterval {
    var withoutDecimals: Double {
        Double(Int(self))
    }
}

extension Date {

    func toFormat(_ format: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        return dateFormatter.string(from: self)
    }
}

extension String {

    func toDate(using format: String) -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format

        if let date = dateFormatter.date(from: self) {
            return date
        } else {
            fatalError("String should be on the correct date format")
        }
    }
}

fileprivate extension BrokerProfileQueryData {

    var closestHistoryEvent: HistoryEvent? {
        events.sorted(by: { $0.date > $1.date }).first
    }

    var sitesScanned: [String] {
        if scanJobData.lastRunDate != nil {
            let scanEvents = scanJobData.scanStartedEvents()
            var sitesScanned = [dataBroker.name]

            for mirrorSite in dataBroker.mirrorSites {
                let wasMirrorSiteScanned = scanEvents.contains { event in
                    mirrorSite.wasExtant(on: event.date)
                }

                if wasMirrorSiteScanned {
                    sitesScanned.append(mirrorSite.name)
                }
            }

            return sitesScanned
        }

        return [String]()
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
    func sortedByLastRunDate() -> Self {
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

fileprivate extension Array where Element == BrokerProfileQueryData {

    typealias ScannedBroker = DBPUIScanProgress.ScannedBroker

    var totalScans: Int {
        guard let broker = self.first?.dataBroker else { return 0 }
        return 1 + broker.mirrorSites.filter { $0.isExtant() }.count
    }

    /// Returns an array of brokers which have been either fully or partially scanned
    ///
    /// A broker is considered fully scanned is all scan jobs for that broker have completed.
    /// A broker is considered partially scanned if at least one scan job for that broker has completed
    /// Mirror brokers will be included in the returned array when `MirrorSite.shouldWeIncludeMirrorSite` returns true
    var scannedBrokers: [ScannedBroker] {
        guard let broker = self.first?.dataBroker else { return [] }

        var completedScans = 0
        self.forEach {
            completedScans += $0.scanJobData.lastRunDate == nil ? 0 : 1
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

    var lastOperation: BrokerJobData? {
        let allJobs = flatMap { $0.jobsData }
        return allJobs.sorted(by: {
            if let date1 = $0.lastRunDate, let date2 = $1.lastRunDate {
                return date1 > date2
            } else if $0.lastRunDate != nil {
                return true
            } else {
                return false
            }
        }).first
    }

    var lastOperationThatErrored: HistoryEvent? {
        let lastError = flatMap { $0.jobsData }
            .flatMap { $0.historyEvents }
            .filter { $0.isError }
            .sorted(by: { $0.date > $1.date })
            .first

        return lastError
    }

    var lastStartedOperation: BrokerJobData? {
        let allJobs = flatMap { $0.jobsData }

        return allJobs.sorted(by: {
            if let date1 = $0.historyEvents.closestHistoryEvent?.date, let date2 = $1.historyEvents.closestHistoryEvent?.date {
                return date1 > date2
            } else if $0.historyEvents.closestHistoryEvent?.date != nil {
                return true
            } else {
                return false
            }
        }).first
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

fileprivate extension BrokerJobData {
    var toString: String {
        if (self as? OptOutJobData) != nil {
            return "optOut"
        } else {
            return "scan"
        }
    }
}

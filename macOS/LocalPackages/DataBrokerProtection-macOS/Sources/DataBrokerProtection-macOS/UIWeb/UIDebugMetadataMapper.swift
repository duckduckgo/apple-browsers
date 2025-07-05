//
//  UIDebugMetadataMapper.swift
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

struct UIDebugMetadataMapper {

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

fileprivate extension BrokerProfileQueryData {

    var closestHistoryEvent: HistoryEvent? {
        events.sorted(by: { $0.date > $1.date }).first
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

fileprivate extension Array where Element == BrokerProfileQueryData {

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

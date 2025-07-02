//
//  OperationPreferredDateUpdater.swift
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

enum OperationPreferredDateUpdaterOrigin {
    case optOut
    case scan
}

protocol OperationPreferredDateUpdating {
    var database: DataBrokerProtectionRepository { get }

    func updateOperationDataDates(origin: OperationPreferredDateUpdaterOrigin,
                                  brokerId: Int64,
                                  profileQueryId: Int64,
                                  extractedProfileId: Int64?,
                                  schedulingConfig: DataBrokerScheduleConfig) throws

    func updateChildrenBrokerForParentBroker(_ parentBroker: DataBroker, profileQueryId: Int64) throws
}

struct OperationPreferredDateUpdater: OperationPreferredDateUpdating {

    let database: DataBrokerProtectionRepository
    private let calculator = OperationPreferredDateCalculator()

    func updateOperationDataDates(origin: OperationPreferredDateUpdaterOrigin,
                                  brokerId: Int64,
                                  profileQueryId: Int64,
                                  extractedProfileId: Int64?,
                                  schedulingConfig: DataBrokerScheduleConfig) throws {

        guard let brokerProfileQuery = try database.brokerProfileQueryData(for: brokerId,
                                                                           and: profileQueryId) else { return }

        try updateScanJobDataDates(origin: origin,
                                   brokerId: brokerId,
                                   profileQueryId: profileQueryId,
                                   extractedProfileId: extractedProfileId,
                                   schedulingConfig: schedulingConfig,
                                   brokerProfileQuery: brokerProfileQuery)

        // We only need to update the optOut date if we have an extracted profile ID
        if let extractedProfileId = extractedProfileId {
            try updateOptOutJobDataDates(origin: origin,
                                         brokerId: brokerId,
                                         profileQueryId: profileQueryId,
                                         extractedProfileId: extractedProfileId,
                                         schedulingConfig: schedulingConfig,
                                         brokerProfileQuery: brokerProfileQuery)
        }
    }

    /// 1, This method fetches scan operations with the profileQueryId and with child sites of parentBrokerId
    /// 2. Then for each one it updates the preferredRunDate of the scan to its confirm scan
    func updateChildrenBrokerForParentBroker(_ parentBroker: DataBroker, profileQueryId: Int64) throws {
        do {
            let childBrokers =  try database.fetchChildBrokers(for: parentBroker.name)

            try childBrokers.forEach { childBroker in
                if let childBrokerId = childBroker.id {
                    let confirmOptOutScanDate = Date().addingTimeInterval(childBroker.schedulingConfig.confirmOptOutScan.hoursToSeconds)
                    try database.updatePreferredRunDate(confirmOptOutScanDate,
                                                        brokerId: childBrokerId,
                                                        profileQueryId: profileQueryId)
                }
            }
        } catch {
            Logger.dataBrokerProtection.error("OperationPreferredDateUpdaterUseCase error: updateChildrenBrokerForParentBroker, error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func updateScanJobDataDates(origin: OperationPreferredDateUpdaterOrigin,
                                        brokerId: Int64,
                                        profileQueryId: Int64,
                                        extractedProfileId: Int64?,
                                        schedulingConfig: DataBrokerScheduleConfig,
                                        brokerProfileQuery: BrokerProfileQueryData) throws {

        let currentScanPreferredRunDate = brokerProfileQuery.scanJobData.preferredRunDate

        var newScanPreferredRunDate = try calculator.dateForScanOperation(currentPreferredRunDate: currentScanPreferredRunDate,
                                                                          historyEvents: brokerProfileQuery.events,
                                                                          extractedProfileID: extractedProfileId,
                                                                          schedulingConfig: schedulingConfig,
                                                                          isDeprecated: brokerProfileQuery.profileQuery.deprecated)
        if let newDate = newScanPreferredRunDate, origin == .optOut {
            newScanPreferredRunDate = returnMostRecentDate(currentScanPreferredRunDate, newDate)
        }

        if newScanPreferredRunDate != currentScanPreferredRunDate {
            Logger.dataBrokerProtection.log("🏴‍☠️ DATE UPDATE: Scan preferredRunDate changing from \(String(describing: currentScanPreferredRunDate), privacy: .public) to \(String(describing: newScanPreferredRunDate), privacy: .public)")
            try updatePreferredRunDate(newScanPreferredRunDate,
                                       brokerId: brokerId,
                                       profileQueryId: profileQueryId,
                                       extractedProfileId: nil)
        }
    }

    private func updateOptOutJobDataDates(origin: OperationPreferredDateUpdaterOrigin,
                                          brokerId: Int64,
                                          profileQueryId: Int64,
                                          extractedProfileId: Int64?,
                                          schedulingConfig: DataBrokerScheduleConfig,
                                          brokerProfileQuery: BrokerProfileQueryData) throws {

        let optOutJob = brokerProfileQuery.optOutJobData.filter { $0.extractedProfile.id == extractedProfileId }.first
        let currentOptOutPreferredRunDate = optOutJob?.preferredRunDate

        var newOptOutPreferredDate = try calculator.dateForOptOutOperation(currentPreferredRunDate: currentOptOutPreferredRunDate,
                                                                           historyEvents: brokerProfileQuery.events,
                                                                           extractedProfileID: extractedProfileId,
                                                                           schedulingConfig: schedulingConfig,
                                                                           attemptCount: optOutJob?.attemptCount)

        if let newDate = newOptOutPreferredDate, origin == .scan {
            newOptOutPreferredDate = returnMostRecentDate(currentOptOutPreferredRunDate, newDate)
        }

        if newOptOutPreferredDate != currentOptOutPreferredRunDate {
            Logger.dataBrokerProtection.log("🏴‍☠️ DATE UPDATE: Opt-out preferredRunDate changing from \(String(describing: currentOptOutPreferredRunDate), privacy: .public) to \(String(describing: newOptOutPreferredDate), privacy: .public)")
            try updatePreferredRunDate(newOptOutPreferredDate,
                                       brokerId: brokerId,
                                       profileQueryId: profileQueryId,
                                       extractedProfileId: extractedProfileId)
        }

        if let extractedProfileId = extractedProfileId,
           let optOutJob = optOutJob,
           let lastEvent = brokerProfileQuery.events.last,
           lastEvent.type == .optOutRequested && optOutJob.submittedSuccessfullyDate == nil
        {
            let submittedSuccessfullyDate = SystemDate().now
            try database.updateSubmittedSuccessfullyDate(submittedSuccessfullyDate, forBrokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
        }
    }

    private func returnMostRecentDate(_ date1: Date?, _ date2: Date?) -> Date? {
        guard let date1 = date1 else { return date2 }
        guard let date2 = date2 else { return date1 }

        return min(date1, date2)
    }

    private func updatePreferredRunDate(_ date: Date?,
                                        brokerId: Int64,
                                        profileQueryId: Int64,
                                        extractedProfileId: Int64?) throws {
        do {
            if let extractedProfileId = extractedProfileId {
                try database.updatePreferredRunDate(date, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
            } else {
                try database.updatePreferredRunDate(date, brokerId: brokerId, profileQueryId: profileQueryId)
            }
        } catch {
            Logger.dataBrokerProtection.error("OperationPreferredDateUpdaterUseCase error: updatePreferredRunDate, error: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        Logger.dataBrokerProtection.log("🏴‍☠️ DATE UPDATE: Updated preferredRunDate to \(String(describing: date), privacy: .public) for brokerId: \(brokerId, privacy: .public), profileQueryId: \(profileQueryId, privacy: .public), extractedProfileId: \(String(describing: extractedProfileId), privacy: .public)")
    }
}

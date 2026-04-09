//
//  DBPContinuedProcessingPlanBuilder.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import DataBrokerProtectionCore
import Foundation

enum DBPContinuedProcessingPlans {
    struct ScanJobID: Hashable, Sendable {
        let brokerId: Int64
        let profileQueryId: Int64
    }

    struct OptOutJobID: Hashable, Sendable {
        let brokerId: Int64
        let profileQueryId: Int64
        let extractedProfileId: Int64
    }

    struct InitialScanPlan {
        let scanJobIDs: [ScanJobID]

        var scanCount: Int {
            scanJobIDs.count
        }
    }

    struct OptOutPlan {
        let optOutJobIDs: [OptOutJobID]

        var optOutCount: Int {
            optOutJobIDs.count
        }
    }
}

/// Builds continued-processing plans from pre-filtered eligible jobs.
enum DBPContinuedProcessingPlanBuilder {
    private struct BrokerQueryKey: Hashable {
        let brokerId: Int64
        let profileQueryId: Int64
    }

    /// Converts eligible scan jobs into an initial scan plan for the progress model.
    static func makeInitialScanPlan(from scanJobs: [ScanJobData]) -> DBPContinuedProcessingPlans.InitialScanPlan {
        let scanJobIDs = scanJobs.map { job in
            DBPContinuedProcessingPlans.ScanJobID(
                brokerId: job.brokerId,
                profileQueryId: job.profileQueryId
            )
        }

        return DBPContinuedProcessingPlans.InitialScanPlan(scanJobIDs: scanJobIDs)
    }

    /// Converts eligible opt-out jobs into an opt-out plan, excluding jobs that runtime would skip.
    static func makeOptOutPlan(
        from optOutJobs: [OptOutJobData],
        brokerProfileQueryData: [BrokerProfileQueryData]
    ) -> DBPContinuedProcessingPlans.OptOutPlan {
        let dataByKey: [BrokerQueryKey: BrokerProfileQueryData] = Dictionary(
            brokerProfileQueryData.compactMap { queryData -> (BrokerQueryKey, BrokerProfileQueryData)? in
                guard let brokerId = queryData.dataBroker.id,
                      let profileQueryId = queryData.profileQuery.id else { return nil }
                return (
                    BrokerQueryKey(brokerId: brokerId, profileQueryId: profileQueryId),
                    queryData
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        let optOutJobIDs = optOutJobs.compactMap { job -> DBPContinuedProcessingPlans.OptOutJobID? in
            guard let extractedProfileId = job.extractedProfile.id else { return nil }
            let key = BrokerQueryKey(brokerId: job.brokerId, profileQueryId: job.profileQueryId)
            guard let queryData = dataByKey[key],
                  shouldIncludeInInitialOptOutProgress(job: job, queryData: queryData) else {
                return nil
            }

            return DBPContinuedProcessingPlans.OptOutJobID(
                brokerId: job.brokerId,
                profileQueryId: job.profileQueryId,
                extractedProfileId: extractedProfileId
            )
        }

        return DBPContinuedProcessingPlans.OptOutPlan(optOutJobIDs: optOutJobIDs)
    }

    /// Filters out opt-out jobs that runtime will skip so they do not inflate the opt-out plan.
    private static func shouldIncludeInInitialOptOutProgress(
        job: OptOutJobData,
        queryData: BrokerProfileQueryData
    ) -> Bool {
        guard job.extractedProfile.removedDate == nil else { return false }
        guard !queryData.dataBroker.performsOptOutWithinParent() else { return false }
        return !job.historyEvents.doesBelongToUserRemovedRecord
    }
}

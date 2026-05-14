//
//  DBPContinuedProcessingPlanBuilderTests.swift
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

import XCTest
@testable import DataBrokerProtection_iOS
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class DBPContinuedProcessingPlanBuilderTests: XCTestCase {

    func testWhenMakeInitialScanPlan_thenMapsScanJobsToScanJobIDs() {
        let scanJobs: [ScanJobData] = [
            .init(brokerId: 1, profileQueryId: 1, preferredRunDate: .now, historyEvents: []),
            .init(brokerId: 2, profileQueryId: 2, preferredRunDate: .now, historyEvents: [])
        ]

        let plan = DBPContinuedProcessingPlanBuilder.makeInitialScanPlan(from: scanJobs)

        XCTAssertEqual(plan.scanJobIDs, [
            DBPContinuedProcessingPlans.ScanJobID(brokerId: 1, profileQueryId: 1),
            DBPContinuedProcessingPlans.ScanJobID(brokerId: 2, profileQueryId: 2)
        ])
    }

    func testWhenMakeOptOutPlan_thenExcludesNonRunnableOptOutJobs() {
        let runnableOptOut = OptOutJobData.mock(
            with: .mockWithoutRemovedDate,
            brokerId: 1,
            profileQueryId: 1,
            preferredRunDate: .now
        )
        let removedOptOut = OptOutJobData.mock(
            with: .mockWithRemovedDate,
            brokerId: 2,
            profileQueryId: 2,
            preferredRunDate: .now
        )
        let parentOptOut = OptOutJobData.mock(
            with: .mockWithoutRemovedDate,
            brokerId: 3,
            profileQueryId: 3,
            preferredRunDate: .now
        )
        let userRemovedOptOut = OptOutJobData.mock(
            with: .mockWithoutRemovedDate,
            brokerId: 4,
            profileQueryId: 4,
            preferredRunDate: .now,
            historyEvents: [.mock(type: .matchRemovedByUser)]
        )

        let brokerProfileQueryData = [
            makeBrokerProfileQueryData(brokerId: 1, profileQueryId: 1, optOutJobData: [runnableOptOut]),
            makeBrokerProfileQueryData(brokerId: 2, profileQueryId: 2, optOutJobData: [removedOptOut]),
            makeBrokerProfileQueryData(brokerId: 3, profileQueryId: 3, dataBroker: .mockWithParentOptOut, optOutJobData: [parentOptOut]),
            makeBrokerProfileQueryData(brokerId: 4, profileQueryId: 4, optOutJobData: [userRemovedOptOut])
        ]

        let plan = DBPContinuedProcessingPlanBuilder.makeOptOutPlan(
            from: [runnableOptOut, removedOptOut, parentOptOut, userRemovedOptOut],
            brokerProfileQueryData: brokerProfileQueryData
        )

        XCTAssertEqual(plan.optOutJobIDs, [
            DBPContinuedProcessingPlans.OptOutJobID(brokerId: 1, profileQueryId: 1, extractedProfileId: 1)
        ])
    }

    func testWhenMakeOptOutPlanWithDuplicateBrokerQueryPairs_thenDoesNotCrash() {
        let sharedBrokerId: Int64 = 1
        let sharedProfileQueryId: Int64 = 1

        let optOut1 = OptOutJobData.mock(
            with: .mockWithoutRemovedDate,
            brokerId: sharedBrokerId,
            profileQueryId: sharedProfileQueryId,
            preferredRunDate: .now
        )
        let optOut2 = OptOutJobData.mock(
            with: .mockWithoutRemovedDate,
            brokerId: sharedBrokerId,
            profileQueryId: sharedProfileQueryId,
            preferredRunDate: .now
        )

        let brokerProfileQueryData = [
            makeBrokerProfileQueryData(brokerId: sharedBrokerId, profileQueryId: sharedProfileQueryId, optOutJobData: [optOut1]),
            makeBrokerProfileQueryData(brokerId: sharedBrokerId, profileQueryId: sharedProfileQueryId, optOutJobData: [optOut2])
        ]

        let plan = DBPContinuedProcessingPlanBuilder.makeOptOutPlan(
            from: [optOut1, optOut2],
            brokerProfileQueryData: brokerProfileQueryData
        )

        XCTAssertGreaterThanOrEqual(plan.optOutCount, 0)
    }

    private func makeBrokerProfileQueryData(
        brokerId: Int64,
        profileQueryId: Int64,
        dataBroker: DataBroker? = nil,
        scanPreferredRunDate: Date? = .now,
        optOutJobData: [OptOutJobData] = []
    ) -> BrokerProfileQueryData {
        BrokerProfileQueryData(
            dataBroker: dataBroker ?? .mock(withId: brokerId),
            profileQuery: ProfileQuery(id: profileQueryId, firstName: "A", lastName: "B", city: "C", state: "D", birthYear: 1980),
            scanJobData: .init(
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                preferredRunDate: scanPreferredRunDate,
                historyEvents: []
            ),
            optOutJobData: optOutJobData
        )
    }
}

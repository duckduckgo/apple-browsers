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

    func testWhenMakeInitialScanPlan_thenIncludesOnlyEligibleManualScanJobs() {
        let plan = DBPContinuedProcessingPlanBuilder.makeInitialScanPlan(
            from: [
                makeBrokerProfileQueryData(brokerId: 1, profileQueryId: 1, scanPreferredRunDate: .now),
                makeBrokerProfileQueryData(brokerId: 2, profileQueryId: 2, scanPreferredRunDate: nil),
                makeBrokerProfileQueryData(brokerId: 3, profileQueryId: 3, scanPreferredRunDate: .now.addingTimeInterval(.hours(1)))
            ],
            priorityDate: .now
        )

        XCTAssertEqual(plan.scanJobIDs, [
            DBPContinuedProcessingPlans.ScanJobID(brokerId: 1, profileQueryId: 1)
        ])
    }

    func testWhenMakeOptOutPlan_thenExcludesNonRunnableOptOutJobs() {
        let plan = DBPContinuedProcessingPlanBuilder.makeOptOutPlan(
            from: [
                makeBrokerProfileQueryData(
                    brokerId: 1,
                    profileQueryId: 1,
                    optOutJobData: [
                        .mock(
                            with: .mockWithoutRemovedDate,
                            brokerId: 1,
                            profileQueryId: 1,
                            preferredRunDate: .now
                        )
                    ]
                ),
                makeBrokerProfileQueryData(
                    brokerId: 2,
                    profileQueryId: 2,
                    optOutJobData: [
                        .mock(
                            with: .mockWithRemovedDate,
                            brokerId: 2,
                            profileQueryId: 2,
                            preferredRunDate: .now
                        )
                    ]
                ),
                makeBrokerProfileQueryData(
                    brokerId: 3,
                    profileQueryId: 3,
                    dataBroker: .mockWithParentOptOut,
                    optOutJobData: [
                        .mock(
                            with: .mockWithoutRemovedDate,
                            brokerId: 3,
                            profileQueryId: 3,
                            preferredRunDate: .now
                        )
                    ]
                ),
                makeBrokerProfileQueryData(
                    brokerId: 4,
                    profileQueryId: 4,
                    optOutJobData: [
                        .mock(
                            with: .mockWithoutRemovedDate,
                            brokerId: 4,
                            profileQueryId: 4,
                            preferredRunDate: .now,
                            historyEvents: [.mock(type: .matchRemovedByUser)]
                        )
                    ]
                )
            ],
            priorityDate: .now
        )

        XCTAssertEqual(plan.optOutJobIDs, [
            DBPContinuedProcessingPlans.OptOutJobID(brokerId: 1, profileQueryId: 1, extractedProfileId: 1)
        ])
    }

    func testWhenMakeOptOutPlanWithDuplicateBrokerQueryPairs_thenDoesNotCrash() {
        let sharedBrokerId: Int64 = 1
        let sharedProfileQueryId: Int64 = 1

        let plan = DBPContinuedProcessingPlanBuilder.makeOptOutPlan(
            from: [
                makeBrokerProfileQueryData(
                    brokerId: sharedBrokerId,
                    profileQueryId: sharedProfileQueryId,
                    optOutJobData: [
                        .mock(
                            with: .mockWithoutRemovedDate,
                            brokerId: sharedBrokerId,
                            profileQueryId: sharedProfileQueryId,
                            preferredRunDate: .now
                        )
                    ]
                ),
                makeBrokerProfileQueryData(
                    brokerId: sharedBrokerId,
                    profileQueryId: sharedProfileQueryId,
                    optOutJobData: [
                        .mock(
                            with: .mockWithoutRemovedDate,
                            brokerId: sharedBrokerId,
                            profileQueryId: sharedProfileQueryId,
                            preferredRunDate: .now
                        )
                    ]
                )
            ],
            priorityDate: .now
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

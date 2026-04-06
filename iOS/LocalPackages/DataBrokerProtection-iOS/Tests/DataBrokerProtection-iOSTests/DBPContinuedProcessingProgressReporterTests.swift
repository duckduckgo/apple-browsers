//
//  DBPContinuedProcessingProgressReporterTests.swift
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

final class DBPContinuedProcessingProgressReporterTests: XCTestCase {

    func testWhenStartInitialRun_thenReservesFixedFiftyFiftyBudget() {
        let sut = DBPContinuedProcessingProgressReporter()

        sut.startInitialRun(
            plan: DBPContinuedProcessingPlans.InitialScanPlan(scanJobIDs: [
                .init(brokerId: 1, profileQueryId: 1),
                .init(brokerId: 2, profileQueryId: 2),
                .init(brokerId: 3, profileQueryId: 3)
            ]),
            scanJobTimeout: 120, heartbeatInterval: 1
        )

        let snapshot = sut.snapshot()

        XCTAssertEqual(snapshot.completed, 0)
        XCTAssertEqual(snapshot.total, 720)
    }

    func testWhenAdvanceHeartbeat_thenConsumesBudgetBeforeGrowingTotal() {
        let sut = DBPContinuedProcessingProgressReporter()

        sut.startInitialRun(
            plan: DBPContinuedProcessingPlans.InitialScanPlan(scanJobIDs: [
                .init(brokerId: 1, profileQueryId: 1)
            ]),
            scanJobTimeout: 2, heartbeatInterval: 1
        )

        sut.advanceHeartbeat()
        XCTAssertEqual(sut.snapshot().completed, 1)
        XCTAssertEqual(sut.snapshot().total, 4)

        sut.advanceHeartbeat()
        XCTAssertEqual(sut.snapshot().completed, 2)
        XCTAssertEqual(sut.snapshot().total, 4)

        sut.advanceHeartbeat()
        XCTAssertEqual(sut.snapshot().completed, 3)
        XCTAssertEqual(sut.snapshot().total, 5)
    }

    func testWhenRecordCompletedScan_thenCompletedSnapsToCompletedScanAllotment() {
        let sut = DBPContinuedProcessingProgressReporter()
        let firstScan = DBPContinuedProcessingPlans.ScanJobID(brokerId: 1, profileQueryId: 1)
        let secondScan = DBPContinuedProcessingPlans.ScanJobID(brokerId: 2, profileQueryId: 2)

        sut.startInitialRun(
            plan: DBPContinuedProcessingPlans.InitialScanPlan(scanJobIDs: [firstScan, secondScan]),
            scanJobTimeout: 120, heartbeatInterval: 1
        )

        sut.recordCompletedScan(firstScan)

        XCTAssertEqual(sut.snapshot().completed, 120)
        XCTAssertEqual(sut.snapshot().total, 480)

        sut.recordCompletedScan(secondScan)

        XCTAssertEqual(sut.snapshot().completed, 240)
    }

    func testWhenEnterOptOutPhase_thenReservedHalfIsDistributedAcrossOptOuts() {
        let sut = DBPContinuedProcessingProgressReporter()
        let firstOptOut = DBPContinuedProcessingPlans.OptOutJobID(brokerId: 1, profileQueryId: 1, extractedProfileId: 11)
        let secondOptOut = DBPContinuedProcessingPlans.OptOutJobID(brokerId: 2, profileQueryId: 2, extractedProfileId: 22)
        let thirdOptOut = DBPContinuedProcessingPlans.OptOutJobID(brokerId: 3, profileQueryId: 3, extractedProfileId: 33)

        sut.startInitialRun(
            plan: DBPContinuedProcessingPlans.InitialScanPlan(scanJobIDs: [
                .init(brokerId: 1, profileQueryId: 1),
                .init(brokerId: 2, profileQueryId: 2)
            ]),
            scanJobTimeout: 181, heartbeatInterval: 1
        )

        sut.enterOptOutPhase(plan: DBPContinuedProcessingPlans.OptOutPlan(optOutJobIDs: [firstOptOut, secondOptOut, thirdOptOut]))
        sut.recordCompletedOptOut(firstOptOut)

        XCTAssertEqual(sut.snapshot().completed, 121)
        XCTAssertEqual(sut.snapshot().total, 724)

        sut.recordCompletedOptOut(secondOptOut)

        XCTAssertEqual(sut.snapshot().completed, 242)
    }

    func testWhenRecordCompletedOptOut_thenCompletedSnapsToCompletedOptOutAllotment() {
        let sut = DBPContinuedProcessingProgressReporter()
        let firstOptOut = DBPContinuedProcessingPlans.OptOutJobID(brokerId: 1, profileQueryId: 1, extractedProfileId: 11)
        let secondOptOut = DBPContinuedProcessingPlans.OptOutJobID(brokerId: 2, profileQueryId: 2, extractedProfileId: 22)

        sut.startInitialRun(
            plan: DBPContinuedProcessingPlans.InitialScanPlan(scanJobIDs: [
                .init(brokerId: 1, profileQueryId: 1)
            ]),
            scanJobTimeout: 120, heartbeatInterval: 1
        )
        sut.enterOptOutPhase(plan: DBPContinuedProcessingPlans.OptOutPlan(optOutJobIDs: [firstOptOut, secondOptOut]))

        sut.recordCompletedOptOut(secondOptOut)

        XCTAssertEqual(sut.snapshot().completed, 60)

        sut.recordCompletedOptOut(firstOptOut)

        XCTAssertEqual(sut.snapshot().completed, 120)
        XCTAssertEqual(sut.snapshot().total, 240)
    }

    func testWhenCompleteAll_thenSnapshotIsFullyComplete() {
        let sut = DBPContinuedProcessingProgressReporter()

        sut.startInitialRun(
            plan: DBPContinuedProcessingPlans.InitialScanPlan(scanJobIDs: [
                .init(brokerId: 1, profileQueryId: 1)
            ]),
            scanJobTimeout: 120, heartbeatInterval: 1
        )
        sut.enterOptOutPhase(plan: DBPContinuedProcessingPlans.OptOutPlan(optOutJobIDs: [
            .init(brokerId: 1, profileQueryId: 1, extractedProfileId: 11)
        ]))

        sut.completeAll()

        let snapshot = sut.snapshot()

        XCTAssertEqual(snapshot.completed, snapshot.total)
        XCTAssertEqual(snapshot.completed, 240)
    }
}

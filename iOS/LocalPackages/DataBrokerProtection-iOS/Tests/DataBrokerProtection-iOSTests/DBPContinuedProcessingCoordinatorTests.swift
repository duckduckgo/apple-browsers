//
//  DBPContinuedProcessingCoordinatorTests.swift
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

@available(iOS 26.0, *)
@MainActor
final class DBPContinuedProcessingCoordinatorTests: XCTestCase {

    func testWhenScanPhaseCompletesAndNoInitialOptOuts_thenDoesNotStartImmediateOptOutsAndClearsDelegate() async {
        let (manager, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(brokerId: 1, profileQueryId: 1)
        ]
        let sut = DBPContinuedProcessingCoordinator(manager: manager)
        manager.continuedProcessingDelegate = sut

        await sut.handleScanPhaseCompleted()

        XCTAssertFalse(dependencies.queueManager.didCallStartImmediateOptOutOperationsIfPermitted)
        XCTAssertNil(manager.continuedProcessingDelegate)
    }

    func testWhenScanPhaseCompletesAndInitialOptOutsExist_thenStartsImmediateOptOuts() async {
        let (manager, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(
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
            )
        ]
        let sut = DBPContinuedProcessingCoordinator(manager: manager)
        manager.continuedProcessingDelegate = sut

        await sut.handleScanPhaseCompleted()
        await Task.yield()

        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateOptOutOperationsIfPermitted)
    }

    func testWhenScanPhaseCompletesAndDeterminingOptOutsFails_thenDoesNotStartImmediateOptOutsAndClearsDelegate() async {
        let (manager, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.fetchAllBrokerProfileQueryDataError = NSError(domain: "test", code: 1)
        let sut = DBPContinuedProcessingCoordinator(manager: manager)
        manager.continuedProcessingDelegate = sut

        await sut.handleScanPhaseCompleted()

        XCTAssertFalse(dependencies.queueManager.didCallStartImmediateOptOutOperationsIfPermitted)
        XCTAssertNil(manager.continuedProcessingDelegate)
    }

    func testWhenExpire_thenStopsContinuedProcessingOperationsAndClearsDelegate() async {
        let (manager, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        let sut = DBPContinuedProcessingCoordinator(manager: manager)
        manager.continuedProcessingDelegate = sut

        await sut.expire()

        XCTAssertTrue(dependencies.queueManager.didCallStop)
        XCTAssertNil(manager.continuedProcessingDelegate)
    }
}

//
//  DataBrokerProtectionIOSManagerContinuedProcessingTests.swift
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

@MainActor
final class DataBrokerProtectionIOSManagerContinuedProcessingTests: XCTestCase {

    func testWhenPrepareContinuedProcessingInitialRunAndPendingScansExist_thenReturnsInitialScanPlan() async throws {
        // Given
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(
                brokerId: 1,
                profileQueryId: 1,
                scanPreferredRunDate: .now
            )
        ]

        // When
        let initialScanPlan = try await sut.prepareContinuedProcessingInitialRun(profile: DBPContinuedProcessingTestUtils.makeProfile())

        // Then
        XCTAssertEqual(initialScanPlan?.scanCount, 1)
        XCTAssertTrue(dependencies.database.wasSaveProfileCalled)
        XCTAssertTrue(dependencies.eventsHandler.profileSavedFired)
    }

    func testWhenCoordinatorIsReadyForScanOperations_thenStartsQueueAndEmitsScanPhaseCompleted() async {
        // Given
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        let expectation = expectation(description: "scan phase completed")
        dependencies.continuedProcessingCoordinator.onEvent = { event in
            if case .scanPhaseCompleted = event {
                expectation.fulfill()
            }
        }

        // When
        await sut.coordinatorIsReadyForScanOperations()
        await fulfillment(of: [expectation], timeout: 1)

        // Then
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testWhenCoordinatorIsReadyForOptOutOperations_thenStartsQueueAndEmitsOptOutPhaseCompleted() async {
        // Given
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        let expectation = expectation(description: "opt-out phase completed")
        dependencies.continuedProcessingCoordinator.onEvent = { event in
            if case .optOutPhaseCompleted = event {
                expectation.fulfill()
            }
        }

        // When
        sut.coordinatorIsReadyForOptOutOperations()
        await fulfillment(of: [expectation], timeout: 1)

        // Then
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateOptOutOperationsIfPermitted)
    }

    func testWhenCoordinatorDidRequestStopOperations_thenStopsQueue() {
        // Given
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()

        // When
        sut.coordinatorDidRequestStopOperations()

        // Then
        XCTAssertTrue(dependencies.queueManager.didCallStop)
    }

    func testWhenSaveProfileAndFeatureFlagIsOff_thenFallsBackToLegacySave() async throws {
        // Given
        let featureFlagger = MockDBPFeatureFlagger(isContinuedProcessingFeatureOn: false)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)

        // When
        try await sut.saveProfile(DBPContinuedProcessingTestUtils.makeProfile())

        // Then
        XCTAssertFalse(dependencies.continuedProcessingCoordinator.didCallStartInitialRun)
        XCTAssertTrue(dependencies.database.wasSaveProfileCalled)
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testWhenSaveProfileAndFeatureFlagIsOn_thenStartsContinuedProcessing() async throws {
        // Given
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(
            featureFlagger: MockDBPFeatureFlagger(isContinuedProcessingFeatureOn: true)
        )
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(
                brokerId: 1,
                profileQueryId: 1,
                scanPreferredRunDate: .now
            )
        ]

        // When
        try await sut.saveProfile(DBPContinuedProcessingTestUtils.makeProfile())

        // Then
        XCTAssertTrue(dependencies.continuedProcessingCoordinator.didCallStartInitialRun)
        XCTAssertEqual(dependencies.continuedProcessingCoordinator.receivedScanPlan?.scanCount, 1)
        XCTAssertTrue(dependencies.database.wasSaveProfileCalled)
        XCTAssertFalse(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testWhenSaveProfileAndContinuedProcessingStartFails_thenFallsBackToImmediateScansWithoutPreparingTwice() async throws {
        // Given
        let coordinator = MockContinuedProcessingCoordinator()
        coordinator.startInitialRunError = NSError(domain: "test", code: 1)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(
            featureFlagger: MockDBPFeatureFlagger(isContinuedProcessingFeatureOn: true),
            continuedProcessingCoordinator: coordinator
        )
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(
                brokerId: 1,
                profileQueryId: 1,
                scanPreferredRunDate: .now
            )
        ]

        // When
        try await sut.saveProfile(DBPContinuedProcessingTestUtils.makeProfile())

        // Then
        XCTAssertTrue(dependencies.continuedProcessingCoordinator.didCallStartInitialRun)
        XCTAssertTrue(dependencies.database.wasSaveProfileCalled)
        XCTAssertEqual(dependencies.database.saveProfileCallCount, 1)
        XCTAssertEqual(dependencies.eventsHandler.profileSavedFireCount, 1)
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }
}

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

    func testWhenStartImmediateScanOperationsForContinuedProcessing_thenStartsQueueAndEmitsScanPhaseCompleted() async {
        // Given
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        let delegate = MockContinuedProcessingEventDelegate()
        let expectation = expectation(description: "scan phase completed")
        delegate.onEvent = { event in
            if case .scanPhaseCompleted = event {
                expectation.fulfill()
            }
        }
        sut.continuedProcessingDelegate = delegate

        // When
        await sut.startImmediateScanOperationsForContinuedProcessing()
        await fulfillment(of: [expectation], timeout: 1)

        // Then
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testWhenStartImmediateOptOutOperationsForContinuedProcessing_thenStartsQueueAndEmitsOptOutPhaseCompleted() async {
        // Given
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        let delegate = MockContinuedProcessingEventDelegate()
        let expectation = expectation(description: "opt-out phase completed")
        delegate.onEvent = { event in
            if case .optOutPhaseCompleted = event {
                expectation.fulfill()
            }
        }
        sut.continuedProcessingDelegate = delegate

        // When
        sut.startImmediateOptOutOperationsForContinuedProcessing()
        await fulfillment(of: [expectation], timeout: 1)

        // Then
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateOptOutOperationsIfPermitted)
    }

    func testWhenStopContinuedProcessingOperations_thenStopsQueue() {
        // Given
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()

        // When
        sut.stopContinuedProcessingOperations()

        // Then
        XCTAssertTrue(dependencies.queueManager.didCallStop)
    }

    func testWhenSaveProfileAndStartInitialRunAndFeatureFlagIsOff_thenFallsBackToLegacySave() async throws {
        // Given
        let featureFlagger = MockDBPFeatureFlagger(isContinuedProcessingFeatureOn: false)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)

        // When
        try await sut.saveProfileAndStartContinuedProcessingInitialRunIfSupported(DBPContinuedProcessingTestUtils.makeProfile())

        // Then
        XCTAssertFalse(dependencies.continuedProcessingCoordinator.didCallStartInitialRun)
        XCTAssertTrue(dependencies.database.wasSaveProfileCalled)
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testWhenSaveProfileAndStartInitialRunAndContinuedProcessingIsNotSupported_thenFallsBackToLegacySave() async throws {
        // Given
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(
            continuedProcessingTestConfiguration: .init(shouldUseContinuedProcessingForInitialRun: false)
        )

        // When
        try await sut.saveProfileAndStartContinuedProcessingInitialRunIfSupported(DBPContinuedProcessingTestUtils.makeProfile())

        // Then
        XCTAssertFalse(dependencies.continuedProcessingCoordinator.didCallStartInitialRun)
        XCTAssertTrue(dependencies.database.wasSaveProfileCalled)
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testWhenSaveProfileAndStartInitialRunAndFeatureFlagIsOn_thenStartsContinuedProcessing() async throws {
        // Given
        let continuedProcessingCoordinator = MockContinuedProcessingCoordinator()
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(
            continuedProcessingTestConfiguration: .init(
                coordinator: continuedProcessingCoordinator,
                shouldUseContinuedProcessingForInitialRun: true
            )
        )
        let profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(
                brokerId: 1,
                profileQueryId: 1,
                scanPreferredRunDate: .now
            )
        ]

        // When
        try await sut.saveProfileAndStartContinuedProcessingInitialRunIfSupported(profile)

        // Then
        XCTAssertTrue(dependencies.continuedProcessingCoordinator.didCallStartInitialRun)
        XCTAssertEqual(dependencies.continuedProcessingCoordinator.receivedScanPlan?.scanCount, 1)
        XCTAssertTrue(dependencies.database.wasSaveProfileCalled)
        XCTAssertFalse(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testWhenSaveProfileAndStartInitialRunAndContinuedProcessingStartFails_thenFallsBackToImmediateScansWithoutPreparingTwice() async throws {
        // Given
        let continuedProcessingCoordinator = MockContinuedProcessingCoordinator()
        continuedProcessingCoordinator.startInitialRunError = NSError(domain: "test", code: 1)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(
            continuedProcessingTestConfiguration: .init(
                coordinator: continuedProcessingCoordinator,
                shouldUseContinuedProcessingForInitialRun: true
            )
        )
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(
                brokerId: 1,
                profileQueryId: 1,
                scanPreferredRunDate: .now
            )
        ]

        // When
        try await sut.saveProfileAndStartContinuedProcessingInitialRunIfSupported(DBPContinuedProcessingTestUtils.makeProfile())

        // Then
        XCTAssertTrue(dependencies.continuedProcessingCoordinator.didCallStartInitialRun)
        XCTAssertTrue(dependencies.database.wasSaveProfileCalled)
        XCTAssertEqual(dependencies.database.saveProfileCallCount, 1)
        XCTAssertEqual(dependencies.eventsHandler.profileSavedFireCount, 1)
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }
}

//
//  SparkleUpdateWideEventTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

#if SPARKLE

import XCTest
import PixelKitTestingUtilities
import PrivacyConfig
import PixelKit
@testable import DuckDuckGo_Privacy_Browser

final class SparkleUpdateWideEventTests: XCTestCase {

    private var sut: SparkleUpdateWideEvent!
    private var mockWideEventManager: WideEventMock!
    private var mockInternalUserDecider: MockInternalUserDecider!

    override func setUp() {
        super.setUp()
        mockWideEventManager = WideEventMock()
        mockInternalUserDecider = MockInternalUserDecider()
        sut = SparkleUpdateWideEvent(
            wideEventManager: mockWideEventManager,
            internalUserDecider: mockInternalUserDecider,
            areAutomaticUpdatesEnabled: true
        )
    }

    override func tearDown() {
        sut = nil
        mockWideEventManager = nil
        mockInternalUserDecider = nil
        super.tearDown()
    }

    // MARK: - A. Flow Lifecycle Tests (Happy Paths)

    func test_startFlow_automaticInitiation_createsFlowWithCorrectData() {
        // When
        sut.startFlow(initiationType: .automatic)

        // Then
        XCTAssertEqual(mockWideEventManager.started.count, 1)
        let startedData = mockWideEventManager.started.first as? UpdateWideEventData
        XCTAssertNotNil(startedData)
        XCTAssertEqual(startedData?.initiationType, .automatic)
        XCTAssertEqual(startedData?.updateConfiguration, .automatic)
        XCTAssertEqual(startedData?.lastKnownStep, .updateCheckStarted)
        XCTAssertNotNil(startedData?.updateCheckDuration)
        XCTAssertNotNil(startedData?.totalDuration)
    }

    func test_startFlow_manualInitiation_setsCorrectInitiationType() {
        // When
        sut.startFlow(initiationType: .manual)

        // Then
        XCTAssertEqual(mockWideEventManager.started.count, 1)
        let startedData = mockWideEventManager.started.first as? UpdateWideEventData
        XCTAssertEqual(startedData?.initiationType, .manual)
    }

    /// Tests that "no update available" completes the flow with success status and reason.
    ///
    /// This belongs in happy path tests because it represents successful system behavior,
    /// not a failure. This outcome helps establish baseline success rates for update checks.
    func test_completeFlow_noUpdateAvailable_completesFlowWithSuccessAndReason() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.completeFlow(status: .success(reason: "no_update_available"))

        // Then
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (completedData, status) = mockWideEventManager.completions[0]
        XCTAssertTrue(completedData is UpdateWideEventData)
        if case .success(let reason) = status {
            XCTAssertEqual(reason, "no_update_available")
        } else {
            XCTFail("Expected success status with no_update_available reason")
        }
    }

    func test_updateFlow_updateFound_populatesVersionAndBuildInfo() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.didFindUpdate(version: "1.2.3", build: "456", isCritical: false)

        // Then
        XCTAssertEqual(mockWideEventManager.updates.count, 1)
        let updatedData = mockWideEventManager.updates.first as? UpdateWideEventData
        XCTAssertEqual(updatedData?.toVersion, "1.2.3")
        XCTAssertEqual(updatedData?.toBuild, "456")
        XCTAssertEqual(updatedData?.updateType, .regular)
    }

    func test_updateFlow_criticalUpdate_setsUpdateTypeToCritical() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.didFindUpdate(version: "1.2.3", build: "456", isCritical: true)

        // Then
        let updatedData = mockWideEventManager.updates.first as? UpdateWideEventData
        XCTAssertEqual(updatedData?.updateType, .critical)
    }

    func test_updateFlow_downloadStarted_startsDownloadDuration() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.didStartDownload()

        // Then
        let updatedData = mockWideEventManager.updates.first as? UpdateWideEventData
        XCTAssertNotNil(updatedData?.downloadDuration)
        XCTAssertEqual(updatedData?.lastKnownStep, .downloadStarted)
    }

    func test_updateFlow_extractionStarted_completesDownloadAndStartsExtraction() {
        // Given
        sut.startFlow(initiationType: .automatic)
        sut.didStartDownload()

        // When
        sut.didStartExtraction()

        // Then
        let updatedData = mockWideEventManager.updates.last as? UpdateWideEventData
        XCTAssertNotNil(updatedData?.extractionDuration)
        XCTAssertEqual(updatedData?.lastKnownStep, .extractionStarted)
    }

    func test_updateFlow_extractionCompleted_completesExtractionDuration() {
        // Given
        sut.startFlow(initiationType: .automatic)
        sut.didStartDownload()
        sut.didStartExtraction()

        // When
        sut.didCompleteExtraction()

        // Then
        let updatedData = mockWideEventManager.updates.last as? UpdateWideEventData
        XCTAssertEqual(updatedData?.lastKnownStep, .extractionCompleted)
    }

    func test_completeFlow_success_completesFlowWithSuccessStatus() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.completeFlow(status: .success)

        // Then
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (_, status) = mockWideEventManager.completions[0]
        if case .success = status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected success status")
        }
    }

    func test_completeFlow_updateInstalled_includesSuccessReasonInPixel() {
        // Given
        sut.startFlow(initiationType: .automatic)
        sut.didFindUpdate(version: "1.1.0", build: "110", isCritical: false)

        // When
        sut.completeFlow(status: .success(reason: "restarting_to_update"))

        // Then
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (completedData, status) = mockWideEventManager.completions[0]
        if case .success(let reason) = status {
            XCTAssertEqual(reason, "restarting_to_update")
        } else {
            XCTFail("Expected success status with restarting_to_update reason")
        }

        // Verify pixel parameters would include the version info
        let pixelParams = (completedData as? UpdateWideEventData)?.pixelParameters() ?? [:]
        XCTAssertEqual(pixelParams["feature.data.ext.to_version"], "1.1.0")
    }

    // MARK: - B. Overlapping Flow Tests

    func test_startFlow_whilePreviousFlowActive_completesOldFlowAsIncomplete() {
        // Given - start first flow
        sut.startFlow(initiationType: .automatic)
        sut.didStartDownload()

        // When - start second flow
        sut.startFlow(initiationType: .manual)

        // Then
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (_, status) = mockWideEventManager.completions[0]
        if case .unknown(let reason) = status {
            XCTAssertEqual(reason, "incomplete")
        } else {
            XCTFail("Expected unknown status with incomplete reason")
        }

        // Verify new flow started
        XCTAssertEqual(mockWideEventManager.started.count, 2)
        let secondFlow = mockWideEventManager.started.last as? UpdateWideEventData
        XCTAssertEqual(secondFlow?.initiationType, .manual)
    }

    func test_startFlow_completesOldFlow_beforeStartingNew() {
        // Given
        sut.startFlow(initiationType: .automatic)
        sut.didFindUpdate(version: "1.0.0", build: "100", isCritical: false)
        sut.didStartDownload()

        let firstFlowID = (mockWideEventManager.started.first as? UpdateWideEventData)?.globalData.id

        // When
        sut.startFlow(initiationType: .manual)

        // Then - old flow completed
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (completedData, _) = mockWideEventManager.completions[0]
        XCTAssertEqual((completedData as? UpdateWideEventData)?.globalData.id, firstFlowID)

        // New flow started
        let secondFlowID = (mockWideEventManager.started.last as? UpdateWideEventData)?.globalData.id
        XCTAssertNotEqual(firstFlowID, secondFlowID)
    }

    // MARK: - C. Cancellation Tests

    func test_cancelFlow_appQuit_recordsCancellationReason() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.cancelFlow(reason: .appQuit)

        // Then
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (completedData, status) = mockWideEventManager.completions[0]
        XCTAssertEqual((completedData as? UpdateWideEventData)?.cancellationReason, .appQuit)
        if case .cancelled = status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected cancelled status")
        }
    }

    func test_cancelFlow_settingsChanged_recordsCancellationReason() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.cancelFlow(reason: .settingsChanged)

        // Then
        let (completedData, _) = mockWideEventManager.completions[0]
        XCTAssertEqual((completedData as? UpdateWideEventData)?.cancellationReason, .settingsChanged)
    }

    func test_cancelFlow_buildExpired_recordsCancellationReason() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.cancelFlow(reason: .buildExpired)

        // Then
        let (completedData, _) = mockWideEventManager.completions[0]
        XCTAssertEqual((completedData as? UpdateWideEventData)?.cancellationReason, .buildExpired)
    }

    func test_cancelFlow_newCheckStarted_recordsCancellationReason() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.cancelFlow(reason: .newCheckStarted)

        // Then
        let (completedData, _) = mockWideEventManager.completions[0]
        XCTAssertEqual((completedData as? UpdateWideEventData)?.cancellationReason, .newCheckStarted)
    }

    func test_cancelFlow_completesAllDurations() {
        // Given - start flow with multiple stages
        sut.startFlow(initiationType: .automatic)
        sut.didFindUpdate(version: "1.0.0", build: "100", isCritical: false)
        sut.didStartDownload()
        sut.didStartExtraction()

        // When
        sut.cancelFlow(reason: .settingsChanged)

        // Then - verify all durations are present (completed by cancelFlow)
        let (completedData, _) = mockWideEventManager.completions[0]
        let updateData = completedData as? UpdateWideEventData
        XCTAssertNotNil(updateData?.totalDuration)
        XCTAssertNotNil(updateData?.downloadDuration)
        XCTAssertNotNil(updateData?.extractionDuration)
    }

    // MARK: - D. Duration Measurement Tests

    func test_updateFlow_updateFound_completesUpdateCheckDuration() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.didFindUpdate(version: "1.0.0", build: "100", isCritical: false)

        // Then
        let updatedData = mockWideEventManager.updates.first as? UpdateWideEventData
        XCTAssertNotNil(updatedData?.updateCheckDuration)
    }

    func test_completeFlow_completesAllActiveDurations() {
        // Given
        sut.startFlow(initiationType: .automatic)
        sut.didFindUpdate(version: "1.0.0", build: "100", isCritical: false)
        sut.didStartDownload()

        // When
        sut.completeFlow(status: .success)

        // Then - verify durations are present in completed flow
        let (completedData, _) = mockWideEventManager.completions[0]
        let updateData = completedData as? UpdateWideEventData
        XCTAssertNotNil(updateData?.totalDuration)
        XCTAssertNotNil(updateData?.updateCheckDuration)
        XCTAssertNotNil(updateData?.downloadDuration)
    }

    // MARK: - E. Data Integrity Tests

    func test_startFlow_withAutomaticUpdatesEnabled_setsAutomaticConfiguration() {
        // Given - sut initialized with automatic updates enabled

        // When
        sut.startFlow(initiationType: .automatic)

        // Then
        let startedData = mockWideEventManager.started.first as? UpdateWideEventData
        XCTAssertEqual(startedData?.updateConfiguration, .automatic)
    }

    func test_startFlow_withManualUpdatesEnabled_setsManualConfiguration() {
        // Given
        let manualSut = SparkleUpdateWideEvent(
            wideEventManager: mockWideEventManager,
            internalUserDecider: mockInternalUserDecider,
            areAutomaticUpdatesEnabled: false
        )

        // When
        manualSut.startFlow(initiationType: .manual)

        // Then
        let startedData = mockWideEventManager.started.first as? UpdateWideEventData
        XCTAssertEqual(startedData?.updateConfiguration, .manual)
    }

    func test_startFlow_internalUser_setsInternalUserFlag() {
        // Given
        mockInternalUserDecider.isInternalUser = true
        let internalSut = SparkleUpdateWideEvent(
            wideEventManager: mockWideEventManager,
            internalUserDecider: mockInternalUserDecider,
            areAutomaticUpdatesEnabled: true
        )

        // When
        internalSut.startFlow(initiationType: .automatic)

        // Then
        let startedData = mockWideEventManager.started.first as? UpdateWideEventData
        XCTAssertEqual(startedData?.isInternalUser, true)
    }

    func test_startFlow_externalUser_doesNotSetInternalUserFlag() {
        // Given
        mockInternalUserDecider.isInternalUser = false

        // When
        sut.startFlow(initiationType: .automatic)

        // Then
        let startedData = mockWideEventManager.started.first as? UpdateWideEventData
        XCTAssertEqual(startedData?.isInternalUser, false)
    }

    func test_updateFlow_tracksLastKnownStep() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When - progress through stages
        sut.didFindUpdate(version: "1.0.0", build: "100", isCritical: false)
        var lastUpdate = mockWideEventManager.updates.last as? UpdateWideEventData
        XCTAssertEqual(lastUpdate?.lastKnownStep, .updateFound)

        sut.didStartDownload()
        lastUpdate = mockWideEventManager.updates.last as? UpdateWideEventData
        XCTAssertEqual(lastUpdate?.lastKnownStep, .downloadStarted)

        sut.didStartExtraction()
        lastUpdate = mockWideEventManager.updates.last as? UpdateWideEventData
        XCTAssertEqual(lastUpdate?.lastKnownStep, .extractionStarted)

        sut.didCompleteExtraction()
        lastUpdate = mockWideEventManager.updates.last as? UpdateWideEventData
        XCTAssertEqual(lastUpdate?.lastKnownStep, .extractionCompleted)
    }

    func test_updateFlow_updateFound_calculatesTimeSinceLastUpdateBucket() {
        let lastUpdateDate = Date().addingTimeInterval(-TimeInterval.days(7))
        SparkleUpdateWideEvent.lastSuccessfulUpdateDate = lastUpdateDate
        sut.startFlow(initiationType: .automatic)

        sut.didFindUpdate(version: "1.0.0", build: "100", isCritical: false)

        let updatedData = mockWideEventManager.updates.first as? UpdateWideEventData
        XCTAssertNotNil(updatedData?.timeSinceLastUpdateBucket)
        XCTAssertEqual(updatedData?.timeSinceLastUpdateBucket, .lessThan1Month)

        let params = updatedData?.pixelParameters()
        XCTAssertEqual(params?["feature.data.ext.time_since_last_update"], "<1M")

        SparkleUpdateWideEvent.lastSuccessfulUpdateDate = nil
    }

    func test_completeFlow_failure_includesDiskSpaceInfo() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.completeFlow(status: .failure)

        // Then
        let (completedData, _) = mockWideEventManager.completions[0]
        let updateData = completedData as? UpdateWideEventData
        XCTAssertNotNil(updateData?.diskSpaceRemainingBytes)
    }

    func test_completeFlow_success_doesNotIncludeDiskSpace() {
        // Given
        sut.startFlow(initiationType: .automatic)

        // When
        sut.completeFlow(status: .success)

        // Then
        let (completedData, _) = mockWideEventManager.completions[0]
        let updateData = completedData as? UpdateWideEventData
        XCTAssertNil(updateData?.diskSpaceRemainingBytes)
    }

    // MARK: - F. Cleanup Tests (Abandoned Flows)

    func test_cleanupAbandonedFlows_noAbandonedFlows_completesWithoutErrors() {
        // Given - no pending flows

        // When
        sut.cleanupAbandonedFlows()

        // Then
        XCTAssertEqual(mockWideEventManager.completions.count, 0)
    }

    func test_cleanupAbandonedFlows_oneAbandonedFlow_marksAsAbandoned() {
        // Given - simulate abandoned flow
        let abandonedFlow = UpdateWideEventData(
            fromVersion: "1.0.0",
            fromBuild: "100",
            initiationType: .automatic,
            updateConfiguration: .automatic,
            isInternalUser: false,
            contextData: WideEventContextData(name: "sparkle_update"),
            globalData: WideEventGlobalData(id: "abandoned-flow-1")
        )
        mockWideEventManager.started.append(abandonedFlow)

        // When
        sut.cleanupAbandonedFlows()

        // Then
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (_, status) = mockWideEventManager.completions[0]
        if case .unknown(let reason) = status {
            XCTAssertEqual(reason, "abandoned")
        } else {
            XCTFail("Expected unknown status with abandoned reason")
        }
    }

    func test_cleanupAbandonedFlows_multipleAbandonedFlows_cleansUpAll() {
        // Given - simulate 3 abandoned flows
        for i in 1...3 {
            let abandonedFlow = UpdateWideEventData(
                fromVersion: "1.0.0",
                fromBuild: "100",
                initiationType: .automatic,
                updateConfiguration: .automatic,
                isInternalUser: false,
                contextData: WideEventContextData(name: "sparkle_update"),
                globalData: WideEventGlobalData(id: "abandoned-flow-\(i)")
            )
            mockWideEventManager.started.append(abandonedFlow)
        }

        // When
        sut.cleanupAbandonedFlows()

        // Then
        XCTAssertEqual(mockWideEventManager.completions.count, 3)
        for (_, status) in mockWideEventManager.completions {
            if case .unknown(let reason) = status {
                XCTAssertEqual(reason, "abandoned")
            } else {
                XCTFail("Expected unknown status with abandoned reason")
            }
        }
    }

    // MARK: - G. Error Handling Tests

    func test_completeFlow_withError_populatesErrorData() {
        // Given
        sut.startFlow(initiationType: .automatic)
        let testError = NSError(domain: "test.error", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        // When
        sut.completeFlow(status: .failure, error: testError)

        // Then
        let (completedData, status) = mockWideEventManager.completions[0]
        let updateData = completedData as? UpdateWideEventData
        XCTAssertNotNil(updateData?.errorData)
        if case .failure = status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected failure status")
        }
    }

    func test_completeFlow_noCurrentFlow_handlesGracefully() {
        // Given - no flow started

        // When
        sut.completeFlow(status: .success)

        // Then - should not crash, no completions recorded
        XCTAssertEqual(mockWideEventManager.completions.count, 0)
    }

    func test_cancelFlow_noCurrentFlow_handlesGracefully() {
        // Given - no flow started

        // When
        sut.cancelFlow(reason: .appQuit)

        // Then - should not crash, no completions recorded
        XCTAssertEqual(mockWideEventManager.completions.count, 0)
    }

    func test_handleAppTermination_duringDownload_cancelsWithAppQuit() {
        // Given - active flow during download (not at extractionCompleted)
        sut.startFlow(initiationType: .automatic)
        sut.didStartDownload()

        // When
        sut.handleAppTermination()

        // Then - should cancel since extraction wasn't completed
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (completedData, status) = mockWideEventManager.completions[0]
        XCTAssertEqual((completedData as? UpdateWideEventData)?.cancellationReason, .appQuit)
        if case .cancelled = status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected cancelled status")
        }
    }

    func test_handleAppTermination_atExtractionCompleted_completesAsInstallingOnQuit() {
        // Given - extraction completed (update ready to install on quit)
        sut.startFlow(initiationType: .automatic)
        sut.didFindUpdate(version: "1.1.0", build: "123", isCritical: false)
        sut.didCompleteDownload()
        sut.didCompleteExtraction()

        // When
        sut.handleAppTermination()

        // Then - should complete as success since update will install on quit
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (_, status) = mockWideEventManager.completions[0]
        if case .success(let reason) = status {
            XCTAssertEqual(reason, "installing_on_quit")
        } else {
            XCTFail("Expected success status with installing_on_quit reason")
        }
    }

    func test_handleAppTermination_atRestartingToUpdate_completesAsRestartingToUpdate() {
        // User clicked "Restart to Update" which sets lastKnownStep to .restartingToUpdate
        sut.startFlow(initiationType: .automatic)
        sut.didFindUpdate(version: "1.1.0", build: "123", isCritical: false)
        sut.didCompleteDownload()
        sut.didCompleteExtraction()
        sut.didInitiateRestart()

        // When
        sut.handleAppTermination()

        // Then - should complete as success because user initiated restart
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (_, status) = mockWideEventManager.completions[0]
        if case .success(let reason) = status {
            XCTAssertEqual(reason, "restarting_to_update")
        } else {
            XCTFail("Expected success status with restarting_to_update reason")
        }
    }

    func test_handleAppTermination_noActiveFlow_handlesGracefully() {
        // Given - no flow started

        // When
        sut.handleAppTermination()

        // Then - should not crash
        XCTAssertEqual(mockWideEventManager.completions.count, 0)
    }

    // MARK: - H. Configuration Updates

    func test_updateConfiguration_automaticToManual_updatesProperty() {
        // Given
        XCTAssertTrue(sut.areAutomaticUpdatesEnabled)

        // When
        sut.areAutomaticUpdatesEnabled = false

        // Then
        XCTAssertFalse(sut.areAutomaticUpdatesEnabled)
    }

    func test_startFlow_afterConfigurationChange_usesNewConfiguration() {
        // Given
        sut.areAutomaticUpdatesEnabled = false

        // When
        sut.startFlow(initiationType: .manual)

        // Then
        let startedData = mockWideEventManager.started.first as? UpdateWideEventData
        XCTAssertEqual(startedData?.updateConfiguration, .manual)
    }
}

#endif

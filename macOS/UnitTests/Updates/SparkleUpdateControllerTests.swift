//
//  SparkleUpdateControllerTests.swift
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

import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Persistence
import PersistenceTestingUtils
import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import Sparkle
import Subscription
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class SparkleUpdateControllerTests: XCTestCase {

    func testSparkleUpdaterErrorReason() {
        let mockWideEventManager = WideEventMock()
        let keyValueStore = InMemoryThrowingKeyValueStore()
        let internalUserDecider = MockInternalUserDecider()
        let featureFlagger = MockFeatureFlagger()

        let updateController = DefaultSparkleUpdateController(
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger,
            pixelFiring: nil,
            notificationPresenter: MockNotificationPresenter(),
            keyValueStore: keyValueStore,
            allowCustomUpdateFeed: false,
            wideEvent: mockWideEventManager,
            isOnboardingFinished: { true }
        )

        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Package installer failed to launch."), "Package installer failed to launch." )
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Guided package installer failed to launch"), "Guided package installer failed to launch")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "An error occurred while running the updater. Please try again later."), "An error occurred while running the updater.")

        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Guided package installer failed to launch with additional error details"), "Guided package installer failed to launch")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Failed to move the new app from /path/to/source to /path/to/destination"), "Failed to move the new app")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Guided package installer returned non-zero exit status (1)"), "Guided package installer returned non-zero exit status")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Found regular application update but expected 'version=1.0' from appcast"), "Found regular application update")

        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Some completely unknown error message"), "unknown")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: ""), "unknown")
        XCTAssertEqual(updateController.sparkleUpdaterErrorReason(from: "Unexpected installer error format"), "unknown")
    }

    func testUpdaterWillRelaunchApplication_setsRestartingToUpdateStep() {
        // Given
        let mockWideEventManager = WideEventMock()
        let keyValueStore = InMemoryThrowingKeyValueStore()
        let internalUserDecider = MockInternalUserDecider()
        let featureFlagger = MockFeatureFlagger()
        let settings = keyValueStore.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>

        let mockWideEvent = SparkleUpdateWideEvent(
            wideEventManager: mockWideEventManager,
            internalUserDecider: internalUserDecider,
            areAutomaticUpdatesEnabled: true,
            settings: settings
        )

        let updateController = DefaultSparkleUpdateController(
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger,
            pixelFiring: nil,
            notificationPresenter: MockNotificationPresenter(),
            keyValueStore: keyValueStore,
            allowCustomUpdateFeed: false,
            wideEvent: mockWideEventManager,
            isOnboardingFinished: { true }
        )

        // Start a flow and simulate finding an update
        // Note: The original test passed mockWideEvent directly to the controller, but now the controller
        // creates its own internal updateWideEvent. We use mockWideEvent to set up the flow state in the
        // shared mockWideEventManager, but we also need to ensure the controller's internal flow is set up.
        mockWideEvent.startFlow(initiationType: .automatic)
        mockWideEvent.didFindUpdate(version: "1.1.0", build: "110", isCritical: false)

        // Ensure the controller's internal flow is also started and has found an update
        // The controller's init calls checkForUpdateRespectingRollout() which starts a flow,
        // but we need to simulate finding an update. Since we can't easily create a mock SUAppcastItem,
        // we'll use the controller's public methods to set up the flow, then verify via the shared manager.
        updateController.checkForUpdateSkippingRollout()

        // Access the controller's internal updateWideEvent via reflection to simulate finding an update
        // This is a workaround since we can't inject mockWideEvent directly anymore
        let mirror = Mirror(reflecting: updateController)
        if let updateWideEvent = mirror.children.first(where: { $0.label == "updateWideEvent" })?.value as? SparkleUpdateWideEvent {
            updateWideEvent.didFindUpdate(version: "1.1.0", build: "110", isCritical: false)
        }

        // Create a mock SPUUpdater
        let mockUpdater = MockSPUUpdater()

        // When
        updateController.updaterWillRelaunchApplication(mockUpdater)

        // Then - verify the step was set to restartingToUpdate (flow not completed yet)
        XCTAssertEqual(mockWideEventManager.completions.count, 0)

        // Verify the flow data has the correct step via the shared mockWideEventManager
        let flowData = mockWideEventManager.updates.last as? UpdateWideEventData
        XCTAssertEqual(flowData?.lastKnownStep, .restartingToUpdate)
        XCTAssertEqual(flowData?.toVersion, "1.1.0")
        XCTAssertEqual(flowData?.toBuild, "110")
    }

    func testDidFinishUpdateCycleFor_withNoUpdateFound_completesWideEvent() {
        let mockWideEventManager = WideEventMock()
        let keyValueStore = InMemoryThrowingKeyValueStore()
        let internalUserDecider = MockInternalUserDecider()
        let featureFlagger = MockFeatureFlagger()

        let updateController = DefaultSparkleUpdateController(
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger,
            pixelFiring: nil,
            notificationPresenter: MockNotificationPresenter(),
            keyValueStore: keyValueStore,
            allowCustomUpdateFeed: false,
            wideEvent: mockWideEventManager,
            isOnboardingFinished: { true }
        )

        // Start a flow through the controller's public interface
        updateController.checkForUpdateSkippingRollout()

        // Simulate the milestone being recorded by calling the delegate method
        // Note: updaterDidNotFindUpdate requires an appcast item in userInfo, but for this test
        // we can skip it since the method returns early if the item is missing
        let firstNoUpdateError = NSError(
            domain: "SUSparkleErrorDomain",
            code: Int(Sparkle.SUError.noUpdateError.rawValue)
        )
        // This will return early since there's no appcast item, which is fine for this test
        updateController.updaterDidNotFindUpdate(MockSPUUpdater(), error: firstNoUpdateError)

        // Create a mock SPUUpdater
        let mockUpdater = MockSPUUpdater()

        // Create the noUpdateError for didFinishUpdateCycleFor
        let noUpdateError = NSError(domain: "SUSparkleErrorDomain", code: Int(Sparkle.SUError.noUpdateError.rawValue))

        // When - didFinishUpdateCycleFor is called with noUpdateError
        updateController.updater(mockUpdater, didFinishUpdateCycleFor: .updatesInBackground, error: noUpdateError)

        // Then - verify the wide event WAS completed with success
        XCTAssertEqual(mockWideEventManager.completions.count, 1)
        let (_, status) = mockWideEventManager.completions[0]

        if case .success(let reason) = status {
            XCTAssertEqual(reason, "no_update_available")
        } else {
            XCTFail("Expected success status with no_update_available reason, got \(status)")
        }
    }

    // MARK: - PendingUpdateInfo Storage Tests

    func testPendingUpdateInfo_storesAndRetrievesFromUserDefaults() throws {
        // Given
        let suiteName = "test_pending_update_info_\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let settings = testDefaults.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
        let testDate = Date(timeIntervalSince1970: 1704067200)
        let pendingInfo = PendingUpdateInfo(
            version: "2.0.0",
            build: "200",
            date: testDate,
            releaseNotes: ["Feature A", "Feature B"],
            releaseNotesSubscription: [],
            isCritical: false
        )

        // When - write
        try settings.set(pendingInfo, for: \.pendingUpdateInfo)

        // Then - read
        let storedInfo = try settings.pendingUpdateInfo

        XCTAssertNotNil(storedInfo)
        XCTAssertEqual(storedInfo?.version, "2.0.0")
        XCTAssertEqual(storedInfo?.build, "200")
        XCTAssertEqual(storedInfo?.date.timeIntervalSince1970 ?? 0, 1704067200, accuracy: 1.0)
        XCTAssertEqual(storedInfo?.releaseNotes, ["Feature A", "Feature B"])
        XCTAssertEqual(storedInfo?.isCritical, false)
    }

}

// MARK: - Mock Classes

private class MockSPUUpdater: SPUUpdater {
    override init(hostBundle: Bundle, applicationBundle: Bundle, userDriver: SPUUserDriver, delegate: (any SPUUpdaterDelegate)?) {
        super.init(hostBundle: hostBundle, applicationBundle: applicationBundle, userDriver: userDriver, delegate: delegate)
    }

    convenience init() {
        let mockUserDriver = MockUserDriver()
        self.init(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: mockUserDriver,
            delegate: nil
        )
    }
}

private class MockUserDriver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {}
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {}
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {}
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {}
}

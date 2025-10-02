//
//  SparkleUpdaterAvailabilityCheckerTests.swift
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
import Sparkle
@testable import DuckDuckGo_Privacy_Browser

final class SparkleUpdaterAvailabilityCheckerTests: XCTestCase {

    private var mockUpdater: MockSPUUpdater!
    private var checker: SparkleUpdaterAvailabilityChecker!

    override func setUp() {
        super.setUp()
        autoreleasepool {
            mockUpdater = MockSPUUpdater()
            checker = SparkleUpdaterAvailabilityChecker(updater: mockUpdater)
        }
    }

    override func tearDown() {
        checker = nil
        mockUpdater = nil
        super.tearDown()
    }

    // MARK: - Protocol Conformance Tests

    func testConformsToUpdaterAvailabilityChecking() {
        XCTAssertTrue(checker is UpdaterAvailabilityChecking)
    }

    // MARK: - Updater Availability Tests

    func testCanCheckForUpdates_WithUpdaterAvailable_ReturnsUpdaterValue() {
        // Given
        mockUpdater.mockCanCheckForUpdates = true

        // When
        let result = checker.canCheckForUpdates

        // Then
        XCTAssertTrue(result)
    }

    func testCanCheckForUpdates_WithUpdaterUnavailable_ReturnsUpdaterValue() {
        // Given
        mockUpdater.mockCanCheckForUpdates = false

        // When
        let result = checker.canCheckForUpdates

        // Then
        XCTAssertFalse(result)
    }

    func testCanCheckForUpdates_WithNilUpdater_ReturnsTrue() {
        // Given
        checker = SparkleUpdaterAvailabilityChecker(updater: nil)

        // When
        let result = checker.canCheckForUpdates

        // Then
        XCTAssertTrue(result)
    }

    func testCanCheckForUpdates_WithDefaultInitializer_ReturnsTrue() {
        // Given
        checker = SparkleUpdaterAvailabilityChecker()

        // When
        let result = checker.canCheckForUpdates

        // Then
        XCTAssertTrue(result) // Since updater is nil by default
    }

    // MARK: - State Change Tests

    func testCanCheckForUpdates_ReflectsUpdaterStateChanges() {
        // Given
        mockUpdater.mockCanCheckForUpdates = true
        XCTAssertTrue(checker.canCheckForUpdates)

        // When
        mockUpdater.mockCanCheckForUpdates = false

        // Then
        XCTAssertFalse(checker.canCheckForUpdates)
    }
}

// MARK: - Mock Classes

private class MockSPUUpdater: SPUUpdater {
    var mockCanCheckForUpdates: Bool = true

    override var canCheckForUpdates: Bool {
        return mockCanCheckForUpdates
    }

    convenience init() {
        let mockUserDriver = MockUserDriver()
        self.init(hostBundle: Bundle.main,
                  applicationBundle: Bundle.main,
                  userDriver: mockUserDriver,
                  delegate: nil)
    }
}

// Reuse MockUserDriver from UpdateCheckStateTests
private class MockUserDriver: NSObject, SPUUserDriver {
    func showCanCheckForUpdatesNow(_ canCheckForUpdatesNow: Bool) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func dismissUserInitiatedUpdateCheck() {}
    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        return SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SUUpdateAlertChoice) -> Void) {
        reply(.skip)
    }
    func showDownloadedUpdateFound(with appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SUUpdateAlertChoice) -> Void) {
        reply(.skip)
    }
    func showResumableUpdateFound(with appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SUUpdateAlertChoice) -> Void) {
        reply(.skip)
    }
    func showInformationalUpdateFound(with appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SUInformationalUpdateAlertChoice) -> Void) {
        reply(.skip)
    }
    func showUpdateReleaseNotes(with downloadData: Data) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithAcknowledgement(_ acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch installUpdateHandler: @escaping (SUUpdateAlertChoice) -> Void) {
        installUpdateHandler(.skip)
    }
    func showInstallingUpdate() {}
    func showSendingTerminationSignal() {}
    func showUpdateInstallationDidFinish(acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func dismissUpdateInstallation() {}
}

#endif

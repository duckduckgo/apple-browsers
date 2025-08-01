//
//  UpdateCheckStateTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser
import Sparkle

// Mock SPUUpdater for testing
class MockSPUUpdater: SPUUpdater {
    var mockCanCheckForUpdates: Bool = true

    override var canCheckForUpdates: Bool {
        return mockCanCheckForUpdates
    }

    convenience init() {
        // Create a minimal mock user driver for testing
        let mockUserDriver = MockUserDriver()
        self.init(hostBundle: Bundle.main,
                  applicationBundle: Bundle.main,
                  userDriver: mockUserDriver,
                  delegate: nil)
        // Note: We intentionally don't call start() here since:
        // 1. It might throw and we don't need it for these tests
        // 2. We're only testing UpdateCheckState rate limiting, not SPUUpdater functionality
    }
}

// Mock user driver to satisfy SPUUpdater requirements
class MockUserDriver: NSObject, SPUUserDriver {
    func showCanCheckForUpdatesNow(_ canCheckForUpdatesNow: Bool) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func dismissUserInitiatedUpdateCheck() {}
    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        return SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.dismiss)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.dismiss)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showSendingTerminationSignal() {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {}
}

/// Tests for UpdateCheckState actor that manages update check rate limiting.
///
/// This test suite validates rate limiting behavior that prevents excessive update checks
/// which could impact performance or server load.
///
/// These behaviors are essential for:
/// - Maintaining app responsiveness during update checks
/// - Preventing server abuse from rapid-fire update requests
/// - Ensuring user-initiated checks can bypass rate limiting when needed
@available(macOS 10.15.0, *)
final class UpdateCheckStateTests: XCTestCase {

    var updateCheckState: UpdateCheckState!
    var mockUpdater: MockSPUUpdater!

    override func setUp() async throws {
        try await super.setUp()
        updateCheckState = UpdateCheckState()
        mockUpdater = MockSPUUpdater()
    }

    override func tearDown() async throws {
        updateCheckState = nil
        mockUpdater = nil
        try await super.tearDown()
    }

    // MARK: - Background Check Tests

    /// Tests that background update checks are allowed when the system is in its initial state.
    func testAllowsBackgroundChecksInInitialState() async {
        let canStart = await updateCheckState.canStartBackgroundCheck(updater: mockUpdater)
        XCTAssertTrue(canStart, "Should be able to start background check in initial state")
    }

    /// Tests that background update checks are rate limited to prevent excessive requests.
    func testBackgroundRateLimitingPreventsExcessiveRequests() async {
        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartBackgroundCheck(updater: mockUpdater)
        XCTAssertFalse(canStart, "Background checks should be rate limited when checking too soon")
    }

    /// Tests that user-initiated checks can bypass rate limiting.
    func testUserInitiatedChecksCanBypassRateLimiting() async {
        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartUserInitiatedCheck(updater: mockUpdater)
        XCTAssertTrue(canStart, "User-initiated checks should bypass rate limiting")
    }

    /// Tests that rate limiting intervals are configurable for different scenarios.
    func testRateLimitingIntervalsAreConfigurable() async {
        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartCheck(updater: mockUpdater, minimumInterval: 0.1)
        XCTAssertFalse(canStart, "Should respect custom minimum interval")
    }

    /// Tests that background checks are blocked when Sparkle doesn't allow updates.
    func testBackgroundChecksAreBlockedWhenSparkleDoesntAllow() async {
        mockUpdater.mockCanCheckForUpdates = false

        let canStart = await updateCheckState.canStartBackgroundCheck(updater: mockUpdater)
        XCTAssertFalse(canStart, "Background checks should not be allowed when Sparkle doesn't allow it")
    }

    /// Tests that user-initiated checks are also blocked when Sparkle doesn't allow updates.
    func testUserInitiatedChecksAreBlockedWhenSparkleDoesntAllow() async {
        mockUpdater.mockCanCheckForUpdates = false

        let canStart = await updateCheckState.canStartUserInitiatedCheck(updater: mockUpdater)
        XCTAssertFalse(canStart, "User-initiated checks should not be allowed when Sparkle doesn't allow it")
    }

    /// Tests that background checks are allowed when Sparkle allows updates.
    func testBackgroundChecksAreAllowedWhenSparkleAllows() async {
        mockUpdater.mockCanCheckForUpdates = true

        let canStart = await updateCheckState.canStartBackgroundCheck(updater: mockUpdater)
        XCTAssertTrue(canStart, "Background checks should be allowed when Sparkle allows it")
    }

    /// Tests that user-initiated checks are allowed when Sparkle allows updates.
    func testUserInitiatedChecksAreAllowedWhenSparkleAllows() async {
        mockUpdater.mockCanCheckForUpdates = true

        let canStart = await updateCheckState.canStartUserInitiatedCheck(updater: mockUpdater)
        XCTAssertTrue(canStart, "User-initiated checks should be allowed when Sparkle allows it")
    }

    /// Tests that nil updater allows background checks (doesn't block them).
    func testNilUpdaterAllowsBackgroundChecks() async {
        let canStart = await updateCheckState.canStartBackgroundCheck(updater: nil)
        XCTAssertTrue(canStart, "Should be able to start background check with nil updater")
    }

    /// Tests that nil updater allows user-initiated checks (doesn't block them).
    func testNilUpdaterAllowsUserInitiatedChecks() async {
        let canStart = await updateCheckState.canStartUserInitiatedCheck(updater: nil)
        XCTAssertTrue(canStart, "Should be able to start user-initiated check with nil updater")
    }

    /// Tests that nil updater still respects rate limiting for background checks.
    func testNilUpdaterRespectsBackgroundRateLimiting() async {
        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartBackgroundCheck(updater: nil)
        XCTAssertFalse(canStart, "Background checks should still be rate limited with nil updater")
    }

    /// Tests that nil updater bypasses rate limiting for user-initiated checks.
    func testNilUpdaterBypassesRateLimitingForUserInitiated() async {
        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartUserInitiatedCheck(updater: nil)
        XCTAssertTrue(canStart, "User-initiated checks should bypass rate limiting even with nil updater")
    }

    // MARK: - recordCheckTime Tests

    /// Tests that recording check timestamps enables rate limiting behavior for background checks.
    func testRecordingTimestampsEnablesBackgroundRateLimiting() async {
        let initialCanStart = await updateCheckState.canStartBackgroundCheck(updater: mockUpdater)
        XCTAssertTrue(initialCanStart, "Should initially be able to start background check")

        await updateCheckState.recordCheckTime()

        let canStartAfterRecord = await updateCheckState.canStartBackgroundCheck(updater: mockUpdater)
        XCTAssertFalse(canStartAfterRecord, "Background checks should be rate limited after recording check time")
    }

    /// Tests that recording check timestamps doesn't affect user-initiated checks.
    func testRecordingTimestampsDoesntAffectUserInitiatedChecks() async {
        let initialCanStart = await updateCheckState.canStartUserInitiatedCheck(updater: mockUpdater)
        XCTAssertTrue(initialCanStart, "Should initially be able to start user-initiated check")

        await updateCheckState.recordCheckTime()

        let canStartAfterRecord = await updateCheckState.canStartUserInitiatedCheck(updater: mockUpdater)
        XCTAssertTrue(canStartAfterRecord, "User-initiated checks should not be affected by rate limiting")
    }

    /// Tests that rate limiting expires after sufficient time passes.
    func testRateLimitingExpiresAfterTime() async {
        await updateCheckState.recordCheckTime()

        // Check immediately after recording - should be rate limited
        let canStartImmediately = await updateCheckState.canStartCheck(updater: mockUpdater, minimumInterval: 0.01)
        XCTAssertFalse(canStartImmediately, "Should be rate limited immediately after recording")

        // Wait for rate limit to expire
        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

        let canStartAfterWait = await updateCheckState.canStartCheck(updater: mockUpdater, minimumInterval: 0.01)
        XCTAssertTrue(canStartAfterWait, "Should be able to start check after rate limit expires")
    }

    // MARK: - Integration Tests

    /// Tests the basic rate limiting workflow for both background and user-initiated checks.
    func testBasicRateLimitingWorkflow() async {
        // Initial state - should allow all checks
        let initialBackgroundStart = await updateCheckState.canStartBackgroundCheck(updater: mockUpdater)
        XCTAssertTrue(initialBackgroundStart, "Should initially be able to start background check")

        let initialUserStart = await updateCheckState.canStartUserInitiatedCheck(updater: mockUpdater)
        XCTAssertTrue(initialUserStart, "Should initially be able to start user-initiated check")

        // Record check time - background should now be rate limited, user-initiated should not
        await updateCheckState.recordCheckTime()
        let backgroundAfterRecord = await updateCheckState.canStartBackgroundCheck(updater: mockUpdater)
        XCTAssertFalse(backgroundAfterRecord, "Background checks should be rate limited after recording check time")

        // User-initiated check can bypass rate limit
        let userAfterRecord = await updateCheckState.canStartUserInitiatedCheck(updater: mockUpdater)
        XCTAssertTrue(userAfterRecord, "User-initiated check should bypass rate limit")
    }

    /// Tests behavior with different Sparkle states and rate limiting.
    func testSparkleStateAndRateLimitingInteraction() async {
        // Record a check time to enable rate limiting
        await updateCheckState.recordCheckTime()

        // Even if rate limited, Sparkle state should still be respected for user-initiated checks
        mockUpdater.mockCanCheckForUpdates = false
        let userWithBlockedSparkle = await updateCheckState.canStartUserInitiatedCheck(updater: mockUpdater)
        XCTAssertFalse(userWithBlockedSparkle, "User-initiated checks should not be allowed if Sparkle blocks")

        // When Sparkle allows but we're rate limited (background)
        mockUpdater.mockCanCheckForUpdates = true
        let backgroundWithAllowedSparkle = await updateCheckState.canStartBackgroundCheck(updater: mockUpdater)
        XCTAssertFalse(backgroundWithAllowedSparkle, "Background checks should still be rate limited even when Sparkle allows")

        // When both Sparkle allows and it's user-initiated
        let userWithAllowedSparkle = await updateCheckState.canStartUserInitiatedCheck(updater: mockUpdater)
        XCTAssertTrue(userWithAllowedSparkle, "User-initiated checks should be allowed when Sparkle allows")
    }

    // MARK: - Constants Tests

    /// Tests that the default rate limiting interval is configured to 5 minutes.
    func testDefaultRateLimitingInterval() {
        XCTAssertEqual(UpdateCheckState.defaultMinimumCheckInterval, .minutes(5), "Default minimum check interval should be 5 minutes")
    }
}

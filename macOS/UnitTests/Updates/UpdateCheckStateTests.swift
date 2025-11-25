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

// Mock updater for testing that implements UpdaterAvailabilityChecking
class MockUpdater: UpdaterAvailabilityChecking {
    var mockCanCheckForUpdates: Bool = true

    var canCheckForUpdates: Bool {
        return mockCanCheckForUpdates
    }
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
    var mockUpdater: MockUpdater!

    override func setUp() async throws {
        try await super.setUp()
        updateCheckState = UpdateCheckState()
        mockUpdater = MockUpdater()
    }

    override func tearDown() async throws {
        updateCheckState = nil
        mockUpdater = nil
        try await super.tearDown()
    }

    // MARK: - Test Helpers

    /// Creates a mock Update for testing purposes
    private func makeMockUpdate() -> Update {
        return Update(
            isInstalled: false,
            type: .regular,
            version: "1.0.0",
            build: "100",
            date: Date(),
            releaseNotes: ["Mock release notes"],
            releaseNotesSubscription: [],
            needsLatestReleaseNote: false
        )
    }

    // MARK: - canStartNewCheck Tests

    /// Tests that update checks are allowed when the system is in its initial state.
    func testAllowsUpdateChecksInInitialState() async {
        let canStart = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: nil)
        XCTAssertTrue(canStart, "Should be able to start check in initial state")
    }

    /// Tests that update checks are rate limited to prevent excessive requests.
    func testRateLimitingPreventsExcessiveRequests() async {
        let mockUpdate = makeMockUpdate()

        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate)
        XCTAssertFalse(canStart, "Should be rate limited when checking too soon")
    }

    /// Tests that rate limiting can be bypassed when needed (e.g., user-initiated checks).
    func testRateLimitingCanBeBypassed() async {
        let mockUpdate = makeMockUpdate()

        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate, minimumInterval: 0)
        XCTAssertTrue(canStart, "Should be able to start check when rate limit is disabled")
    }

    /// Tests that rate limiting intervals are configurable for different scenarios.
    func testRateLimitingIntervalsAreConfigurable() async {
        let mockUpdate = makeMockUpdate()
        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate, minimumInterval: 0.1)
        XCTAssertFalse(canStart, "Should respect custom minimum interval")
    }

    /// Tests that checks are blocked when Sparkle doesn't allow updates.
    func testChecksAreBlockedWhenSparkleDoesntAllow() async {
        mockUpdater.mockCanCheckForUpdates = false

        let canStart = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: nil)
        XCTAssertFalse(canStart, "Should not be able to start check when Sparkle doesn't allow it")
    }

    /// Tests that checks are allowed when Sparkle allows updates.
    func testChecksAreAllowedWhenSparkleAllows() async {
        mockUpdater.mockCanCheckForUpdates = true

        let canStart = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: nil)
        XCTAssertTrue(canStart, "Should be able to start check when Sparkle allows it")
    }

    /// Tests that nil updater allows update checks (doesn't block them).
    func testNilUpdaterAllowsChecks() async {
        let canStart = await updateCheckState.canStartNewCheck(updater: nil, latestUpdate: nil)
        XCTAssertTrue(canStart, "Should be able to start check with nil updater")
    }

    /// Tests that nil updater still respects rate limiting.
    func testNilUpdaterRespectsRateLimiting() async {
        let mockUpdate = makeMockUpdate()

        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartNewCheck(updater: nil, latestUpdate: mockUpdate)
        XCTAssertFalse(canStart, "Should still be rate limited with nil updater")
    }

    // MARK: - recordCheckTime Tests

    /// Tests that recording check timestamps enables rate limiting behavior.
    func testRecordingTimestampsEnablesRateLimiting() async {
        let mockUpdate = makeMockUpdate()
        let initialCanStart = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: nil)
        XCTAssertTrue(initialCanStart, "Should initially be able to start check")

        await updateCheckState.recordCheckTime()

        let canStartAfterRecord = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate)
        XCTAssertFalse(canStartAfterRecord, "Should be rate limited after recording check time")
    }

    /// Tests that rate limiting expires after sufficient time passes.
    func testRateLimitingExpiresAfterTime() async {
        let mockUpdate = makeMockUpdate()
        await updateCheckState.recordCheckTime()

        // Check immediately after recording - should be rate limited
        let canStartImmediately = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate, minimumInterval: 0.01)
        XCTAssertFalse(canStartImmediately, "Should be rate limited immediately after recording")

        // Wait for rate limit to expire
        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

        let canStartAfterWait = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate, minimumInterval: 0.01)
        XCTAssertTrue(canStartAfterWait, "Should be able to start check after rate limit expires")
    }

    // MARK: - Integration Tests

    /// Tests the basic rate limiting workflow.
    func testBasicRateLimitingWorkflow() async {
        let mockUpdate = makeMockUpdate()
        // Initial state - should allow checks
        let initialCanStart = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: nil)
        XCTAssertTrue(initialCanStart, "Should initially be able to start check")

        // Record check time - should now be rate limited
        await updateCheckState.recordCheckTime()
        let canStartAfterRecord = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate)
        XCTAssertFalse(canStartAfterRecord, "Should be rate limited after recording check time")

        // User-initiated check can bypass rate limit
        let canStartUserInitiated = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate, minimumInterval: 0)
        XCTAssertTrue(canStartUserInitiated, "User-initiated check should bypass rate limit")
    }

    /// Tests behavior with different Sparkle states and rate limiting.
    func testSparkleStateAndRateLimitingInteraction() async {
        let mockUpdate = makeMockUpdate()
        // Record a check time to enable rate limiting
        await updateCheckState.recordCheckTime()

        // Even if rate limited, Sparkle state should still be respected
        mockUpdater.mockCanCheckForUpdates = false
        let canStartWithBlockedSparkle = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate, minimumInterval: 0)
        XCTAssertFalse(canStartWithBlockedSparkle, "Should not be able to start even when bypassing rate limit if Sparkle blocks")

        // When Sparkle allows but we're rate limited
        mockUpdater.mockCanCheckForUpdates = true
        let canStartWithAllowedSparkle = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate)
        XCTAssertFalse(canStartWithAllowedSparkle, "Should still be rate limited even when Sparkle allows")

        // When both Sparkle allows and rate limit is bypassed
        let canStartBothAllowed = await updateCheckState.canStartNewCheck(updater: mockUpdater, latestUpdate: mockUpdate, minimumInterval: 0)
        XCTAssertTrue(canStartBothAllowed, "Should be able to start when both conditions are met")
    }

    // MARK: - Constants Tests

    /// Tests that the default rate limiting interval is configured to 5 minutes.
    func testDefaultRateLimitingInterval() {
        XCTAssertEqual(UpdateCheckState.defaultMinimumCheckInterval, .minutes(5), "Default minimum check interval should be 5 minutes")
    }
}

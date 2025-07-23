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

/// Tests for UpdateCheckState actor that manages update check coordination and rate limiting.
///
/// This test suite validates two critical behaviors:
/// 1. **Rate Limiting**: Prevents excessive update checks that could impact performance or server load
/// 2. **Task Coordination**: Ensures only one update check runs at a time to prevent resource conflicts
///
/// These behaviors are essential for:
/// - Maintaining app responsiveness during update checks
/// - Preventing server abuse from rapid-fire update requests
/// - Ensuring user-initiated checks take priority over automatic background checks
/// - Handling edge cases like cancelled tasks and concurrent access safely
@available(macOS 10.15.0, *)
final class UpdateCheckStateTests: XCTestCase {

    var updateCheckState: UpdateCheckState!

    override func setUp() async throws {
        try await super.setUp()
        updateCheckState = UpdateCheckState()
    }

    override func tearDown() async throws {
        await updateCheckState.cancelActiveTask()
        updateCheckState = nil
        try await super.tearDown()
    }

    // MARK: - canStartNewCheck Tests

    /// Tests that update checks are allowed when the system is in its initial state.
    func testAllowsUpdateChecksInInitialState() async {
        let canStart = await updateCheckState.canStartNewCheck()
        XCTAssertTrue(canStart, "Should be able to start check in initial state")
    }

    /// Tests that concurrent update checks are prevented when one is already running.
    func testPreventsConcurrentUpdateChecks() async {
        let activeTask = Task<Void, Never> { @MainActor in
            try? await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)
        }
        await updateCheckState.setActiveTask(activeTask)

        let canStart = await updateCheckState.canStartNewCheck()
        XCTAssertFalse(canStart, "Should not be able to start check with active task")

        activeTask.cancel()
        await updateCheckState.setActiveTask(nil)
    }

    /// Tests that cancelled update tasks don't block new update checks.
    func testCancelledTasksDontBlockNewChecks() async {
        let cancelledTask = Task<Void, Never> { @MainActor in
            try? await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)
        }
        cancelledTask.cancel()
        await updateCheckState.setActiveTask(cancelledTask)

        let canStart = await updateCheckState.canStartNewCheck()
        XCTAssertTrue(canStart, "Should be able to start check with cancelled task")
    }

    /// Tests that update checks are rate limited to prevent excessive requests.
    func testRateLimitingPreventsExcessiveRequests() async {
        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartNewCheck()
        XCTAssertFalse(canStart, "Should be rate limited when checking too soon")
    }

    /// Tests that rate limiting can be bypassed when needed (e.g., user-initiated checks).
    func testRateLimitingCanBeBypassed() async {
        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartNewCheck(minimumInterval: 0)
        XCTAssertTrue(canStart, "Should be able to start check when rate limit is disabled")
    }

    /// Tests that rate limiting intervals can be configured for different scenarios.
    func testRateLimitingIntervalsAreConfigurable() async {
        await updateCheckState.recordCheckTime()

        let canStart = await updateCheckState.canStartNewCheck(minimumInterval: 0.1)
        XCTAssertFalse(canStart, "Should respect custom minimum interval")
    }

    // MARK: - cancelActiveTask Tests

    /// Tests that running update checks can be cancelled to allow new ones to start.
    func testRunningChecksCanBeCancelled() async {
        let activeTask = Task<Void, Never> { @MainActor in
            try? await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)
        }
        await updateCheckState.setActiveTask(activeTask)

        await updateCheckState.cancelActiveTask()

        XCTAssertTrue(activeTask.isCancelled, "Task should be cancelled")

        let canStart = await updateCheckState.canStartNewCheck()
        XCTAssertTrue(canStart, "Should be able to start new check after cancellation")
    }

    /// Tests that cancelling update checks is safe even when none are running.
    func testCancellingIsSafeWhenNoneRunning() async {
        await updateCheckState.cancelActiveTask()

        let canStart = await updateCheckState.canStartNewCheck()
        XCTAssertTrue(canStart, "Should still be able to start check")
    }

    // MARK: - setActiveTask Tests

    /// Tests that update checks are blocked while another check is tracked as active.
    func testChecksAreBlockedWhileAnotherIsActive() async {
        let task = Task<Void, Never> { @MainActor in
        }

        await updateCheckState.setActiveTask(task)

        let canStart = await updateCheckState.canStartNewCheck()
        XCTAssertFalse(canStart, "Should not be able to start check with active task set")

        task.cancel()
        await updateCheckState.setActiveTask(nil)
    }

    /// Tests that update checks are unblocked when the active check is cleared.
    func testChecksAreUnblockedWhenActiveCheckCleared() async {
        let task = Task<Void, Never> { @MainActor in
            try? await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)
        }
        await updateCheckState.setActiveTask(task)

        await updateCheckState.setActiveTask(nil)

        let canStart = await updateCheckState.canStartNewCheck()
        XCTAssertTrue(canStart, "Should be able to start check after clearing active task")

        task.cancel()
    }

    // MARK: - recordCheckTime Tests

    /// Tests that recording check timestamps enables rate limiting behavior.
    func testRecordingTimestampsEnablesRateLimiting() async {
        let initialCanStart = await updateCheckState.canStartNewCheck()
        XCTAssertTrue(initialCanStart, "Should initially be able to start check")

        await updateCheckState.recordCheckTime()

        let canStartAfterRecord = await updateCheckState.canStartNewCheck()
        XCTAssertFalse(canStartAfterRecord, "Should be rate limited after recording check time")
    }

    // MARK: - Integration Tests

    /// Tests the complete update check workflow from start to finish including rate limiting.
    func testCompleteUpdateCheckWorkflow() async {
        let initialCanStart = await updateCheckState.canStartNewCheck()
        XCTAssertTrue(initialCanStart, "Should initially be able to start check")

        await updateCheckState.recordCheckTime()
        let task = Task<Void, Never> { @MainActor in
            try? await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)
        }
        await updateCheckState.setActiveTask(task)

        let canStartDuringTask = await updateCheckState.canStartNewCheck()
        XCTAssertFalse(canStartDuringTask, "Should not be able to start with active task and rate limit")

        await task.value
        await updateCheckState.setActiveTask(nil)

        let canStartAfterTask = await updateCheckState.canStartNewCheck()
        XCTAssertFalse(canStartAfterTask, "Should still be rate limited after task completion")

        let canStartWithoutRateLimit = await updateCheckState.canStartNewCheck(minimumInterval: 0)
        XCTAssertTrue(canStartWithoutRateLimit, "Should be able to start when rate limit is disabled")
    }

    /// Tests that user-initiated update checks can override automatic rate limiting.
    func testUserInitiatedChecksOverrideRateLimiting() async {
        await updateCheckState.recordCheckTime()
        let automaticTask = Task<Void, Never> { @MainActor in
            try? await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)
        }
        await updateCheckState.setActiveTask(automaticTask)

        await updateCheckState.cancelActiveTask()

        let canStartUserInitiated = await updateCheckState.canStartNewCheck(minimumInterval: 0)
        XCTAssertTrue(canStartUserInitiated, "User-initiated check should be able to start immediately")
        XCTAssertTrue(automaticTask.isCancelled, "Automatic task should be cancelled")
    }

    // MARK: - Constants Tests

    /// Tests that the default rate limiting interval is configured to 5 minutes.
    func testDefaultRateLimitingInterval() {
        XCTAssertEqual(UpdateCheckState.defaultMinimumCheckInterval, .minutes(5), "Default minimum check interval should be 5 minutes")
    }
}

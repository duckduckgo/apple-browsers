//
//  DataBrokerProtectionIOSManagerScanCompletionTests.swift
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
final class DataBrokerProtectionIOSManagerScanCompletionTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var isAuthenticated = false
    private var stateManager: DefaultFreemiumDBPUserStateManager!

    override func setUp() {
        super.setUp()
        suiteName = "DataBrokerProtectionIOSManagerScanCompletionTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        isAuthenticated = false
        stateManager = DefaultFreemiumDBPUserStateManager(
            userDefaults: userDefaults,
            isUserAuthenticated: { [self] in isAuthenticated },
            isFreemiumEnabled: { true }
        )
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        stateManager = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Polls until `predicate()` returns true or the timeout elapses. Used to wait for the
    /// scan-completion `Task` to drain; when the predicate stays false on purpose (e.g. the
    /// authenticated no-write case), callers should assert a separate side-effect that the
    /// callback ran (see `firstScanCompletedFired` / `firstScanCompletedAndMatchesFoundFired`).
    private func awaitCondition(
        timeout: TimeInterval = 1.0,
        _ predicate: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Path A: startImmediateScanOperations completion block

    @discardableResult
    private func runPathA(
        hasMatches: Bool,
        authenticated: Bool,
        hasMatchesError: Error? = nil
    ) async -> IOSManagerTestDependencies {
        isAuthenticated = authenticated
        let (sut, deps) = DBPIOSManagerTestUtils.makeTestIOSManager(
            freemiumDBPUserStateManagerOverride: stateManager
        )
        deps.database.hasMatchesToReturn = hasMatches
        deps.database.hasMatchesError = hasMatchesError
        deps.authenticationManager.isUserAuthenticatedValue = authenticated

        await sut.startImmediateScanOperations()
        // The callback's Task fires `.firstScanCompletedAndMatchesFound` when hasMatches is true,
        // so we can anchor the wait on that.
        // Otherwise we wait for a freemium write (unauthenticated hasMatches=false case).
        await awaitCondition {
            deps.eventsHandler.firstScanCompletedAndMatchesFoundFired
                || stateManager.firstScanResult != nil
        }
        _ = sut
        return deps
    }

    func test_pathA_unauthenticated_hasMatchesTrue_persistsMatchesFound() async {
        let deps = await runPathA(hasMatches: true, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .matchesFound)
        XCTAssertTrue(deps.eventsHandler.firstScanCompletedFired)
        XCTAssertTrue(deps.eventsHandler.firstScanCompletedAndMatchesFoundFired)
    }

    func test_pathA_unauthenticated_hasMatchesFalse_persistsNoMatches() async {
        let deps = await runPathA(hasMatches: false, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .noMatches)
        XCTAssertTrue(deps.eventsHandler.firstScanCompletedFired)
        XCTAssertFalse(deps.eventsHandler.firstScanCompletedAndMatchesFoundFired)
    }

    func test_pathA_authenticated_persistsNothing() async {
        let deps = await runPathA(hasMatches: true, authenticated: true)
        // firstScanCompletedAndMatchesFoundFired proves the completion handler actually ran;
        // without it, a no-op callback could silently pass the "stays nil" assertion.
        XCTAssertTrue(deps.eventsHandler.firstScanCompletedAndMatchesFoundFired)
        XCTAssertNil(stateManager.firstScanResult)
    }

    // MARK: - Path B: coordinatorIsReadyForScanOperations completion block

    @discardableResult
    private func runPathB(
        hasMatches: Bool,
        authenticated: Bool,
        hasMatchesError: Error? = nil
    ) async -> IOSManagerTestDependencies {
        isAuthenticated = authenticated
        let (sut, deps) = DBPIOSManagerTestUtils.makeTestIOSManager(
            freemiumDBPUserStateManagerOverride: stateManager
        )
        deps.database.hasMatchesToReturn = hasMatches
        deps.database.hasMatchesError = hasMatchesError
        deps.authenticationManager.isUserAuthenticatedValue = authenticated

        await sut.coordinatorIsReadyForScanOperations()
        await awaitCondition {
            deps.eventsHandler.firstScanCompletedAndMatchesFoundFired
                || stateManager.firstScanResult != nil
        }
        _ = sut
        return deps
    }

    func test_pathB_unauthenticated_hasMatchesTrue_persistsMatchesFound() async {
        let deps = await runPathB(hasMatches: true, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .matchesFound)
        XCTAssertTrue(deps.eventsHandler.firstScanCompletedAndMatchesFoundFired)
    }

    func test_pathB_unauthenticated_hasMatchesFalse_persistsNoMatches() async {
        let deps = await runPathB(hasMatches: false, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .noMatches)
        XCTAssertFalse(deps.eventsHandler.firstScanCompletedAndMatchesFoundFired)
    }

    func test_pathB_authenticated_persistsNothing() async {
        let deps = await runPathB(hasMatches: true, authenticated: true)
        XCTAssertTrue(deps.eventsHandler.firstScanCompletedAndMatchesFoundFired)
        XCTAssertNil(stateManager.firstScanResult)
    }

    // MARK: - Cross-path first-scan-wins

    func test_pathA_thenPathB_firstScanWins() async {
        await runPathA(hasMatches: false, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .noMatches)

        await runPathB(hasMatches: true, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .noMatches)
    }

    func test_pathB_thenPathA_firstScanWins() async {
        await runPathB(hasMatches: true, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .matchesFound)

        await runPathA(hasMatches: false, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .matchesFound)
    }

    // MARK: - Transient DB error leaves firstScanResult unset

    func test_pathA_unauthenticated_hasMatchesThrows_leavesFirstScanResultNil() async {
        isAuthenticated = false
        let (sut, deps) = DBPIOSManagerTestUtils.makeTestIOSManager(
            freemiumDBPUserStateManagerOverride: stateManager
        )
        deps.database.hasMatchesError = ScanCompletionTestError.hasMatchesFailed
        deps.authenticationManager.isUserAuthenticatedValue = false

        await sut.startImmediateScanOperations()
        // Give the Task time to drain; nothing should land in state.
        try? await Task.sleep(nanoseconds: 100_000_000)
        _ = sut

        XCTAssertNil(stateManager.firstScanResult)
        XCTAssertFalse(deps.eventsHandler.firstScanCompletedAndMatchesFoundFired)

        // A later successful scan must still be able to record the correct outcome.
        await runPathA(hasMatches: true, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .matchesFound)
    }

    // MARK: - Interrupted runs: freemium write is gated, pre-existing event fire is preserved

    func test_pathA_unauthenticated_interruptedRun_doesNotWriteFirstScanResult_butStillFiresMatchesFound() async {
        isAuthenticated = false
        let (sut, deps) = DBPIOSManagerTestUtils.makeTestIOSManager(
            freemiumDBPUserStateManagerOverride: stateManager
        )
        deps.database.hasMatchesToReturn = true
        deps.authenticationManager.isUserAuthenticatedValue = false
        deps.queueManager.startImmediateScanOperationsIfPermittedCompletionError =
            DataBrokerProtectionJobsErrorCollection(oneTimeError: BrokerProfileJobQueueError.interrupted)

        await sut.startImmediateScanOperations()
        try? await Task.sleep(nanoseconds: 100_000_000)
        _ = sut

        // Branch-new behavior: interrupted run must not first-write-lock firstScanResult.
        XCTAssertNil(stateManager.firstScanResult)
        XCTAssertFalse(deps.eventsHandler.firstScanCompletedFired)
        // Pre-existing behavior: `.firstScanCompletedAndMatchesFound` still fires on
        // interruption when hasMatches is true, matching the pre-branch completion block.
        XCTAssertTrue(deps.eventsHandler.firstScanCompletedAndMatchesFoundFired)

        // A later non-interrupted run still records correctly.
        await runPathA(hasMatches: true, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .matchesFound)
    }

    func test_pathB_unauthenticated_interruptedRun_doesNotWriteFirstScanResult_butStillFiresMatchesFound() async {
        isAuthenticated = false
        let (sut, deps) = DBPIOSManagerTestUtils.makeTestIOSManager(
            freemiumDBPUserStateManagerOverride: stateManager
        )
        deps.database.hasMatchesToReturn = true
        deps.authenticationManager.isUserAuthenticatedValue = false
        deps.queueManager.startImmediateScanOperationsIfPermittedCompletionError =
            DataBrokerProtectionJobsErrorCollection(oneTimeError: BrokerProfileJobQueueError.interrupted)

        await sut.coordinatorIsReadyForScanOperations()
        try? await Task.sleep(nanoseconds: 100_000_000)
        _ = sut

        XCTAssertNil(stateManager.firstScanResult)
        XCTAssertFalse(deps.eventsHandler.firstScanCompletedFired)
        XCTAssertTrue(deps.eventsHandler.firstScanCompletedAndMatchesFoundFired)
    }
}

private enum ScanCompletionTestError: Error {
    case hasMatchesFailed
}

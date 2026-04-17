//
//  DataBrokerProtectionIOSManagerScanCompletionTests.swift
//  DuckDuckGo
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
            isUserAuthenticated: { [self] in isAuthenticated }
        )
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        stateManager = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Spins the runloop until `stateManager.firstScanResult` is non-nil or the timeout expires.
    /// The scan-completion callback spawns a `Task` that isn't awaited by the mock queue manager,
    /// so we poll briefly. Timeout is conservative so the test fails fast on real regressions.
    private func awaitFirstScanResult(timeout: TimeInterval = 1.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if stateManager.firstScanResult != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Path A: startImmediateScanOperations completion block

    private func runPathA(hasMatches: Bool, authenticated: Bool) async {
        isAuthenticated = authenticated
        let (sut, deps) = DBPContinuedProcessingTestUtils.makeTestIOSManager(
            freemiumDBPUserStateManagerOverride: stateManager
        )
        deps.database.hasMatchesToReturn = hasMatches
        deps.authenticationManager.isUserAuthenticatedValue = authenticated

        await sut.startImmediateScanOperations()
        await awaitFirstScanResult()
        _ = sut  // keep sut alive through the callback
    }

    func test_pathA_unauthenticated_hasMatchesTrue_persistsMatchesFound() async {
        await runPathA(hasMatches: true, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .matchesFound)
    }

    func test_pathA_unauthenticated_hasMatchesFalse_persistsNoMatches() async {
        await runPathA(hasMatches: false, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .noMatches)
    }

    func test_pathA_authenticated_persistsNothing() async {
        await runPathA(hasMatches: true, authenticated: true)
        XCTAssertNil(stateManager.firstScanResult)
    }

    // MARK: - Path B: coordinatorIsReadyForScanOperations completion block

    private func runPathB(hasMatches: Bool, authenticated: Bool) async {
        isAuthenticated = authenticated
        let (sut, deps) = DBPContinuedProcessingTestUtils.makeTestIOSManager(
            freemiumDBPUserStateManagerOverride: stateManager
        )
        deps.database.hasMatchesToReturn = hasMatches
        deps.authenticationManager.isUserAuthenticatedValue = authenticated

        await sut.coordinatorIsReadyForScanOperations()
        await awaitFirstScanResult()
        _ = sut
    }

    func test_pathB_unauthenticated_hasMatchesTrue_persistsMatchesFound() async {
        await runPathB(hasMatches: true, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .matchesFound)
    }

    func test_pathB_unauthenticated_hasMatchesFalse_persistsNoMatches() async {
        await runPathB(hasMatches: false, authenticated: false)
        XCTAssertEqual(stateManager.firstScanResult, .noMatches)
    }

    func test_pathB_authenticated_persistsNothing() async {
        await runPathB(hasMatches: true, authenticated: true)
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
}

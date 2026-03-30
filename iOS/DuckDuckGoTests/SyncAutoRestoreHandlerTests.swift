//
//  SyncAutoRestoreHandlerTests.swift
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
@testable import DDGSync
@testable import DuckDuckGo

final class SyncAutoRestoreHandlerTests: XCTestCase {

    private var mockDecisionManager: MockSyncAutoRestoreDecisionManager!
    private var mockSyncService: MockSyncAutoRestoreSyncService!
    private var sut: SyncAutoRestoreHandler!

    override func setUp() {
        super.setUp()
        mockDecisionManager = MockSyncAutoRestoreDecisionManager()
        mockSyncService = MockSyncAutoRestoreSyncService()
        sut = SyncAutoRestoreHandler(decisionManager: mockDecisionManager, syncService: mockSyncService)
    }

    override func tearDown() {
        sut = nil
        mockSyncService = nil
        mockDecisionManager = nil
        super.tearDown()
    }

    func testExistingDecisionForwardsToDecisionManager() {
        mockDecisionManager.existingDecisionValue = true

        XCTAssertEqual(sut.existingDecision(), true)
    }

    func testPersistDecisionForwardsToDecisionManager() throws {
        try sut.persistDecision(true)
        XCTAssertEqual(mockDecisionManager.persistedDecisions, [true])
    }

    func testPersistDecisionWhenDecisionManagerThrowsThenRethrows() {
        mockDecisionManager.persistDecisionError = HandlerTestError.expected

        XCTAssertThrowsError(try sut.persistDecision(true))
        XCTAssertTrue(mockDecisionManager.persistedDecisions.isEmpty)
    }

    func testClearDecisionForwardsToDecisionManager() {
        sut.clearDecision()

        XCTAssertEqual(mockDecisionManager.clearDecisionCallCount, 1)
    }

    func testIsEligibleForAutoRestoreWhenFeatureDisabledReturnsFalse() {
        mockDecisionManager.isAutoRestoreFeatureEnabled = false
        mockDecisionManager.existingDecisionValue = true
        mockSyncService.account = makeAccount()
        mockSyncService.authState = .inactive

        XCTAssertFalse(sut.isEligibleForAutoRestore())
    }

    func testIsEligibleForAutoRestoreWhenDecisionIsFalseReturnsFalse() {
        mockDecisionManager.isAutoRestoreFeatureEnabled = true
        mockDecisionManager.existingDecisionValue = false
        mockSyncService.account = makeAccount()
        mockSyncService.authState = .inactive

        XCTAssertFalse(sut.isEligibleForAutoRestore())
    }

    func testIsEligibleForAutoRestoreWhenAccountMissingReturnsFalse() {
        mockDecisionManager.isAutoRestoreFeatureEnabled = true
        mockDecisionManager.existingDecisionValue = true
        mockSyncService.account = nil
        mockSyncService.authState = .inactive

        XCTAssertFalse(sut.isEligibleForAutoRestore())
    }

    func testIsEligibleForAutoRestoreWhenAuthStateNotInactiveReturnsFalse() {
        mockDecisionManager.isAutoRestoreFeatureEnabled = true
        mockDecisionManager.existingDecisionValue = true
        mockSyncService.account = makeAccount()
        mockSyncService.authState = .active

        XCTAssertFalse(sut.isEligibleForAutoRestore())
    }

    func testIsEligibleForAutoRestoreWhenAllConditionsMetReturnsTrue() {
        mockDecisionManager.isAutoRestoreFeatureEnabled = true
        mockDecisionManager.existingDecisionValue = true
        mockSyncService.account = makeAccount()
        mockSyncService.authState = .inactive

        XCTAssertTrue(sut.isEligibleForAutoRestore())
    }

    func testRestoreFromPreservedAccountWhenSyncThrowsThenThrowsError() async {
        mockSyncService.enableSyncFromPreservedAccountError = HandlerTestError.expected

        do {
            try await sut.restoreFromPreservedAccount(source: .settings)
            XCTFail("Expected restore to throw")
        } catch {
            XCTAssertEqual(mockSyncService.enableSyncFromPreservedAccountCallCount, 1)
        }
    }

    func testRestoreFromPreservedAccountWhenSyncSucceedsCallsThrough() async {
        do {
            try await sut.restoreFromPreservedAccount(source: .settings)
        } catch {
            XCTFail("Expected restore to succeed")
        }

        XCTAssertEqual(mockSyncService.enableSyncFromPreservedAccountCallCount, 1)
    }

    private func makeAccount() -> SyncAccount {
        SyncAccount(
            deviceId: "device-id",
            deviceName: "iPhone",
            deviceType: "phone",
            userId: "user-id",
            primaryKey: Data(),
            secretKey: Data(),
            token: "token",
            state: .active
        )
    }
}

private enum HandlerTestError: Error {
    case expected
}

private final class MockSyncAutoRestoreDecisionManager: SyncAutoRestoreDecisionManaging {

    var isAutoRestoreFeatureEnabled = true
    var existingDecisionValue: Bool?
    var persistDecisionError: Error?
    private(set) var persistedDecisions: [Bool] = []
    private(set) var clearDecisionCallCount = 0

    func existingDecision() -> Bool? {
        existingDecisionValue
    }

    func persistDecision(_ decision: Bool) throws {
        if let persistDecisionError {
            throw persistDecisionError
        }
        persistedDecisions.append(decision)
    }

    func clearDecision() {
        clearDecisionCallCount += 1
    }

    func shouldPreserveAccountWhenSyncDisabled() -> Bool {
        isAutoRestoreFeatureEnabled && existingDecisionValue == true
    }
}

private final class MockSyncAutoRestoreSyncService: SyncAutoRestoreSyncing {

    var account: SyncAccount?
    var authState: SyncAuthState = .inactive
    var enableSyncFromPreservedAccountError: Error?
    private(set) var enableSyncFromPreservedAccountCallCount = 0

    func enableSyncFromPreservedAccount() async throws {
        enableSyncFromPreservedAccountCallCount += 1

        if let enableSyncFromPreservedAccountError {
            throw enableSyncFromPreservedAccountError
        }
    }
}

//
//  TokenRecoveryCoordinatorTests.swift
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
@testable import Subscription
@_spi(Testing) import Networking
import SubscriptionTestingUtilities

final class TokenRecoveryCoordinatorTests: XCTestCase {

    private final class StubStrategy: TokenRecoveryStrategy {
        private let result: Result<Void, Error>
        private(set) var calls = 0

        init(_ result: Result<Void, Error>) {
            self.result = result
        }

        func recover(_ context: TokenRecoveryContext) async throws {
            calls += 1
            try result.get()
        }
    }

    private let invalidTokenContext = TokenRecoveryContext(trigger: .invalidToken, deadPrimary: nil, lastSignOutDate: nil)

    // MARK: - Coordinator

    func testRecover_stopsAtFirstSuccess() async throws {
        let first = StubStrategy(.success(()))
        let second = StubStrategy(.success(()))
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [first, second], missingTokenStrategies: [])

        try await coordinator.recover(invalidTokenContext)

        XCTAssertEqual(first.calls, 1)
        XCTAssertEqual(second.calls, 0)
    }

    func testRecover_fallsThroughOnFailure() async throws {
        let first = StubStrategy(.failure(URLError(.timedOut)))
        let second = StubStrategy(.success(()))
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [first, second], missingTokenStrategies: [])

        try await coordinator.recover(invalidTokenContext)

        XCTAssertEqual(first.calls, 1)
        XCTAssertEqual(second.calls, 1)
    }

    func testRecover_everyStrategyNotApplicable_throwsNotAttempted() async {
        let coordinator = TokenRecoveryCoordinator(
            invalidTokenStrategies: [StubStrategy(.failure(TokenBackupError.unavailable)),
                                     StubStrategy(.failure(SubscriptionManagerError.tokenRecoveryNotAttempted))],
            missingTokenStrategies: [])

        do {
            try await coordinator.recover(invalidTokenContext)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .tokenRecoveryNotAttempted)
        }
    }

    func testRecover_noStrategies_throwsNotAttempted() async {
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [], missingTokenStrategies: [])

        do {
            try await coordinator.recover(invalidTokenContext)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .tokenRecoveryNotAttempted)
        }
    }

    func testRecover_realFailureAndNotApplicable_throwsTheRealFailure() async {
        let coordinator = TokenRecoveryCoordinator(
            invalidTokenStrategies: [StubStrategy(.failure(URLError(.timedOut))),
                                     StubStrategy(.failure(SubscriptionManagerError.tokenRecoveryNotAttempted))],
            missingTokenStrategies: [])

        do {
            try await coordinator.recover(invalidTokenContext)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    func testRecover_backupRejected_isARealFailure() async {
        let coordinator = TokenRecoveryCoordinator(
            invalidTokenStrategies: [StubStrategy(.failure(TokenBackupError.accountMismatch))],
            missingTokenStrategies: [])

        do {
            try await coordinator.recover(invalidTokenContext)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .accountMismatch)
        }
    }

    func testRecover_sessionChanged_stopsWithoutTryingLaterStrategies() async {
        let later = StubStrategy(.success(()))
        let coordinator = TokenRecoveryCoordinator(
            invalidTokenStrategies: [StubStrategy(.failure(TokenBackupError.sessionChanged)), later],
            missingTokenStrategies: [])

        do {
            try await coordinator.recover(invalidTokenContext)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .sessionChanged)
        }
        XCTAssertEqual(later.calls, 0)
    }

    func testRecover_missingTokenTrigger_usesOnlyTheMissingTokenStrategies() async throws {
        let invalidOnly = StubStrategy(.success(()))
        let missingOnly = StubStrategy(.success(()))
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [invalidOnly], missingTokenStrategies: [missingOnly])

        try await coordinator.recover(TokenRecoveryContext(trigger: .missingToken, deadPrimary: nil, lastSignOutDate: nil))

        XCTAssertEqual(invalidOnly.calls, 0)
        XCTAssertEqual(missingOnly.calls, 1)
    }

    // MARK: - Backup strategy

    func testBackupStrategy_passesAccountAndSignOutDate_andReportsTheTrigger() async throws {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        var restoredTriggers: [TokenRecoveryTrigger] = []
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { restoredTriggers.append($0) })
        let signOut = Date()

        try await strategy.recover(TokenRecoveryContext(trigger: .invalidToken,
                                                        deadPrimary: OAuthTokensFactory.makeTokenContainer(externalID: "acct"),
                                                        lastSignOutDate: signOut))

        XCTAssertEqual(client.restoreFromBackupCalls.count, 1)
        XCTAssertEqual(client.restoreFromBackupCalls.first?.expectedExternalID, "acct")
        XCTAssertEqual(client.restoreFromBackupCalls.first?.notIssuedBefore, signOut)
        XCTAssertEqual(restoredTriggers, [.invalidToken])
    }

    func testBackupStrategy_noDeadPrimary_acceptsAnyAccount() async throws {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { _ in })

        try await strategy.recover(TokenRecoveryContext(trigger: .missingToken, deadPrimary: nil, lastSignOutDate: nil))

        XCTAssertEqual(client.restoreFromBackupCalls.count, 1)
        XCTAssertNil(client.restoreFromBackupCalls.first?.expectedExternalID)
    }

    func testBackupStrategy_failure_doesNotReportARestore() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(URLError(.timedOut))
        var restoredTriggers: [TokenRecoveryTrigger] = []
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { restoredTriggers.append($0) })

        try? await strategy.recover(invalidTokenContext)

        XCTAssertTrue(restoredTriggers.isEmpty)
    }

    // MARK: - App Store strategy

    func testAppStoreStrategy_runsTheExpiredTokenRestore() async throws {
        let restoreFlow = AppStoreRestoreFlowMock()
        let strategy = AppStoreTokenRecovery(recoverer: DeadTokenRecoverer(), purchasePlatform: .appStore, restoreFlow: restoreFlow)

        try await strategy.recover(invalidTokenContext)

        XCTAssertTrue(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func testAppStoreStrategy_stripe_isNotAttempted() async {
        let restoreFlow = AppStoreRestoreFlowMock()
        let strategy = AppStoreTokenRecovery(recoverer: DeadTokenRecoverer(), purchasePlatform: .stripe, restoreFlow: restoreFlow)

        do {
            try await strategy.recover(invalidTokenContext)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .tokenRecoveryNotAttempted)
        }
        XCTAssertFalse(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }
}

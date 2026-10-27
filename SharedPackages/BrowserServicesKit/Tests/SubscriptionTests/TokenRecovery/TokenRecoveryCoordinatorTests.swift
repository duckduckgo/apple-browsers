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
import FoundationExtensions
@testable import Subscription
@_spi(Testing) @testable import Networking
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

    private let invalidTokenContext = TokenRecoveryContext(trigger: .invalidToken, deadPrimary: nil)

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

    func testRecover_backupReadFailed_triesTheNextStrategyAndThrowsTheReadFailure() async {
        let readFailed = TokenBackupError.readFailed(underlying: NSError(domain: "keychain", code: 1))
        let next = StubStrategy(.failure(SubscriptionManagerError.tokenRecoveryNotAttempted))
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [StubStrategy(.failure(readFailed)), next],
                                                   missingTokenStrategies: [])

        do {
            try await coordinator.recover(invalidTokenContext)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, readFailed)
        }
        XCTAssertEqual(next.calls, 1)
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

        try await coordinator.recover(TokenRecoveryContext(trigger: .missingToken, deadPrimary: nil))

        XCTAssertEqual(invalidOnly.calls, 0)
        XCTAssertEqual(missingOnly.calls, 1)
    }

    // MARK: - Backup strategy

    func testBackupStrategy_passesTheAccount_andReportsTheTrigger() async throws {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        var restoredTriggers: [TokenRecoveryTrigger] = []
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { restoredTriggers.append($0) })

        try await strategy.recover(TokenRecoveryContext(trigger: .invalidToken,
                                                        deadPrimary: OAuthTokensFactory.makeTokenContainer(externalID: "acct")))

        XCTAssertEqual(client.restoreFromBackupCalls.count, 1)
        XCTAssertEqual(client.restoreFromBackupCalls.first?.expectedExternalID, "acct")
        XCTAssertEqual(restoredTriggers, [.invalidToken])
    }

    func testBackupStrategy_noDeadPrimary_acceptsAnyAccount() async throws {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { _ in })

        try await strategy.recover(TokenRecoveryContext(trigger: .missingToken, deadPrimary: nil))

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

    // MARK: - Backup strategy backoff

    private let missingTokenContext = TokenRecoveryContext(trigger: .missingToken, deadPrimary: nil)

    private final class Clock {
        var now = Date()
    }

    func testBackupStrategy_missingToken_afterATransientFailure_skipsUntilTheRetryInterval() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(URLError(.timedOut))
        let clock = Clock()
        let strategy = BackupTokenRecovery(oAuthClient: client, retryInterval: .minutes(5), now: { clock.now }, onRestored: { _ in })

        try? await strategy.recover(missingTokenContext)
        do {
            try await strategy.recover(missingTokenContext)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }
        XCTAssertEqual(client.restoreFromBackupCalls.count, 1)

        clock.now = clock.now.addingTimeInterval(.minutes(6))
        try? await strategy.recover(missingTokenContext)
        XCTAssertEqual(client.restoreFromBackupCalls.count, 2)
    }

    func testBackupStrategy_missingToken_afterABackupReadFailure_skipsUntilTheRetryInterval() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(TokenBackupError.readFailed(underlying: NSError(domain: "keychain", code: 1)))
        let strategy = BackupTokenRecovery(oAuthClient: client, retryInterval: .minutes(5), now: { Date() }, onRestored: { _ in })

        try? await strategy.recover(missingTokenContext)
        try? await strategy.recover(missingTokenContext)

        XCTAssertEqual(client.restoreFromBackupCalls.count, 1)
    }

    func testBackupStrategy_isTemporary_onlyForNetworkServerAndReadFailures() {
        let suspended = OAuthRequestError(from: OAuthRequest.BodyError(errorCode: .suspendedAccount, tokenStatus: nil))

        XCTAssertTrue(BackupTokenRecovery.isTemporary(URLError(.timedOut)))
        XCTAssertTrue(BackupTokenRecovery.isTemporary(APIRequestV2Error.urlSession(URLError(.notConnectedToInternet))))
        XCTAssertTrue(BackupTokenRecovery.isTemporary(OAuthServiceError.invalidResponseCode(.internalServerError)))
        XCTAssertTrue(BackupTokenRecovery.isTemporary(OAuthServiceError.invalidResponseCode(.tooManyRequests)))
        XCTAssertTrue(BackupTokenRecovery.isTemporary(TokenBackupError.readFailed(underlying: NSError(domain: "keychain", code: 1))))

        XCTAssertFalse(BackupTokenRecovery.isTemporary(OAuthServiceError.authAPIError(suspended)))
        XCTAssertFalse(BackupTokenRecovery.isTemporary(OAuthServiceError.invalidResponseCode(.badRequest)))
        XCTAssertFalse(BackupTokenRecovery.isTemporary(OAuthClientError.invalidTokenRequest(.reused)))
        XCTAssertFalse(BackupTokenRecovery.isTemporary(TokenBackupError.expired))
        XCTAssertFalse(BackupTokenRecovery.isTemporary(NSError(domain: "JWT", code: 1)))
    }

    func testBackupStrategy_invalidToken_isNotHeldBackByAMissingTokenFailure() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(URLError(.timedOut))
        let strategy = BackupTokenRecovery(oAuthClient: client, retryInterval: .minutes(5), now: { Date() }, onRestored: { _ in })

        try? await strategy.recover(missingTokenContext)
        try? await strategy.recover(invalidTokenContext)

        XCTAssertEqual(client.restoreFromBackupCalls.count, 2)
    }

    func testBackupStrategy_rejectedOrTerminalFailures_doNotBackOff() async {
        let client = MockOAuthClient()
        let strategy = BackupTokenRecovery(oAuthClient: client, retryInterval: .minutes(5), now: { Date() }, onRestored: { _ in })

        client.restoreFromBackupResponse = .failure(TokenBackupError.accountMismatch)
        try? await strategy.recover(missingTokenContext)
        client.restoreFromBackupResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        try? await strategy.recover(missingTokenContext)
        client.restoreFromBackupResponse = .failure(TokenBackupError.unavailable)
        try? await strategy.recover(missingTokenContext)

        XCTAssertEqual(client.restoreFromBackupCalls.count, 3)
    }

    func testBackupStrategy_successAfterTheRetryInterval_clearsTheBackoff() async throws {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(URLError(.timedOut))
        let clock = Clock()
        let strategy = BackupTokenRecovery(oAuthClient: client, retryInterval: .minutes(5), now: { clock.now }, onRestored: { _ in })
        try? await strategy.recover(missingTokenContext)

        clock.now = clock.now.addingTimeInterval(.minutes(6))
        client.restoreFromBackupResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        try await strategy.recover(missingTokenContext)
        client.restoreFromBackupResponse = .failure(TokenBackupError.unavailable)
        try? await strategy.recover(missingTokenContext)

        XCTAssertEqual(client.restoreFromBackupCalls.count, 3)
    }
}

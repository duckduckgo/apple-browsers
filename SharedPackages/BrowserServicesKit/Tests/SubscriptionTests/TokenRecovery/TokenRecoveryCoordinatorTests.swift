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
        let method: TokenRecoveryMethod
        private let result: TokenRecoveryResult
        private(set) var calls = 0

        init(_ result: TokenRecoveryResult, method: TokenRecoveryMethod = .backup) {
            self.result = result
            self.method = method
        }

        func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryResult {
            calls += 1
            return result
        }
    }

    private let invalidTokenContext = TokenRecoveryContext(trigger: .invalidToken, deadPrimary: nil)

    // MARK: - Coordinator

    func testRecover_stopsAtFirstSuccess() async {
        let first = StubStrategy(.recovered)
        let second = StubStrategy(.recovered)
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [first, second], missingTokenStrategies: [])

        let result = await coordinator.recover(invalidTokenContext).result

        XCTAssertEqual(result.outcome, .recovered)
        XCTAssertEqual(first.calls, 1)
        XCTAssertEqual(second.calls, 0)
    }

    func testRecover_fallsThroughOnFailure() async {
        let first = StubStrategy(.failed(URLError(.timedOut)))
        let second = StubStrategy(.recovered)
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [first, second], missingTokenStrategies: [])

        let result = await coordinator.recover(invalidTokenContext).result

        XCTAssertEqual(result.outcome, .recovered)
        XCTAssertEqual(first.calls, 1)
        XCTAssertEqual(second.calls, 1)
    }

    func testRecover_backupReadFailed_triesTheNextStrategyAndReturnsTheReadFailure() async {
        let readFailed = TokenBackupError.readFailed(underlying: NSError(domain: "keychain", code: 1))
        let next = StubStrategy(.notApplicable)
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [StubStrategy(.failed(readFailed)), next],
                                                   missingTokenStrategies: [])

        let result = await coordinator.recover(invalidTokenContext).result

        XCTAssertEqual(result.failure as? TokenBackupError, readFailed)
        XCTAssertEqual(next.calls, 1)
    }

    func testRecover_everyStrategyNotApplicable_isNotApplicable() async {
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [StubStrategy(.notApplicable), StubStrategy(.notApplicable)],
                                                   missingTokenStrategies: [])

        let result = await coordinator.recover(invalidTokenContext).result

        XCTAssertEqual(result.outcome, .notApplicable)
    }

    func testRecover_noStrategies_isNotApplicable() async {
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [], missingTokenStrategies: [])

        let result = await coordinator.recover(invalidTokenContext).result

        XCTAssertEqual(result.outcome, .notApplicable)
    }

    func testRecover_realFailureAndNotApplicable_returnsTheRealFailure() async {
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [StubStrategy(.failed(URLError(.timedOut))), StubStrategy(.notApplicable)],
                                                   missingTokenStrategies: [])

        let result = await coordinator.recover(invalidTokenContext).result

        XCTAssertEqual((result.failure as? URLError)?.code, .timedOut)
    }

    func testRecover_twoFailures_returnsTheLastOne() async {
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [StubStrategy(.failed(URLError(.timedOut))),
                                                                            StubStrategy(.failed(TokenBackupError.expired))],
                                                   missingTokenStrategies: [])

        let result = await coordinator.recover(invalidTokenContext).result

        XCTAssertEqual(result.failure as? TokenBackupError, .expired)
    }

    func testRecover_sessionChanged_stopsWithoutTryingLaterStrategies() async {
        let later = StubStrategy(.recovered)
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [StubStrategy(.sessionChanged), later],
                                                   missingTokenStrategies: [])

        let result = await coordinator.recover(invalidTokenContext).result

        XCTAssertEqual(result.outcome, .sessionChanged)
        XCTAssertEqual(later.calls, 0)
    }

    func testRecover_reportsEachStrategyThatRan_andTheMethodThatRecovered() async {
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [StubStrategy(.failed(TokenBackupError.expired), method: .backup),
                                                                            StubStrategy(.recovered, method: .appStore)],
                                                   missingTokenStrategies: [])

        let report = await coordinator.recover(invalidTokenContext)

        XCTAssertEqual(report.attempts.map(\.method), [.backup, .appStore])
        XCTAssertEqual(report.result(of: .backup)?.failure as? TokenBackupError, .expired)
        XCTAssertEqual(report.result(of: .appStore)?.outcome, .recovered)
        XCTAssertEqual(report.recoveredBy, .appStore)
    }

    func testRecover_nothingRecovered_reportsNoRecoveryMethod() async {
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [StubStrategy(.failed(URLError(.timedOut)), method: .backup),
                                                                            StubStrategy(.notApplicable, method: .appStore)],
                                                   missingTokenStrategies: [])

        let report = await coordinator.recover(invalidTokenContext)

        XCTAssertNil(report.recoveredBy)
        XCTAssertEqual(report.result(of: .appStore)?.outcome, .notApplicable)
    }

    // MARK: - Backup recovery outcome

    func testBackupRecoveryOutcome_mapsEachBackupResult() {
        XCTAssertEqual(BackupRecoveryOutcome(nil), .notAttempted)
        XCTAssertEqual(BackupRecoveryOutcome(.notApplicable), .notAttempted)
        XCTAssertEqual(BackupRecoveryOutcome(.recovered), .succeeded)
        XCTAssertEqual(BackupRecoveryOutcome(.sessionChanged), .sessionChanged)
        XCTAssertEqual(BackupRecoveryOutcome(.failed(TokenBackupError.accountMismatch)), .rejected)
        XCTAssertEqual(BackupRecoveryOutcome(.failed(OAuthClientError.invalidTokenRequest(.reused))), .rejected)
        XCTAssertEqual(BackupRecoveryOutcome(.failed(URLError(.timedOut))), .failed)
        XCTAssertEqual(BackupRecoveryOutcome(.failed(TokenBackupError.readFailed(underlying: NSError(domain: "keychain", code: 1)))), .failed)
        XCTAssertEqual(BackupRecoveryOutcome(.failed(NSError(domain: "unknown", code: 1))), .failed)
    }

    func testRecover_missingTokenTrigger_usesOnlyTheMissingTokenStrategies() async {
        let invalidOnly = StubStrategy(.recovered)
        let missingOnly = StubStrategy(.recovered)
        let coordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [invalidOnly], missingTokenStrategies: [missingOnly])

        _ = await coordinator.recover(TokenRecoveryContext(trigger: .missingToken, deadPrimary: nil))

        XCTAssertEqual(invalidOnly.calls, 0)
        XCTAssertEqual(missingOnly.calls, 1)
    }

    // MARK: - Backup strategy

    func testBackupStrategy_passesTheAccount_andReportsTheTrigger() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        var restoredTriggers: [TokenRecoveryTrigger] = []
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { restoredTriggers.append($0) })

        let result = await strategy.recover(TokenRecoveryContext(trigger: .invalidToken,
                                                                 deadPrimary: OAuthTokensFactory.makeTokenContainer(externalID: "acct")))

        XCTAssertEqual(result.outcome, .recovered)
        XCTAssertEqual(client.restoreFromBackupCalls.count, 1)
        XCTAssertEqual(client.restoreFromBackupCalls.first?.expectedExternalID, "acct")
        XCTAssertEqual(restoredTriggers, [.invalidToken])
    }

    func testBackupStrategy_noDeadPrimary_acceptsAnyAccount() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { _ in })

        _ = await strategy.recover(TokenRecoveryContext(trigger: .missingToken, deadPrimary: nil))

        XCTAssertEqual(client.restoreFromBackupCalls.count, 1)
        XCTAssertNil(client.restoreFromBackupCalls.first?.expectedExternalID)
    }

    func testBackupStrategy_failure_isReturnedWithoutReportingARestore() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(URLError(.timedOut))
        var restoredTriggers: [TokenRecoveryTrigger] = []
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { restoredTriggers.append($0) })

        let result = await strategy.recover(invalidTokenContext)

        XCTAssertEqual((result.failure as? URLError)?.code, .timedOut)
        XCTAssertTrue(restoredTriggers.isEmpty)
    }

    func testBackupStrategy_noBackup_isNotApplicable() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(TokenBackupError.unavailable)
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { _ in })

        let result = await strategy.recover(invalidTokenContext)

        XCTAssertEqual(result.outcome, .notApplicable)
    }

    func testBackupStrategy_sessionChanged_isReported() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(TokenBackupError.sessionChanged)
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { _ in })

        let result = await strategy.recover(invalidTokenContext)

        XCTAssertEqual(result.outcome, .sessionChanged)
    }

    func testBackupStrategy_rejectedBackup_isAFailure() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(TokenBackupError.accountMismatch)
        let strategy = BackupTokenRecovery(oAuthClient: client, onRestored: { _ in })

        let result = await strategy.recover(invalidTokenContext)

        XCTAssertEqual(result.failure as? TokenBackupError, .accountMismatch)
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

        _ = await strategy.recover(missingTokenContext)
        let skipped = await strategy.recover(missingTokenContext)
        XCTAssertEqual(skipped.outcome, .notApplicable)
        XCTAssertEqual(client.restoreFromBackupCalls.count, 1)

        clock.now = clock.now.addingTimeInterval(.minutes(6))
        _ = await strategy.recover(missingTokenContext)
        XCTAssertEqual(client.restoreFromBackupCalls.count, 2)
    }

    func testBackupStrategy_missingToken_afterABackupReadFailure_skipsUntilTheRetryInterval() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(TokenBackupError.readFailed(underlying: NSError(domain: "keychain", code: 1)))
        let strategy = BackupTokenRecovery(oAuthClient: client, retryInterval: .minutes(5), now: { Date() }, onRestored: { _ in })

        _ = await strategy.recover(missingTokenContext)
        _ = await strategy.recover(missingTokenContext)

        XCTAssertEqual(client.restoreFromBackupCalls.count, 1)
    }

    func testBackupStrategy_invalidToken_isNotHeldBackByAMissingTokenFailure() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(URLError(.timedOut))
        let strategy = BackupTokenRecovery(oAuthClient: client, retryInterval: .minutes(5), now: { Date() }, onRestored: { _ in })

        _ = await strategy.recover(missingTokenContext)
        _ = await strategy.recover(invalidTokenContext)

        XCTAssertEqual(client.restoreFromBackupCalls.count, 2)
    }

    func testBackupStrategy_rejectedOrTerminalFailures_doNotBackOff() async {
        let client = MockOAuthClient()
        let strategy = BackupTokenRecovery(oAuthClient: client, retryInterval: .minutes(5), now: { Date() }, onRestored: { _ in })

        client.restoreFromBackupResponse = .failure(TokenBackupError.accountMismatch)
        _ = await strategy.recover(missingTokenContext)
        client.restoreFromBackupResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        _ = await strategy.recover(missingTokenContext)
        client.restoreFromBackupResponse = .failure(TokenBackupError.unavailable)
        _ = await strategy.recover(missingTokenContext)
        client.restoreFromBackupResponse = .failure(TokenBackupError.sessionChanged)
        _ = await strategy.recover(missingTokenContext)
        _ = await strategy.recover(missingTokenContext)

        XCTAssertEqual(client.restoreFromBackupCalls.count, 5)
    }

    func testBackupStrategy_successAfterTheRetryInterval_clearsTheBackoff() async {
        let client = MockOAuthClient()
        client.restoreFromBackupResponse = .failure(URLError(.timedOut))
        let clock = Clock()
        let strategy = BackupTokenRecovery(oAuthClient: client, retryInterval: .minutes(5), now: { clock.now }, onRestored: { _ in })
        _ = await strategy.recover(missingTokenContext)

        clock.now = clock.now.addingTimeInterval(.minutes(6))
        client.restoreFromBackupResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        _ = await strategy.recover(missingTokenContext)
        client.restoreFromBackupResponse = .failure(TokenBackupError.unavailable)
        _ = await strategy.recover(missingTokenContext)

        XCTAssertEqual(client.restoreFromBackupCalls.count, 3)
    }
}

//
//  TokenBackupStoreTests.swift
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
@_spi(Testing) @testable import Networking

final class TokenBackupStoreTests: XCTestCase {

    private let primary = OAuthTokensFactory.makeTokenContainer(accessToken: "primaryA", refreshToken: "primaryR")

    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "TokenBackupStoreTests.\(UUID().uuidString)")
    }

    override func tearDown() {
        userDefaults = nil
        super.tearDown()
    }

    private func makeStore(storage: any AuthTokenStoring, now: Date = Date()) -> TokenBackupStore {
        TokenBackupStore(storage: storage, userDefaults: userDefaults, maxAge: .days(14), now: { now })
    }

    /// Records a sign-out whose newest token was issued at `date`, before any backup is stored.
    private func recordSignOut(at date: Date) {
        makeStore(storage: MockTokenStorage()).recordSignOut(current: OAuthTokensFactory.makeTokenContainer(refreshTokenIssuedAt: date),
                                                             currentReadFailed: false)
    }

    // MARK: - needsRenewal

    func testNeedsRenewal_noBackup_isTrue() {
        XCTAssertTrue(makeStore(storage: MockTokenStorage()).needsRenewal(for: primary))
    }

    func testNeedsRenewal_freshBackupForSameAccount_isFalse() {
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR"))

        XCTAssertFalse(makeStore(storage: storage).needsRenewal(for: primary))
    }

    func testNeedsRenewal_backupOlderThanMaxAge_isTrue() {
        let issuedAt = Date()
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                 refreshTokenIssuedAt: issuedAt,
                                                                                                 refreshTokenExpiresAt: issuedAt.addingTimeInterval(.days(30))))

        XCTAssertTrue(makeStore(storage: storage, now: issuedAt.addingTimeInterval(.days(15))).needsRenewal(for: primary))
    }

    func testNeedsRenewal_backupYoungerThanMaxAge_isFalse() {
        let issuedAt = Date()
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                 refreshTokenIssuedAt: issuedAt,
                                                                                                 refreshTokenExpiresAt: issuedAt.addingTimeInterval(.days(30))))

        XCTAssertFalse(makeStore(storage: storage, now: issuedAt.addingTimeInterval(.days(13))).needsRenewal(for: primary))
    }

    func testNeedsRenewal_expiredBackup_isTrue() {
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                 refreshTokenExpiresAt: Date().addingTimeInterval(-1)))

        XCTAssertTrue(makeStore(storage: storage).needsRenewal(for: primary))
    }

    func testNeedsRenewal_backupExpiredByTheInjectedClock_isTrue() {
        let issuedAt = Date()
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                 refreshTokenIssuedAt: issuedAt,
                                                                                                 refreshTokenExpiresAt: issuedAt.addingTimeInterval(.days(1))))

        XCTAssertTrue(makeStore(storage: storage, now: issuedAt.addingTimeInterval(.days(2))).needsRenewal(for: primary))
    }

    func testNeedsRenewal_backupForAnotherAccount_isTrue() {
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", externalID: "someone-else"))

        XCTAssertTrue(makeStore(storage: storage).needsRenewal(for: primary))
    }

    func testNeedsRenewal_readFails_isFalse() {
        XCTAssertFalse(makeStore(storage: ThrowingTokenStorage()).needsRenewal(for: primary))
    }

    // MARK: - save and remove

    func testSave_storesBackup() throws {
        let storage = MockTokenStorage()
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR")

        try makeStore(storage: storage).save(backup)

        XCTAssertEqual(try storage.getTokenContainer(), backup)
    }

    func testSave_failure_throws() {
        XCTAssertThrowsError(try makeStore(storage: ThrowingTokenStorage()).save(OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR")))
    }

    func testRemove_deletesBackup() throws {
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR"))

        makeStore(storage: storage).remove()

        XCTAssertNil(try storage.getTokenContainer())
    }

    func testRemove_failureIsIgnored() {
        makeStore(storage: ThrowingTokenStorage()).remove()
    }

    // MARK: - usableBackup

    private func assertRejected(_ expected: TokenBackupError,
                                store: TokenBackupStore,
                                expectedExternalID: String?,
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        do {
            _ = try store.usableBackup(expectedExternalID: expectedExternalID)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func testUsableBackup_validBackup_returnsIt() throws {
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", externalID: "acct")
        let storage = MockTokenStorage(tokenContainer: backup)

        let result = try makeStore(storage: storage).usableBackup(expectedExternalID: "acct")

        XCTAssertEqual(result, backup)
        XCTAssertEqual(try storage.getTokenContainer(), backup)
    }

    func testUsableBackup_noBackup_isUnavailable() {
        assertRejected(.unavailable, store: makeStore(storage: MockTokenStorage()), expectedExternalID: nil)
    }

    func testUsableBackup_readFails_isReadFailedWithTheStorageError() {
        let storageError = NSError(domain: "keychain", code: 1)

        assertRejected(.readFailed(underlying: storageError), store: makeStore(storage: ThrowingTokenStorage()), expectedExternalID: nil)
        XCTAssertEqual(TokenBackupError.readFailed(underlying: storageError).underlyingError as NSError?, storageError)
    }

    func testUsableBackup_anotherAccount_isRejectedAndDeleted() throws {
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", externalID: "other"))

        assertRejected(.accountMismatch, store: makeStore(storage: storage), expectedExternalID: "acct")
        XCTAssertNil(try storage.getTokenContainer())
    }

    func testUsableBackup_noExpectedAccount_acceptsAnyAccount() throws {
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", externalID: "other")

        XCTAssertEqual(try makeStore(storage: MockTokenStorage(tokenContainer: backup)).usableBackup(expectedExternalID: nil), backup)
    }

    func testUsableBackup_issuedBeforeSignOut_isRejectedAndDeleted() throws {
        let signOut = Date()
        recordSignOut(at: signOut)
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                 refreshTokenIssuedAt: signOut.addingTimeInterval(-60)))

        assertRejected(.predatesSignOut, store: makeStore(storage: storage), expectedExternalID: nil)
        XCTAssertNil(try storage.getTokenContainer())
    }

    func testUsableBackup_issuedAtTheCutoff_isRejected() throws {
        let cutoff = Date()
        recordSignOut(at: cutoff)
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", refreshTokenIssuedAt: cutoff))

        assertRejected(.predatesSignOut, store: makeStore(storage: storage), expectedExternalID: nil)
    }

    func testUsableBackup_issuedAfterSignOut_isUsable() throws {
        recordSignOut(at: Date().addingTimeInterval(-60))
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", refreshTokenIssuedAt: Date())

        XCTAssertEqual(try makeStore(storage: MockTokenStorage(tokenContainer: backup)).usableBackup(expectedExternalID: nil), backup)
    }

    func testUsableBackup_noSignOutRecorded_isUsable() throws {
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", refreshTokenIssuedAt: Date().addingTimeInterval(-3600))

        XCTAssertEqual(try makeStore(storage: MockTokenStorage(tokenContainer: backup)).usableBackup(expectedExternalID: nil), backup)
    }

    // MARK: - recordSignOut

    func testRecordSignOut_recordsTheNewestIssueDateOfTheCurrentAndBackupTokens() {
        let currentIssuedAt = Date().addingTimeInterval(-3600)
        let backupIssuedAt = Date().addingTimeInterval(-60)
        let store = makeStore(storage: MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                                 refreshTokenIssuedAt: backupIssuedAt)))

        store.recordSignOut(current: OAuthTokensFactory.makeTokenContainer(refreshTokenIssuedAt: currentIssuedAt), currentReadFailed: false)

        XCTAssertEqual(store.signOutCutoff, backupIssuedAt)
    }

    func testRecordSignOut_nothingStored_keepsThePreviousCutoff() {
        let previous = Date().addingTimeInterval(-3600)
        recordSignOut(at: previous)
        let store = makeStore(storage: MockTokenStorage())

        store.recordSignOut(current: nil, currentReadFailed: false)

        XCTAssertEqual(store.signOutCutoff, previous)
    }

    func testRecordSignOut_nothingStoredAndNoPreviousSignOut_recordsNoCutoff() {
        let store = makeStore(storage: MockTokenStorage())

        store.recordSignOut(current: nil, currentReadFailed: false)

        XCTAssertNil(store.signOutCutoff)
    }

    func testRecordSignOut_currentUnreadableAndNoBackup_recordsTheCurrentDate() {
        let now = Date()
        let store = makeStore(storage: MockTokenStorage(), now: now)

        store.recordSignOut(current: nil, currentReadFailed: true)

        XCTAssertEqual(store.signOutCutoff, now)
    }

    func testRecordSignOut_currentUnreadable_stillUsesTheBackupIssueDate() {
        let backupIssuedAt = Date().addingTimeInterval(-60)
        let store = makeStore(storage: MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                                 refreshTokenIssuedAt: backupIssuedAt)),
                              now: Date())

        store.recordSignOut(current: nil, currentReadFailed: true)

        XCTAssertEqual(store.signOutCutoff, backupIssuedAt)
    }

    func testUsableBackup_expiredByTheInjectedClock_isRejectedAndDeleted() throws {
        let issuedAt = Date()
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                 refreshTokenIssuedAt: issuedAt,
                                                                                                 refreshTokenExpiresAt: issuedAt.addingTimeInterval(.days(30))))

        assertRejected(.expired, store: makeStore(storage: storage, now: issuedAt.addingTimeInterval(.days(31))), expectedExternalID: nil)
        XCTAssertNil(try storage.getTokenContainer())
    }
}

private final class ThrowingTokenStorage: AuthTokenStoring {
    func getTokenContainer() throws -> TokenContainer? {
        throw NSError(domain: "keychain", code: 1)
    }

    func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        throw NSError(domain: "keychain", code: 2)
    }
}

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

    private func makeStore(storage: any AuthTokenStoring, now: Date = Date()) -> TokenBackupStore {
        TokenBackupStore(storage: storage, maxAge: .days(14), now: { now })
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

        makeStore(storage: storage).save(backup)

        XCTAssertEqual(try storage.getTokenContainer(), backup)
    }

    func testSave_failureIsIgnored() {
        makeStore(storage: ThrowingTokenStorage()).save(OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR"))
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
                                issuedAfter: Date?,
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        do {
            _ = try store.usableBackup(expectedExternalID: expectedExternalID, issuedAfter: issuedAfter)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func testUsableBackup_validBackup_returnsIt() throws {
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", externalID: "acct")
        let storage = MockTokenStorage(tokenContainer: backup)

        let result = try makeStore(storage: storage).usableBackup(expectedExternalID: "acct", issuedAfter: nil)

        XCTAssertEqual(result, backup)
        XCTAssertEqual(try storage.getTokenContainer(), backup)
    }

    func testUsableBackup_noBackup_isUnavailable() {
        assertRejected(.unavailable, store: makeStore(storage: MockTokenStorage()), expectedExternalID: nil, issuedAfter: nil)
    }

    func testUsableBackup_readFails_isReadFailedWithTheStorageError() {
        let storageError = NSError(domain: "keychain", code: 1)

        assertRejected(.readFailed(underlying: storageError), store: makeStore(storage: ThrowingTokenStorage()), expectedExternalID: nil, issuedAfter: nil)
        XCTAssertEqual(TokenBackupError.readFailed(underlying: storageError).underlyingError as NSError?, storageError)
    }

    func testUsableBackup_anotherAccount_isRejectedAndDeleted() throws {
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", externalID: "other"))

        assertRejected(.accountMismatch, store: makeStore(storage: storage), expectedExternalID: "acct", issuedAfter: nil)
        XCTAssertNil(try storage.getTokenContainer())
    }

    func testUsableBackup_noExpectedAccount_acceptsAnyAccount() throws {
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", externalID: "other")

        XCTAssertEqual(try makeStore(storage: MockTokenStorage(tokenContainer: backup)).usableBackup(expectedExternalID: nil, issuedAfter: nil), backup)
    }

    func testUsableBackup_issuedBeforeSignOut_isRejectedAndDeleted() throws {
        let signOut = Date()
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                 refreshTokenIssuedAt: signOut.addingTimeInterval(-60)))

        assertRejected(.predatesSignOut, store: makeStore(storage: storage), expectedExternalID: nil, issuedAfter: signOut)
        XCTAssertNil(try storage.getTokenContainer())
    }

    func testUsableBackup_issuedAtTheCutoff_isRejected() throws {
        let cutoff = Date()
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", refreshTokenIssuedAt: cutoff))

        assertRejected(.predatesSignOut, store: makeStore(storage: storage), expectedExternalID: nil, issuedAfter: cutoff)
    }

    func testUsableBackup_issuedAfterSignOut_isUsable() throws {
        let signOut = Date().addingTimeInterval(-60)
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", refreshTokenIssuedAt: Date())

        XCTAssertEqual(try makeStore(storage: MockTokenStorage(tokenContainer: backup)).usableBackup(expectedExternalID: nil, issuedAfter: signOut), backup)
    }

    func testUsableBackup_expiredByTheInjectedClock_isRejectedAndDeleted() throws {
        let issuedAt = Date()
        let storage = MockTokenStorage(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                                 refreshTokenIssuedAt: issuedAt,
                                                                                                 refreshTokenExpiresAt: issuedAt.addingTimeInterval(.days(30))))

        assertRejected(.expired, store: makeStore(storage: storage, now: issuedAt.addingTimeInterval(.days(31))), expectedExternalID: nil, issuedAfter: nil)
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

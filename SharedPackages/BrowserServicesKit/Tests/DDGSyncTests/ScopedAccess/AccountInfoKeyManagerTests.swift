//
//  AccountInfoKeyManagerTests.swift
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

final class AccountInfoKeyManagerTests: XCTestCase {

    private let account = SyncAccount.mock
    private let crypter = CryptingMock()

    func testWhenDefaultCredentialKeyIsCachedThenLoadsWithoutFetching() async throws {
        let protectedKey = try makeDefaultCredentialProtectedKey()
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([protectedKey])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        let key = try await manager.loadKey(for: account)

        XCTAssertEqual(key.kid, protectedKey.kid)
        XCTAssertTrue(scopedAccess.fetchProtectedKeysCalls.isEmpty)
    }

    func testWhenCacheIsCorruptThenFetchesAndCachesServerKeys() async throws {
        let protectedKey = try makeDefaultCredentialProtectedKey()
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = Data("invalid".utf8)
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = [protectedKey]
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        let key = try await manager.loadKey(for: account)

        let cachedData = try XCTUnwrap(secureStore.theProtectedKeysData)
        let cachedKeys = try JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: cachedData)
        XCTAssertEqual(key.kid, protectedKey.kid)
        XCTAssertEqual(scopedAccess.fetchProtectedKeysCalls.map(\.userId), [account.userId])
        XCTAssertEqual(cachedKeys.map(\.kid), [protectedKey.kid])
    }

    func testWhenOnlyThirdPartyWrapperIsCachedThenLoadsUsingScopedPassword() async throws {
        let scopedPassword = Data(repeating: 0x03, count: 32)
        let protectedKey = try makeThirdPartyCredentialProtectedKey(scopedPassword: scopedPassword)
        let secureStore = SecureStorageStub()
        secureStore.theScopedPassword = scopedPassword
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([protectedKey])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        let key = try await manager.loadKey(for: account)

        XCTAssertEqual(key.kid, protectedKey.kid)
        XCTAssertTrue(scopedAccess.fetchProtectedKeysCalls.isEmpty)
    }

    func testWhenThirdPartyWrapperIsCachedWithoutScopedPasswordThenRecoversAndCachesPassword() async throws {
        let scopedPassword = Data(repeating: 0x03, count: 32)
        let protectedKey = try makeThirdPartyCredentialProtectedKey(scopedPassword: scopedPassword)
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([protectedKey])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchAccessCredentialsStub = [
            AccessCredential(id: SyncCredentialID.thirdParty, scope: "sync", encrypted3PartyCredential: "encrypted")
        ]
        scopedAccess.recoverScopedPasswordStub = scopedPassword
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        let key = try await manager.loadKey(for: account)

        XCTAssertEqual(key.kid, protectedKey.kid)
        XCTAssertEqual(scopedAccess.fetchAccessCredentialsCalls.map(\.userId), [account.userId])
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.map(\.userID), [account.userId])
        XCTAssertEqual(secureStore.theScopedPassword, scopedPassword)
    }

    func testWhenCachedThirdPartyKeyAndRefreshFailTransientlyThenPreservesProtectedKeyCache() async throws {
        let scopedPassword = Data(repeating: 0x03, count: 32)
        let accountInfoKey = try makeThirdPartyCredentialProtectedKey(scopedPassword: scopedPassword)
        let unrelatedKey = ProtectedKey(kid: "unrelated-key",
                                        encryptedPrivateKey: "unrelated-encrypted-key",
                                        publicKey: accountInfoKey.publicKey,
                                        encryptedWith: SyncCredentialID.defaultCredential,
                                        purpose: "unrelated-purpose")
        let cachedData = try JSONEncoder.snakeCaseKeys.encode([accountInfoKey, unrelatedKey])
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = cachedData
        let scopedAccess = ScopedAccessCredentialManagingMock()
        let transientError = URLError(.notConnectedToInternet)
        scopedAccess.fetchAccessCredentialsError = transientError
        scopedAccess.fetchProtectedKeysError = transientError
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        do {
            _ = try await manager.loadKey(for: account)
            XCTFail("Expected transient key loading error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, transientError.code)
        }

        XCTAssertEqual(secureStore.theProtectedKeysData, cachedData)
        XCTAssertEqual(scopedAccess.fetchAccessCredentialsCalls.map(\.userId), [account.userId])
        XCTAssertEqual(scopedAccess.fetchProtectedKeysCalls.map(\.userId), [account.userId])
    }

    func testWhenServerHasNoAccountInfoKeyThenThrows() async throws {
        let secureStore = SecureStorageStub()
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = []
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        do {
            _ = try await manager.loadKey(for: account)
            XCTFail("Expected missing protected key error")
        } catch {
            XCTAssertEqual(error as? AccountInfoKeyManagerError, .missingProtectedKey)
        }
    }

    private func makeDefaultCredentialProtectedKey() throws -> ProtectedKey {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()
        let encryptedPrivateKey = try crypter.encrypt(keyMaterial.privateKeyPKCS8, using: account.secretKey)
        return ProtectedKey(kid: UUID().uuidString,
                            encryptedPrivateKey: Base64URL.encode(encryptedPrivateKey),
                            publicKey: keyMaterial.publicKeyJWK,
                            encryptedWith: SyncCredentialID.defaultCredential,
                            purpose: ProtectedKeyPurpose.accountInfo)
    }

    private func makeThirdPartyCredentialProtectedKey(scopedPassword: Data) throws -> ProtectedKey {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let encryptedPrivateKey = try JWECompactCodec().encryptDirect(payload: keyMaterial.privateKeyPKCS8,
                                                                      contentEncryptionKey: thirdPartyMainKey,
                                                                      kid: SyncCredentialID.thirdParty)
        return ProtectedKey(kid: UUID().uuidString,
                            encryptedPrivateKey: encryptedPrivateKey,
                            publicKey: keyMaterial.publicKeyJWK,
                            encryptedWith: SyncCredentialID.thirdParty,
                            purpose: ProtectedKeyPurpose.accountInfo)
    }
}

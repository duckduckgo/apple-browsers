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

import Foundation
import Testing

@testable import DDGSync

@Suite("Account info key manager")
struct AccountInfoKeyManagerTests {

    private let account = SyncAccount.mock
    private let crypter = CryptingMock()

    @available(iOS 16, macOS 13, *)
    @Test("A cached default-credential key loads without fetching", .timeLimit(.minutes(1)))
    func testWhenDefaultCredentialKeyIsCachedThenLoadsWithoutFetching() async throws {
        let protectedKey = try makeDefaultCredentialProtectedKey()
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([protectedKey])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        let key = try await manager.loadKey(for: account)

        #expect(key.kid == protectedKey.kid)
        #expect(scopedAccess.fetchProtectedKeysCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A corrupt cache is replaced with server keys", .timeLimit(.minutes(1)))
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

        let cachedData = try #require(secureStore.theProtectedKeysData)
        let cachedKeys = try JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: cachedData)
        #expect(key.kid == protectedKey.kid)
        #expect(scopedAccess.fetchProtectedKeysCalls.map(\.userId) == [account.userId])
        #expect(cachedKeys.map(\.kid) == [protectedKey.kid])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cached third-party wrapper loads using the scoped password", .timeLimit(.minutes(1)))
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

        #expect(key.kid == protectedKey.kid)
        #expect(scopedAccess.fetchProtectedKeysCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A stale refresh cannot remove a cached wrapper for the same key", .timeLimit(.minutes(1)))
    func testWhenRefreshReturnsFewerWrappersForMatchingKeyThenPreservesCachedWrapper() async throws {
        let scopedPassword = Data(repeating: 0x03, count: 32)
        let protectedKeys = try makeDualWrappedProtectedKeys(scopedPassword: scopedPassword)
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([
            protectedKeys.defaultCredential,
            protectedKeys.thirdParty
        ])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = [protectedKeys.defaultCredential]
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        _ = try await manager.refreshKey(for: account)

        let cachedData = try #require(secureStore.theProtectedKeysData)
        let cachedKeys = try JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: cachedData)
        #expect(Set(cachedKeys.map(\.encryptedWith)) == Set([
            SyncCredentialID.defaultCredential,
            SyncCredentialID.thirdParty
        ]))
        #expect(cachedKeys.allSatisfy { $0.kid == protectedKeys.defaultCredential.kid })
    }

    @available(iOS 16, macOS 13, *)
    @Test("A refreshed key identity replaces wrappers for the old key", .timeLimit(.minutes(1)))
    func testWhenRefreshReturnsDifferentKeyThenDoesNotPreserveCachedWrappers() async throws {
        let scopedPassword = Data(repeating: 0x03, count: 32)
        let cachedKeys = try makeDualWrappedProtectedKeys(scopedPassword: scopedPassword)
        let refreshedKey = try makeDefaultCredentialProtectedKey()
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([
            cachedKeys.defaultCredential,
            cachedKeys.thirdParty
        ])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = [refreshedKey]
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        _ = try await manager.refreshKey(for: account)

        let cachedData = try #require(secureStore.theProtectedKeysData)
        let persistedKeys = try JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: cachedData)
        #expect(persistedKeys.map(\.kid) == [refreshedKey.kid])
        #expect(persistedKeys.map(\.encryptedWith) == [SyncCredentialID.defaultCredential])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed default wrapper falls back to the third-party wrapper", .timeLimit(.minutes(1)))
    func testWhenDefaultWrapperCannotBeUnwrappedThenFallsBackToThirdPartyWrapper() async throws {
        let scopedPassword = Data(repeating: 0x03, count: 32)
        let protectedKeys = try makeDualWrappedProtectedKeys(scopedPassword: scopedPassword)
        let malformedDefaultWrapper = ProtectedKey(kid: protectedKeys.defaultCredential.kid,
                                                    encryptedPrivateKey: "%",
                                                    publicKey: protectedKeys.defaultCredential.publicKey,
                                                    encryptedWith: SyncCredentialID.defaultCredential,
                                                    purpose: ProtectedKeyPurpose.accountInfo)
        let secureStore = SecureStorageStub()
        secureStore.theScopedPassword = scopedPassword
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([
            malformedDefaultWrapper,
            protectedKeys.thirdParty
        ])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        let key = try await manager.loadKey(for: account)

        #expect(key.kid == protectedKeys.thirdParty.kid)
        #expect(scopedAccess.fetchProtectedKeysCalls.isEmpty)
        #expect(scopedAccess.fetchAccessCredentialsCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The default wrapper is preferred without recovering a scoped password", .timeLimit(.minutes(1)))
    func testWhenBothWrappersAreCachedThenPrefersDefaultWithoutRecoveringScopedPassword() async throws {
        let scopedPassword = Data(repeating: 0x03, count: 32)
        let protectedKeys = try makeDualWrappedProtectedKeys(scopedPassword: scopedPassword)
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([
            protectedKeys.thirdParty,
            protectedKeys.defaultCredential
        ])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        let key = try await manager.loadKey(for: account)

        #expect(key.kid == protectedKeys.defaultCredential.kid)
        #expect(scopedAccess.fetchProtectedKeysCalls.isEmpty)
        #expect(scopedAccess.fetchAccessCredentialsCalls.isEmpty)
        #expect(scopedAccess.recoverScopedPasswordCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A missing scoped password is recovered and cached", .timeLimit(.minutes(1)))
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

        #expect(key.kid == protectedKey.kid)
        #expect(scopedAccess.fetchAccessCredentialsCalls.map(\.userId) == [account.userId])
        #expect(scopedAccess.recoverScopedPasswordCalls.map(\.userID) == [account.userId])
        #expect(secureStore.theScopedPassword == scopedPassword)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancellation during cached-key recovery does not trigger a refresh", .timeLimit(.minutes(1)))
    func testWhenCachedKeyRecoveryIsCancelledThenDoesNotRefresh() async throws {
        let scopedPassword = Data(repeating: 0x03, count: 32)
        let protectedKey = try makeThirdPartyCredentialProtectedKey(scopedPassword: scopedPassword)
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([protectedKey])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchAccessCredentialsError = CancellationError()
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        await #expect(throws: CancellationError.self) {
            try await manager.loadKey(for: account)
        }

        #expect(scopedAccess.fetchAccessCredentialsCalls.map(\.userId) == [account.userId])
        #expect(scopedAccess.fetchProtectedKeysCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Transient refresh failures preserve the protected-key cache", .timeLimit(.minutes(1)))
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
            Issue.record("Expected transient key loading error")
        } catch {
            #expect((error as? URLError)?.code == transientError.code)
        }

        #expect(secureStore.theProtectedKeysData == cachedData)
        #expect(scopedAccess.fetchAccessCredentialsCalls.map(\.userId) == [account.userId])
        #expect(scopedAccess.fetchProtectedKeysCalls.map(\.userId) == [account.userId])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Inconsistent public keys are rejected", .timeLimit(.minutes(1)))
    func testWhenAccountInfoWrappersDescribeDifferentPublicKeysThenThrowsInvalidProtectedKeySet() async throws {
        let protectedKey = try makeDefaultCredentialProtectedKey()
        let differentPublicKey = try ScopedAccessKeyFactory.makeRSAKeyMaterial().publicKeyJWK
        let inconsistentWrapper = ProtectedKey(kid: protectedKey.kid,
                                               encryptedPrivateKey: "unused",
                                               publicKey: differentPublicKey,
                                               encryptedWith: SyncCredentialID.thirdParty,
                                               purpose: ProtectedKeyPurpose.accountInfo)

        await assertRefreshing([protectedKey, inconsistentWrapper], expectedError: .invalidProtectedKeySet)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unsupported wrappers are rejected", .timeLimit(.minutes(1)))
    func testWhenAccountInfoKeyHasUnsupportedWrapperThenThrowsUnavailableWrappingKey() async {
        let protectedKey = ProtectedKey(kid: "account-info-key",
                                        encryptedPrivateKey: "unused",
                                        publicKey: .mock,
                                        encryptedWith: "unsupported",
                                        purpose: ProtectedKeyPurpose.accountInfo)

        await assertRefreshing([protectedKey], expectedError: .unavailableWrappingKey)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Malformed default wrappers are rejected", .timeLimit(.minutes(1)))
    func testWhenDefaultWrapperIsNotBase64URLThenThrowsUnableToUnwrapPrivateKey() async {
        let protectedKey = ProtectedKey(kid: "account-info-key",
                                        encryptedPrivateKey: "%",
                                        publicKey: .mock,
                                        encryptedWith: SyncCredentialID.defaultCredential,
                                        purpose: ProtectedKeyPurpose.accountInfo)

        await assertRefreshing([protectedKey], expectedError: .unableToUnwrapPrivateKey)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A private key that does not match the public key is rejected", .timeLimit(.minutes(1)))
    func testWhenPrivateKeyDoesNotMatchPublicKeyThenThrowsPublicKeyMismatch() async throws {
        let privateKeyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()
        let publicKeyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()
        let encryptedPrivateKey = try crypter.encrypt(privateKeyMaterial.privateKeyPKCS8, using: account.secretKey)
        let protectedKey = ProtectedKey(kid: "account-info-key",
                                        encryptedPrivateKey: Base64URL.encode(encryptedPrivateKey),
                                        publicKey: publicKeyMaterial.publicKeyJWK,
                                        encryptedWith: SyncCredentialID.defaultCredential,
                                        purpose: ProtectedKeyPurpose.accountInfo)

        await assertRefreshing([protectedKey], expectedError: .publicKeyMismatch)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A missing account info key is reported", .timeLimit(.minutes(1)))
    func testWhenServerHasNoAccountInfoKeyThenThrows() async throws {
        let secureStore = SecureStorageStub()
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = []
        let manager = AccountInfoKeyManager(secureStore: secureStore,
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        do {
            _ = try await manager.loadKey(for: account)
            Issue.record("Expected missing protected key error")
        } catch {
            #expect((error as? AccountInfoKeyManagerError) == .missingProtectedKey)
        }
    }

    private func assertRefreshing(_ protectedKeys: [ProtectedKey],
                                  expectedError: AccountInfoKeyManagerError,
                                  sourceLocation: SourceLocation = SourceLocation(fileID: #fileID,
                                                                                 filePath: #filePath,
                                                                                 line: #line,
                                                                                 column: #column)) async {
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = protectedKeys
        let manager = AccountInfoKeyManager(secureStore: SecureStorageStub(),
                                            scopedAccess: scopedAccess,
                                            crypter: crypter)

        do {
            _ = try await manager.refreshKey(for: account)
            Issue.record("Expected key refresh to fail", sourceLocation: sourceLocation)
        } catch {
            #expect((error as? AccountInfoKeyManagerError) == expectedError, sourceLocation: sourceLocation)
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

    private func makeDualWrappedProtectedKeys(scopedPassword: Data) throws -> (defaultCredential: ProtectedKey, thirdParty: ProtectedKey) {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()
        let kid = UUID().uuidString
        let encryptedDefaultPrivateKey = try crypter.encrypt(keyMaterial.privateKeyPKCS8, using: account.secretKey)
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let encryptedThirdPartyPrivateKey = try JWECompactCodec().encryptDirect(payload: keyMaterial.privateKeyPKCS8,
                                                                                contentEncryptionKey: thirdPartyMainKey,
                                                                                kid: SyncCredentialID.thirdParty)
        return (
            defaultCredential: ProtectedKey(kid: kid,
                                            encryptedPrivateKey: Base64URL.encode(encryptedDefaultPrivateKey),
                                            publicKey: keyMaterial.publicKeyJWK,
                                            encryptedWith: SyncCredentialID.defaultCredential,
                                            purpose: ProtectedKeyPurpose.accountInfo),
            thirdParty: ProtectedKey(kid: kid,
                                     encryptedPrivateKey: encryptedThirdPartyPrivateKey,
                                     publicKey: keyMaterial.publicKeyJWK,
                                     encryptedWith: SyncCredentialID.thirdParty,
                                     purpose: ProtectedKeyPurpose.accountInfo))
    }
}

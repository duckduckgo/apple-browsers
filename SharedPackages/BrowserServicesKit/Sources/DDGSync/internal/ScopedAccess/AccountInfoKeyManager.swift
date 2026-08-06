//
//  AccountInfoKeyManager.swift
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
import os.log
import Security

struct AccountInfoKey: @unchecked Sendable {
    let kid: String
    let publicKey: SecKey
    let privateKey: SecKey
}

enum AccountInfoKeyManagerError: Error, Equatable {
    case missingProtectedKey
    case invalidProtectedKeySet
    case unavailableWrappingKey
    case unableToUnwrapPrivateKey
    case publicKeyMismatch
}

protocol AccountInfoKeyManaging {
    func loadKey(for account: SyncAccount) async throws -> AccountInfoKey
    func refreshKey(for account: SyncAccount) async throws -> AccountInfoKey
}

actor AccountInfoKeyManager: AccountInfoKeyManaging {

    private let secureStore: SecureStoring
    private let scopedAccess: ScopedAccessCredentialManaging
    private let crypter: CryptingInternal
    private let jweCompactCodec: JWECompactCodec

    init(secureStore: SecureStoring,
         scopedAccess: ScopedAccessCredentialManaging,
         crypter: CryptingInternal,
         jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.secureStore = secureStore
        self.scopedAccess = scopedAccess
        self.crypter = crypter
        self.jweCompactCodec = jweCompactCodec
    }

    func loadKey(for account: SyncAccount) async throws -> AccountInfoKey {
        if let protectedKeys = cachedProtectedKeys() {
            do {
                let key = try await makeAccountInfoKey(from: protectedKeys, account: account)
                Logger.sync.debug("Sync-UnifiedDevices: loaded account_info key from secure storage")
                return key
            } catch {
                // Preserve structurally valid cached keys until an authoritative refresh succeeds.
            }
        }
        return try await refreshKey(for: account)
    }

    func refreshKey(for account: SyncAccount) async throws -> AccountInfoKey {
        Logger.sync.debug("Sync-UnifiedDevices: fetching account_info key from server")
        let protectedKeys = try await scopedAccess.fetchProtectedKeys(account)
            .removingDuplicateWrappingIdentities()
        let key = try await makeAccountInfoKey(from: protectedKeys, account: account)
        cache(protectedKeys)
        return key
    }

    private func cachedProtectedKeys() -> [ProtectedKey]? {
        guard let data = try? secureStore.protectedKeys() else {
            return nil
        }
        guard let protectedKeys = try? JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: data) else {
            try? secureStore.removeProtectedKeys()
            return nil
        }
        return protectedKeys.removingDuplicateWrappingIdentities()
    }

    private func cache(_ protectedKeys: [ProtectedKey]) {
        guard let encodedKeys = try? JSONEncoder.snakeCaseKeys.encode(protectedKeys) else {
            return
        }
        try? secureStore.persistProtectedKeys(encodedKeys)
    }

    private func makeAccountInfoKey(from protectedKeys: [ProtectedKey],
                                    account: SyncAccount) async throws -> AccountInfoKey {
        let accountInfoKeys = protectedKeys.filter { $0.purpose == ProtectedKeyPurpose.accountInfo }
        guard let firstKey = accountInfoKeys.first else {
            throw AccountInfoKeyManagerError.missingProtectedKey
        }
        guard !firstKey.kid.isEmpty,
              accountInfoKeys.allSatisfy({ $0.kid == firstKey.kid && $0.publicKey == firstKey.publicKey }) else {
            throw AccountInfoKeyManagerError.invalidProtectedKeySet
        }

        let defaultCredentialKeys = accountInfoKeys.filter { $0.encryptedWith == SyncCredentialID.defaultCredential }
        let otherKeys = accountInfoKeys.filter { $0.encryptedWith != SyncCredentialID.defaultCredential }
        let orderedKeys = defaultCredentialKeys + otherKeys
        var hasSupportedWrapper = false
        var lastError: Error?
        for protectedKey in orderedKeys {
            guard [SyncCredentialID.defaultCredential, SyncCredentialID.thirdParty].contains(protectedKey.encryptedWith) else {
                continue
            }
            hasSupportedWrapper = true
            do {
                let privateKeyPKCS8 = try await unwrapPrivateKey(protectedKey, account: account)
                let key = try makeAccountInfoKey(protectedKey: protectedKey, privateKeyPKCS8: privateKeyPKCS8)
                if protectedKey.encryptedWith == SyncCredentialID.defaultCredential {
                    Logger.sync.debug("Sync-UnifiedDevices: unwrapped account_info key with ddg credential")
                } else {
                    Logger.sync.debug("Sync-UnifiedDevices: unwrapped account_info key with 3party credential")
                }
                return key
            } catch {
                lastError = error
            }
        }

        guard hasSupportedWrapper else {
            throw AccountInfoKeyManagerError.unavailableWrappingKey
        }
        if let lastError {
            throw lastError
        }
        throw AccountInfoKeyManagerError.unableToUnwrapPrivateKey
    }

    private func unwrapPrivateKey(_ protectedKey: ProtectedKey, account: SyncAccount) async throws -> Data {
        switch protectedKey.encryptedWith {
        case SyncCredentialID.defaultCredential:
            guard let encryptedPrivateKey = Base64URL.decode(protectedKey.encryptedPrivateKey) else {
                throw AccountInfoKeyManagerError.unableToUnwrapPrivateKey
            }
            return try crypter.decryptData(encryptedPrivateKey, using: account.secretKey)
        case SyncCredentialID.thirdParty:
            let scopedPassword = try await scopedPassword(for: account)
            let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
            return try jweCompactCodec.decryptDirect(token: protectedKey.encryptedPrivateKey,
                                                     contentEncryptionKey: thirdPartyMainKey,
                                                     expectedKid: SyncCredentialID.thirdParty)
        default:
            throw AccountInfoKeyManagerError.unavailableWrappingKey
        }
    }

    private func scopedPassword(for account: SyncAccount) async throws -> Data {
        if let scopedPassword = try secureStore.scopedPassword(), !scopedPassword.isEmpty {
            return scopedPassword
        }

        let accessCredentials = try await scopedAccess.fetchAccessCredentials(account)
        guard let scopedPassword = try scopedAccess.recoverScopedPassword(from: accessCredentials,
                                                                          primaryKey: account.primaryKey,
                                                                          userID: account.userId),
              !scopedPassword.isEmpty else {
            throw AccountInfoKeyManagerError.unavailableWrappingKey
        }
        try? secureStore.persistScopedPassword(scopedPassword)
        return scopedPassword
    }

    private func makeAccountInfoKey(protectedKey: ProtectedKey,
                                    privateKeyPKCS8: Data) throws -> AccountInfoKey {
        let publicKey = try RSAKeyImporter.makePublicKey(from: protectedKey.publicKey)
        let privateKey = try RSAKeyImporter.makePrivateKey(fromPKCS8: privateKeyPKCS8)
        guard let derivedPublicKey = SecKeyCopyPublicKey(privateKey),
              let expectedPublicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let derivedPublicKeyData = SecKeyCopyExternalRepresentation(derivedPublicKey, nil) as Data?,
              expectedPublicKeyData == derivedPublicKeyData else {
            throw AccountInfoKeyManagerError.publicKeyMismatch
        }
        return AccountInfoKey(kid: protectedKey.kid,
                              publicKey: publicKey,
                              privateKey: privateKey)
    }
}

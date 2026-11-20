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

struct AuditLogKeyMaterial: Sendable {
    let key: AccountInfoKey
    let passwordRecovery: ThirdPartyPasswordRecoveryState
}

enum AccountInfoKeyManagerError: Error, Equatable {
    case missingProtectedKey
    case invalidProtectedKeySet
    case unavailableWrappingKey
    case unableToUnwrapPrivateKey
    case publicKeyMismatch
}

protocol AccountInfoKeyProviding {
    func loadKey(for account: SyncAccount) async throws -> AccountInfoKey
    func refreshKey(for account: SyncAccount) async throws -> AccountInfoKey
}

protocol AccountInfoKeyManaging: AccountInfoKeyProviding {
    func loadKeyForAuditLog(for account: SyncAccount) async throws -> AuditLogKeyMaterial
    func preloadKey(from protectedKeys: [ProtectedKey], accessCredentials: [AccessCredential], for account: SyncAccount) async throws
    func clearCachedKey(for account: SyncAccount) async
}

actor AccountInfoKeyManager: AccountInfoKeyManaging {

    private struct AccountIdentity: Equatable {
        let userID: String
        let secretKey: Data

        init(account: SyncAccount) {
            userID = account.userId
            secretKey = account.secretKey
        }
    }

    private struct CachedAccountInfoKey {
        let accountIdentity: AccountIdentity
        let key: AccountInfoKey
    }

    private let secureStore: SecureStoring
    private let scopedAccess: ScopedAccessCredentialManaging
    private let crypter: CryptingInternal
    private let jweCompactCodec: JWECompactCodec
    private var cachedAccountInfoKey: CachedAccountInfoKey?

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
        let accountIdentity = AccountIdentity(account: account)
        if let cachedAccountInfoKey,
           cachedAccountInfoKey.accountIdentity == accountIdentity {
            return cachedAccountInfoKey.key
        }
        cachedAccountInfoKey = nil

        if let protectedKeys = cachedProtectedKeys() {
            do {
                let key = try await loadAccountInfoKey(from: protectedKeys, account: account)
                cache(key, for: accountIdentity)
                Logger.sync.debug("Sync-UnifiedDevices: loaded account_info key from secure storage")
                return key
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                // Preserve structurally valid cached keys until an authoritative refresh succeeds.
            }
        }
        return try await refreshKey(for: account)
    }

    /// Audit requests use fetched keys in memory without updating normal Sync's caches.
    func loadKeyForAuditLog(for account: SyncAccount) async throws -> AuditLogKeyMaterial {
        try Task.checkCancellation()
        var passwordRecovery = ThirdPartyPasswordRecoveryState.notAttempted
        if let data = try secureStore.protectedKeys(),
           let protectedKeys = try? JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: data),
           let keys = try? validatedAccountInfoKeys(from: protectedKeys.removingDuplicateWrappingIdentities()),
           let key = try await loadAuditLogKey(from: keys, account: account, passwordRecovery: &passwordRecovery) {
            return AuditLogKeyMaterial(key: key, passwordRecovery: passwordRecovery)
        }
        try Task.checkCancellation()
        let protectedKeys = try await scopedAccess.fetchProtectedKeys(account).removingDuplicateWrappingIdentities()
        try Task.checkCancellation()
        let keys = try validatedAccountInfoKeys(from: protectedKeys)
        guard !keys.isEmpty else { throw AccountInfoKeyManagerError.unavailableWrappingKey }
        guard let key = try await loadAuditLogKey(from: keys, account: account, passwordRecovery: &passwordRecovery) else {
            throw AccountInfoKeyManagerError.unableToUnwrapPrivateKey
        }
        return AuditLogKeyMaterial(key: key, passwordRecovery: passwordRecovery)
    }

    private func loadAuditLogKey(from keys: [ProtectedKey],
                                 account: SyncAccount,
                                 passwordRecovery: inout ThirdPartyPasswordRecoveryState) async throws -> AccountInfoKey? {
        let defaultCredentialKeys = keys.filter { $0.encryptedWith == SyncCredentialID.defaultCredential }
        if let key = decryptAccountInfoKey(from: defaultCredentialKeys, account: account) { return key }
        let thirdPartyKeys = keys.filter { $0.encryptedWith == SyncCredentialID.thirdParty }
        guard !thirdPartyKeys.isEmpty else { return nil }
        if let password = try secureStore.scopedPassword(), !password.isEmpty,
           let key = decryptAccountInfoKey(from: thirdPartyKeys, account: account, scopedPassword: password) {
            return key
        }
        try Task.checkCancellation()
        let password: Data?
        switch passwordRecovery {
        case .completed(let recoveredPassword):
            password = recoveredPassword
        case .notAttempted:
            let credentials = try await scopedAccess.fetchAccessCredentials(account)
            try Task.checkCancellation()
            let recoveredPassword = try? scopedAccess.recoverScopedPassword(from: credentials, primaryKey: account.primaryKey, userID: account.userId)
            password = recoveredPassword.flatMap { $0.isEmpty ? nil : $0 }
            passwordRecovery = .completed(password)
        }
        guard let password else {
            return nil
        }
        return decryptAccountInfoKey(from: thirdPartyKeys, account: account, scopedPassword: password)
    }

    private func decryptAccountInfoKey(from keys: [ProtectedKey], account: SyncAccount, scopedPassword: Data? = nil) -> AccountInfoKey? {
        for protectedKey in keys {
            if let key = try? decryptAccountInfoKey(protectedKey, account: account, scopedPassword: scopedPassword) {
                return key
            }
        }
        return nil
    }

    func preloadKey(from protectedKeys: [ProtectedKey], accessCredentials: [AccessCredential], for account: SyncAccount) async throws {
        let key = try await loadAccountInfoKey(
            from: protectedKeys.removingDuplicateWrappingIdentities(),
            account: account,
            providedAccessCredentials: accessCredentials)
        cache(key, for: AccountIdentity(account: account))
        Logger.sync.debug("Sync-UnifiedDevices: loaded account_info key from login response")
    }

    func refreshKey(for account: SyncAccount) async throws -> AccountInfoKey {
        Logger.sync.debug("Sync-UnifiedDevices: fetching account_info key from server")
        let protectedKeys = try await scopedAccess.fetchProtectedKeys(account)
            .removingDuplicateWrappingIdentities()
        let key = try await loadAccountInfoKey(from: protectedKeys, account: account)
        cache(protectedKeys)
        cache(key, for: AccountIdentity(account: account))
        return key
    }

    func clearCachedKey(for account: SyncAccount) {
        guard cachedAccountInfoKey?.accountIdentity == AccountIdentity(account: account) else {
            return
        }
        cachedAccountInfoKey = nil
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
        let protectedKeysToCache = protectedKeys.preservingCachedWrappersForMatchingKeys(cachedProtectedKeys() ?? [])
        guard let encodedKeys = try? JSONEncoder.snakeCaseKeys.encode(protectedKeysToCache) else {
            return
        }
        try? secureStore.persistProtectedKeys(encodedKeys)
    }

    private func cache(_ key: AccountInfoKey, for accountIdentity: AccountIdentity) {
        cachedAccountInfoKey = CachedAccountInfoKey(accountIdentity: accountIdentity, key: key)
    }

    private func loadAccountInfoKey(from protectedKeys: [ProtectedKey],
                                    account: SyncAccount,
                                    providedAccessCredentials: [AccessCredential]? = nil) async throws -> AccountInfoKey {
        let accountInfoKeys = try validatedAccountInfoKeys(from: protectedKeys)

        guard !accountInfoKeys.isEmpty else {
            throw AccountInfoKeyManagerError.unavailableWrappingKey
        }
        var lastError: Error?
        for protectedKey in accountInfoKeys {
            do {
                let password: Data?
                if protectedKey.encryptedWith == SyncCredentialID.thirdParty {
                    password = try await loadScopedPassword(for: account, providedAccessCredentials: providedAccessCredentials)
                } else {
                    password = nil
                }
                let key = try decryptAccountInfoKey(protectedKey, account: account, scopedPassword: password)
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

        if let lastError {
            throw lastError
        }
        throw AccountInfoKeyManagerError.unableToUnwrapPrivateKey
    }

    private func validatedAccountInfoKeys(from protectedKeys: [ProtectedKey]) throws -> [ProtectedKey] {
        let accountInfoKeys = protectedKeys.filter { $0.purpose == ProtectedKeyPurpose.accountInfo }
        guard let firstKey = accountInfoKeys.first else {
            throw AccountInfoKeyManagerError.missingProtectedKey
        }
        guard !firstKey.kid.isEmpty,
              accountInfoKeys.allSatisfy({ $0.kid == firstKey.kid && $0.publicKey == firstKey.publicKey }) else {
            throw AccountInfoKeyManagerError.invalidProtectedKeySet
        }

        let defaultCredentialKeys = accountInfoKeys.filter { $0.encryptedWith == SyncCredentialID.defaultCredential }
        let thirdPartyKeys = accountInfoKeys.filter { $0.encryptedWith == SyncCredentialID.thirdParty }
        return defaultCredentialKeys + thirdPartyKeys
    }

    private func decryptAccountInfoKey(_ protectedKey: ProtectedKey,
                                       account: SyncAccount,
                                       scopedPassword: Data?) throws -> AccountInfoKey {
        let privateKeyPKCS8: Data
        switch protectedKey.encryptedWith {
        case SyncCredentialID.defaultCredential:
            guard let encryptedPrivateKey = Base64URL.decode(protectedKey.encryptedPrivateKey) else {
                throw AccountInfoKeyManagerError.unableToUnwrapPrivateKey
            }
            privateKeyPKCS8 = try crypter.decryptData(encryptedPrivateKey, using: account.secretKey)
        case SyncCredentialID.thirdParty:
            guard let scopedPassword else {
                throw AccountInfoKeyManagerError.unavailableWrappingKey
            }
            let mainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
            privateKeyPKCS8 = try jweCompactCodec.decryptDirect(token: protectedKey.encryptedPrivateKey,
                                                               contentEncryptionKey: mainKey,
                                                               expectedKid: SyncCredentialID.thirdParty)
        default:
            throw AccountInfoKeyManagerError.unavailableWrappingKey
        }
        return try makeAccountInfoKey(protectedKey: protectedKey, privateKeyPKCS8: privateKeyPKCS8)
    }

    private func loadScopedPassword(for account: SyncAccount,
                                    providedAccessCredentials: [AccessCredential]?) async throws -> Data {
        if let providedAccessCredentials {
            guard let scopedPassword = try scopedAccess.recoverScopedPassword(from: providedAccessCredentials,
                                                                              primaryKey: account.primaryKey,
                                                                              userID: account.userId),
                  !scopedPassword.isEmpty else {
                throw AccountInfoKeyManagerError.unavailableWrappingKey
            }
            return scopedPassword
        }

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

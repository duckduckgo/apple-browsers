//
//  ScopedAccessCredentialManager.swift
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

import CryptoKit
import Foundation

/// Creates and recovers the scoped ("3party") access credential and its protected keys that let a limited client share a sync account.
struct ScopedAccessCredentialManager: ScopedAccessCredentialManaging {

    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    let crypter: CryptingInternal
    private let jweCompactCodec = JWECompactCodec()
    private let scopedAccessCredentialEnvelope = ScopedAccessCredentialEnvelope()

    func recoverScopedPassword(from accessCredentials: [AccessCredential]?, primaryKey: Data, userID: String) throws -> Data? {
        guard let thirdPartyCredential = accessCredentials?.first(where: { $0.id == SyncCode.RecoveryKeyV2.thirdPartyCredentialId }) else {
            return nil
        }
        guard let encryptedCredential = thirdPartyCredential.encrypted3PartyCredential, !encryptedCredential.isEmpty else {
            throw SyncError.invalidDataInResponse("3P access credential missing encrypted_3party_credential")
        }
        let defaultCredentialMainKey = ScopedAccessKeyDerivation.mainKey(from: primaryKey, userID: userID)
        return try scopedAccessCredentialEnvelope.decryptScopedPassword(from: encryptedCredential, using: defaultCredentialMainKey)
    }

    func ensureThirdPartyScopedPassword(for account: SyncAccount,
                                        purpose: String,
                                        cachedScopedPassword: () throws -> Data?) async throws -> EnsuredThirdPartyCredential {
        let accessCredentials = try await fetchAccessCredentials(account)
        if let scopedPassword = try recoverScopedPassword(from: accessCredentials, primaryKey: account.primaryKey, userID: account.userId) {
            return EnsuredThirdPartyCredential(scopedPassword: scopedPassword, protectedKeysToCache: [])
        }

        let scopedPassword = try scopedPasswordForNewThirdPartyCredential(cachedScopedPassword: cachedScopedPassword)
        let keyPreparation = try await protectedKeysForThirdPartyCredential(purpose: purpose,
                                                                            account: account)
        let ensuredScopedPassword = try await ensureThirdPartyAccessCredential(for: account,
                                                                              scopedPassword: scopedPassword,
                                                                              keys: keyPreparation.protectedKeys,
                                                                              shouldUploadDefaultCredentialKeys: keyPreparation.shouldUploadDefaultCredentialKeys)
        return EnsuredThirdPartyCredential(scopedPassword: ensuredScopedPassword,
                                           protectedKeysToCache: keyPreparation.protectedKeysToCache)
    }

    func makeRecoveryCode(for account: SyncAccount, scopedPassword: Data) -> String? {
        guard !scopedPassword.isEmpty else {
            return nil
        }
        let payload = SyncCode.RecoveryKeyV2(
            userId: account.userId,
            secret: Base64URL.encode(scopedPassword),
            cid: SyncCode.RecoveryKeyV2.thirdPartyCredentialId,
            v: SyncCode.RecoveryKeyV2.currentVersion
        )
        do {
            let json = try SyncCode(recovery: .v2(payload)).toJSON()
            return Base64URL.encode(json)
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }

    private func ensureThirdPartyAccessCredential(for account: SyncAccount,
                                                  scopedPassword: Data,
                                                  keys protectedKeys: [ProtectedKey],
                                                  shouldUploadDefaultCredentialKeys: Bool) async throws -> Data {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let existingCredentialInfo = try crypter.extractLoginInfo(recoveryKey: SyncCode.RecoveryKey(userId: account.userId, primaryKey: account.primaryKey))
        let hashedPassword = existingCredentialInfo.passwordHash.base64EncodedString()
        let credentialHashedPassword = ScopedAccessKeyDerivation.hashedPassword(from: scopedPassword, userID: account.userId)
        let defaultCredentialMainKey = ScopedAccessKeyDerivation.mainKey(from: account.primaryKey, userID: account.userId)
        let encryptedThirdPartyCredentialToken = try scopedAccessCredentialEnvelope.encryptScopedPassword(scopedPassword,
                                                                                                          using: defaultCredentialMainKey,
                                                                                                          kid: SyncCredentialID.defaultCredential)

        let createCredentialKeys = try accessCredentialProtectedKeys(from: protectedKeys,
                                                                     scopedPassword: scopedPassword,
                                                                     account: account,
                                                                     shouldUploadDefaultCredentialKeys: shouldUploadDefaultCredentialKeys)
            .removingDuplicateWrappingIdentities()

        do {
            try await postThirdPartyAccessCredential(token: token,
                                                     hashedPassword: hashedPassword,
                                                     credentialHashedPassword: credentialHashedPassword,
                                                     encryptedThirdPartyCredential: encryptedThirdPartyCredentialToken,
                                                     keys: createCredentialKeys)
        } catch SyncError.unexpectedStatusCode(let statusCode) where statusCode == 409 {
            let accessCredentials = try await fetchAccessCredentials(account)
            if let scopedPassword = try recoverScopedPassword(from: accessCredentials, primaryKey: account.primaryKey, userID: account.userId) {
                return scopedPassword
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
        return scopedPassword
    }

    func fetchAccessCredentials(_ account: SyncAccount) async throws -> [AccessCredential] {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let request = api.createAuthenticatedGetRequest(url: endpoints.accessCredentials, authToken: token)
        do {
            let result = try await request.execute()
            guard let body = result.data else {
                throw SyncError.noResponseBody
            }
            return try decodeAccessCredentials(from: body)
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 404 {
                return []
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    func fetchProtectedKeys(_ account: SyncAccount) async throws -> [ProtectedKey] {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let request = api.createAuthenticatedGetRequest(url: endpoints.keys, authToken: token)
        do {
            let result = try await request.execute()
            guard let body = result.data else {
                throw SyncError.noResponseBody
            }
            return try decodeProtectedKeys(from: body)
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 404 {
                return []
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    func setKeyIfAbsent(purpose: String, key: ProtectedKey, for account: SyncAccount) async throws -> ProtectedKey? {
        try await setKeysIfAbsent(purpose: purpose, keys: [key], for: account)
            .first
    }

    private func setKeysIfAbsent(purpose: String, keys: [ProtectedKey], for account: SyncAccount) async throws -> [ProtectedKey] {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let deduplicatedKeys = keys.removingDuplicateWrappingIdentities()
        let params = SetKeyIfAbsentParameters(keys: deduplicatedKeys)
        let requestJSON = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createAuthenticatedJSONRequest(url: setKeyIfAbsentURL(purpose: purpose), method: .post, authToken: token, json: requestJSON)
        do {
            let result = try await request.execute()
            guard result.response.statusCode == 201 else {
                throw SyncError.unexpectedStatusCode(result.response.statusCode)
            }
            guard let body = result.data, !body.isEmpty else {
                return deduplicatedKeys
            }
            return try decodeProtectedKeys(from: body, expectedKeys: deduplicatedKeys)
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 409 {
                return try await reconcileConflictingProtectedKeys(purpose: purpose, expectedKeys: deduplicatedKeys, account: account)
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    private func protectedKeysForThirdPartyCredential(purpose: String,
                                                      account: SyncAccount) async throws -> ProtectedKeysForThirdPartyCredential {
        let fetchedProtectedKeys = try await fetchProtectedKeys(account)
        let fetchedDefaultCredentialKeys = defaultCredentialKeys(in: fetchedProtectedKeys)
        if fetchedDefaultCredentialKeys.contains(where: { $0.purpose == purpose }) {
            return ProtectedKeysForThirdPartyCredential(protectedKeys: protectedKeys(for: purpose, in: fetchedProtectedKeys),
                                                        shouldUploadDefaultCredentialKeys: false,
                                                        protectedKeysToCache: fetchedProtectedKeys)
        }

        let protectedKey = try makeDefaultCredentialProtectedKey(purpose: purpose, account: account)
        return ProtectedKeysForThirdPartyCredential(protectedKeys: [protectedKey],
                                                    shouldUploadDefaultCredentialKeys: true,
                                                    protectedKeysToCache: fetchedProtectedKeys + [protectedKey])
    }

    private func defaultCredentialKeys(in keys: [ProtectedKey]) -> [ProtectedKey] {
        keys
            .filter { $0.encryptedWith == SyncCredentialID.defaultCredential }
            .removingDuplicateWrappingIdentities()
    }

    private func protectedKeys(for purpose: String, in keys: [ProtectedKey]) -> [ProtectedKey] {
        keys
            .filter { $0.purpose == purpose }
            .removingDuplicateWrappingIdentities()
    }

    private func makeDefaultCredentialProtectedKey(purpose: String, account: SyncAccount) throws -> ProtectedKey {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()
        let encryptedPrivateKeyBytes = try crypter.encrypt(keyMaterial.privateKeyPKCS8, using: account.secretKey)
        return ProtectedKey(
            kid: UUID().uuidString,
            encryptedPrivateKey: Base64URL.encode(encryptedPrivateKeyBytes),
            publicKey: keyMaterial.publicKeyJWK,
            encryptedWith: SyncCredentialID.defaultCredential,
            purpose: purpose
        )
    }

    private func scopedPasswordForNewThirdPartyCredential(cachedScopedPassword: () throws -> Data?) throws -> Data {
        if let scopedPassword = try cachedScopedPassword(), !scopedPassword.isEmpty {
            return scopedPassword
        }

        return try ScopedAccessKeyFactory.makeScopedPassword()
    }

    private func postThirdPartyAccessCredential(token: String,
                                                hashedPassword: String,
                                                credentialHashedPassword: String,
                                                encryptedThirdPartyCredential: String,
                                                keys: [ProtectedKey]) async throws {
        let params = CreateThirdPartyCredentialParameters(
            hashedPassword: hashedPassword,
            credentialHashedPassword: credentialHashedPassword,
            encrypted3partyCredential: encryptedThirdPartyCredential,
            keys: keys
        )
        let requestJson = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createAuthenticatedJSONRequest(url: accessCredentialURL(id: SyncCode.RecoveryKeyV2.thirdPartyCredentialId),
                                                         method: .post,
                                                         authToken: token,
                                                         json: requestJson)
        let result = try await request.execute()
        guard result.response.statusCode == 201 else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }
    }

    private func decodeAccessCredentials(from data: Data) throws -> [AccessCredential] {
        let wrappedResult = try JSONDecoder.snakeCaseKeys.decode(FetchAccessCredentialsResult.self, from: data)
        guard let accessCredentials = wrappedResult.accessCredentials else {
            throw SyncError.unableToDecodeResponse("Failed to decode access credentials")
        }
        return accessCredentials
    }

    private func decodeProtectedKeys(from data: Data) throws -> [ProtectedKey] {
        let wrappedResult = try JSONDecoder.snakeCaseKeys.decode(FetchProtectedKeysResult.self, from: data)
        guard let keys = wrappedResult.keys else {
            throw SyncError.unableToDecodeResponse("Failed to decode protected keys")
        }
        return keys
    }

    private func reconcileConflictingProtectedKeys(purpose: String, expectedKeys: [ProtectedKey], account: SyncAccount) async throws -> [ProtectedKey] {
        let keys = try await fetchProtectedKeys(account)
        let matchingKeys = selectBestMatchingKeys(in: keys, expectedKeys: expectedKeys)
        if matchingKeys.count == expectedKeys.count {
            return matchingKeys
        }
        throw SyncError.invalidDataInResponse("set-if-absent returned 409 for purpose=\(purpose), but no matching keys were found after refetch")
    }

    private func decodeProtectedKeys(from data: Data, expectedKeys: [ProtectedKey]) throws -> [ProtectedKey] {
        let result = try JSONDecoder.snakeCaseKeys.decode(SetKeyIfAbsentResult.self, from: data)
        guard let keys = result.keys else {
            throw SyncError.unableToDecodeResponse("Failed to decode protected keys")
        }
        return selectBestMatchingKeys(in: keys, expectedKeys: expectedKeys)
    }

    private func accessCredentialURL(id: String) -> URL {
        endpoints.accessCredentials.appendingPathComponent(id)
    }

    private func setKeyIfAbsentURL(purpose: String) -> URL {
        endpoints.keys
            .appendingPathComponent("purpose")
            .appendingPathComponent(purpose)
            .appendingPathComponent("set-if-absent")
    }

    private func selectBestMatchingKeys(in keys: [ProtectedKey],
                                        expectedKeys: [ProtectedKey]) -> [ProtectedKey] {
        expectedKeys.compactMap { expectedKey in
            keys.first(where: { $0.hasSameWrappingIdentity(as: expectedKey) })
        }
    }

    private func accessCredentialProtectedKeys(from protectedKeys: [ProtectedKey],
                                               scopedPassword: Data,
                                               account: SyncAccount,
                                               shouldUploadDefaultCredentialKeys: Bool) throws -> [ProtectedKey] {
        let existingThirdPartyKeys = protectedKeys
            .filter { $0.encryptedWith == SyncCode.RecoveryKeyV2.thirdPartyCredentialId }
            .removingDuplicateWrappingIdentities()
        let defaultCredentialKeysToRewrap = protectedKeys
            .filter { key in
                key.encryptedWith == SyncCredentialID.defaultCredential
                && !existingThirdPartyKeys.contains { thirdPartyKey in
                    thirdPartyKey.kid == key.kid && thirdPartyKey.purpose == key.purpose
                }
            }
        let defaultCredentialKeysToUpload = shouldUploadDefaultCredentialKeys ? defaultCredentialKeysToRewrap : []
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let thirdPartyCredentialKeys = try rewrapProtectedKeys(defaultCredentialKeysToRewrap,
                                                               toWrappingKey: thirdPartyMainKey,
                                                               accountSecretKey: account.secretKey)
        return defaultCredentialKeysToUpload + thirdPartyCredentialKeys + existingThirdPartyKeys
    }

    private func rewrapProtectedKeys(_ keys: [ProtectedKey],
                                     toWrappingKey: Data,
                                     accountSecretKey: Data) throws -> [ProtectedKey] {
        let keysToRewrap = keys
            .filter { $0.encryptedWith == SyncCredentialID.defaultCredential }
            .removingDuplicateWrappingIdentities()
        return try keysToRewrap.map { key in
            let decryptedPrivateKey = try decryptDefaultCredentialPrivateKeyForRewrap(
                key,
                accountSecretKey: accountSecretKey
            )
            let rewrappedEncryptedPrivateKey = try jweCompactCodec.encryptDirect(payload: decryptedPrivateKey,
                                                                                 contentEncryptionKey: toWrappingKey,
                                                                                 kid: SyncCode.RecoveryKeyV2.thirdPartyCredentialId)
            return ProtectedKey(kid: key.kid,
                                encryptedPrivateKey: rewrappedEncryptedPrivateKey,
                                publicKey: key.publicKey,
                                encryptedWith: SyncCode.RecoveryKeyV2.thirdPartyCredentialId,
                                purpose: key.purpose)
        }
    }

    private func decryptDefaultCredentialPrivateKeyForRewrap(_ key: ProtectedKey,
                                                             accountSecretKey: Data) throws -> Data {
        guard let encryptedPrivateKeyBytes = Base64URL.decode(key.encryptedPrivateKey) else {
            throw SyncError.invalidDataInResponse("ddg protected key has invalid encrypted_private_key encoding")
        }

        return try crypter.decryptData(encryptedPrivateKeyBytes, using: accountSecretKey)
    }

    struct FetchProtectedKeysResult: Decodable {
        let keys: [ProtectedKey]?
    }

    struct FetchAccessCredentialsResult: Decodable {
        let accessCredentials: [AccessCredential]?
    }

    struct CreateThirdPartyCredentialParameters: Encodable {
        let hashedPassword: String
        let credentialHashedPassword: String
        let encrypted3partyCredential: String
        let keys: [ProtectedKey]

        enum CodingKeys: String, CodingKey {
            case hashedPassword = "hashed_password"
            case credentialHashedPassword = "credential_hashed_password"
            case encrypted3partyCredential = "encrypted_3party_credential"
            case keys
        }
    }

    struct SetKeyIfAbsentParameters: Encodable {
        let keys: [ProtectedKey]
    }

    struct SetKeyIfAbsentResult: Decodable {
        let keys: [ProtectedKey]?
    }

    private struct ProtectedKeysForThirdPartyCredential {
        let protectedKeys: [ProtectedKey]
        let shouldUploadDefaultCredentialKeys: Bool
        let protectedKeysToCache: [ProtectedKey]
    }

}

struct EnsuredThirdPartyCredential {
    let scopedPassword: Data
    let protectedKeysToCache: [ProtectedKey]
}

/// Derives the scoped credential's hashed password and main key from a secret via HKDF-SHA256, salted by user ID.
enum ScopedAccessKeyDerivation {

    /// HKDF `info` label distinguishing the password-hash derivation.
    private static let passwordInfo = "Password"
    /// HKDF `info` label distinguishing the main-key derivation.
    private static let mainKeyInfo = "Main Key"

    static func hashedPassword(from secret: Data, userID: String) -> String {
        Base64URL.encode(derive(input: secret, salt: userID, info: passwordInfo))
    }

    static func mainKey(from secret: Data, userID: String) -> Data {
        derive(input: secret, salt: userID, info: mainKeyInfo)
    }

    private static func derive(input: Data, salt: String, info: String, length: Int = 32) -> Data {
        let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: input),
                                                salt: Data(salt.utf8),
                                                info: Data(info.utf8),
                                                outputByteCount: length)
        return derivedKey.withUnsafeBytes { Data($0) }
    }
}

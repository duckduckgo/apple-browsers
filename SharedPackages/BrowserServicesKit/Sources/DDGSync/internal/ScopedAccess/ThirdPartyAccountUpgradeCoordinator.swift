//
//  ThirdPartyAccountUpgradeCoordinator.swift
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

import DDGSyncCrypto
import Foundation
import os.log

/// Promotes a third-party (scoped) account into a full native ("default credential") account during pairing.
protocol ThirdPartyAccountUpgradeCoordinating {
    func upgradeThirdPartyAccountToDefaultCredential(_ recoveryCode: String, deviceName: String, deviceType: String) async throws -> UpgradedThirdPartyAccount
}

struct UpgradedThirdPartyAccount {
    let account: SyncAccount
    let devices: [RegisteredDevice]
    let scopedPassword: Data
    let protectedKeys: [ProtectedKey]
}

/// Failure points in the third-party-to-native upgrade flow, kept distinct so callers can map them to pairing errors.
enum ThirdPartyAccountUpgradeError: Error, Equatable {
    case invalidRecoveryCode
    case temporaryThirdPartyLoginFailed
    case accessCredentialsFetchFailed
    case nativeCredentialAlreadyPresent
    case protectedKeysFetchFailed
    case noUsableThirdPartyProtectedKeys
    case nativeCredentialMaterialGenerationFailed
    case protectedKeyRewrapFailed
    case thirdPartyCredentialEncryptionFailed
    case nativeCredentialCreationRequestFailed
    case nativeCredentialCreationFailed(statusCode: Int)
    case invalidTemporaryLoginResponse
    case finalNativeLoginFailed
    case invalidFinalNativeLoginResponse
}

/// Performs the third-party-to-native account upgrade: temporary 3party login, native credential creation, then final native login.
struct ThirdPartyAccountUpgradeCoordinator: ThirdPartyAccountUpgradeCoordinating {

    /// Auth scopes requested at login: full sync for the native credential, AI Chats only for the temporary 3party session.
    private enum LoginScope {
        static let defaultCredential = "sync"
        static let thirdPartyAccountManagement = "ai_chats"
    }

    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    let crypter: CryptingInternal
    let scopedAccess: ScopedAccessCredentialManaging
    let account: AccountManaging

    /// Back-off delays for retrying the final native login on transient failures after the credential
    /// is created. Nanoseconds; default is 0.5s then 1s — two retries.
    private let finalNativeLoginRetryDelays: [UInt64]

    private let retrySleep: @Sendable (UInt64) async throws -> Void

    private let jweCompactCodec = JWECompactCodec()
    private let scopedAccessCredentialEnvelope = ScopedAccessCredentialEnvelope()

    init(endpoints: Endpoints,
         api: RemoteAPIRequestCreating,
         crypter: CryptingInternal,
         scopedAccess: ScopedAccessCredentialManaging,
         account: AccountManaging,
         finalNativeLoginRetryDelays: [UInt64] = [500_000_000, 1_000_000_000],
         retrySleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.endpoints = endpoints
        self.api = api
        self.crypter = crypter
        self.scopedAccess = scopedAccess
        self.account = account
        self.finalNativeLoginRetryDelays = finalNativeLoginRetryDelays
        self.retrySleep = retrySleep
    }

    /// Upgrades a 3party account to a native (default) credential: temporary scoped login → create the native credential (rewrapping 3party keys) → drop the temp device → log in as the new native device.
    func upgradeThirdPartyAccountToDefaultCredential(_ recoveryCode: String, deviceName: String, deviceType: String) async throws -> UpgradedThirdPartyAccount {
        // Decode the 3party recovery code and use it for a temporary scoped login.
        let recoveryKey = try decodeThirdPartyRecoveryKey(from: recoveryCode)
        let scopedPassword = try decodeScopedPassword(from: recoveryKey)

        let thirdPartyLogin: ThirdPartyLogin
        do {
            thirdPartyLogin = try await loginThirdPartyCredential(recoveryKey, scopedPassword: scopedPassword, deviceName: deviceName, deviceType: deviceType)
        } catch let error as ThirdPartyAccountUpgradeError {
            throw error
        } catch {
            throw ThirdPartyAccountUpgradeError.temporaryThirdPartyLoginFailed
        }

        let thirdPartyAccount = SyncAccount(deviceId: thirdPartyLogin.deviceId,
                                            deviceName: deviceName,
                                            deviceType: deviceType,
                                            userId: recoveryKey.userId,
                                            primaryKey: scopedPassword,
                                            secretKey: thirdPartyLogin.mainKey,
                                            token: thirdPartyLogin.token,
                                            state: .addingNewDevice)

        var didLogoutTemporaryThirdPartyDevice = false
        do {
            // Confirm the account has not already been upgraded before creating native credentials.
            let accessCredentials = try await fetchAccessCredentials(for: thirdPartyAccount)
            guard !accessCredentials.contains(where: { $0.id == SyncCredentialID.defaultCredential }) else {
                throw ThirdPartyAccountUpgradeError.nativeCredentialAlreadyPresent
            }

            // Rewrap 3party-protected keys to the new native secret key and store the old scoped password as a protected credential.
            let thirdPartyProtectedKeys = try await fetchUsableThirdPartyProtectedKeys(for: thirdPartyAccount)
            let accountKeys = try generateDefaultCredentialMaterial(userId: recoveryKey.userId)
            let defaultCredentialMainKey = ScopedAccessKeyDerivation.mainKey(from: accountKeys.primaryKey, userID: recoveryKey.userId)
            let rewrappedProtectedKeys = try rewrapThirdPartyProtectedKeys(thirdPartyProtectedKeys, fromWrappingKey: thirdPartyLogin.mainKey, toAccountSecretKey: accountKeys.secretKey)
            let encryptedThirdPartyCredential = try encryptThirdPartyCredential(scopedPassword, defaultCredentialMainKey: defaultCredentialMainKey)
            try await postDefaultAccessCredential(token: thirdPartyLogin.token,
                                                 hashedPassword: thirdPartyLogin.hashedPassword,
                                                 credentialHashedPassword: accountKeys.passwordHash.base64EncodedString(),
                                                 protectedEncryptionKey: accountKeys.protectedSecretKey.base64EncodedString(),
                                                 encryptedThirdPartyCredential: encryptedThirdPartyCredential,
                                                 keys: rewrappedProtectedKeys)

            // Remove the temporary 3party device before logging in as the newly-created native device.
            await logoutTemporaryThirdPartyDevice(thirdPartyLogin)
            didLogoutTemporaryThirdPartyDevice = true

            let nativeLogin = try await loginDefaultCredentialWithRetry(userId: recoveryKey.userId, accountKeys: accountKeys, deviceName: deviceName, deviceType: deviceType)

            return UpgradedThirdPartyAccount(account: nativeLogin.account, devices: nativeLogin.devices, scopedPassword: scopedPassword, protectedKeys: rewrappedProtectedKeys)
        } catch {
            if !didLogoutTemporaryThirdPartyDevice {
                await logoutTemporaryThirdPartyDevice(thirdPartyLogin)
            }
            throw error
        }
    }

    private func decodeThirdPartyRecoveryKey(from recoveryCode: String) throws -> SyncCode.RecoveryKeyV2 {
        guard let syncCode = try? SyncCode.decodeBase64String(recoveryCode) else {
            throw ThirdPartyAccountUpgradeError.invalidRecoveryCode
        }
        guard case .v2(let recoveryKey) = syncCode.recovery,
              recoveryKey.cid == SyncCode.RecoveryKeyV2.thirdPartyCredentialId else {
            throw ThirdPartyAccountUpgradeError.invalidRecoveryCode
        }
        return recoveryKey
    }

    private func decodeScopedPassword(from recoveryKey: SyncCode.RecoveryKeyV2) throws -> Data {
        guard let scopedPassword = Base64URL.decode(recoveryKey.secret), !scopedPassword.isEmpty else {
            throw ThirdPartyAccountUpgradeError.invalidRecoveryCode
        }
        return scopedPassword
    }

    private func fetchAccessCredentials(for account: SyncAccount) async throws -> [AccessCredential] {
        do {
            return try await scopedAccess.fetchAccessCredentials(account)
        } catch {
            throw ThirdPartyAccountUpgradeError.accessCredentialsFetchFailed
        }
    }

    private func fetchUsableThirdPartyProtectedKeys(for account: SyncAccount) async throws -> [ProtectedKey] {
        let protectedKeys: [ProtectedKey]
        do {
            protectedKeys = try await scopedAccess.fetchProtectedKeys(account)
        } catch {
            throw ThirdPartyAccountUpgradeError.protectedKeysFetchFailed
        }

        let thirdPartyProtectedKeys = protectedKeys
            .filter { $0.encryptedWith == SyncCode.RecoveryKeyV2.thirdPartyCredentialId }
            .removingDuplicateWrappingIdentities()
        guard !thirdPartyProtectedKeys.isEmpty else {
            throw ThirdPartyAccountUpgradeError.noUsableThirdPartyProtectedKeys
        }
        return thirdPartyProtectedKeys
    }

    private func generateDefaultCredentialMaterial(userId: String) throws -> AccountCreationKeys {
        do {
            return try crypter.createAccountCreationKeys(userId: userId, password: UUID().uuidString)
        } catch {
            throw ThirdPartyAccountUpgradeError.nativeCredentialMaterialGenerationFailed
        }
    }

    private func rewrapThirdPartyProtectedKeys(_ keys: [ProtectedKey], fromWrappingKey wrappingKey: Data, toAccountSecretKey accountSecretKey: Data) throws -> [ProtectedKey] {
        do {
            return try keys.map { key in
                let decryptedPrivateKey = try jweCompactCodec.decryptDirect(token: key.encryptedPrivateKey, contentEncryptionKey: wrappingKey)
                let rewrappedEncryptedPrivateKey = try crypter.encrypt(decryptedPrivateKey, using: accountSecretKey)
                return ProtectedKey(kid: key.kid,
                                    encryptedPrivateKey: Base64URL.encode(rewrappedEncryptedPrivateKey),
                                    publicKey: key.publicKey,
                                    encryptedWith: SyncCredentialID.defaultCredential,
                                    purpose: key.purpose)
            }
        } catch {
            throw ThirdPartyAccountUpgradeError.protectedKeyRewrapFailed
        }
    }

    private func encryptThirdPartyCredential(_ scopedPassword: Data, defaultCredentialMainKey: Data) throws -> String {
        do {
            let encryptedCredential = try scopedAccessCredentialEnvelope.encryptScopedPassword(
                scopedPassword,
                using: defaultCredentialMainKey,
                kid: SyncCredentialID.defaultCredential)
            return encryptedCredential
        } catch {
            throw ThirdPartyAccountUpgradeError.thirdPartyCredentialEncryptionFailed
        }
    }

    private func loginThirdPartyCredential(_ recoveryKey: SyncCode.RecoveryKeyV2, scopedPassword: Data, deviceName: String, deviceType: String) async throws -> ThirdPartyLogin {
        let deviceId = UUID().uuidString
        let hashedPassword = ScopedAccessKeyDerivation.hashedPassword(from: scopedPassword, userID: recoveryKey.userId)
        let params = ThirdPartyLoginParameters(userId: recoveryKey.userId,
                                               hashedPassword: hashedPassword,
                                               deviceId: deviceId,
                                               deviceName: Data(deviceName.utf8).base64EncodedString(),
                                               deviceType: Data(deviceType.utf8).base64EncodedString(),
                                               scope: LoginScope.thirdPartyAccountManagement)
        let requestJson = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createUnauthenticatedJSONRequest(url: endpoints.login, method: .post, json: requestJson)
        let result = try await request.execute()
        guard let body = result.data else {
            throw ThirdPartyAccountUpgradeError.invalidTemporaryLoginResponse
        }
        guard let loginResult = try? JSONDecoder.snakeCaseKeys.decode(ThirdPartyLoginResult.self, from: body) else {
            throw ThirdPartyAccountUpgradeError.invalidTemporaryLoginResponse
        }
        return ThirdPartyLogin(deviceId: deviceId,
                               token: loginResult.token,
                               hashedPassword: hashedPassword,
                               mainKey: ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: recoveryKey.userId),
                               devices: loginResult.registeredDevices)
    }

    private func logoutTemporaryThirdPartyDevice(_ thirdPartyLogin: ThirdPartyLogin) async {
        do {
            try await account.logout(deviceId: thirdPartyLogin.deviceId, token: thirdPartyLogin.token)
        } catch {
            Logger.sync.error("3party account upgrade failed to log out temporary 3party device: \(String(reflecting: error))")
        }
    }

    private func loginDefaultCredentialWithRetry(userId: String, accountKeys: AccountCreationKeys, deviceName: String, deviceType: String) async throws -> LoginResult {
        var retryDelays = finalNativeLoginRetryDelays

        while true {
            do {
                return try await loginDefaultCredential(userId: userId, accountKeys: accountKeys, deviceName: deviceName, deviceType: deviceType)
            } catch let error as ThirdPartyAccountUpgradeError {
                throw error
            } catch {
                guard shouldRetryFinalNativeLogin(after: error), !retryDelays.isEmpty else {
                    throw ThirdPartyAccountUpgradeError.finalNativeLoginFailed
                }
                let retryDelay = retryDelays.removeFirst()
                if retryDelay > 0 {
                    try await retrySleep(retryDelay)
                }
            }
        }
    }

    private func shouldRetryFinalNativeLogin(after error: Error) -> Bool {
        if let error = error as? SyncError,
           case .unexpectedStatusCode(let code) = error {
            return code != 401
        }
        return true
    }

    private func postDefaultAccessCredential(token: String,
                                             hashedPassword: String,
                                             credentialHashedPassword: String,
                                             protectedEncryptionKey: String,
                                             encryptedThirdPartyCredential: String,
                                             keys: [ProtectedKey]) async throws {
        let params = CreateDefaultCredentialParameters(
            hashedPassword: hashedPassword,
            credentialHashedPassword: credentialHashedPassword,
            protectedEncryptionKey: protectedEncryptionKey,
            encrypted3partyCredential: encryptedThirdPartyCredential,
            keys: keys
        )
        let requestJson = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createAuthenticatedJSONRequest(url: accessCredentialURL(id: SyncCredentialID.defaultCredential),
                                                         method: .post,
                                                         authToken: token,
                                                         json: requestJson)
        let statusCode: Int
        do {
            statusCode = try await request.execute().response.statusCode
        } catch SyncError.unexpectedStatusCode(let code) {
            statusCode = code
        } catch {
            throw ThirdPartyAccountUpgradeError.nativeCredentialCreationRequestFailed
        }

        switch statusCode {
        case 200, 201, 204:
            return
        case 409:
            throw ThirdPartyAccountUpgradeError.nativeCredentialAlreadyPresent
        default:
            throw ThirdPartyAccountUpgradeError.nativeCredentialCreationFailed(statusCode: statusCode)
        }
    }

    private func loginDefaultCredential(userId: String,
                                        accountKeys: AccountCreationKeys,
                                        deviceName: String,
                                        deviceType: String) async throws -> LoginResult {
        let deviceId = UUID().uuidString
        let loginInfo = try crypter.extractLoginInfo(
            recoveryKey: SyncCode.RecoveryKey(userId: userId, primaryKey: accountKeys.primaryKey))
        let params = DefaultCredentialLoginParameters(
            userId: userId,
            hashedPassword: accountKeys.passwordHash.base64EncodedString(),
            deviceId: deviceId,
            deviceName: try crypter.encryptAndBase64Encode(deviceName, using: accountKeys.primaryKey),
            deviceType: try crypter.encryptAndBase64Encode(deviceType, using: accountKeys.primaryKey),
            scope: LoginScope.defaultCredential
        )
        let requestJson = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createUnauthenticatedJSONRequest(url: endpoints.login, method: .post, json: requestJson)
        let result = try await request.execute()
        guard let body = result.data else {
            throw ThirdPartyAccountUpgradeError.invalidFinalNativeLoginResponse
        }
        guard let loginResult = try? JSONDecoder.snakeCaseKeys.decode(DefaultCredentialLoginResult.self, from: body) else {
            throw ThirdPartyAccountUpgradeError.invalidFinalNativeLoginResponse
        }
        guard let protectedSecretKey = Data(base64Encoded: loginResult.protectedEncryptionKey) else {
            throw ThirdPartyAccountUpgradeError.invalidFinalNativeLoginResponse
        }
        let secretKey = try crypter.extractSecretKey(protectedSecretKey: protectedSecretKey,
                                                     stretchedPrimaryKey: loginInfo.stretchedPrimaryKey)
        let devices = try loginResult.devices.map {
            RegisteredDevice(
                id: $0.id,
                name: try crypter.base64DecodeAndDecrypt($0.name, using: accountKeys.primaryKey),
                type: try crypter.base64DecodeAndDecrypt($0.type, using: accountKeys.primaryKey)
            )
        }
        return LoginResult(
            account: SyncAccount(
                deviceId: deviceId,
                deviceName: deviceName,
                deviceType: deviceType,
                userId: userId,
                primaryKey: accountKeys.primaryKey,
                secretKey: secretKey,
                token: loginResult.token,
                state: .addingNewDevice
            ),
            devices: devices,
            keys: loginResult.keys,
            accessCredentials: loginResult.accessCredentials
        )
    }

    private func accessCredentialURL(id: String) -> URL {
        endpoints.accessCredentials.appendingPathComponent(id)
    }

}

private struct CreateDefaultCredentialParameters: Encodable {
    let hashedPassword: String
    let credentialHashedPassword: String
    let protectedEncryptionKey: String
    let encrypted3partyCredential: String
    let keys: [ProtectedKey]

    enum CodingKeys: String, CodingKey {
        case hashedPassword = "hashed_password"
        case credentialHashedPassword = "credential_hashed_password"
        case protectedEncryptionKey = "protected_encryption_key"
        case encrypted3partyCredential = "encrypted_3party_credential"
        case keys
    }
}

private struct ThirdPartyLoginParameters: Encodable {
    let userId: String
    let hashedPassword: String
    let deviceId: String
    let deviceName: String
    let deviceType: String
    let scope: String
}

private struct DefaultCredentialLoginParameters: Encodable {
    let userId: String
    let hashedPassword: String
    let deviceId: String
    let deviceName: String
    let deviceType: String
    let scope: String
}

private struct DefaultCredentialLoginResult: Decodable {
    let devices: [RegisteredDevice]
    let token: String
    let protectedEncryptionKey: String
    let accessCredentials: [AccessCredential]?
    let keys: [ProtectedKey]?
}

private struct ThirdPartyLoginResult: Decodable {
    let devices: [ThirdPartyLoginDevice]?
    let token: String

    var registeredDevices: [RegisteredDevice] {
        devices?.map { $0.registeredDevice } ?? []
    }
}

private struct ThirdPartyLoginDevice: Decodable {
    let id: String
    let name: String
    let type: String?

    var registeredDevice: RegisteredDevice {
        RegisteredDevice(id: id,
                         name: Self.base64DecodedUTF8(name) ?? name,
                         type: type.flatMap { Self.base64DecodedUTF8($0) } ?? type ?? "")
    }

    private static func base64DecodedUTF8(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct ThirdPartyLogin {
    let deviceId: String
    let token: String
    let hashedPassword: String
    let mainKey: Data
    let devices: [RegisteredDevice]
}

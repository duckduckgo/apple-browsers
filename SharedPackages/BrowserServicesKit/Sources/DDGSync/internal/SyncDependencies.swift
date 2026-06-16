//
//  SyncDependencies.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import PrivacyConfig
import Combine
import Common
import Foundation
import Persistence
import Networking

protocol SyncDependenciesDebuggingSupport {
    func updateServerEnvironment(_ serverEnvironment: ServerEnvironment)
}

protocol SyncDependencies: SyncDependenciesDebuggingSupport {

    var endpoints: Endpoints { get }
    var account: AccountManaging { get }
    var scopedAccess: ScopedAccessCredentialManaging { get }
    var api: RemoteAPIRequestCreating { get }
    var payloadCompressor: SyncPayloadCompressing { get }
    var keyValueStore: ThrowingKeyValueStoring { get }
    var legacyKeyValueStore: KeyValueStoring { get }
    var secureStore: SecureStoring { get }
    var crypter: CryptingInternal { get }
    var scheduler: SchedulingInternal { get }
    var privacyConfigurationManager: PrivacyConfigurationManaging { get }
    var errorEvents: EventMapping<SyncError> { get }
    var shouldPreserveAccountWhenSyncDisabled: () -> Bool { get }
    var syncFeatureFlags: any SyncFeatureFlagProviding { get }

    func createRemoteConnector() throws -> RemoteConnecting
    func createRemoteKeyExchanger() throws -> any RemoteKeyExchanging
    func createRemoteExchangeRecoverer(_ exchangeInfo: ExchangeInfo) throws -> any RemoteExchangeRecovering
    func createRecoveryKeyTransmitter() throws -> RecoveryKeyTransmitting
    func createExchangePublicKeyTransmitter() throws -> ExchangePublicKeyTransmitting
    func createExchangeRecoveryKeyTransmitter(exchangeMessage: ExchangeMessage) throws -> ExchangeRecoveryKeyTransmitting
    func createPairingV2MessageExchanger() -> PairingV2MessageExchanging
    func createThirdPartyAccountUpgradeCoordinator() -> ThirdPartyAccountUpgradeCoordinating
    func createTokenRescope() -> TokenRescoping
    func createAIChats() -> AIChatsHandling
}

protocol AccountManaging {

    func createAccount(deviceName: String, deviceType: String) async throws -> SyncAccount
    func deleteAccount(_ account: SyncAccount) async throws

    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> LoginResult
    func refreshToken(_ account: SyncAccount, deviceName: String) async throws -> LoginResult

    func logout(deviceId: String, token: String) async throws

    func fetchDevicesForAccount(_ account: SyncAccount) async throws -> [RegisteredDevice]
}

/// Manages the scoped ("3party") access credential: recovering, creating, and fetching its password and protected keys.
protocol ScopedAccessCredentialManaging {
    /// Decrypts the existing scoped password from the account's 3party access credential, or nil if there isn't one yet.
    func recoverScopedPassword(from accessCredentials: [AccessCredential]?,
                               primaryKey: Data,
                               userID: String) throws -> Data?
    /// Returns the account's scoped password, creating and uploading the 3party credential (and its protected keys) if absent; reuses `cachedScopedPassword` when creating.
    func ensureThirdPartyScopedPassword(for account: SyncAccount,
                                        purpose: String,
                                        cachedScopedPassword: () throws -> Data?) async throws -> EnsuredThirdPartyCredential
    /// Builds the Base64URL recovery code that shares the account via the scoped password, or nil if the password is empty.
    func makeRecoveryCode(for account: SyncAccount, scopedPassword: Data) -> String?
    /// Fetches the account's access credentials (empty if none exist).
    func fetchAccessCredentials(_ account: SyncAccount) async throws -> [AccessCredential]
    /// Fetches the account's protected keys (empty if none exist).
    func fetchProtectedKeys(_ account: SyncAccount) async throws -> [ProtectedKey]
    /// Uploads a protected key for the given purpose only if one isn't already stored, returning the stored key (existing or new).
    func setKeyIfAbsent(purpose: String, key: ProtectedKey, for account: SyncAccount) async throws -> ProtectedKey?
}

protocol SecureStoring {
    func persistAccount(_ account: SyncAccount) throws
    func account() throws -> SyncAccount?
    func removeAccount() throws
    func persistScopedPassword(_ scopedPassword: Data) throws
    func scopedPassword() throws -> Data?
    func removeScopedPassword() throws
    func persistProtectedKeys(_ data: Data) throws
    func removeProtectedKeys() throws
}

protocol CryptingInternal: Crypting {

    func encrypt(_ value: Data, using secretKey: Data) throws -> Data
    func decryptData(_ value: Data, using secretKey: Data) throws -> Data

    func seal(_ data: Data, secretKey: Data) throws -> Data
    func unseal(encryptedData: Data, publicKey: Data, secretKey: Data) throws -> Data

    func createAccountCreationKeys(userId: String, password: String) throws ->
        AccountCreationKeys

    func extractLoginInfo(recoveryKey: SyncCode.RecoveryKey) throws -> ExtractedLoginInfo

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data

    func prepareForConnect() throws -> ConnectInfo

    func prepareForExchange() throws -> ExchangeInfo
}

public struct HTTPResult {
    let data: Data?
    let response: HTTPURLResponse
}

public protocol HTTPRequesting {
    func execute() async throws -> HTTPResult
}

public protocol RemoteAPIRequestCreating {
    func createRequest(url: URL,
                       method: APIRequest.HTTPMethod,
                       headers: [String: String],
                       parameters: [String: String],
                       body: Data?,
                       contentType: String?) -> HTTPRequesting
}

protocol RecoveryKeyTransmitting {

    func send(_ code: SyncCode.ConnectCode) async throws

}

protocol ExchangePublicKeyTransmitting {

    func sendGeneratedExchangeInfo(_ code: SyncCode.ExchangeKey, deviceName: String) async throws -> ExchangeInfo

}

protocol ExchangeRecoveryKeyTransmitting {

    func send() async throws

}

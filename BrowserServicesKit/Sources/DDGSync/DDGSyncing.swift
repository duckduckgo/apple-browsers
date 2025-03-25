//
//  DDGSyncing.swift
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

import BrowserServicesKit
import Combine
import DDGSyncCrypto
import Foundation

public enum SyncAuthState: String, Sendable, Codable {
    /// Sync engine is not initialized.
    case initializing
    /// Sync is not enabled.
    case inactive
    /// Sync is in progress of adding a new device to an existing account.
    case addingNewDevice
    /// User is logged in to sync.
    case active
}

/**
 This protocol should be implemented by clients to feed DDGSync with the list of syncable data providers.
 */
public protocol DataProvidersSource: AnyObject {
    /**
     Clients should implement this method and return data providers for all types of syncable data.

     This function is called whenever sync account setup is finished
     and initial sync operation is ready to be performed.
     */
    func makeDataProviders() -> [DataProviding]
}

public protocol DDGSyncing: DDGSyncingDebuggingSupport {

    var dataProvidersSource: DataProvidersSource? { get set }

    /**
     Describes current availability of sync features.
     */
    var featureFlags: SyncFeatureFlags { get }

    /**
     Emits changes to current availability of sync features
     */
    var featureFlagsPublisher: AnyPublisher<SyncFeatureFlags, Never> { get }

    /**
     Describes current state of sync account.

     Must be different than `initializing` to guarantee that querying state info works as expected.
     */
    var authState: SyncAuthState { get }

    /**
     Emits changes to current state of sync account.
     */
    var authStatePublisher: AnyPublisher<SyncAuthState, Never> { get }

    /**
     The currently logged in sync account. Returns nil if client is not authenticated
     */
    var account: SyncAccount? { get }

    /**
     Used to trigger Sync by the client app.

     Sync is not started directly, but instead its schedule is handled internally based on input events.
     Clients should use `scheduler` and `Scheduling` API to notify Sync about app events, such as making
     changes to syncable data or lifecycle-related events.
     */
    var scheduler: Scheduling { get }

    /**
     Used to aggregate success and error stats of sync operations.
     */
    var syncDailyStats: SyncDailyStats { get }

    /**
     Returns true if there is an ongoing sync operation.
     */
    var isSyncInProgress: Bool { get }

    /**
     Emits boolean values representing current sync operation status.
     */
    var isSyncInProgressPublisher: AnyPublisher<Bool, Never> { get }

    /**
     Initializes Sync object, loads account info and prepares internal state.
     */
    func initializeIfNeeded()

    /**
     Creates an account.

     Account creation has the following flow:
     * Create a device id, user id and password (UUIDs - future versions will support passing these in)
     * Generate secure keys
     * Call /signup endpoint
     * Store Primary Key, Secret Key, User Id and JWT token

     Notes:
     * The primary key in combination with the user id, is the recovery code.  This can be used to (re)connect devices.
     * The JWT token contains the authorisation required to call an endpoint.  If a device is removed from sync the token will be invalidated on the server and subsequent calls will fail.

     */
    func createAccount(deviceName: String, deviceType: String) async throws

    /**
     Logs in to an existing account using a recovery key.
     */
    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> [RegisteredDevice]

    /**
     Returns a device id and temporary secret key ready for display and allows callers attempt to fetch the transmitted recovery key.
     */
    func remoteConnect() throws -> RemoteConnecting

    /**
     Sends this device's recovery key to the server encrypted using supplied key
     */
    func transmitRecoveryKey(_ connectCode: SyncCode.ConnectCode) async throws

    /**
     Creates controller to manage connecting to another device
     */
    func createConnectionController(deviceName: String, deviceType: String, delegate: SyncConnectionControllerDelegate) -> SyncConnectionControlling

    /**
     Sends this device's public key to the server encrypted using supplied key
     Step B from https://app.asana.com/0/0/1209571867429615
     */
    func transmitGeneratedExchangeInfo(_ exchangeCode: SyncCode.ExchangeKey, deviceName: String) async throws -> ExchangeInfo

    /**
     Sends this device's recovery key to the server encrypted using supplied key
     Step D from https://app.asana.com/0/0/1209571867429615
     */
    func transmitExchangeRecoveryKey(for exchangeMessage: ExchangeMessage) async throws

    /**
     Disconnect this client from the sync service. Removes all local info, but leaves in places bookmarks, etc.
     */
    func disconnect() async throws

    /**
     Disconnect the specified device from the sync service.

     - Parameter deviceId: ID of the device to be disconnected.
     */
    func disconnect(deviceId: String) async throws

    /**
     Fetch the devices associated with thtis account.
     */
    func fetchDevices() async throws -> [RegisteredDevice]

    /**
     Updated the device name.
     */
    func updateDeviceName(_ name: String) async throws -> [RegisteredDevice]

    /**
     Deletes this account, but does not affect locally stored data.
     */
    func deleteAccount() async throws
}

public protocol DDGSyncingDebuggingSupport {
    var serverEnvironment: ServerEnvironment { get }
    func updateServerEnvironment(_ serverEnvironment: ServerEnvironment)
}

public enum ServerEnvironment: LosslessStringConvertible {
    case development
    case production

    var baseURL: URL {
        switch self {
        case .development:
            return URL(string: "https://dev-sync-use.duckduckgo.com")!
        case .production:
            return URL(string: "https://sync.duckduckgo.com")!
        }
    }

    public var description: String {
        switch self {
        case .development:
            return "Development"
        case .production:
            return "Production"
        }
    }

    public init?(_ description: String) {
        switch description {
        case "Development":
            self = .development
        case "Production":
            self = .production
        default:
            return nil
        }
    }
}

public protocol Crypting {

    /**
     * Retrieves secret key from Sync account data stored in keychain.
     *
     * The key can be cached locally and used as `secretKey` when passed to
     * `encryptAndBase64Encode` and `base64DecodeAndDecrypt` functions.
     *
     * This function throws an error if Sync account is not present
     * (or can't be retrieved from keychain).
     */
    func fetchSecretKey() throws -> Data

    /**
     * Encrypts `value` using provided `secretKey` and encodes it using Base64 encoding.
     *
     * Throws an error if value cannot be encrypted.
     */
    func encryptAndBase64Encode(_ value: String, using secretKey: Data) throws -> String

    /**
     * Decodes Base64-encoded `value` and decrypts it using provided `secretKey`.
     *
     * Throws an error if value is not a valid Base64-encoded string or when decryption fails.
     */
    func base64DecodeAndDecrypt(_ value: String, using secretKey: Data) throws -> String

    /**
     * Encrypts `value` and encodes it using Base64 encoding.
     *
     * This is a convenience function for calling `encryptAndBase64Encode(_:secretKey:)`
     * as it calls `fetchSecretKey` internally to retrieve encryption key.
     * Fetching key may be an expensive operation and should be avoided when the function
     * is called multiple times (e.g. to encrypt a collection of values). In this scenario,
     * fetching key upfront with `fetchSecretKey` and passing it to `encryptAndBase64Encode(_:secretKey:)`
     * is preferred.
     */
    func encryptAndBase64Encode(_ value: String) throws -> String

    /**
     * Decodes Base64-encoded `value` and decrypts it.
     *
     * This is a convenience function for calling `base64DecodeAndDecrypt(_:secretKey:)`
     * as it calls `fetchSecretKey` internally to retrieve decryption key.
     * Fetching key may be an expensive operation and should be avoided when the function
     * is called multiple times (e.g. to decrypt a collection of values). In this scenario,
     * fetching key upfront with `fetchSecretKey` and passing it to `base64DecodeAndDecrypt(_:secretKey:)`
     * is preferred.
     */
    func base64DecodeAndDecrypt(_ value: String) throws -> String
}

public protocol RemoteConnecting {

    var code: String { get }

    func pollForRecoveryKey() async throws -> SyncCode.RecoveryKey?

    func stopPolling()

}

protocol RemoteKeyExchanging {

    /// Step A from https://app.asana.com/0/72649045549333/1209571867429615/f
    var code: String { get }

    /// Step C from https://app.asana.com/0/72649045549333/1209571867429615/f
    func pollForPublicKey() async throws -> ExchangeMessage?

    func stopPolling()
}

protocol RemoteExchangeRecovering {

    /// Step E from https://app.asana.com/0/72649045549333/1209571867429615/f
    func pollForRecoveryKey() async throws -> SyncCode.RecoveryKey?

    func stopPolling()
}

/**
 * Describes Sync scheduler.
 *
 * Client apps can call scheduler API directly to notify about events
 * that should trigger sync.
 */
public protocol Scheduling {
    /// This should be called whenever any syncable object changes.
    func notifyDataChanged()
    /// This should be called on application launch and when the app becomes active.
    func notifyAppLifecycleEvent()
    /// This should be called from externally scheduled background jobs that trigger sync periodically.
    func requestSyncImmediately()
    /// This should be called when sync needs to be cancelled, e.g. in response to app going to background.
    func cancelSyncAndSuspendSyncQueue()
    /// This should be called when sync can be resumed, e.g. in response to app going to foreground.
    func resumeSyncQueue()
}

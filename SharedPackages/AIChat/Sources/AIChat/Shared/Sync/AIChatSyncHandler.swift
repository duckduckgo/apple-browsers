//
//  AIChatSyncHandler.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation
import DDGSync

public protocol AIChatSyncHandling {

    func isSyncTurnedOn() -> Bool
    var authStatePublisher: AnyPublisher<SyncAuthState, Never> { get }
    func getSyncStatus(featureAvailable: Bool) throws -> AIChatSyncHandler.SyncStatus
    func getScopedToken() async throws -> AIChatSyncHandler.SyncToken
    func encrypt(_ string: String) throws -> AIChatSyncHandler.EncryptedData
    func decrypt(_ string: String) throws -> AIChatSyncHandler.DecryptedData
    func setAIChatHistoryEnabled(_ enabled: Bool)
}

public class AIChatSyncHandler: AIChatSyncHandling {

    public enum Errors: Error {
        case internalError
        case emptyResponse
    }

    public struct SyncStatus: Codable {
        let syncAvailable: Bool
        let userId: String?
        let deviceId: String?
        let deviceName: String?
        let deviceType: String?

        public init(syncAvailable: Bool,
                    userId: String? = nil,
                    deviceId: String? = nil,
                    deviceName: String? = nil,
                    deviceType: String? = nil) {
            self.syncAvailable = syncAvailable
            self.userId = userId
            self.deviceId = deviceId
            self.deviceName = deviceName
            self.deviceType = deviceType
        }
    }

    public struct SyncToken: Encodable {
        let token: String
    }

    public struct EncryptedData: Encodable {
        let encryptedData: String
    }

    public struct DecryptedData: Encodable {
        let decryptedData: String
    }

    private let sync: DDGSyncing
    private let httpRequestErrorHandler: ((Error) -> Void)?

    public init(sync: DDGSyncing,
                httpRequestErrorHandler: ((Error) -> Void)? = nil) {
        self.sync = sync
        self.httpRequestErrorHandler = httpRequestErrorHandler
    }

    private func validateSetup() throws {
        guard sync.authState != .initializing else {
            throw Errors.internalError
        }
    }

    /// The account backing a live sync session, or `nil` when sync is off.
    ///
    /// Deliberately not a plain `account != nil` check: the account lives in the keychain, which
    /// survives app deletion, and `syncAutoRestore` preserves it while leaving `authState` as
    /// `.inactive`.
    private var activeSyncAccount: SyncAccount? {
        switch sync.authState {
        case .active, .addingNewDevice:
            return sync.account
        case .initializing, .inactive:
            return nil
        }
    }

    public func isSyncTurnedOn() -> Bool {
        activeSyncAccount != nil
    }

    public var authStatePublisher: AnyPublisher<SyncAuthState, Never> {
        sync.authStatePublisher
    }

    public func getSyncStatus(featureAvailable: Bool) throws -> SyncStatus {
        guard featureAvailable else {
            return SyncStatus(syncAvailable: false,
                              userId: nil,
                              deviceId: nil,
                              deviceName: nil,
                              deviceType: nil)
        }

        try validateSetup()

        // Sync off reports the feature as available but signed out rather than throwing — the
        // web app treats an error as a transient failure and retries.
        guard let account = activeSyncAccount else {
            return SyncStatus(syncAvailable: true,
                              userId: nil,
                              deviceId: nil,
                              deviceName: nil,
                              deviceType: nil)
        }

        return SyncStatus(syncAvailable: true,
                          userId: account.userId,
                          deviceId: account.deviceId,
                          deviceName: account.deviceName,
                          deviceType: account.deviceType)
    }

    public func getScopedToken() async throws -> SyncToken {
        try validateSetup()

        // `accountNotFound` is deliberate: the caller already maps it to "sync off".
        guard activeSyncAccount != nil else {
            throw SyncError.accountNotFound
        }

        do {
            guard let token = try await sync.mainTokenRescope(to: "ai_chats"),
                  token.isEmpty == false else {
                throw Errors.emptyResponse
            }

            return SyncToken(token: token)
        } catch {
            httpRequestErrorHandler?(error)
            throw error
        }
    }

    public func encrypt(_ string: String) throws -> EncryptedData {
        try validateSetup()

        let data = try sync.encryptAndBase64URLEncode([string]).first ?? ""

        return EncryptedData(encryptedData: data)
    }

    public func decrypt(_ string: String) throws -> DecryptedData {
        try validateSetup()

        let data = try sync.base64URLDecodeAndDecrypt([string]).first ?? ""
        return DecryptedData(decryptedData: data)
    }

    public func setAIChatHistoryEnabled(_ enabled: Bool) {
        sync.setAIChatHistoryEnabled(enabled)
    }
}

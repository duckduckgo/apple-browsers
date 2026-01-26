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

    public init(sync: DDGSyncing) {
        self.sync = sync
    }

    private func validateSetup() throws {
        guard sync.authState != .initializing else {
            throw Errors.internalError
        }
    }

    public func isSyncTurnedOn() -> Bool {
        sync.authState != .initializing && sync.account != nil
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

        guard let account = sync.account else {
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

        guard let token = try await sync.mainTokenRescope(to: "ai_chats"),
                token.isEmpty == false else {
            throw Errors.emptyResponse
        }

        return SyncToken(token: token)
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

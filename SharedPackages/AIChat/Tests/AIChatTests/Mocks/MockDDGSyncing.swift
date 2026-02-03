//
//  MockDDGSyncing.swift
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

import Combine
import Foundation
@testable import DDGSync

final class MockDDGSyncing: DDGSyncing {

    // MARK: - Configurable State

    var authState: SyncAuthState = .active
    var account: SyncAccount?
    var isAIChatHistoryEnabled: Bool = true

    // MARK: - Delete AI Chats

    var deleteAIChatsCallCount = 0
    var deleteAIChatsUntilDate: Date?
    var deleteAIChatsError: Error?
    var onDeleteAIChats: (() -> Void)?

    func deleteAIChats(until: Date) async throws {
        deleteAIChatsCallCount += 1
        deleteAIChatsUntilDate = until
        onDeleteAIChats?()
        if let error = deleteAIChatsError {
            throw error
        }
    }

    // MARK: - Delete AI Chats by Chat IDs

    var deleteAIChatsByChatIdsCallCount = 0
    var deleteAIChatsByChatIds: [String]?
    var deleteAIChatsByChatIdsError: Error?
    var onDeleteAIChatsByChatIds: (() -> Void)?

    func deleteAIChats(chatIds: [String]) async throws {
        deleteAIChatsByChatIdsCallCount += 1
        deleteAIChatsByChatIds = chatIds
        onDeleteAIChatsByChatIds?()
        if let error = deleteAIChatsByChatIdsError {
            throw error
        }
    }

    // MARK: - Token Rescope

    var mainTokenRescopeResult: String?
    var mainTokenRescopeScope: String?

    func mainTokenRescope(to scope: String) async throws -> String? {
        mainTokenRescopeScope = scope
        return mainTokenRescopeResult
    }

    // MARK: - Encryption

    var encryptResult: [String] = []
    var encryptError: Error?
    var encryptInput: [String]?

    func encryptAndBase64URLEncode(_ values: [String]) throws -> [String] {
        encryptInput = values
        if let error = encryptError {
            throw error
        }
        return encryptResult
    }

    // MARK: - Decryption

    var decryptResult: [String] = []
    var decryptError: Error?
    var decryptInput: [String]?

    func base64URLDecodeAndDecrypt(_ values: [String]) throws -> [String] {
        decryptInput = values
        if let error = decryptError {
            throw error
        }
        return decryptResult
    }

    // MARK: - AI Chat History

    var setAIChatHistoryEnabledCallCount = 0

    func setAIChatHistoryEnabled(_ enabled: Bool) {
        setAIChatHistoryEnabledCallCount += 1
        isAIChatHistoryEnabled = enabled
    }

    // MARK: - Unused Protocol Requirements

    var dataProvidersSource: DataProvidersSource?
    var featureFlags: SyncFeatureFlags = .all
    var featureFlagsPublisher: AnyPublisher<SyncFeatureFlags, Never> { Just(featureFlags).eraseToAnyPublisher() }
    var authStatePublisher: AnyPublisher<SyncAuthState, Never> { Just(authState).eraseToAnyPublisher() }
    var scheduler: Scheduling { MockScheduling() }
    var syncDailyStats: SyncDailyStats { fatalError("Not implemented") }
    var isSyncInProgress: Bool { false }
    var isSyncInProgressPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var serverEnvironment: ServerEnvironment { .production }

    func initializeIfNeeded() {}
    func createAccount(deviceName: String, deviceType: String) async throws {}
    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> [RegisteredDevice] { [] }
    func remoteConnect() throws -> RemoteConnecting { fatalError("Not implemented") }
    func transmitRecoveryKey(_ connectCode: SyncCode.ConnectCode) async throws {}
    func createConnectionController(deviceName: String, deviceType: String, delegate: SyncConnectionControllerDelegate) -> SyncConnectionControlling { fatalError("Not implemented") }
    func transmitGeneratedExchangeInfo(_ exchangeCode: SyncCode.ExchangeKey, deviceName: String) async throws -> ExchangeInfo { fatalError("Not implemented") }
    func transmitExchangeRecoveryKey(for exchangeMessage: ExchangeMessage) async throws {}
    func setCustomOperations(_ operations: [any SyncCustomOperation]) {}
    func disconnect() async throws {}
    func disconnect(deviceId: String) async throws {}
    func fetchDevices() async throws -> [RegisteredDevice] { [] }
    func updateDeviceName(_ name: String) async throws -> [RegisteredDevice] { [] }
    func deleteAccount() async throws {}
    func encryptAndBase64Encode(_ values: [String]) throws -> [String] { values }
    func base64DecodeAndDecrypt(_ values: [String]) throws -> [String] { values }
    func updateServerEnvironment(_ serverEnvironment: ServerEnvironment) {}
}

// MARK: - Mock Scheduling

final class MockScheduling: Scheduling {
    func notifyDataChanged() {}
    func notifyAppLifecycleEvent() {}
    func requestSyncImmediately() {}
    func cancelSyncAndSuspendSyncQueue() {}
    func resumeSyncQueue() {}
}

// MARK: - Mock SyncAccount Factory

enum MockSyncAccount {
    static var valid: SyncAccount {
        SyncAccount(
            deviceId: "test-device-id",
            deviceName: "Test Device",
            deviceType: "iPhone",
            userId: "test-user-id",
            primaryKey: Data(),
            secretKey: Data(),
            token: "test-token",
            state: .active
        )
    }
}

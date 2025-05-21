//
//  MockDDGSyncing.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Combine
import PersistenceTestingUtils
@testable import DuckDuckGo_Privacy_Browser
@testable import DDGSync

class MockDDGSyncing: DDGSyncing {
    func createConnectionController(deviceName: String, deviceType: String, delegate: any SyncConnectionControllerDelegate) -> any SyncConnectionControlling {
        MockSyncConnectionControlling()
    }

    func transmitGeneratedExchangeInfo(_ exchangeCode: SyncCode.ExchangeKey, deviceName: String) async throws -> ExchangeInfo {
        .init(keyId: "", publicKey: .init(), secretKey: .init())
    }

    func transmitExchangeRecoveryKey(for exchangeMessage: ExchangeMessage) async throws {

    }

    var registeredDevices = [RegisteredDevice(id: "1", name: "Device 1", type: "desktop"), RegisteredDevice(id: "2", name: "Device 2", type: "mobile"), RegisteredDevice(id: "3", name: "Device 1", type: "desktop")]
    var disconnectCalled = false

    var dataProvidersSource: DataProvidersSource?

    @Published var featureFlags: SyncFeatureFlags = .all

    var featureFlagsPublisher: AnyPublisher<SyncFeatureFlags, Never> {
        $featureFlags.eraseToAnyPublisher()
    }

    @Published var authState: SyncAuthState = .inactive

    var authStatePublisher: AnyPublisher<SyncAuthState, Never> {
        $authState.eraseToAnyPublisher()
    }

    var account: SyncAccount?

    var scheduler: Scheduling

    var syncDailyStats = SyncDailyStats(store: MockKeyValueStore())

    @Published var isSyncInProgress: Bool

    var isSyncInProgressPublisher: AnyPublisher<Bool, Never> {
        $isSyncInProgress.eraseToAnyPublisher()
    }

    init(dataProvidersSource: DataProvidersSource? = nil, authState: SyncAuthState, account: SyncAccount? = nil, scheduler: Scheduling = CapturingScheduler(), isSyncInProgress: Bool) {
        self.dataProvidersSource = dataProvidersSource
        self.authState = authState
        self.account = account
        self.scheduler = scheduler
        self.isSyncInProgress = isSyncInProgress
    }

    func initializeIfNeeded() {
    }

    func createAccount(deviceName: String, deviceType: String) async throws {
    }

    var stubLogin: [RegisteredDevice] = []
    lazy var spyLogin: (SyncCode.RecoveryKey, String, String) throws -> [RegisteredDevice] = { _, _, _ in
        return self.stubLogin
    }

    @Published var loginCalled: Bool = false
    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> [RegisteredDevice] {
        loginCalled = true
        return try spyLogin(recoveryKey, deviceName, deviceType)
    }

    func remoteConnect() throws -> RemoteConnecting {
        return MockRemoteConnecting()
    }

    func transmitRecoveryKey(_ connectCode: SyncCode.ConnectCode) async throws {
    }

    func disconnect() async throws {
        disconnectCalled = true
    }

    func disconnect(deviceId: String) async throws {
    }

    func fetchDevices() async throws -> [RegisteredDevice] {
        return registeredDevices
    }

    func updateDeviceName(_ name: String) async throws -> [RegisteredDevice] {
        return []
    }

    func deleteAccount() async throws {
    }

    var serverEnvironment: ServerEnvironment = .production

    func updateServerEnvironment(_ serverEnvironment: ServerEnvironment) {
    }
}

final class MockSyncConnectionControlling: SyncConnectionControlling {
    
    @Published var cancelCalled: Bool = false
    func cancel() async {
        cancelCalled = true
    }

    @Published var startExhangeModeCalled: Bool = false
    var spyStartExchangeModelShouldGenerateURLBasedCode: Bool?
    var stubStartExchangeMode: String = ""
    var stubStartExchangeModeError: Error?
    func startExchangeMode(shouldGenerateURLBasedCode: Bool) async throws -> String {
        startExhangeModeCalled = true
        spyStartExchangeModelShouldGenerateURLBasedCode = shouldGenerateURLBasedCode
        if let error = stubStartExchangeModeError {
            throw error
        }
        return stubStartExchangeMode
    }

    @Published var startConnectModeCalled: Bool = false
    var spyStartConnectModeShouldGenerateURLBasedCode: Bool?
    var stubStartConnectMode: String = ""
    var stubStartConnectModeError: Error?
    func startConnectMode(shouldGenerateURLBasedCode: Bool) async throws -> String {
        startConnectModeCalled = true
        spyStartConnectModeShouldGenerateURLBasedCode = shouldGenerateURLBasedCode
        if let error = stubStartConnectModeError {
            throw error
        }
        return stubStartConnectMode
    }

    @Published var startPairingModeCalled: Bool = false
    var spyStartPairingModeInfo: PairingInfo?
    var stubStartPairingMode: Bool = true
    func startPairingMode(_ pairingInfo: PairingInfo) async -> Bool {
        startPairingModeCalled = true
        spyStartPairingModeInfo = pairingInfo
        return stubStartPairingMode
    }

    @Published var syncCodeEnteredCalled: Bool = false
    var spySyncCodeEnteredCode: String?
    var spySyncCodeEnteredCanScanURLBarcodes: Bool?
    var stubSyncCodeEntered: Bool = true
    func syncCodeEntered(code: String, canScanURLBarcodes: Bool) async -> Bool {
        syncCodeEnteredCalled = true
        spySyncCodeEnteredCode = code
        spySyncCodeEnteredCanScanURLBarcodes = canScanURLBarcodes
        return stubSyncCodeEntered
    }

    @Published var loginAndShowDeviceConnectedCalled: Bool = false
    var spyLoginAndShowDeviceConnectedRecoveryKey: SyncCode.RecoveryKey?
    var spyLoginAndShowDeviceConnectedIsRecovery: Bool?
    var stubLoginAndShowDeviceConnectedError: Error?
    func loginAndShowDeviceConnected(recoveryKey: SyncCode.RecoveryKey, isRecovery: Bool) async throws {
        loginAndShowDeviceConnectedCalled = true
        spyLoginAndShowDeviceConnectedRecoveryKey = recoveryKey
        spyLoginAndShowDeviceConnectedIsRecovery = isRecovery
        if let error = stubLoginAndShowDeviceConnectedError {
            throw error
        }
    }
}

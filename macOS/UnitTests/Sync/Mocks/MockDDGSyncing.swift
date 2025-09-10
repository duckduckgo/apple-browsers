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

    var createAccountCallback: ((String, String) -> Void)?
    var createAccountError: Error?
    func createAccount(deviceName: String, deviceType: String) async throws {
        if let createAccountError {
            throw createAccountError
        }
        createAccountCallback?(deviceName, deviceType)
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

    var disconnectCalled = false
    var spyDisconnectCalled = { }
    func disconnect() async throws {
        disconnectCalled = true
        spyDisconnectCalled()
    }

    var disconnectDeviceCallback: ((String) -> Void)?
    var disconnectDeviceError: Error?
    func disconnect(deviceId: String) async throws {
        if let disconnectDeviceError {
            throw disconnectDeviceError
        }
        disconnectDeviceCallback?(deviceId)
    }

    var fetchDevicesCallback: (() -> Void)?
    func fetchDevices() async throws -> [RegisteredDevice] {
        fetchDevicesCallback?()
        return registeredDevices
    }

    var updateDeviceNameCallback: ((String) -> Void)?
    var updateDeviceNameError: Error?
    func updateDeviceName(_ name: String) async throws -> [RegisteredDevice] {
        if let updateDeviceNameError {
            throw updateDeviceNameError
        }
        updateDeviceNameCallback?(name)
        return []
    }

    var deleteAccountCallback: (() -> Void)?
    var deleteAccountError: Error?
    func deleteAccount() async throws {
        if let deleteAccountError {
            throw deleteAccountError
        }
        deleteAccountCallback?()
    }

    var serverEnvironment: ServerEnvironment = .production

    func updateServerEnvironment(_ serverEnvironment: ServerEnvironment) {
    }
}

final class MockSyncConnectionControlling: SyncConnectionControlling {

    var cancelCalled = { }
    func cancel() async {
        cancelCalled()
    }

    var spyStartExchangeModelShouldGenerateURLBasedCode: Bool?
    var startExchangeModeStub: PairingInfo = .init(base64Code: "", deviceName: "")
    var startExchangeModeError: Error?
    func startExchangeMode() async throws -> PairingInfo {
        if let error = startExchangeModeError {
            throw error
        }
        return startExchangeModeStub
    }

    var spyStartConnectModeShouldGenerateURLBasedCode: Bool?
    var startConnectModeStub: PairingInfo = .init(base64Code: "", deviceName: "")
    var startConnectModeError: Error?
    func startConnectMode() async throws -> PairingInfo {
        if let error = startConnectModeError {
            throw error
        }
        return startConnectModeStub
    }

    var spyStartPairingModeInfo: PairingInfo?
    var stubStartPairingMode: Bool = true
    var startPairingModeCalled: (PairingInfo) -> Void = { _ in }
    func startPairingMode(_ pairingInfo: PairingInfo) async -> Bool {
        startPairingModeCalled(pairingInfo)
        spyStartPairingModeInfo = pairingInfo
        return stubStartPairingMode
    }

    var syncCodeEnteredCalled: (String, Bool, SyncCodeSource) -> Void = { _, _, _ in }
    var spySyncCodeEnteredCode: String?
    var spySyncCodeEnteredCanScanURLBarcodes: Bool?
    var spySyncCodeEnteredCodeSource: SyncCodeSource?
    var stubSyncCodeEntered: Bool = true
    func syncCodeEntered(code: String, canScanURLBarcodes: Bool, codeSource: SyncCodeSource) async -> Bool {
        spySyncCodeEnteredCode = code
        spySyncCodeEnteredCanScanURLBarcodes = canScanURLBarcodes
        spySyncCodeEnteredCodeSource = codeSource
        syncCodeEnteredCalled(code, canScanURLBarcodes, codeSource)
        return stubSyncCodeEntered
    }

    var loginAndShowDeviceConnectedCalled: (SyncCode.RecoveryKey, Bool) -> Void = { _, _ in }
    var spyLoginAndShowDeviceConnectedRecoveryKey: SyncCode.RecoveryKey?
    var spyLoginAndShowDeviceConnectedIsRecovery: Bool?
    var stubLoginAndShowDeviceConnectedError: Error?
    func loginAndShowDeviceConnected(recoveryKey: SyncCode.RecoveryKey, isRecovery: Bool) async throws {
        loginAndShowDeviceConnectedCalled(recoveryKey, isRecovery)
        spyLoginAndShowDeviceConnectedRecoveryKey = recoveryKey
        spyLoginAndShowDeviceConnectedIsRecovery = isRecovery
        if let error = stubLoginAndShowDeviceConnectedError {
            throw error
        }
    }
}

extension SyncAccount {
    static var mock: SyncAccount {
        SyncAccount(
            deviceId: "deviceId",
            deviceName: "deviceName",
            deviceType: "deviceType",
            userId: "userId",
            primaryKey: "primaryKey".data(using: .utf8)!,
            secretKey: "secretKey".data(using: .utf8)!,
            token: "token",
            state: .active
        )
    }
}

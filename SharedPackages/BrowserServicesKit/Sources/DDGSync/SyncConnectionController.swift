//
//  SyncConnectionController.swift
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

import Foundation
import BrowserServicesKit

@MainActor
public protocol SyncConnectionControllerDelegate: AnyObject {
    func controllerWillBeginTransmittingRecoveryKey() async
    func controllerDidFinishTransmittingRecoveryKey()

    func controllerDidReceiveRecoveryKey()

    func controllerDidRecognizeScannedCode() async

    func controllerDidCreateSyncAccount()
    func controllerDidCompleteAccountConnection(shouldShowSyncEnabled: Bool)

    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool)

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey) async

    func controllerDidError(_ error: SyncConnectionError, underlyingError: Error?)
}

public enum SyncConnectionError: Error {
    case unableToRecognizeCode

    case failedToFetchPublicKey
    case failedToTransmitExchangeRecoveryKey
    case failedToFetchConnectRecoveryKey
    case failedToLogIn

    case failedToTransmitExchangeKey
    case failedToFetchExchangeRecoveryKey

    case failedToCreateAccount
    case failedToTransmitConnectRecoveryKey
}

public protocol SyncConnectionControlling {
    /**
     Returns a device ID, public key and secret key ready for display and allows callers attempt to fetch the transmitted public key
     */
    func startExchangeMode()  async throws -> PairingInfo

    /**
     Returns a device id and temporary secret key ready for display and allows callers attempt to fetch the transmitted recovery key.
     */
    func startConnectMode() async throws -> PairingInfo

    /**
     Cancels any in-flight connection flows
     */
    func cancel() async

    @discardableResult
    func startPairingMode(_ pairingInfo: PairingInfo) async -> Bool

    /**
     Handles a scanned or pasted key and starts excange, recovery or connect flow
     */
    @discardableResult
    func syncCodeEntered(code: String, canScanURLBarcodes: Bool) async -> Bool

    /**
     Logs in to an existing account using a recovery key.
     */
    func loginAndShowDeviceConnected(recoveryKey: SyncCode.RecoveryKey, isRecovery: Bool) async throws
}

public actor SyncConnectionController: SyncConnectionControlling {
    private let deviceName: String
    private let deviceType: String
    private let syncService: DDGSyncing
    private let dependencies: SyncDependencies

    weak var delegate: SyncConnectionControllerDelegate?

    private var exchanger: RemoteKeyExchanging?
    private var connector: RemoteConnecting?
    private var isCodeHandlingInFlight: Bool = false

    private var recoveryCode: String {
        guard let code = syncService.account?.recoveryCode else {
            return ""
        }

        return code
    }

    init(deviceName: String, deviceType: String, delegate: SyncConnectionControllerDelegate? = nil, syncService: DDGSyncing, dependencies: SyncDependencies) {
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.syncService = syncService
        self.delegate = delegate
        self.dependencies = dependencies
    }

    public func startExchangeMode() throws -> PairingInfo {
        let exchanger = try remoteExchange()
        self.exchanger = exchanger
        startExchangePolling()
        let pairingInfo = PairingInfo(base64Code: exchanger.code, deviceName: deviceName)
        return pairingInfo
    }

    public func startConnectMode() throws -> PairingInfo {
        let connector = try remoteConnect()
        self.connector = connector
        self.startConnectPolling()
        let pairingInfo = PairingInfo(base64Code: connector.code, deviceName: deviceName)
        return pairingInfo
    }

    public func cancel() {
        isCodeHandlingInFlight = false
        stopConnectMode()
        stopExchangeMode()
    }

    @discardableResult
    public func startPairingMode(_ pairingInfo: PairingInfo) async -> Bool {
        let syncCode: SyncCode
        do {
            syncCode = try SyncCode.decodeBase64String(pairingInfo.base64Code)
        } catch {
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: error)
            return false
        }

        await delegate?.controllerDidRecognizeScannedCode()

        if let exchangeKey = syncCode.exchangeKey {
            return await handleExchangeKey(exchangeKey)
        } else if let connectKey = syncCode.connect {
            return await handleConnectKey(connectKey)
        } else {
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: nil)
            return false
        }
    }

    @discardableResult
    public func syncCodeEntered(code: String, canScanURLBarcodes: Bool = true) async -> Bool {
        guard !isCodeHandlingInFlight else {
            return false
        }
        isCodeHandlingInFlight = true
        defer {
            isCodeHandlingInFlight = false
        }

        let syncCode: SyncCode
        do {
            if canScanURLBarcodes, let url = URL(string: code), let pairingInfo = PairingInfo(url: url) {
                return await startPairingMode(pairingInfo)
            } else {
                syncCode = try SyncCode.decodeBase64String(code)
            }
        } catch {
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: error)
            return false
        }

        await delegate?.controllerDidRecognizeScannedCode()

        if let exchangeKey = syncCode.exchangeKey {
            return await handleExchangeKey(exchangeKey)
        } else if let recoveryKey = syncCode.recovery {
            return await handleRecoveryKey(recoveryKey, isRecovery: true)
        } else if let connectKey = syncCode.connect {
            return await handleConnectKey(connectKey)
        } else {
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: nil)
            return false
        }
    }

    public func loginAndShowDeviceConnected(recoveryKey: SyncCode.RecoveryKey, isRecovery: Bool) async throws {
        let registeredDevices = try await syncService.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
        await delegate?.controllerDidCompleteLogin(registeredDevices: registeredDevices, isRecovery: isRecovery)
    }

    private func remoteConnect() throws -> RemoteConnecting {
        try dependencies.createRemoteConnector()
    }

    private func remoteExchange() throws -> RemoteKeyExchanging {
        try dependencies.createRemoteKeyExchanger()
    }

    private func startExchangePolling() {
        Task { @MainActor in
            let exchangeMessage: ExchangeMessage
            do {
                guard let message = try await exchanger?.pollForPublicKey() else {
                    // Polling likely cancelled
                    return
                }
                exchangeMessage = message
            } catch {
                await delegate?.controllerDidError(.failedToFetchPublicKey, underlyingError: error)
                return
            }

            await delegate?.controllerWillBeginTransmittingRecoveryKey()
            do {
                try await syncService.transmitExchangeRecoveryKey(for: exchangeMessage)
            } catch {
                await delegate?.controllerDidError(.failedToTransmitExchangeRecoveryKey, underlyingError: error)
            }

            await delegate?.controllerDidFinishTransmittingRecoveryKey()
            await exchanger?.stopPolling()
        }
    }

    private func startConnectPolling() {
        Task { @MainActor in
            let recoveryKey: SyncCode.RecoveryKey
            do {
                guard let key = try await connector?.pollForRecoveryKey() else {
                    // Polling likely cancelled
                    return
                }
                recoveryKey = key
            } catch {
                await delegate?.controllerDidError(.failedToFetchConnectRecoveryKey, underlyingError: error)
                return
            }

            await delegate?.controllerDidReceiveRecoveryKey()

            do {
                try await loginAndShowDeviceConnected(recoveryKey: recoveryKey, isRecovery: false)
            } catch {
                await delegate?.controllerDidError(.failedToLogIn, underlyingError: error)
            }
        }
    }

    private func handleExchangeKey(_ exchangeKey: SyncCode.ExchangeKey) async -> Bool {
        let exchangeInfo: ExchangeInfo
        do {
            exchangeInfo = try await self.syncService.transmitGeneratedExchangeInfo(exchangeKey, deviceName: deviceName)
        } catch {
            await delegate?.controllerDidError(.failedToTransmitExchangeKey, underlyingError: error)
            return false
        }

        do {
            guard let recoveryKey = try await self.remoteExchangeRecoverer(exchangeInfo: exchangeInfo).pollForRecoveryKey() else {
                // Polling likelly cancelled.
                return false
            }
            return await handleRecoveryKey(recoveryKey, isRecovery: false)
        } catch {
            await delegate?.controllerDidError(.failedToFetchExchangeRecoveryKey, underlyingError: error)
            return false
        }
    }

    private func remoteExchangeRecoverer(exchangeInfo: ExchangeInfo) throws -> RemoteExchangeRecovering {
        return try dependencies.createRemoteExchangeRecoverer(exchangeInfo)
    }

    private func handleRecoveryKey(_ recoveryKey: SyncCode.RecoveryKey, isRecovery: Bool) async -> Bool {
        do {
            try await loginAndShowDeviceConnected(recoveryKey: recoveryKey, isRecovery: isRecovery)
            return true
        } catch {
            await handleRecoveryCodeLoginError(recoveryKey: recoveryKey, error: error)
            return false
        }
    }

    private func handleConnectKey(_ connectKey: SyncCode.ConnectCode) async -> Bool {
        var shouldShowSyncEnabled = true

        if syncService.account == nil {
            do {
                try await syncService.createAccount(deviceName: deviceName, deviceType: deviceType)
                await delegate?.controllerDidCreateSyncAccount()
                shouldShowSyncEnabled = false
            } catch {
                Task {
                    await delegate?.controllerDidError(.failedToCreateAccount, underlyingError: error)
                }
                return false
            }
        }
        do {
            try await syncService.transmitRecoveryKey(connectKey)
            await delegate?.controllerDidCompleteAccountConnection(shouldShowSyncEnabled: shouldShowSyncEnabled)
        } catch {
            await delegate?.controllerDidError(.failedToTransmitConnectRecoveryKey, underlyingError: error)
            return false
        }

        return true
    }

    private func stopConnectMode() {
        self.connector?.stopPolling()
        self.connector = nil
    }

    private func stopExchangeMode() {
        exchanger?.stopPolling()
        exchanger = nil
    }

    private func handleRecoveryCodeLoginError(recoveryKey: SyncCode.RecoveryKey, error: Error) async {
        if syncService.account != nil {
            await delegate?.controllerDidFindTwoAccountsDuringRecovery(recoveryKey)
        } else {
            await delegate?.controllerDidError(.failedToLogIn, underlyingError: error)
        }
    }
}

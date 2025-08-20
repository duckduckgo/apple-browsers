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

    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource) async

    func controllerDidCreateSyncAccount()
    func controllerDidCompleteAccountConnection(shouldShowSyncEnabled: Bool, setupSource: SyncSetupSource, codeSource: SyncCodeSource)

    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool, setupRole: SyncSetupRole)

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey, setupRole: SyncSetupRole) async

    func controllerDidError(_ error: SyncConnectionError, underlyingError: Error?, setupRole: SyncSetupRole) async
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

    case pollingForRecoveryKeyTimedOut
}

public protocol SyncConnectionControlling {
    /**
     Returns a device ID, public key and secret key ready for display and allows callers attempt to fetch the transmitted public key
     */
    func startExchangeMode() async throws -> PairingInfo

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
    func syncCodeEntered(code: String, canScanURLBarcodes: Bool, codeSource: SyncCodeSource) async -> Bool
}

private actor SyncConnectionState {
    private var _isCodeHandlingInFlight: Bool = false
    private var _exchanger: RemoteKeyExchanging?
    private var _connector: RemoteConnecting?

    func setCodeHandlingInFlight(_ value: Bool) {
        _isCodeHandlingInFlight = value
    }

    func isCodeHandlingInFlight() -> Bool {
        return _isCodeHandlingInFlight
    }

    func setExchanger(_ exchanger: RemoteKeyExchanging?) {
        _exchanger = exchanger
    }

    func getExchanger() -> RemoteKeyExchanging? {
        return _exchanger
    }

    func setConnector(_ connector: RemoteConnecting?) {
        _connector = connector
    }

    func getConnector() -> RemoteConnecting? {
        return _connector
    }

    func stopConnectMode() {
        _connector?.stopPolling()
        _connector = nil
    }

    func stopExchangeMode() {
        _exchanger?.stopPolling()
        _exchanger = nil
    }
}

public class SyncConnectionController: SyncConnectionControlling {
    private let deviceName: String
    private let deviceType: String
    private let syncService: DDGSyncing
    private let dependencies: SyncDependencies

    private weak var delegate: SyncConnectionControllerDelegate?

    private let state = SyncConnectionState()

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

    public func startExchangeMode() async throws -> PairingInfo {
        let exchanger = try remoteExchange()
        await state.setExchanger(exchanger)
        startExchangePolling()
        let pairingInfo = PairingInfo(base64Code: exchanger.code, deviceName: deviceName)
        return pairingInfo
    }

    public func startConnectMode() async throws -> PairingInfo {
        let connector = try remoteConnect()
        await state.setConnector(connector)
        self.startConnectPolling()
        let pairingInfo = PairingInfo(base64Code: connector.code, deviceName: deviceName)
        return pairingInfo
    }

    public func cancel() async {
        await state.setCodeHandlingInFlight(false)
        await state.stopConnectMode()
        await state.stopExchangeMode()
    }

    @discardableResult
    public func startPairingMode(_ pairingInfo: PairingInfo) async -> Bool {
        let syncCodeSource = SyncCodeSource.deepLink
        return await startPairingMode(pairingInfo, codeSource: syncCodeSource)
    }

    private func startPairingMode(_ pairingInfo: PairingInfo, codeSource: SyncCodeSource) async -> Bool {
        let syncCode: SyncCode
        do {
            syncCode = try SyncCode.decodeBase64String(pairingInfo.base64Code)
        } catch {
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: error, setupRole: .receiver(.unknown, codeSource))
            return false
        }

        if let exchangeKey = syncCode.exchangeKey {
            await delegate?.controllerDidRecognizeCode(setupSource: .exchange, codeSource: codeSource)
            return await handleExchangeKey(exchangeKey, codeSource: codeSource)
        } else if let connectKey = syncCode.connect {
            await delegate?.controllerDidRecognizeCode(setupSource: .connect, codeSource: codeSource)
            return await handleConnectKey(connectKey, codeSource: codeSource)
        } else {
            await delegate?.controllerDidRecognizeCode(setupSource: .recovery, codeSource: codeSource)
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: nil, setupRole: .receiver(.unknown, codeSource))
            return false
        }
    }

    @discardableResult
    public func syncCodeEntered(code: String, canScanURLBarcodes: Bool, codeSource: SyncCodeSource) async -> Bool {
        guard !(await state.isCodeHandlingInFlight()) else {
            return false
        }
        await state.setCodeHandlingInFlight(true)
        defer {
            Task {
                await state.setCodeHandlingInFlight(false)
            }
        }

        let syncCode: SyncCode
        do {
            if canScanURLBarcodes, let url = URL(string: code), let pairingInfo = PairingInfo(url: url) {
                return await startPairingMode(pairingInfo, codeSource: codeSource)
            } else {
                syncCode = try SyncCode.decodeBase64String(code)
            }
        } catch {
            // Very important that this returning blocks further execution as it could be a camera scanning continuously
            // and therefore call this multiple times.
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: error, setupRole: .receiver(.unknown, codeSource))
            return false
        }

        if let exchangeKey = syncCode.exchangeKey {
            await delegate?.controllerDidRecognizeCode(setupSource: .exchange, codeSource: codeSource)
            return await handleExchangeKey(exchangeKey, codeSource: codeSource)
        } else if let recoveryKey = syncCode.recovery {
            await delegate?.controllerDidRecognizeCode(setupSource: .recovery, codeSource: codeSource)
            return await handleRecoveryKey(recoveryKey, isRecovery: true, setupRole: .receiver(.recovery, codeSource))
        } else if let connectKey = syncCode.connect {
            await delegate?.controllerDidRecognizeCode(setupSource: .connect, codeSource: codeSource)
            return await handleConnectKey(connectKey, codeSource: codeSource)
        } else {
            // We shouldn't ever really reach this point
            assertionFailure("Shouldn't be able to parse SyncCode without any of the supported keys")
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: nil, setupRole: .receiver(.unknown, codeSource))
            return false
        }
    }

    func loginAndShowDeviceConnected(recoveryKey: SyncCode.RecoveryKey, isRecovery: Bool, setupRole: SyncSetupRole) async throws {
        let registeredDevices = try await syncService.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
        await delegate?.controllerDidCompleteLogin(registeredDevices: registeredDevices, isRecovery: isRecovery, setupRole: setupRole)
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
                guard let message = try await (await state.getExchanger())?.pollForPublicKey() else {
                    // Polling likely cancelled
                    return
                }
                exchangeMessage = message
            } catch {
                await delegate?.controllerDidError(.failedToFetchPublicKey, underlyingError: error, setupRole: .sharer)
                return
            }

            await delegate?.controllerWillBeginTransmittingRecoveryKey()
            do {
                try await syncService.transmitExchangeRecoveryKey(for: exchangeMessage)
            } catch {
                await delegate?.controllerDidError(.failedToTransmitExchangeRecoveryKey, underlyingError: error, setupRole: .sharer)
            }

            delegate?.controllerDidFinishTransmittingRecoveryKey()
            (await state.getExchanger())?.stopPolling()
        }
    }

    private func startConnectPolling() {
        Task { @MainActor in
            let recoveryKey: SyncCode.RecoveryKey
            do {
                guard let key = try await (await state.getConnector())?.pollForRecoveryKey() else {
                    // Polling likely cancelled
                    return
                }
                recoveryKey = key
            } catch {
                await delegate?.controllerDidError(.failedToFetchConnectRecoveryKey, underlyingError: error, setupRole: .sharer)
                return
            }

            delegate?.controllerDidReceiveRecoveryKey()

            do {
                try await loginAndShowDeviceConnected(recoveryKey: recoveryKey, isRecovery: false, setupRole: .sharer)
            } catch {
                await delegate?.controllerDidError(.failedToLogIn, underlyingError: error, setupRole: .sharer)
            }
        }
    }

    private func handleExchangeKey(_ exchangeKey: SyncCode.ExchangeKey, codeSource: SyncCodeSource) async -> Bool {
        let exchangeInfo: ExchangeInfo
        let setupRole: SyncSetupRole = .receiver(.exchange, codeSource)
        do {
            exchangeInfo = try await self.syncService.transmitGeneratedExchangeInfo(exchangeKey, deviceName: deviceName)
        } catch {
            await delegate?.controllerDidError(.failedToTransmitExchangeKey, underlyingError: error, setupRole: setupRole)
            return false
        }

        do {
            guard let recoveryKey = try await self.remoteExchangeRecoverer(exchangeInfo: exchangeInfo).pollForRecoveryKey() else {
                // Polling likelly cancelled.
                return false
            }
            return await handleRecoveryKey(recoveryKey, isRecovery: false, setupRole: setupRole)
        } catch SyncError.pollingDidTimeOut {
            await delegate?.controllerDidError(.pollingForRecoveryKeyTimedOut, underlyingError: nil, setupRole: setupRole)
            return false
        } catch {
            await delegate?.controllerDidError(.failedToFetchExchangeRecoveryKey, underlyingError: error, setupRole: setupRole)
            return false
        }
    }

    private func remoteExchangeRecoverer(exchangeInfo: ExchangeInfo) throws -> RemoteExchangeRecovering {
        return try dependencies.createRemoteExchangeRecoverer(exchangeInfo)
    }

    private func handleRecoveryKey(_ recoveryKey: SyncCode.RecoveryKey, isRecovery: Bool, setupRole: SyncSetupRole) async -> Bool {
        do {
            try await loginAndShowDeviceConnected(recoveryKey: recoveryKey, isRecovery: isRecovery, setupRole: setupRole)
            return true
        } catch {
            await handleRecoveryCodeLoginError(recoveryKey: recoveryKey, error: error, setupRole: setupRole)
            return false
        }
    }

    private func handleConnectKey(_ connectKey: SyncCode.ConnectCode, codeSource: SyncCodeSource) async -> Bool {
        var shouldShowSyncEnabled = true

        if syncService.account == nil {
            do {
                try await syncService.createAccount(deviceName: deviceName, deviceType: deviceType)
                await delegate?.controllerDidCreateSyncAccount()
                shouldShowSyncEnabled = false
            } catch {
                Task {
                    await delegate?.controllerDidError(.failedToCreateAccount, underlyingError: error, setupRole: .receiver(.connect, codeSource))
                }
                return false
            }
        }
        do {
            try await syncService.transmitRecoveryKey(connectKey)
            await delegate?.controllerDidCompleteAccountConnection(shouldShowSyncEnabled: shouldShowSyncEnabled, setupSource: .connect, codeSource: codeSource)
        } catch {
            await delegate?.controllerDidError(.failedToTransmitConnectRecoveryKey, underlyingError: error, setupRole: .receiver(.connect, codeSource))
            return false
        }

        return true
    }

    private func handleRecoveryCodeLoginError(recoveryKey: SyncCode.RecoveryKey, error: Error, setupRole: SyncSetupRole) async {
        if syncService.account != nil {
            await delegate?.controllerDidFindTwoAccountsDuringRecovery(recoveryKey, setupRole: setupRole)
        } else {
            await delegate?.controllerDidError(.failedToLogIn, underlyingError: error, setupRole: setupRole)
        }
    }
}

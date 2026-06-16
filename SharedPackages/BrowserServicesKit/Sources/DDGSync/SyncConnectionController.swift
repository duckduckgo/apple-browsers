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

@MainActor
public protocol SyncConnectionControllerDelegate: AnyObject {
    func controllerWillBeginTransmittingRecoveryKey() async
    func controllerDidFinishTransmittingRecoveryKey(shouldWaitForDevicesToChange: Bool)

    func controllerDidReceiveRecoveryKey()

    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource) async

    func controllerWillPerformServerSyncOperation(setupRole: SyncSetupRole) async -> Bool
    func controllerShouldAllowPairingV2PeerToJoin(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool
    func controllerShouldJoinPairingV2Peer(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool

    func controllerDidCreateSyncAccount(shouldShowSyncEnabled: Bool)
    func controllerDidCompleteAccountConnection(shouldShowSyncEnabled: Bool, setupSource: SyncSetupSource, codeSource: SyncCodeSource)

    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool, setupRole: SyncSetupRole)
    func controllerDidCompletePairingWithAlreadyConnectedAccount(setupRole: SyncSetupRole)

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey,
                                                    setupRole: SyncSetupRole,
                                                    shouldPromptBeforeSwitchingAccounts: Bool) async

    func controllerDidError(_ error: SyncConnectionError, underlyingError: Error?, setupRole: SyncSetupRole) async
}

public enum SyncConnectionError: Error {
    case unableToRecognizeCode
    case updateRequired
    case unsupportedThirdPartyRecoveryCode
    case thirdPartyAccountAlreadyUpgraded
    case syncCancelledFromOtherDevice

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
    func syncCodeEntered(code: String, canScanLegacyURLBarcodes: Bool, codeSource: SyncCodeSource) async -> Bool
}

private actor SyncConnectionState {
    private var _isCodeHandlingInFlight: Bool = false
    private var _exchanger: RemoteKeyExchanging?
    private var _connector: RemoteConnecting?
    private var _pairingV2Coordinator: PairingV2Coordinator?
    private var _pairingV2PresenterPollingTask: Task<Void, Never>?

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

    func replacePairingV2Coordinator(with coordinator: PairingV2Coordinator) async {
        await cancelPairingV2()
        _pairingV2Coordinator = coordinator
    }

    func setPairingV2PresenterPollingTask(_ task: Task<Void, Never>, for coordinator: PairingV2Coordinator) {
        guard _pairingV2Coordinator === coordinator else {
            task.cancel()
            return
        }

        _pairingV2PresenterPollingTask?.cancel()
        _pairingV2PresenterPollingTask = task
    }

    func isActivePairingV2Coordinator(_ coordinator: PairingV2Coordinator) -> Bool {
        _pairingV2Coordinator === coordinator
    }

    func clearPairingV2Coordinator(_ coordinator: PairingV2Coordinator) {
        guard _pairingV2Coordinator === coordinator else {
            return
        }
        _pairingV2PresenterPollingTask = nil
        _pairingV2Coordinator = nil
    }

    func stopConnectMode() {
        _connector?.stopPolling()
        _connector = nil
    }

    func stopExchangeMode() {
        _exchanger?.stopPolling()
        _exchanger = nil
    }

    func cancelPairingV2() async {
        let coordinator = _pairingV2Coordinator
        _pairingV2Coordinator = nil
        _pairingV2PresenterPollingTask?.cancel()
        _pairingV2PresenterPollingTask = nil

        await coordinator?.cancel()
    }

    func prepareForNewFlow() async {
        stopConnectMode()
        stopExchangeMode()
        await cancelPairingV2()
    }
}

public class SyncConnectionController: SyncConnectionControlling {
    private static let pairingURLBase = URL(string: "https://duckduckgo.com")!

    private let deviceName: String
    private let deviceType: String
    private let syncService: DDGSyncing
    private let dependencies: SyncDependencies
    private let pairingV2PollingTimeout: TimeInterval
    private let pairingV2PollIntervalNanoseconds: UInt64

    private weak var delegate: SyncConnectionControllerDelegate?

    private let state = SyncConnectionState()

    private var isPairingV2PresentationEnabled: Bool {
        isPairingV2ScanningEnabled && dependencies.syncFeatureFlags.isPairingV2CodeEnabled()
    }

    private var isPairingV2ScanningEnabled: Bool {
        dependencies.syncFeatureFlags.isPairingV2ScanningEnabled()
    }

    init(deviceName: String,
         deviceType: String,
         delegate: SyncConnectionControllerDelegate? = nil,
         syncService: DDGSyncing,
         dependencies: SyncDependencies,
         pairingV2PollingTimeout: TimeInterval = PairingV2PollingDefaults.sessionTimeout,
         pairingV2PollIntervalNanoseconds: UInt64 = PairingV2PollingDefaults.pollIntervalNanoseconds) {
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.syncService = syncService
        self.delegate = delegate
        self.dependencies = dependencies
        self.pairingV2PollingTimeout = pairingV2PollingTimeout
        self.pairingV2PollIntervalNanoseconds = pairingV2PollIntervalNanoseconds
    }

    public func startExchangeMode() async throws -> PairingInfo {
        guard !isPairingV2PresentationEnabled else {
            return try await startPairingV2PresenterMode()
        }

        await state.prepareForNewFlow()
        let exchanger = try remoteExchange()
        await state.setExchanger(exchanger)
        startExchangePolling()
        let pairingInfo = PairingInfo(base64Code: exchanger.code, deviceName: deviceName)
        return pairingInfo
    }

    public func startConnectMode() async throws -> PairingInfo {
        guard !isPairingV2PresentationEnabled else {
            return try await startPairingV2PresenterMode()
        }

        await state.prepareForNewFlow()
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
        await state.cancelPairingV2()
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
            await delegate?.controllerDidError(syncCodeDecodingConnectionError(for: error), underlyingError: error, setupRole: .receiver(.unknown, codeSource))
            return false
        }

        if let exchangeKey = syncCode.exchangeKey {
            let setupRole: SyncSetupRole = .receiver(.exchange, codeSource)
            await delegate?.controllerDidRecognizeCode(setupSource: .exchange, codeSource: codeSource)
            guard await shouldContinueServerSyncOperation(setupRole: setupRole) else {
                return false
            }
            await state.prepareForNewFlow()
            return await handleExchangeKey(exchangeKey, codeSource: codeSource)
        } else if let connectKey = syncCode.connect {
            let setupRole: SyncSetupRole = .receiver(.connect, codeSource)
            await delegate?.controllerDidRecognizeCode(setupSource: .connect, codeSource: codeSource)
            guard await shouldContinueServerSyncOperation(setupRole: setupRole) else {
                return false
            }
            await state.prepareForNewFlow()
            return await handleConnectKey(connectKey, codeSource: codeSource)
        } else {
            await delegate?.controllerDidRecognizeCode(setupSource: .recovery, codeSource: codeSource)
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: nil, setupRole: .receiver(.unknown, codeSource))
            return false
        }
    }

    @discardableResult
    public func syncCodeEntered(code: String, canScanLegacyURLBarcodes: Bool, codeSource: SyncCodeSource) async -> Bool {
        guard !(await state.isCodeHandlingInFlight()) else {
            return false
        }
        await state.setCodeHandlingInFlight(true)
        defer {
            Task {
                await state.setCodeHandlingInFlight(false)
            }
        }

        if let result = await handleURLCode(code, canScanLegacyURLBarcodes: canScanLegacyURLBarcodes, codeSource: codeSource) {
            return result
        }

        do {
            let syncCode = try SyncCode.decodeBase64String(code)
            return await handleDecodedSyncCode(syncCode, codeSource: codeSource)
        } catch {
            // Very important that this returning blocks further execution as it could be a camera scanning continuously
            // and therefore call this multiple times.
            await delegate?.controllerDidError(syncCodeDecodingConnectionError(for: error), underlyingError: error, setupRole: .receiver(.unknown, codeSource))
            return false
        }
    }

    private func handleURLCode(_ code: String, canScanLegacyURLBarcodes: Bool, codeSource: SyncCodeSource) async -> Bool? {
        guard let url = URL(string: code) else {
            return nil
        }

        if let pairingV2Payload = PairingV2QRCodePayload(url: url) {
            return await handlePairingV2(qrPayload: pairingV2Payload, codeSource: codeSource)
        }

        if let unsupportedVersion = PairingV2QRCodePayload.unsupportedMajorVersion(in: url) {
            return await handleUnsupportedPairingV2Version(unsupportedVersion, codeSource: codeSource)
        }

        guard canScanLegacyURLBarcodes, let pairingInfo = PairingInfo(url: url) else {
            return nil
        }

        return await startPairingMode(pairingInfo, codeSource: codeSource)
    }

    private func handleUnsupportedPairingV2Version(_ unsupportedVersion: String, codeSource: SyncCodeSource) async -> Bool {
        let setupRole: SyncSetupRole = .receiver(.exchange, codeSource)
        guard isPairingV2ScanningEnabled else {
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: nil, setupRole: setupRole)
            return false
        }

        await delegate?.controllerDidError(.updateRequired, underlyingError: PairingV2Error.unsupportedVersion(unsupportedVersion), setupRole: setupRole)
        return false
    }

    private func handleDecodedSyncCode(_ syncCode: SyncCode, codeSource: SyncCodeSource) async -> Bool {
        if let exchangeKey = syncCode.exchangeKey {
            let setupRole: SyncSetupRole = .receiver(.exchange, codeSource)
            await delegate?.controllerDidRecognizeCode(setupSource: .exchange, codeSource: codeSource)
            guard await shouldContinueServerSyncOperation(setupRole: setupRole) else {
                return false
            }
            await state.prepareForNewFlow()
            return await handleExchangeKey(exchangeKey, codeSource: codeSource)
        } else if let recovery = syncCode.recovery {
            return await handleRecoveryCode(recovery, codeSource: codeSource)
        } else if let connectKey = syncCode.connect {
            let setupRole: SyncSetupRole = .receiver(.connect, codeSource)
            await delegate?.controllerDidRecognizeCode(setupSource: .connect, codeSource: codeSource)
            guard await shouldContinueServerSyncOperation(setupRole: setupRole) else {
                return false
            }
            await state.prepareForNewFlow()
            return await handleConnectKey(connectKey, codeSource: codeSource)
        } else {
            // We shouldn't ever really reach this point
            assertionFailure("Shouldn't be able to parse SyncCode without any of the supported keys")
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: nil, setupRole: .receiver(.unknown, codeSource))
            return false
        }
    }

    private func startPairingV2PresenterMode() async throws -> PairingInfo {
        await state.prepareForNewFlow()
        let coordinator = makePairingV2Coordinator()
        let payload = try await coordinator.startPresenting()
        let url: URL
        do {
            url = try payload.toURL(baseURL: Self.pairingURLBase)
        } catch {
            await coordinator.cancel()
            throw error
        }

        await state.replacePairingV2Coordinator(with: coordinator)
        startPairingV2PresenterPolling(coordinator)

        return PairingInfo(pairingV2URL: url, deviceName: deviceName)
    }

    private func handlePairingV2(qrPayload: PairingV2QRCodePayload, codeSource: SyncCodeSource) async -> Bool {
        let setupRole: SyncSetupRole = .receiver(.exchange, codeSource)
        guard isPairingV2ScanningEnabled else {
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: nil, setupRole: setupRole)
            return false
        }
        await delegate?.controllerDidRecognizeCode(setupSource: .exchange, codeSource: codeSource)
        guard await shouldContinueServerSyncOperation(setupRole: setupRole) else {
            return false
        }

        await state.prepareForNewFlow()
        let coordinator = makePairingV2Coordinator()
        await state.replacePairingV2Coordinator(with: coordinator)
        defer {
            Task {
                await self.state.clearPairingV2Coordinator(coordinator)
            }
        }

        do {
            try await coordinator.startScanning(qrPayload: qrPayload)
            let completion = try await pollPairingV2UntilFinished(coordinator)
            await handlePairingV2Completion(completion, coordinator: coordinator, setupRole: setupRole)
            return true
        } catch {
            await handlePairingV2PollingError(error, coordinator: coordinator, setupRole: setupRole)
            return false
        }
    }

    private func startPairingV2PresenterPolling(_ coordinator: PairingV2Coordinator) {
        let task = Task { @MainActor in
            defer {
                Task {
                    await self.state.clearPairingV2Coordinator(coordinator)
                }
            }

            let setupRole = SyncSetupRole.sharer
            var didNotifyPeerConnected = false
            do {
                let completion = try await pollPairingV2UntilFinished(coordinator) { state in
                    guard !didNotifyPeerConnected && self.shouldDismissPairingV2PresenterCode(for: state) else {
                        return
                    }
                    didNotifyPeerConnected = true
                    await self.delegate?.controllerWillBeginTransmittingRecoveryKey()
                }
                await handlePairingV2Completion(completion, coordinator: coordinator, setupRole: setupRole)
            } catch {
                await handlePairingV2PollingError(error, coordinator: coordinator, setupRole: setupRole)
            }
        }

        Task {
            await state.setPairingV2PresenterPollingTask(task, for: coordinator)
        }
    }

    private func handlePairingV2PollingError(_ error: Error, coordinator: PairingV2Coordinator, setupRole: SyncSetupRole) async {
        if let pairingV2Error = error as? PairingV2Error, pairingV2Error == .cancelled {
            return
        }

        guard await state.isActivePairingV2Coordinator(coordinator) else {
            return
        }

        if let syncError = error as? SyncError {
            await handlePairingV2SyncError(syncError, coordinator: coordinator, setupRole: setupRole)
        } else if let pairingV2Error = error as? PairingV2Error {
            await delegate?.controllerDidError(pairingV2ConnectionError(for: pairingV2Error), underlyingError: nil, setupRole: setupRole)
        } else if let cryptoError = error as? PairingV2MessageCryptoError {
            await delegate?.controllerDidError(pairingV2CryptoConnectionError(for: cryptoError), underlyingError: cryptoError, setupRole: setupRole)
        } else {
            await delegate?.controllerDidError(.failedToFetchExchangeRecoveryKey, underlyingError: error, setupRole: setupRole)
        }

        await coordinator.cancel()
    }

    private func handlePairingV2SyncError(_ error: SyncError, coordinator: PairingV2Coordinator, setupRole: SyncSetupRole) async {
        switch error {
        case .pollingDidTimeOut:
            await delegate?.controllerDidError(.pollingForRecoveryKeyTimedOut, underlyingError: nil, setupRole: setupRole)
        case .accountAlreadyExists:
            await handlePairingV2AccountAlreadyExists(coordinator, setupRole: setupRole)
        default:
            await delegate?.controllerDidError(.failedToFetchExchangeRecoveryKey, underlyingError: error, setupRole: setupRole)
        }
    }

    private func handlePairingV2AccountAlreadyExists(_ coordinator: PairingV2Coordinator, setupRole: SyncSetupRole) async {
        if let recoveryKey = coordinator.pendingRecoveryKey {
            await delegate?.controllerDidFindTwoAccountsDuringRecovery(
                recoveryKey,
                setupRole: setupRole,
                shouldPromptBeforeSwitchingAccounts: false)
        } else {
            await delegate?.controllerDidError(.failedToLogIn, underlyingError: SyncError.accountAlreadyExists, setupRole: setupRole)
        }
    }

    private func pairingV2CryptoConnectionError(for error: PairingV2MessageCryptoError) -> SyncConnectionError {
        switch error {
        case .unsupportedVersion(let version):
            return unsupportedVersionConnectionError(for: version, supportedMajor: PairingV2ProtocolVersion.supportedMajor)
        default:
            return .unableToRecognizeCode
        }
    }

    private func pollPairingV2UntilFinished(_ coordinator: PairingV2Coordinator,
                                            onDidPoll: ((PairingV2State) async -> Void)? = nil) async throws -> PairingV2State.Completion {
        try await coordinator.pollUntilFinished(
            timeout: pairingV2PollingTimeout,
            pollInterval: pairingV2PollIntervalNanoseconds,
            onDidPoll: onDidPoll)
    }

    private func handlePairingV2Completion(_ completion: PairingV2State.Completion,
                                           coordinator: PairingV2Coordinator,
                                           setupRole: SyncSetupRole) async {
        switch completion {
        case .loggedIn:
            await delegate?.controllerDidCompleteLogin(registeredDevices: coordinator.completedRegisteredDevices ?? [], isRecovery: false, setupRole: setupRole)
        case .recoveryCodeSent(let credentialKind):
            await delegate?.controllerDidFinishTransmittingRecoveryKey(shouldWaitForDevicesToChange: credentialKind == .ddg)
        case .alreadyConnected:
            await delegate?.controllerDidCompletePairingWithAlreadyConnectedAccount(setupRole: setupRole)
        }
    }

    private func shouldDismissPairingV2PresenterCode(for state: PairingV2State) -> Bool {
        switch state {
        case .waitingForPeerStatus,
             .hostWaitingForConfirmation,
             .hostPreparingRecoveryCode,
             .hostSendingRecoveryCode,
             .joinerWaitingForConfirmation,
             .joinerWaitingForRecoveryCode,
             .joinerLoggingIn:
            return true
        case .idle, .waitingForPeerHello, .completed, .failed:
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
                (await state.getExchanger())?.stopPolling()
                return
            }

            delegate?.controllerDidFinishTransmittingRecoveryKey(shouldWaitForDevicesToChange: true)
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

            guard await shouldContinueServerSyncOperation(setupRole: .sharer) else {
                return
            }

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

    private func handleRecoveryCode(_ recovery: SyncCode.Recovery, codeSource: SyncCodeSource) async -> Bool {
        let setupRole: SyncSetupRole = .receiver(.recovery, codeSource)

        if case .v2(let recoveryKey) = recovery {
            guard isPairingV2ScanningEnabled else {
                await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: nil, setupRole: setupRole)
                return false
            }
            guard recoveryKey.cid != SyncCode.RecoveryKeyV2.thirdPartyCredentialId else {
                await delegate?.controllerDidError(.unsupportedThirdPartyRecoveryCode, underlyingError: nil, setupRole: setupRole)
                return false
            }
        }

        let recoveryKey: SyncCode.RecoveryKey
        do {
            recoveryKey = try recovery.defaultCredentialRecoveryKey()
        } catch {
            await delegate?.controllerDidError(.unableToRecognizeCode, underlyingError: error, setupRole: .receiver(.unknown, codeSource))
            return false
        }

        await delegate?.controllerDidRecognizeCode(setupSource: .recovery, codeSource: codeSource)
        guard await shouldContinueServerSyncOperation(setupRole: setupRole) else {
            return false
        }
        await state.prepareForNewFlow()
        return await handleRecoveryKey(recoveryKey, isRecovery: true, setupRole: setupRole)
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
                await delegate?.controllerDidCreateSyncAccount(shouldShowSyncEnabled: true)
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
            await delegate?.controllerDidFindTwoAccountsDuringRecovery(
                recoveryKey,
                setupRole: setupRole,
                shouldPromptBeforeSwitchingAccounts: true)
        } else {
            await delegate?.controllerDidError(.failedToLogIn, underlyingError: error, setupRole: setupRole)
        }
    }

    private func shouldContinueServerSyncOperation(setupRole: SyncSetupRole) async -> Bool {
        await delegate?.controllerWillPerformServerSyncOperation(setupRole: setupRole) ?? true
    }

    private func makePairingV2Coordinator() -> PairingV2Coordinator {
        return PairingV2Coordinator(
            syncService: syncService,
            messageExchanger: dependencies.createPairingV2MessageExchanger(),
            deviceName: deviceName,
            deviceType: deviceType,
            flags: PairingV2RolloutFlags(isV2ScanningEnabled: isPairingV2ScanningEnabled,
                                         isV2CodeEnabled: isPairingV2PresentationEnabled),
            confirmationDelegate: self
        )
    }

    private func pairingV2ConnectionError(for error: PairingV2Error) -> SyncConnectionError {
        switch error {
        case .recoveryCodePreparationFailed, .recoveryCodeSendFailed:
            return .failedToTransmitExchangeRecoveryKey
        case .loginFailed:
            return .failedToLogIn
        case .nativeCredentialAlreadyPresent:
            return .thirdPartyAccountAlreadyUpgraded
        case .recoveryCodeDenied, .recoveryCodeUnavailable:
            return .syncCancelledFromOtherDevice
        case .unsupportedVersion(let version):
            return unsupportedVersionConnectionError(for: version, supportedMajor: PairingV2ProtocolVersion.supportedMajor)
        case .v2ScanningDisabled, .unknownCode, .unsupportedFlow:
            return .unableToRecognizeCode
        case .secondHello, .unexpectedEvent, .pairingSessionNotReady, .relayChannelUnavailable, .relayChannelExpired:
            return .failedToFetchExchangeRecoveryKey
        case .cancelled:
            return .syncCancelledFromOtherDevice
        }
    }

    private func syncCodeDecodingConnectionError(for error: Error) -> SyncConnectionError {
        guard let error = error as? SyncCode.RecoveryCodeVersionError,
              case .unsupported(let version) = error else {
            return .unableToRecognizeCode
        }
        guard isPairingV2ScanningEnabled else {
            return .unableToRecognizeCode
        }
        return unsupportedVersionConnectionError(for: version, supportedMajor: SyncCode.Recovery.supportedMajor)
    }

    private func unsupportedVersionConnectionError(for version: String, supportedMajor: Int) -> SyncConnectionError {
        guard let major = SyncProtocolVersion.parseMajor(version),
              major > supportedMajor else {
            return .unableToRecognizeCode
        }
        return .updateRequired
    }
}

@MainActor
public extension SyncConnectionControllerDelegate {
    func controllerWillPerformServerSyncOperation(setupRole _: SyncSetupRole) async -> Bool {
        true
    }

    func controllerShouldAllowPairingV2PeerToJoin(peerName _: String?, peerKind _: PairingV2DeviceKind) async -> Bool {
        false
    }

    func controllerShouldJoinPairingV2Peer(peerName _: String?, peerKind _: PairingV2DeviceKind) async -> Bool {
        false
    }

    func controllerDidCompletePairingWithAlreadyConnectedAccount(setupRole _: SyncSetupRole) {
    }
}

extension SyncConnectionController: PairingV2ConfirmationDelegate {

    func pairingV2CoordinatorShouldAllowPeerToJoin(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        await delegate?.controllerShouldAllowPairingV2PeerToJoin(peerName: peerName, peerKind: peerKind) ?? false
    }

    func pairingV2CoordinatorShouldJoinPeer(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        await delegate?.controllerShouldJoinPairingV2Peer(peerName: peerName, peerKind: peerKind) ?? false
    }

    func pairingV2CoordinatorDidCreateSyncAccount(credentialKind: PairingV2DeviceKind) async {
        await delegate?.controllerDidCreateSyncAccount(shouldShowSyncEnabled: credentialKind == .ddg)
    }
}

//
//  PairingV2Coordinator.swift
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

import Foundation
import os.log

/// UI-facing confirmation decisions and account notifications needed by the Pairing V2 coordinator.
protocol PairingV2ConfirmationDelegate: AnyObject {
    /// Asks the local host whether the peer may join and receive this device's recovery code.
    func pairingV2CoordinatorShouldAllowPeerToJoin(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool
    /// Asks the local joiner whether to continue with the host that offered a recovery code.
    func pairingV2CoordinatorShouldJoinPeer(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool
    /// Notifies the app that Pairing V2 created a local account before preparing a recovery code.
    func pairingV2CoordinatorDidCreateSyncAccount(credentialKind: PairingV2DeviceKind) async
}

/// Default timing for the polling loop in `pollUntilFinished`.
enum PairingV2PollingDefaults {
    /// Give up on the pairing session after this many seconds (5 minutes).
    static let sessionTimeout: TimeInterval = 300
    /// Wait this long between relay polls (1 second, in nanoseconds).
    static let pollIntervalNanoseconds: UInt64 = 1_000_000_000
}

final class PairingV2Coordinator {

    private let syncService: DDGSyncing
    private let messageExchanger: PairingV2MessageExchanging
    private let messageCrypto: PairingV2MessageCrypto
    private let deviceName: String
    private let deviceType: String
    private let localKind: PairingV2DeviceKind
    private let flags: PairingV2RolloutFlags
    private weak var confirmationDelegate: PairingV2ConfirmationDelegate?

    private var stateMachine = PairingV2StateMachine()
    private var localKeyPair: PairingV2KeyPair?
    private var peerChannelID: String?
    private var peerPublicKey: String?
    private var lastProcessedSequence = 0
    private var hasClosedLocalChannel = false
    private(set) var completedRegisteredDevices: [RegisteredDevice]?
    private(set) var pendingRecoveryKey: SyncCode.RecoveryKey?

    init(syncService: DDGSyncing,
         messageExchanger: PairingV2MessageExchanging,
         messageCrypto: PairingV2MessageCrypto = PairingV2MessageCrypto(),
         deviceName: String,
         deviceType: String,
         localKind: PairingV2DeviceKind = .ddg,
         flags: PairingV2RolloutFlags,
         confirmationDelegate: PairingV2ConfirmationDelegate? = nil) {
        self.syncService = syncService
        self.messageExchanger = messageExchanger
        self.messageCrypto = messageCrypto
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.localKind = localKind
        self.flags = flags
        self.confirmationDelegate = confirmationDelegate
    }

    var state: PairingV2State {
        stateMachine.state
    }

    func startPresenting() async throws -> PairingV2QRCodePayload {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair()
        localKeyPair = keyPair
        peerChannelID = nil
        peerPublicKey = nil
        lastProcessedSequence = 0
        hasClosedLocalChannel = false

        let commands = stateMachine.handle(
            .presentCodeRequested(localClient: localClient(isPresenter: true), flags: flags)
        )
        try await execute(commands)

        return PairingV2QRCodePayload(channelId: keyPair.channelID, publicKey: keyPair.publicKey)
    }

    func startScanning(qrPayload: PairingV2QRCodePayload) async throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair()
        localKeyPair = keyPair
        peerChannelID = qrPayload.channelId
        peerPublicKey = qrPayload.publicKey
        lastProcessedSequence = 0
        hasClosedLocalChannel = false

        let commands = stateMachine.handle(
            .scannedCode(.v2Linking(peerChannelID: qrPayload.channelId, localChannelID: keyPair.channelID), localClient: localClient(isPresenter: false), flags: flags)
        )
        try await execute(commands)
    }

    /// Performs one poll of this device's channel and handles any new messages.
    /// Production polling goes through `pollUntilFinished`; this is internal for unit testing.
    func pollOnce() async throws {
        guard let channelID = localKeyPair?.channelID else {
            throw PairingV2Error.pairingSessionNotReady(.localKeyPair)
        }

        let messages: [PairingV2SequencedMessage]
        do {
            messages = try await messageExchanger.fetchMessages(from: channelID, after: lastProcessedSequence)
        } catch PairingV2Error.relayChannelUnavailable {
            try await execute(stateMachine.handle(.failed(.relayChannelUnavailable)))
            throw PairingV2Error.relayChannelUnavailable
        } catch PairingV2Error.relayChannelExpired {
            try await execute(stateMachine.handle(.failed(.relayChannelExpired)))
            throw PairingV2Error.relayChannelExpired
        }
        for message in messages.sorted(by: { $0.seq < $1.seq }) {
            guard !hasFinishedPairing else {
                return
            }
            try await handle(message.encryptedMessage)
            lastProcessedSequence = max(lastProcessedSequence, message.seq)
        }
    }

    func pollUntilFinished(timeout: TimeInterval = PairingV2PollingDefaults.sessionTimeout,
                           pollInterval: UInt64 = PairingV2PollingDefaults.pollIntervalNanoseconds,
                           onDidPoll: ((PairingV2State) async -> Void)? = nil) async throws -> PairingV2State.Completion {
        let timeoutDate = Date().addingTimeInterval(timeout)

        while true {
            if let completion = try checkPairingCompletion() {
                return completion
            }

            if Date() > timeoutDate {
                throw SyncError.pollingDidTimeOut
            }

            try await pollOnce()
            await onDidPoll?(state)
            if let completion = try checkPairingCompletion() {
                return completion
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
    }

    func cancel() async {
        _ = stateMachine.handle(.failed(.cancelled))
        await closeLocalChannel()
    }

    private func closeLocalChannel() async {
        guard !hasClosedLocalChannel else {
            return
        }
        guard let channelID = localKeyPair?.channelID else {
            return
        }
        hasClosedLocalChannel = true
        try? await messageExchanger.closeChannel(channelID)
    }

    private func closeLocalChannelBestEffort() {
        guard !hasClosedLocalChannel else {
            return
        }
        guard let channelID = localKeyPair?.channelID else {
            return
        }

        hasClosedLocalChannel = true
        Task { [messageExchanger] in
            try? await messageExchanger.closeChannel(channelID)
        }
    }

    private func handle(_ encryptedMessage: PairingV2EncryptedMessage) async throws {
        guard let privateKey = localKeyPair?.privateKey else {
            throw PairingV2Error.pairingSessionNotReady(.localPrivateKey)
        }

        guard let message = try messageCrypto.decrypt(encryptedMessage, privateKey: privateKey, expectedSenderChannelID: peerChannelID) else {
            return
        }

        let commands: [PairingV2Command]
        let stateBeforeMessage = stateMachine.state
        switch message {
        case .hello(let message):
            if shouldRejectRedundantHello(message, stateBeforeMessage: stateBeforeMessage) {
                commands = stateMachine.handle(.failed(.secondHello))
            } else {
                commands = stateMachine.handle(.receivedHello(message))
            }
            if case .waitingForPeerHello = stateBeforeMessage, !hasFinishedPairing {
                peerChannelID = message.channelId
                peerPublicKey = message.publicKey
            }

        case .recoveryCodeAvailable(let message):
            commands = stateMachine.handle(.receivedPeerStatus(.recoveryCodeAvailable(name: message.name, kind: message.kind, userId: message.userId)))

        case .recoveryCodeRequest(let message):
            commands = stateMachine.handle(.receivedPeerStatus(.recoveryCodeRequest(name: message.name, kind: message.kind)))

        case .recoveryCodeAwaitingConfirmation:
            commands = stateMachine.handle(.receivedRecoveryCodeAwaitingConfirmation)

        case .recoveryCodeConfirmed:
            commands = stateMachine.handle(.receivedRecoveryCodeConfirmed)

        case .recoveryCodeResponse(let message):
            commands = stateMachine.handle(.receivedRecoveryCode(message.recoveryCode))

        case .recoveryCodeDenied:
            commands = stateMachine.handle(.receivedRecoveryCodeDenied)

        case .recoveryCodeUnavailable:
            commands = stateMachine.handle(.receivedRecoveryCodeUnavailable)
        }

        try await execute(commands)
    }

    private func shouldRejectRedundantHello(_ message: PairingV2HelloMessage, stateBeforeMessage: PairingV2State) -> Bool {
        guard case .waitingForPeerStatus(let session) = stateBeforeMessage,
              !session.localClient.isPresenter,
              !session.hasReceivedHello else {
            return false
        }

        return message.channelId != peerChannelID || message.publicKey != peerPublicKey
    }

    private func execute(_ commands: [PairingV2Command]) async throws {
        for command in commands {
            try await execute(command)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func execute(_ command: PairingV2Command) async throws {
        switch command {
        case .openV2Channel(let channelID):
            let channelID = try channelID ?? requiredLocalChannelID()
            try await messageExchanger.openChannel(channelID)

        case .sendHello:
            let keyPair = try requiredLocalKeyPair()
            try await send(.hello(.init(channelId: keyPair.channelID, publicKey: keyPair.publicKey)))

        case .sendRecoveryCodeStatus(let status):
            try await send(recoveryCodeStatusMessage(for: status))

        case .sendRecoveryCodeAwaitingConfirmation:
            try await send(.recoveryCodeAwaitingConfirmation(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAwaitingConfirmation)))

        case .sendRecoveryCodeConfirmed:
            try await send(.recoveryCodeConfirmed(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed)))

        case .sendRecoveryCodeDenied:
            try await send(.recoveryCodeDenied(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeDenied)))

        case .sendRecoveryCodeUnavailable:
            try await send(.recoveryCodeUnavailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeUnavailable)))

        case .requestHostConfirmation(let peerName, let peerKind):
            guard let confirmationDelegate else {
                try await execute(stateMachine.handle(.hostConfirmationDenied))
                return
            }
            let isConfirmed = await confirmationDelegate.pairingV2CoordinatorShouldAllowPeerToJoin(peerName: peerName, peerKind: peerKind)
            let event: PairingV2Event = isConfirmed ? .hostConfirmationAccepted : .hostConfirmationDenied
            try await execute(stateMachine.handle(event))

        case .requestJoinerConfirmation(let peerName, let peerKind):
            guard let confirmationDelegate else {
                try await execute(stateMachine.handle(.joinerConfirmationDenied))
                return
            }
            let isConfirmed = await confirmationDelegate.pairingV2CoordinatorShouldJoinPeer(peerName: peerName, peerKind: peerKind)
            let event: PairingV2Event = isConfirmed ? .joinerConfirmationAccepted : .joinerConfirmationDenied
            try await execute(stateMachine.handle(event))

        case .prepareRecoveryCode(let credentialKind, let purpose):
            let recoveryCode: String
            do {
                recoveryCode = try await prepareRecoveryCode(credentialKind: credentialKind, purpose: purpose)
            } catch let error as PairingV2Error {
                do {
                    try await execute(stateMachine.handle(.failed(error)))
                } catch {
                    await closeLocalChannel()
                }
                throw error
            } catch {
                let pairingError = pairingV2RecoveryCodePreparationError(for: error)
                do {
                    try await execute(stateMachine.handle(.failed(pairingError)))
                } catch {
                    await closeLocalChannel()
                }
                throw pairingError
            }
            try await execute(stateMachine.handle(.recoveryCodePrepared(recoveryCode)))

        case .sendRecoveryCode(let recoveryCode):
            do {
                try await sendRecoveryCode(recoveryCode)
            } catch let error as PairingV2Error {
                try await execute(stateMachine.handle(.failed(error)))
                throw error
            } catch {
                try await execute(stateMachine.handle(.failed(.recoveryCodeSendFailed)))
                throw PairingV2Error.recoveryCodeSendFailed
            }
            try await execute(stateMachine.handle(.recoveryCodeSent))

        case .loginWithRecoveryCode(let recoveryCode):
            do {
                try await login(with: recoveryCode)
            } catch SyncError.accountAlreadyExists {
                throw SyncError.accountAlreadyExists
            } catch SyncError.unexpectedStatusCode(let statusCode) where statusCode == 401 {
                try await execute(stateMachine.handle(.failed(.invalidCredentials)))
                throw PairingV2Error.invalidCredentials
            } catch SyncError.failedToWriteSecureStore {
                try await execute(stateMachine.handle(.failed(.localStorageFailed)))
                throw PairingV2Error.localStorageFailed
            } catch {
                try await execute(stateMachine.handle(.failed(.loginFailed)))
                throw PairingV2Error.loginFailed
            }
            try await execute(stateMachine.handle(.loginSucceeded))

        case .upgradeThirdPartyAccountWithRecoveryCode(let recoveryCode):
            do {
                try await upgradeThirdPartyAccount(with: recoveryCode)
            } catch let error as ThirdPartyAccountUpgradeError {
                let pairingError = pairingV2AccountUpgradeError(for: error)
                try await execute(stateMachine.handle(.failed(pairingError)))
                throw pairingError
            } catch let error as PairingV2Error {
                try await execute(stateMachine.handle(.failed(error)))
                throw error
            } catch {
                try await execute(stateMachine.handle(.failed(.upgradeFailed)))
                throw PairingV2Error.upgradeFailed
            }
            try await execute(stateMachine.handle(.loginSucceeded))

        case .stopPolling:
            // Do not block successful pairing on relay channel cleanup.
            closeLocalChannelBestEffort()

        case .abort:
            await closeLocalChannel()
        }
    }

    private func send(_ message: PairingV2ApplicationMessage) async throws {
        guard let peerChannelID else {
            throw PairingV2Error.pairingSessionNotReady(.peerChannelID)
        }
        guard let peerPublicKey else {
            throw PairingV2Error.pairingSessionNotReady(.peerPublicKey)
        }

        let encryptedMessage = try messageCrypto.encrypt(message, recipientPublicKey: peerPublicKey, senderChannelID: try requiredLocalChannelID())
        try await messageExchanger.send([encryptedMessage], to: peerChannelID)
    }

    private func recoveryCodeStatusMessage(for status: PairingV2PeerStatus) -> PairingV2ApplicationMessage {
        let name = status.name ?? deviceName

        if status.hasAccount {
            return .recoveryCodeAvailable(
                .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                      name: name,
                      kind: status.kind,
                      userId: status.userId ?? syncService.account?.userId))
        }
        return .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest, name: name, kind: status.kind))
    }

    private func prepareRecoveryCode(credentialKind: PairingV2DeviceKind, purpose: String) async throws -> String {
        try await ensureSyncAccountExists(credentialKind: credentialKind)

        switch credentialKind {
        case .thirdParty:
            return try await syncService.prepareThirdPartyRecoveryCode(purpose: purpose)
        case .ddg:
            guard let recoveryCode = syncService.account?.recoveryCodeV2 else {
                throw SyncError.invalidRecoveryKey
            }
            return recoveryCode
        }
    }

    private func ensureSyncAccountExists(credentialKind: PairingV2DeviceKind) async throws {
        guard syncService.account == nil else {
            return
        }

        do {
            try await syncService.createAccount(deviceName: deviceName, deviceType: deviceType)
        } catch {
            throw PairingV2Error.accountCreationFailed
        }
        await confirmationDelegate?.pairingV2CoordinatorDidCreateSyncAccount(credentialKind: credentialKind)
    }

    private func sendRecoveryCode(_ recoveryCode: String) async throws {
        let response = PairingV2ApplicationMessage.recoveryCodeResponse(
            .init(recoveryCode: recoveryCode)
        )
        try await send(response)
    }

    private func login(with recoveryCode: String) async throws {
        let syncCode = try SyncCode.decodeBase64String(recoveryCode)
        guard let recovery = syncCode.recovery else {
            throw SyncError.invalidRecoveryKey
        }
        let recoveryKey = try recovery.defaultCredentialRecoveryKey()
        pendingRecoveryKey = recoveryKey
        completedRegisteredDevices = try await syncService.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
    }

    private func upgradeThirdPartyAccount(with recoveryCode: String) async throws {
        do {
            completedRegisteredDevices = try await syncService.upgradeThirdPartyAccountToDefaultCredential(recoveryCode,
                                                                                                           deviceName: deviceName,
                                                                                                           deviceType: deviceType)
        } catch {
            Logger.sync.error("Pairing V2 3party account upgrade failed: \(String(reflecting: error))")
            throw error
        }
    }

    private func pairingV2RecoveryCodePreparationError(for error: Error) -> PairingV2Error {
        guard let error = error as? ScopedAccessCredentialError else {
            return .recoveryCodePreparationFailed
        }

        switch error {
        case .missingThirdPartyCredential:
            return .missingThirdPartyCredential
        case .undecryptableThirdPartyCredential:
            return .undecryptableThirdPartyCredential
        case .accountExtendFailed:
            return .accountExtendFailed
        }
    }

    private func pairingV2AccountUpgradeError(for error: ThirdPartyAccountUpgradeError) -> PairingV2Error {
        switch error {
        case .nativeCredentialAlreadyPresent:
            return .nativeCredentialAlreadyPresent
        case .noUsableThirdPartyProtectedKeys:
            return .missingThirdPartyKey
        case .localStorageFailed:
            return .localStorageFailed
        case .invalidCredentials:
            return .invalidCredentials
        case .finalNativeLoginFailed,
                .invalidFinalNativeLoginResponse:
            return .loginFailed
        default:
            return .upgradeFailed
        }
    }

    private func localClient(isPresenter: Bool) -> PairingV2LocalClient {
        PairingV2LocalClient(name: deviceName, kind: localKind, hasAccount: syncService.account != nil, isPresenter: isPresenter, userId: syncService.account?.userId)
    }

    private func requiredLocalKeyPair() throws -> PairingV2KeyPair {
        guard let localKeyPair else {
            throw PairingV2Error.pairingSessionNotReady(.localKeyPair)
        }
        return localKeyPair
    }

    private func requiredLocalChannelID() throws -> String {
        try requiredLocalKeyPair().channelID
    }

    private func checkPairingCompletion() throws -> PairingV2State.Completion? {
        switch stateMachine.state {
        case .completed(let completion):
            return completion
        case .failed(let error):
            throw error
        default:
            return nil
        }
    }

    private var hasFinishedPairing: Bool {
        switch stateMachine.state {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }
}

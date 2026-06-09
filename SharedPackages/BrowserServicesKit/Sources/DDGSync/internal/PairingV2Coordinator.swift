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

protocol PairingV2ConfirmationDelegate: AnyObject {
    func pairingV2CoordinatorShouldAllowPeerToJoin(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool
    func pairingV2CoordinatorShouldJoinPeer(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool
    func pairingV2CoordinatorDidCreateSyncAccount(credentialKind: PairingV2DeviceKind) async
}

enum PairingV2PollingDefaults {
    static let sessionTimeout: TimeInterval = 300
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
    private let debugLogHandler: PairingV2DebugLogHandler?
    private weak var confirmationDelegate: PairingV2ConfirmationDelegate?

    private var stateMachine = PairingV2StateMachine()
    private var localKeyPair: PairingV2KeyPair?
    private var peerChannelID: String?
    private var peerPublicKey: String?
    private var lastProcessedSequence = 0
    private var hasClosedLocalChannel = false
    private(set) var completedRegisteredDevices: [RegisteredDevice]?
    private(set) var pendingRecoveryKey: SyncCode.RecoveryKey?
    private(set) var recoveryCodePreparationFailureError: Error?

    init(syncService: DDGSyncing,
         messageExchanger: PairingV2MessageExchanging,
         messageCrypto: PairingV2MessageCrypto = PairingV2MessageCrypto(),
         deviceName: String,
         deviceType: String,
         localKind: PairingV2DeviceKind = .ddg,
         flags: PairingV2RolloutFlags,
         debugLogHandler: PairingV2DebugLogHandler? = nil,
         confirmationDelegate: PairingV2ConfirmationDelegate? = nil) {
        self.syncService = syncService
        self.messageExchanger = messageExchanger
        self.messageCrypto = messageCrypto
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.localKind = localKind
        self.flags = flags
        self.debugLogHandler = debugLogHandler
        self.confirmationDelegate = confirmationDelegate
    }

    var state: PairingV2State {
        stateMachine.state
    }

    func startPresenting() async throws -> PairingV2QRCodePayload {
        let client = localClient(isPresenter: true)
        debugSummary("* presenter started")
        debugSummary("* local \(summaryDescription(for: client))")
        debugSummary("* \(summaryDescription(for: flags))")

        let keyPair = try PairingV2KeyPairFactory.makeKeyPair()
        localKeyPair = keyPair
        peerChannelID = nil
        peerPublicKey = nil
        lastProcessedSequence = 0
        hasClosedLocalChannel = false
        recoveryCodePreparationFailureError = nil
        debugSummary("* local channel \(keyPair.channelID)")

        let commands = stateMachine.handle(
            .presentCodeRequested(localClient: client, flags: flags)
        )
        debugSummary("* \(summaryDescription(for: stateMachine.state))")
        try await execute(commands)

        return PairingV2QRCodePayload(channelId: keyPair.channelID, publicKey: keyPair.publicKey)
    }

    func startScanning(qrPayload: PairingV2QRCodePayload) async throws {
        let client = localClient(isPresenter: false)
        debugSummary("* scanner started")
        debugSummary("* local \(summaryDescription(for: client))")
        debugSummary("* \(summaryDescription(for: flags))")
        debugSummary("* peer channel \(qrPayload.channelId)")

        let keyPair = try PairingV2KeyPairFactory.makeKeyPair()
        localKeyPair = keyPair
        peerChannelID = qrPayload.channelId
        peerPublicKey = qrPayload.publicKey
        lastProcessedSequence = 0
        hasClosedLocalChannel = false
        recoveryCodePreparationFailureError = nil
        debugSummary("* local channel \(keyPair.channelID)")

        let commands = stateMachine.handle(
            .scannedCode(.v2Linking(peerChannelID: qrPayload.channelId, localChannelID: keyPair.channelID), localClient: localClient(isPresenter: false), flags: flags)
        )
        debugSummary("* \(summaryDescription(for: stateMachine.state))")
        try await execute(commands)
    }

    func pollOnce() async throws {
        guard let channelID = localKeyPair?.channelID else {
            throw PairingV2Error.pairingSessionNotReady(.localKeyPair)
        }

        debugSummary("* poll after seq \(lastProcessedSequence)")
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
        debugSummary("* \(messages.count) message(s)")
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
                           onStateUpdate: ((PairingV2State) async -> Void)? = nil) async throws -> PairingV2State.Completion {
        let timeoutDate = Date().addingTimeInterval(timeout)

        while true {
            if let completion = try completedPairingOrThrowFailure() {
                debugSummary("* polling completed \(completion)")
                return completion
            }

            if Date() > timeoutDate {
                debugSummary("* polling timed out after \(Int(timeout))s")
                throw SyncError.pollingDidTimeOut
            }

            try await pollOnce()
            await onStateUpdate?(state)
            if let completion = try completedPairingOrThrowFailure() {
                debugSummary("* polling completed \(completion)")
                return completion
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
    }

    func cancel() async {
        debugSummary("* cancel requested")
        _ = stateMachine.handle(.failed(.cancelled))
        await closeLocalChannel()
    }

    func closeLocalChannel() async {
        guard !hasClosedLocalChannel else {
            return
        }
        guard let channelID = localKeyPair?.channelID else {
            return
        }
        hasClosedLocalChannel = true
        debugSummary("* closing channel \(channelID)")
        try? await messageExchanger.closeChannel(channelID)
    }

    private func handle(_ encryptedMessage: PairingV2EncryptedMessage) async throws {
        guard let privateKey = localKeyPair?.privateKey else {
            throw PairingV2Error.pairingSessionNotReady(.localPrivateKey)
        }

        guard let message = try messageCrypto.decrypt(encryptedMessage, privateKey: privateKey, expectedSenderChannelID: peerChannelID) else {
            Logger.sync.debug("Pairing V2 dropped unknown message type")
            debugSummary("<- unknown message")
            return
        }
        Logger.sync.debug("Pairing V2 received message: \(message.type, privacy: .public)")
        debugSummary("<- \(summaryDescription(for: message))")
        debugRaw("<- \(message.type) payload=\(jsonString(for: encryptedMessage))")

        let commands: [PairingV2Command]
        let stateBeforeMessage = stateMachine.state
        switch message {
        case .hello(let message):
            if shouldRejectRedundantHello(message, stateBeforeMessage: stateBeforeMessage) {
                debugSummary("* redundant hello rejected: does not match scanned code")
                commands = stateMachine.handle(.failed(.secondHello))
            } else {
                if isRedundantHelloFromScannedPeer(message, stateBeforeMessage: stateBeforeMessage) {
                    debugSummary("* redundant hello accepted: matches scanned code")
                }
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

        debugSummary("* \(summaryDescription(for: stateMachine.state))")
        debugFlowDecisionIfNeeded(for: stateMachine.state)
        try await execute(commands)
    }

    private func isRedundantHelloFromScannedPeer(_ message: PairingV2HelloMessage, stateBeforeMessage: PairingV2State) -> Bool {
        guard case .waitingForPeerStatus(let session) = stateBeforeMessage,
              !session.localClient.isPresenter,
              !session.hasReceivedHello else {
            return false
        }

        return message.channelId == peerChannelID && message.publicKey == peerPublicKey
    }

    private func shouldRejectRedundantHello(_ message: PairingV2HelloMessage, stateBeforeMessage: PairingV2State) -> Bool {
        guard case .waitingForPeerStatus(let session) = stateBeforeMessage,
              !session.localClient.isPresenter,
              !session.hasReceivedHello else {
            return false
        }

        return message.channelId != peerChannelID || message.publicKey != peerPublicKey
    }

    private func debugFlowDecisionIfNeeded(for state: PairingV2State) {
        switch state {
        case .completed(.alreadyConnected):
            debugSummary("* same account detected; completing without recovery code")
        case .hostWaitingForConfirmation(_, let credentialKind):
            debugSummary("* elected host; credential=\(credentialKind.rawValue)")
        case .joinerWaitingForConfirmation:
            debugSummary("* elected joiner")
        default:
            break
        }
    }

    private func execute(_ commands: [PairingV2Command]) async throws {
        for command in commands {
            try await execute(command)
        }
    }

    private func execute(_ command: PairingV2Command) async throws {
        debugSummary("* \(debugDescription(for: command))")
        switch command {
        case .openV2Channel(let channelID):
            let channelID = try channelID ?? requiredLocalChannelID()
            try await messageExchanger.openChannel(channelID)
            debugSummary("* opened channel \(channelID)")

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
                debugSummary("* no confirmation delegate; denying host confirmation")
                try await execute(stateMachine.handle(.hostConfirmationDenied))
                return
            }
            let isConfirmed = await confirmationDelegate.pairingV2CoordinatorShouldAllowPeerToJoin(peerName: peerName, peerKind: peerKind)
            debugSummary("* host confirmation \(summaryDescription(forConfirmation: isConfirmed))")
            let event: PairingV2Event = isConfirmed ? .hostConfirmationAccepted : .hostConfirmationDenied
            try await execute(stateMachine.handle(event))

        case .requestJoinerConfirmation(let peerName, let peerKind):
            guard let confirmationDelegate else {
                debugSummary("* no confirmation delegate; denying joiner confirmation")
                try await execute(stateMachine.handle(.joinerConfirmationDenied))
                return
            }
            let isConfirmed = await confirmationDelegate.pairingV2CoordinatorShouldJoinPeer(peerName: peerName, peerKind: peerKind)
            debugSummary("* joiner confirmation \(summaryDescription(forConfirmation: isConfirmed))")
            let event: PairingV2Event = isConfirmed ? .joinerConfirmationAccepted : .joinerConfirmationDenied
            try await execute(stateMachine.handle(event))

        case .prepareRecoveryCode(let credentialKind, let purpose):
            let recoveryCode: String
            do {
                recoveryCode = try await prepareRecoveryCode(credentialKind: credentialKind, purpose: purpose)
            } catch {
                recoveryCodePreparationFailureError = error
                debugSummary("* recovery code preparation failed: \(error.localizedDescription)")
                do {
                    try await execute(stateMachine.handle(.failed(.recoveryCodePreparationFailed)))
                } catch {
                    await closeLocalChannel()
                }
                throw PairingV2Error.recoveryCodePreparationFailed
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
            } catch {
                try await execute(stateMachine.handle(.failed(.loginFailed)))
                throw PairingV2Error.loginFailed
            }
            try await execute(stateMachine.handle(.loginSucceeded))

        case .upgradeThirdPartyAccountWithRecoveryCode(let recoveryCode):
            do {
                try await upgradeThirdPartyAccount(with: recoveryCode)
            } catch let error as ThirdPartyAccountUpgradeError {
                let pairingError: PairingV2Error
                switch error {
                case .nativeCredentialAlreadyPresent:
                    pairingError = .nativeCredentialAlreadyPresent
                default:
                    pairingError = .loginFailed
                }
                try await execute(stateMachine.handle(.failed(pairingError)))
                throw pairingError
            } catch let error as PairingV2Error {
                try await execute(stateMachine.handle(.failed(error)))
                throw error
            } catch {
                try await execute(stateMachine.handle(.failed(.loginFailed)))
                throw PairingV2Error.loginFailed
            }
            try await execute(stateMachine.handle(.loginSucceeded))

        case .stopPolling:
            await closeLocalChannel()

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
        Logger.sync.debug("Pairing V2 sending message: \(message.type, privacy: .public) to channel: \(peerChannelID, privacy: .public)")
        debugSummary("-> \(summaryDescription(for: message))")
        debugRaw("-> \(message.type) payload=\(jsonString(for: encryptedMessage))")
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
        do {
            try await ensureSyncAccountExists(credentialKind: credentialKind)
        } catch {
            debugSummary("* failed to create sync account before recovery code preparation: \(String(reflecting: error))")
            throw error
        }

        switch credentialKind {
        case .thirdParty:
            let recoveryCode: String
            do {
                recoveryCode = try await syncService.prepareThirdPartyRecoveryCode(purpose: purpose)
            } catch {
                debugSummary("* failed to prepare third-party recovery code: \(String(reflecting: error))")
                throw error
            }
            debugSummary("* prepared \(credentialKind.rawValue) recovery code")
            return recoveryCode
        case .ddg:
            guard let account = syncService.account, let recoveryCode = account.recoveryCodeV2 else {
                debugSummary("* default recovery code unavailable")
                throw SyncError.invalidRecoveryKey
            }
            debugSummary("* using native recovery code")
            return recoveryCode
        }
    }

    private func ensureSyncAccountExists(credentialKind: PairingV2DeviceKind) async throws {
        guard syncService.account == nil else {
            debugSummary("* local account already exists")
            return
        }

        debugSummary("* creating native sync account")
        try await syncService.createAccount(deviceName: deviceName, deviceType: deviceType)
        debugSummary("* native sync account created")
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
        debugSummary("* decoded recovery code; logging in")
        completedRegisteredDevices = try await syncService.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
        debugSummary("* login completed; devices=\(completedRegisteredDevices?.count ?? 0)")
    }

    private func upgradeThirdPartyAccount(with recoveryCode: String) async throws {
        debugSummary("* UA 01 received 3party recovery code")
        debugSummary("* UA 02 temporary 3party login scope=ai_chats")
        debugSummary("* UA 04 fetch access credentials; UA 05 fetch keys")
        debugSummary("* UA 06 generate ddg credential; UA 07 rewrap 3party keys")
        debugSummary("* UA 08 encrypt 3party credential; UA 09 post /access-credentials/ddg")
        debugSummary("* UA 10 final native login scope=sync")
        do {
            completedRegisteredDevices = try await syncService.upgradeThirdPartyAccountToDefaultCredential(recoveryCode,
                                                                                                           deviceName: deviceName,
                                                                                                           deviceType: deviceType)
        } catch {
            debugSummary("* UA failed during 3party upgrade: \(String(reflecting: error))")
            Logger.sync.error("Pairing V2 3party account upgrade failed: \(String(reflecting: error), privacy: .public)")
            throw error
        }
        debugSummary("* UA 11 native account persisted by DDGSync; devices=\(completedRegisteredDevices?.count ?? 0)")
    }

    private func debugSummary(_ message: String) {
        debugLogHandler?(.init(kind: .summary, message: message))
    }

    private func debugRaw(_ message: String) {
        debugLogHandler?(.init(kind: .raw, message: message))
    }

    private func debugDescription(for command: PairingV2Command) -> String {
        switch command {
        case .openV2Channel:
            return "open channel"
        case .stopPolling:
            return "stop polling"
        case .sendHello:
            return "send hello"
        case .sendRecoveryCodeStatus(let status):
            return status.hasAccount ? "send recovery_code_available" : "send recovery_code_request"
        case .sendRecoveryCodeAwaitingConfirmation:
            return "send recovery_code_awaiting_confirmation"
        case .sendRecoveryCodeConfirmed:
            return "send recovery_code_confirmed"
        case .sendRecoveryCodeDenied:
            return "send recovery_code_denied"
        case .sendRecoveryCodeUnavailable:
            return "send recovery_code_unavailable"
        case .requestHostConfirmation:
            return "request host confirmation"
        case .requestJoinerConfirmation:
            return "request joiner confirmation"
        case .prepareRecoveryCode(let credentialKind, let purpose):
            return "prepare \(credentialKind.rawValue) recovery code for \(purpose)"
        case .sendRecoveryCode:
            return "send recovery_code_response"
        case .loginWithRecoveryCode:
            return "login with recovery code"
        case .upgradeThirdPartyAccountWithRecoveryCode:
            return "upgrade 3party account"
        case .abort(let error):
            return "abort \(error)"
        }
    }

    private func summaryDescription(for state: PairingV2State) -> String {
        switch state {
        case .idle:
            return "idle"
        case .waitingForPeerHello:
            return "waiting for hello"
        case .waitingForPeerStatus:
            return "waiting for peer status"
        case .hostWaitingForConfirmation:
            return "role host, waiting for confirmation"
        case .hostPreparingRecoveryCode(_, let credentialKind):
            return "role host, preparing \(credentialKind.rawValue) recovery code"
        case .hostSendingRecoveryCode:
            return "role host, sending recovery code"
        case .joinerWaitingForConfirmation:
            return "role joiner, waiting for confirmation"
        case .joinerWaitingForRecoveryCode:
            return "role joiner, waiting for recovery code"
        case .joinerLoggingIn:
            return "role joiner, logging in"
        case .completed(let completion):
            return "completed \(completion)"
        case .failed(let error):
            return "failed \(error)"
        }
    }

    private func summaryDescription(for message: PairingV2ApplicationMessage) -> String {
        switch message {
        case .hello(let message):
            return "hello channel=\(message.channelId)"
        case .recoveryCodeAvailable(let message):
            return "recovery_code_available kind=\(message.kind.rawValue)\(message.name.map { " name=\"\($0)\"" } ?? "")"
        case .recoveryCodeRequest(let message):
            return "recovery_code_request kind=\(message.kind.rawValue)\(message.name.map { " name=\"\($0)\"" } ?? "")"
        case .recoveryCodeAwaitingConfirmation(let message),
                .recoveryCodeConfirmed(let message):
            return "\(message.type)"
        case .recoveryCodeDenied(let message),
                .recoveryCodeUnavailable(let message):
            return "\(message.type)"
        case .recoveryCodeResponse:
            return "recovery_code_response"
        }
    }

    private func summaryDescription(for client: PairingV2LocalClient) -> String {
        let role = client.isPresenter ? "presenter" : "scanner"
        let account = client.hasAccount ? "hasAccount" : "noAccount"
        return "\(role) kind=\(client.kind.rawValue) \(account)"
    }

    private func summaryDescription(for flags: PairingV2RolloutFlags) -> String {
        "flags scan=\(flags.isV2ScanningEnabled) code=\(flags.isV2CodeEnabled)"
    }

    private func summaryDescription(forConfirmation isConfirmed: Bool) -> String {
        isConfirmed ? "accepted" : "denied"
    }

    private func jsonString<T: Encodable>(for value: T) -> String {
        guard let data = try? JSONEncoder.snakeCaseKeys.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "<unable to encode>"
        }
        return string
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

    private func completedPairingOrThrowFailure() throws -> PairingV2State.Completion? {
        switch stateMachine.state {
        case .completed(let completion):
            return completion
        case .failed(let error):
            debugSummary("* polling failed \(error)")
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

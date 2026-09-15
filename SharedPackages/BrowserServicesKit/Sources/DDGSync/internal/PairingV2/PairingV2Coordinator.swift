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
    /// Dismisses a pending host or joiner confirmation without treating it as a user decision.
    func pairingV2CoordinatorDismissConfirmation() async
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
    private let shouldAuthenticateExchangeEndpoints: Bool
    private let advertisedVersion: PairingV2ProtocolVersion
    private let makeKeyPair: () throws -> PairingV2KeyPair
    private let makeChannelSecret: () throws -> String
    private weak var confirmationDelegate: PairingV2ConfirmationDelegate?

    private var stateMachine = PairingV2StateMachine()
    private var entryRole: PairingV2EntryRole?
    private var localKeyPair: PairingV2KeyPair?
    private var localChannelSecret: String?
    private var peerChannelID: String?
    private var peerPublicKey: String?
    private var lastProcessedSequence = 0
    private var hasOpenedLocalChannel = false
    private var hasClosedLocalChannel = false
    private var pendingConfirmation: PairingV2PendingConfirmation?
    private var pendingRecoveryCode: PairingV2RecoveryCodeResponseMessage?
    private(set) var completedRegisteredDevices: [RegisteredDevice]?
    private(set) var pendingRecoveryKey: SyncCode.RecoveryKey?
    private(set) var negotiatedVersion: PairingV2ProtocolVersion = .v2

    init(syncService: DDGSyncing,
         messageExchanger: PairingV2MessageExchanging,
         messageCrypto: PairingV2MessageCrypto = PairingV2MessageCrypto(),
         deviceName: String,
         deviceType: String,
         localKind: PairingV2DeviceKind = .ddg,
         flags: PairingV2RolloutFlags,
         canSendExchangeChannelSecret: Bool,
         advertisedVersion: PairingV2ProtocolVersion,
         confirmationDelegate: PairingV2ConfirmationDelegate? = nil,
         makeKeyPair: @escaping () throws -> PairingV2KeyPair = { try PairingV2KeyPairFactory.makeKeyPair() },
         makeChannelSecret: @escaping () throws -> String = { try PairingV2ChannelSecretFactory.makeSecret() }) {
        self.syncService = syncService
        self.messageExchanger = messageExchanger
        self.messageCrypto = messageCrypto
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.localKind = localKind
        self.flags = flags
        self.shouldAuthenticateExchangeEndpoints = advertisedVersion >= .v2Point1 || canSendExchangeChannelSecret
        self.advertisedVersion = advertisedVersion
        self.confirmationDelegate = confirmationDelegate
        self.makeKeyPair = makeKeyPair
        self.makeChannelSecret = makeChannelSecret
    }

    var state: PairingV2State {
        stateMachine.state
    }

    func startPresenting() async throws -> PairingV2QRCodePayload {
        prepareForNewSession(entryRole: .presenter)
        let keyPair = try generateKeyPair(failureStage: .presenterGenerateCode)
        localKeyPair = keyPair

        let commands = stateMachine.handle(
            .presentCodeRequested(localClient: localClient(isPresenter: true), flags: flags)
        )
        try await execute(commands)

        return PairingV2QRCodePayload(version: advertisedVersion.rawValue, channelId: keyPair.channelID, publicKey: keyPair.publicKey)
    }

    func startScanning(qrPayload: PairingV2QRCodePayload) async throws {
        prepareForNewSession(entryRole: .scanner)
        let keyPair = try generateKeyPair(failureStage: .scannerGenerateKeys)
        localKeyPair = keyPair
        peerChannelID = qrPayload.channelId
        peerPublicKey = qrPayload.publicKey
        negotiateProtocolVersion(with: qrPayload.version)

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

        try await handleConfirmationResult()
        guard !hasFinishedPairing else {
            return
        }

        let messages: [PairingV2SequencedMessage]
        do {
            messages = try await performRelayOperation(
                at: failureStage(presenter: .presenterPollOwnChannel, scanner: .scannerPollOwnChannel)
            ) {
                try await messageExchanger.fetchMessages(from: channelID,
                                                          after: lastProcessedSequence,
                                                          authorizationSecret: localChannelSecret)
            }
        } catch let operationFailure as PairingV2OperationFailure {
            if let stateMachineError = operationFailure.context.kind?.stateMachineError {
                try await execute(stateMachine.handle(.failed(stateMachineError)))
            }
            throw operationFailure
        }
        try await processPolledMessages(messages)
    }

    private func processPolledMessages(_ messages: [PairingV2SequencedMessage]) async throws {
        for message in messages.sorted(by: { $0.seq < $1.seq }) where message.seq > lastProcessedSequence {
            guard !hasFinishedPairing else {
                return
            }

            guard let applicationMessage = try decrypt(message.encryptedMessage) else {
                lastProcessedSequence = max(lastProcessedSequence, message.seq)
                continue
            }
            if case .joinerWaitingForConfirmation = state,
               case .recoveryCodeResponse(let response) = applicationMessage {
                // The peer may release its code before the local user confirms. Keep it while continuing to receive other messages.
                pendingRecoveryCode = pendingRecoveryCode ?? response
            } else {
                try await handle(applicationMessage)
            }
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
        let commands = stateMachine.handle(.failed(.cancelled))
        await dismissPendingConfirmation()
        try? await execute(commands)
        await closeLocalChannel(byeReason: .cancelled)
    }

    func completeAccountSwitch(didSucceed: Bool) async throws {
        if didSucceed {
            await reportJoinStatus(.success)
            try await execute(stateMachine.handle(.loginSucceeded))
        } else {
            await reportJoinStatus(.loginFailed)
            try await execute(stateMachine.handle(.failed(.loginFailed)))
        }
    }

    private func closeLocalChannel(byeReason: PairingV2ByeReason) async {
        guard let teardown = makeChannelTeardown(byeReason: byeReason) else {
            return
        }
        await Self.perform(teardown, using: messageExchanger)
    }

    private func closeLocalChannelBestEffort(byeReason: PairingV2ByeReason) {
        guard let teardown = makeChannelTeardown(byeReason: byeReason) else {
            return
        }
        Task { [messageExchanger] in
            await Self.perform(teardown, using: messageExchanger)
        }
    }

    private func makeChannelTeardown(byeReason: PairingV2ByeReason) -> PairingV2ChannelTeardown? {
        guard hasOpenedLocalChannel, !hasClosedLocalChannel else {
            return nil
        }
        guard let channelID = localKeyPair?.channelID else {
            return nil
        }

        let authorizationSecret = localChannelSecret
        hasClosedLocalChannel = true
        localChannelSecret = nil

        var bye: PairingV2EncryptedMessage?
        if supportsBye {
            if let peerPublicKey, peerChannelID != nil {
                bye = try? messageCrypto.encrypt(.bye(.init(reason: byeReason)),
                                                 recipientPublicKey: peerPublicKey,
                                                 senderChannelID: channelID)
            }
        }

        return PairingV2ChannelTeardown(localChannelID: channelID,
                                        peerChannelID: peerChannelID,
                                        authorizationSecret: authorizationSecret,
                                        bye: bye)
    }

    private static func perform(_ teardown: PairingV2ChannelTeardown,
                                using messageExchanger: PairingV2MessageExchanging) async {
        if let bye = teardown.bye, let peerChannelID = teardown.peerChannelID {
            try? await messageExchanger.send([bye],
                                             to: peerChannelID,
                                             authorizationSecret: teardown.authorizationSecret)
        }
        try? await messageExchanger.closeChannel(teardown.localChannelID,
                                                 authorizationSecret: teardown.authorizationSecret)
    }

    private func decrypt(_ encryptedMessage: PairingV2EncryptedMessage) throws -> PairingV2ApplicationMessage? {
        guard let privateKey = localKeyPair?.privateKey else {
            throw PairingV2Error.pairingSessionNotReady(.localPrivateKey)
        }
        guard let message = try messageCrypto.decrypt(encryptedMessage, privateKey: privateKey, expectedSenderChannelID: peerChannelID) else {
            return nil
        }
        guard message.minimumProtocolVersion <= negotiatedVersion else {
            return nil
        }
        return message
    }

    private func handle(_ message: PairingV2ApplicationMessage) async throws {
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
                negotiateProtocolVersion(with: message.version)
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

        case .recoveryCodeDone(let message):
            commands = stateMachine.handle(.receivedRecoveryCodeDone(message.reason))

        case .bye(let message):
            commands = stateMachine.handle(.receivedBye(message.reason))
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
        let relayFailureStage = entryRole.flatMap { command.relayFailureStage(for: $0) }

        switch command {
        case .openV2Channel(let channelID):
            let channelID = try channelID ?? requiredLocalChannelID()
            let authorizationSecret = try generateChannelSecret()

            do {
                try await performRelayOperation(at: relayFailureStage) {
                    try await messageExchanger.openChannel(channelID, authorizationSecret: authorizationSecret)
                }
            } catch let operationFailure as PairingV2OperationFailure {
                // The PUT may have succeeded before its response was lost. Now that the
                // request has finished, make one cleanup attempt with the same credentials.
                if operationFailure.context.kind == .networkError {
                    try? await messageExchanger.closeChannel(
                        channelID,
                        authorizationSecret: authorizationSecret
                    )
                }
                throw operationFailure
            }

            localChannelSecret = authorizationSecret
            hasOpenedLocalChannel = true

            // If cancelled while channel creation was in flight, clean up now using the secret the server accepted
            if case .failed(.cancelled) = stateMachine.state {
                await closeLocalChannel(byeReason: .cancelled)
                throw PairingV2Error.cancelled
            }

        case .sendHello:
            let keyPair = try requiredLocalKeyPair()
            try await send(.hello(.init(channelId: keyPair.channelID, publicKey: keyPair.publicKey, version: advertisedVersion.rawValue)),
                           failureStage: relayFailureStage)

        case .sendRecoveryCodeStatus(let status):
            try await send(recoveryCodeStatusMessage(for: status), failureStage: relayFailureStage)

        case .sendRecoveryCodeAwaitingConfirmation:
            try await send(.recoveryCodeAwaitingConfirmation(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAwaitingConfirmation)), failureStage: relayFailureStage)

        case .sendRecoveryCodeConfirmed:
            try await send(.recoveryCodeConfirmed(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed)), failureStage: relayFailureStage)

        case .sendRecoveryCodeDenied:
            try await send(.recoveryCodeDenied(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeDenied)), failureStage: relayFailureStage)

        case .sendRecoveryCodeUnavailable:
            try await send(.recoveryCodeUnavailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeUnavailable)), failureStage: relayFailureStage)

        case .requestHostConfirmation(let peerName, let peerKind):
            guard let confirmationDelegate else {
                try await execute(stateMachine.handle(.hostConfirmationDenied))
                return
            }
            beginConfirmation { [weak confirmationDelegate] in
                let isConfirmed = await confirmationDelegate?.pairingV2CoordinatorShouldAllowPeerToJoin(peerName: peerName, peerKind: peerKind) ?? false
                return isConfirmed ? .hostConfirmationAccepted : .hostConfirmationDenied
            }

        case .requestJoinerConfirmation(let peerName, let peerKind):
            guard let confirmationDelegate else {
                try await execute(stateMachine.handle(.joinerConfirmationDenied))
                return
            }
            beginConfirmation { [weak confirmationDelegate] in
                let isConfirmed = await confirmationDelegate?.pairingV2CoordinatorShouldJoinPeer(peerName: peerName, peerKind: peerKind) ?? false
                return isConfirmed ? .joinerConfirmationAccepted : .joinerConfirmationDenied
            }

        case .prepareRecoveryCode(let credentialKind, let purpose):
            let recoveryCode: String
            do {
                recoveryCode = try await prepareRecoveryCode(credentialKind: credentialKind, purpose: purpose)
            } catch let error as PairingV2Error {
                try await handleRecoveryCodePreparationFailure(error)
            } catch {
                let pairingError = pairingV2RecoveryCodePreparationError(for: error)
                try await handleRecoveryCodePreparationFailure(pairingError)
            }
            try await execute(stateMachine.handle(.recoveryCodePrepared(recoveryCode)))

        case .sendRecoveryCode(let recoveryCode):
            do {
                try await sendRecoveryCode(recoveryCode, failureStage: relayFailureStage)
            } catch let operationFailure as PairingV2OperationFailure {
                try await execute(stateMachine.handle(.failed(.recoveryCodeSendFailed)))
                throw operationFailure
            } catch let error as PairingV2Error {
                try await execute(stateMachine.handle(.failed(error)))
                throw error
            } catch {
                try await execute(stateMachine.handle(.failed(.recoveryCodeSendFailed)))
                throw PairingV2Error.recoveryCodeSendFailed
            }
            try await execute(stateMachine.handle(.recoveryCodeSent(shouldWaitForJoinStatus: supportsRecoveryCodeDone)))

        case .loginWithRecoveryCode(let recoveryCode):
            do {
                try await login(with: recoveryCode)
            } catch SyncError.accountAlreadyExists {
                throw SyncError.accountAlreadyExists
            } catch SyncError.unexpectedStatusCode(let statusCode) where statusCode == 401 {
                await reportJoinStatus(.loginFailed)
                try await execute(stateMachine.handle(.failed(.invalidCredentials)))
                throw PairingV2Error.invalidCredentials
            } catch SyncError.failedToWriteSecureStore {
                await reportJoinStatus(.loginFailed)
                try await execute(stateMachine.handle(.failed(.localStorageFailed)))
                throw PairingV2Error.localStorageFailed
            } catch {
                await reportJoinStatus(.loginFailed)
                try await execute(stateMachine.handle(.failed(.loginFailed)))
                throw PairingV2Error.loginFailed
            }
            await reportJoinStatus(.success)
            try await execute(stateMachine.handle(.loginSucceeded))

        case .upgradeThirdPartyAccountWithRecoveryCode(let recoveryCode):
            do {
                try await upgradeThirdPartyAccount(with: recoveryCode)
            } catch let error as ThirdPartyAccountUpgradeError {
                let pairingError = pairingV2AccountUpgradeError(for: error)
                await reportJoinStatus(.scopeRejected)
                try await execute(stateMachine.handle(.failed(pairingError)))
                throw pairingError
            } catch let error as PairingV2Error {
                await reportJoinStatus(.scopeRejected)
                try await execute(stateMachine.handle(.failed(error)))
                throw error
            } catch {
                await reportJoinStatus(.scopeRejected)
                try await execute(stateMachine.handle(.failed(.upgradeFailed)))
                throw PairingV2Error.upgradeFailed
            }
            await reportJoinStatus(.success)
            try await execute(stateMachine.handle(.loginSucceeded))

        case .stopPolling:
            // Do not block successful pairing on relay channel cleanup.
            closeLocalChannelBestEffort(byeReason: .done)

        case .abort(let error):
            await dismissPendingConfirmation()
            await closeLocalChannel(byeReason: error == .cancelled ? .cancelled : .error)
        }
    }

    private func send(_ message: PairingV2ApplicationMessage, failureStage: PairingV2FailureStage?) async throws {
        guard message.minimumProtocolVersion <= negotiatedVersion else {
            return
        }
        guard let peerChannelID else {
            throw PairingV2Error.pairingSessionNotReady(.peerChannelID)
        }
        guard let peerPublicKey else {
            throw PairingV2Error.pairingSessionNotReady(.peerPublicKey)
        }

        let encryptedMessage = try messageCrypto.encrypt(message, recipientPublicKey: peerPublicKey, senderChannelID: try requiredLocalChannelID())
        try await performRelayOperation(at: failureStage) {
            try await messageExchanger.send([encryptedMessage],
                                            to: peerChannelID,
                                            authorizationSecret: localChannelSecret)
        }
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

    private func sendRecoveryCode(_ recoveryCode: String, failureStage: PairingV2FailureStage?) async throws {
        let response = PairingV2ApplicationMessage.recoveryCodeResponse(
            .init(recoveryCode: recoveryCode)
        )
        try await send(response, failureStage: failureStage)
    }

    private func reportJoinStatus(_ reason: PairingV2RecoveryCodeDoneReason) async {
        guard supportsRecoveryCodeDone else {
            return
        }
        do {
            try await send(.recoveryCodeDone(.init(reason: reason)), failureStage: nil)
        } catch {
            Logger.sync.debug("Pairing V2 could not report join status: \(String(reflecting: error))")
        }
    }

    private func beginConfirmation(_ operation: @escaping () async -> PairingV2Event) {
        let confirmation = PairingV2PendingConfirmation()
        pendingConfirmation = confirmation
        Task {
            await confirmation.resolve(operation())
        }
    }

    private func handleConfirmationResult() async throws {
        guard let confirmation = pendingConfirmation,
              let event = await confirmation.result,
              pendingConfirmation === confirmation else {
            return
        }
        pendingConfirmation = nil
        let recoveryCode = pendingRecoveryCode
        pendingRecoveryCode = nil
        try await execute(stateMachine.handle(event))
        if let recoveryCode, !hasFinishedPairing {
            try await handle(.recoveryCodeResponse(recoveryCode))
        }
    }

    private func dismissPendingConfirmation() async {
        let confirmation = pendingConfirmation
        pendingConfirmation = nil
        pendingRecoveryCode = nil
        if confirmation != nil {
            await confirmationDelegate?.pairingV2CoordinatorDismissConfirmation()
        }
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

    private func handleRecoveryCodePreparationFailure(_ error: PairingV2Error) async throws -> Never {
        do {
            try await execute(stateMachine.handle(.failed(error)))
        } catch let relayFailure as PairingV2OperationFailure {
            await closeLocalChannel(byeReason: .error)
            throw relayFailure
        } catch {
            await closeLocalChannel(byeReason: .error)
        }
        throw error
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

    private func prepareForNewSession(entryRole: PairingV2EntryRole) {
        self.entryRole = entryRole
        negotiatedVersion = .v2
        localKeyPair = nil
        localChannelSecret = nil
        peerChannelID = nil
        peerPublicKey = nil
        lastProcessedSequence = 0
        hasOpenedLocalChannel = false
        hasClosedLocalChannel = false
        pendingConfirmation = nil
        pendingRecoveryCode = nil
    }

    private func negotiateProtocolVersion(with peerVersion: String) {
        negotiatedVersion = advertisedVersion.negotiated(with: peerVersion)
        Logger.sync.debug("\("Pairing V2 negotiated version: \(self.negotiatedVersion.rawValue), local: \(self.advertisedVersion.rawValue), peer: \(peerVersion)", privacy: .private)")
    }

    private func generateKeyPair(failureStage: PairingV2FailureStage) throws -> PairingV2KeyPair {
        do {
            return try makeKeyPair()
        } catch {
            throw PairingV2OperationFailure(generationStage: failureStage, underlyingError: error)
        }
    }

    private func generateChannelSecret() throws -> String? {
        guard shouldAuthenticateExchangeEndpoints else {
            return nil
        }

        do {
            return try makeChannelSecret()
        } catch {
            guard let failureStage = failureStage(presenter: .presenterGenerateCode, scanner: .scannerGenerateKeys) else {
                throw error
            }
            throw PairingV2OperationFailure(generationStage: failureStage, underlyingError: error)
        }
    }

    private func failureStage(presenter: PairingV2FailureStage, scanner: PairingV2FailureStage) -> PairingV2FailureStage? {
        entryRole?.failureStage(presenter: presenter, scanner: scanner)
    }

    private func performRelayOperation<Result>(at failureStage: PairingV2FailureStage?,
                                               operation: () async throws -> Result) async throws -> Result {
        do {
            return try await operation()
        } catch let operationFailure as PairingV2OperationFailure {
            throw operationFailure
        } catch {
            guard let failureStage, let operationFailure = PairingV2OperationFailure(relayError: error, stage: failureStage) else {
                throw error
            }
            throw operationFailure
        }
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

    var supportsRecoveryCodeDone: Bool {
        negotiatedVersion >= .v2Point1
    }

    var supportsBye: Bool {
        negotiatedVersion >= .v2Point1
    }
}

private actor PairingV2PendingConfirmation {
    private(set) var result: PairingV2Event?

    func resolve(_ event: PairingV2Event) {
        result = event
    }
}

private struct PairingV2ChannelTeardown {
    let localChannelID: String
    let peerChannelID: String?
    let authorizationSecret: String?
    let bye: PairingV2EncryptedMessage?
}

enum PairingV2EntryRole {
    case presenter
    case scanner

    func failureStage(presenter: PairingV2FailureStage, scanner: PairingV2FailureStage) -> PairingV2FailureStage {
        switch self {
        case .presenter:
            return presenter
        case .scanner:
            return scanner
        }
    }
}

extension PairingV2Command {

    func relayFailureStage(for entryRole: PairingV2EntryRole) -> PairingV2FailureStage? {
        switch self {
        case .openV2Channel:
            return entryRole.failureStage(presenter: .presenterOpenOwnChannel, scanner: .scannerOpenOwnChannel)
        case .sendHello:
            guard case .scanner = entryRole else {
                return nil
            }
            return .scannerSendHello
        case .sendRecoveryCodeStatus:
            return entryRole.failureStage(presenter: .presenterSendPeerStatus, scanner: .scannerSendPeerStatus)
        case .sendRecoveryCodeAwaitingConfirmation,
                .sendRecoveryCodeConfirmed:
            return entryRole.failureStage(presenter: .presenterSendConfirmationStatus, scanner: .scannerSendConfirmationStatus)
        case .sendRecoveryCodeDenied:
            return entryRole.failureStage(presenter: .presenterSendRecoveryDenied, scanner: .scannerSendRecoveryDenied)
        case .sendRecoveryCode:
            return entryRole.failureStage(presenter: .presenterSendRecoveryCode, scanner: .scannerSendRecoveryCode)
        case .sendRecoveryCodeUnavailable:
            return entryRole.failureStage(presenter: .presenterSendRecoveryUnavailable, scanner: .scannerSendRecoveryUnavailable)
        case .stopPolling,
                .requestHostConfirmation,
                .requestJoinerConfirmation,
                .prepareRecoveryCode,
                .loginWithRecoveryCode,
                .upgradeThirdPartyAccountWithRecoveryCode,
                .abort:
            return nil
        }
    }
}

private extension PairingV2FailureKind {

    var stateMachineError: PairingV2Error? {
        switch self {
        case .unavailable:
            return .relayChannelUnavailable
        case .expired:
            return .relayChannelExpired
        case .httpError, .networkError:
            return nil
        }
    }
}

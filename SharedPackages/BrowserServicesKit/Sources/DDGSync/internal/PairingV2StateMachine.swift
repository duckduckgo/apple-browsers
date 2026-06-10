//
//  PairingV2StateMachine.swift
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

/// Whether a pairing participant is a native DuckDuckGo client or a third-party (scoped) client.
public enum PairingV2DeviceKind: String, Codable, Equatable {
    case ddg
    case thirdParty = "3party"
}

struct PairingV2LocalClient: Equatable {
    let name: String?
    let kind: PairingV2DeviceKind
    let hasAccount: Bool
    let isPresenter: Bool
    let userId: String?

    init(name: String? = nil, kind: PairingV2DeviceKind, hasAccount: Bool, isPresenter: Bool, userId: String? = nil) {
        self.name = name
        self.kind = kind
        self.hasAccount = hasAccount
        self.isPresenter = isPresenter
        self.userId = userId
    }
}

struct PairingV2PeerStatus: Equatable {
    let name: String?
    let kind: PairingV2DeviceKind
    let hasAccount: Bool
    let userId: String?

    static func recoveryCodeAvailable(name: String? = nil, kind: PairingV2DeviceKind, userId: String? = nil) -> PairingV2PeerStatus {
        PairingV2PeerStatus(name: name, kind: kind, hasAccount: true, userId: userId)
    }

    static func recoveryCodeRequest(name: String? = nil, kind: PairingV2DeviceKind) -> PairingV2PeerStatus {
        PairingV2PeerStatus(name: name, kind: kind, hasAccount: false, userId: nil)
    }
}

enum PairingV2ScannedCode: Equatable {
    case v1Linking
    case v2Linking(peerChannelID: String, localChannelID: String)
    case unknown
}

struct PairingV2RolloutFlags: Equatable {
    let isV2ScanningEnabled: Bool
    let isV2CodeEnabled: Bool
}

struct PairingV2Session: Equatable {
    let localClient: PairingV2LocalClient
    let peerChannelID: String?
    let localChannelID: String?
    let peerStatus: PairingV2PeerStatus?
    let purpose: String
    let hasReceivedHello: Bool

    init(localClient: PairingV2LocalClient,
         peerChannelID: String?,
         localChannelID: String? = nil,
         peerStatus: PairingV2PeerStatus? = nil,
         purpose: String = "ai_chats",
         hasReceivedHello: Bool = false) {
        self.localClient = localClient
        self.peerChannelID = peerChannelID
        self.localChannelID = localChannelID
        self.peerStatus = peerStatus
        self.purpose = purpose
        self.hasReceivedHello = hasReceivedHello
    }

    func withPeerStatus(_ peerStatus: PairingV2PeerStatus) -> PairingV2Session {
        PairingV2Session(localClient: localClient,
                         peerChannelID: peerChannelID,
                         localChannelID: localChannelID,
                         peerStatus: peerStatus,
                         purpose: purpose,
                         hasReceivedHello: hasReceivedHello)
    }

    func withReceivedHello() -> PairingV2Session {
        PairingV2Session(localClient: localClient,
                         peerChannelID: peerChannelID,
                         localChannelID: localChannelID,
                         peerStatus: peerStatus,
                         purpose: purpose,
                         hasReceivedHello: true)
    }
}

enum PairingV2State: Equatable {
    enum Completion: Equatable {
        case recoveryCodeSent(credentialKind: PairingV2DeviceKind)
        case loggedIn
        case alreadyConnected
    }

    case idle
    case waitingForPeerHello(PairingV2Session)
    case waitingForPeerStatus(PairingV2Session)
    case hostWaitingForConfirmation(PairingV2Session, credentialKind: PairingV2DeviceKind)
    case hostPreparingRecoveryCode(PairingV2Session, credentialKind: PairingV2DeviceKind)
    case hostSendingRecoveryCode(PairingV2Session, credentialKind: PairingV2DeviceKind, recoveryCode: String)
    case joinerWaitingForConfirmation(PairingV2Session)
    case joinerWaitingForRecoveryCode(PairingV2Session)
    case joinerLoggingIn(PairingV2Session, recoveryCode: String)
    case completed(Completion)
    case failed(PairingV2Error)
}

enum PairingV2Event: Equatable {
    case presentCodeRequested(localClient: PairingV2LocalClient, flags: PairingV2RolloutFlags)
    case scannedCode(PairingV2ScannedCode, localClient: PairingV2LocalClient, flags: PairingV2RolloutFlags)
    case receivedHello(PairingV2HelloMessage)
    case receivedPeerStatus(PairingV2PeerStatus)
    case nativeCredentialAlreadyPresent
    case hostConfirmationAccepted
    case hostConfirmationDenied
    case joinerConfirmationAccepted
    case joinerConfirmationDenied
    case recoveryCodePrepared(String)
    case recoveryCodeSent
    case receivedRecoveryCodeAwaitingConfirmation
    case receivedRecoveryCodeConfirmed
    case receivedRecoveryCodeDenied
    case receivedRecoveryCodeUnavailable
    case receivedRecoveryCode(String)
    case loginSucceeded
    case failed(PairingV2Error)
}

enum PairingV2Command: Equatable {
    case openV2Channel(channelID: String?)
    case stopPolling
    case sendHello
    case sendRecoveryCodeStatus(PairingV2PeerStatus)
    case sendRecoveryCodeAwaitingConfirmation
    case sendRecoveryCodeConfirmed
    case sendRecoveryCodeDenied
    case sendRecoveryCodeUnavailable
    case requestHostConfirmation(peerName: String?, peerKind: PairingV2DeviceKind)
    case requestJoinerConfirmation(peerName: String?, peerKind: PairingV2DeviceKind)
    case prepareRecoveryCode(credentialKind: PairingV2DeviceKind, purpose: String)
    case sendRecoveryCode(String)
    case loginWithRecoveryCode(String)
    case upgradeThirdPartyAccountWithRecoveryCode(String)
    case abort(PairingV2Error)
}

enum PairingV2Error: Error, Equatable {
    case v2ScanningDisabled
    case unknownCode
    case secondHello
    case unexpectedEvent(PairingV2UnexpectedEvent)
    case pairingSessionNotReady(PairingV2MissingSessionData)
    case nativeCredentialAlreadyPresent
    case recoveryCodePreparationFailed
    case recoveryCodeSendFailed
    case loginFailed
    case recoveryCodeDenied
    case recoveryCodeUnavailable
    case unsupportedVersion(String)
    case unsupportedFlow(String)
    case relayChannelUnavailable
    case relayChannelExpired
    case cancelled
}

enum PairingV2UnexpectedEvent: Equatable {
    case startRequestedWhileSessionActive
    case helloAfterPeerStatus
    case helloBeforeChannelHierarchyReady
    case peerStatusBeforeChannelHierarchyReady
    case hostConfirmationAcceptedWhileNotAwaitingConfirmation
    case hostConfirmationDeniedWhileNotAwaitingConfirmation
    case joinerConfirmationAcceptedWhileNotAwaitingConfirmation
    case joinerConfirmationDeniedWhileNotAwaitingConfirmation
    case recoveryCodePreparedWhileNotHosting
    case recoveryCodeMessageReceivedWhileNotJoining(PairingV2RecoveryCodeMessage)
    case recoveryCodeSentWhileNotSending
    case loginSucceededWhileNotLoggingIn
}

enum PairingV2RecoveryCodeMessage: Equatable {
    case awaitingConfirmation
    case confirmed
    case denied
    case unavailable
    case response
}

enum PairingV2MissingSessionData: Equatable {
    case localKeyPair
    case localPrivateKey
    case peerChannelID
    case peerPublicKey
}

enum PairingV2RoleDecision: Equatable {
    case host(joinerKind: PairingV2DeviceKind)
    case joiner(hostKind: PairingV2DeviceKind)
}

/// Decides host vs. joiner from both sides' account status, kind, presenter flag, and channel IDs (see numbered rules below).
enum PairingV2RoleElection {

    static func decideRole(localClient: PairingV2LocalClient,
                           peerStatus: PairingV2PeerStatus,
                           localChannelID: String? = nil,
                           peerChannelID: String? = nil) -> PairingV2RoleDecision {
        let peerKind = peerStatus.kind

        // Rule 1: account beats no-account.
        if localClient.hasAccount && !peerStatus.hasAccount {
            return .host(joinerKind: peerKind)
        }

        // Rule 2: no-account joins an account.
        if !localClient.hasAccount && peerStatus.hasAccount {
            return .joiner(hostKind: peerKind)
        }

        // Rules 3-4: DDG beats 3party.
        if localClient.kind == .ddg && peerKind == .thirdParty {
            return .host(joinerKind: peerKind)
        }

        // Rule 5: presenter hosts when account and kind do not decide.
        if localClient.isPresenter {
            return .host(joinerKind: peerKind)
        }

        // Rule 6: mutual scanners use channel IDs as a deterministic tie-break.
        if let localChannelID, let peerChannelID {
            return localChannelID < peerChannelID
                ? .host(joinerKind: peerKind)
                : .joiner(hostKind: peerKind)
        }

        // Rule 7: scanners join by default.
        return .joiner(hostKind: peerKind)
    }
}

struct PairingV2StateMachine {

    private(set) var state: PairingV2State = .idle

    private var canStartPairingSession: Bool {
        switch state {
        case .idle, .completed, .failed:
            return true
        default:
            return false
        }
    }

    private var canFailCurrentPairingSession: Bool {
        switch state {
        case .completed, .failed:
            return false
        default:
            return true
        }
    }

    mutating func handle(_ event: PairingV2Event) -> [PairingV2Command] {
        switch event {
        case .presentCodeRequested(let localClient, let flags):
            return handlePresentCodeRequested(localClient: localClient, flags: flags)

        case .scannedCode(let scannedCode, let localClient, let flags):
            return handleScannedCode(scannedCode, localClient: localClient, flags: flags)

        case .receivedHello(let message):
            return handleReceivedHello(message)

        case .receivedPeerStatus(let peerStatus):
            return handleReceivedPeerStatus(peerStatus)

        case .nativeCredentialAlreadyPresent:
            return fail(with: .nativeCredentialAlreadyPresent)

        case .hostConfirmationAccepted:
            return handleHostConfirmationAccepted()

        case .hostConfirmationDenied:
            return handleHostConfirmationDenied()

        case .joinerConfirmationAccepted:
            return handleJoinerConfirmationAccepted()

        case .joinerConfirmationDenied:
            return handleJoinerConfirmationDenied()

        case .recoveryCodePrepared(let recoveryCode):
            return handleRecoveryCodePrepared(recoveryCode)

        case .recoveryCodeSent:
            return handleRecoveryCodeSent()

        case .receivedRecoveryCodeAwaitingConfirmation:
            return handleRecoveryCodeProgress(message: .awaitingConfirmation)

        case .receivedRecoveryCodeConfirmed:
            return handleRecoveryCodeProgress(message: .confirmed)

        case .receivedRecoveryCodeDenied:
            return handleRecoveryCodeTerminalAbort(message: .denied, error: .recoveryCodeDenied)

        case .receivedRecoveryCodeUnavailable:
            return handleRecoveryCodeTerminalAbort(message: .unavailable, error: .recoveryCodeUnavailable)

        case .receivedRecoveryCode(let recoveryCode):
            return handleReceivedRecoveryCode(recoveryCode)

        case .loginSucceeded:
            return handleLoginSucceeded()

        case .failed(let error):
            guard canFailCurrentPairingSession else {
                return []
            }
            return fail(with: error)
        }
    }

    private mutating func handlePresentCodeRequested(localClient: PairingV2LocalClient, flags: PairingV2RolloutFlags) -> [PairingV2Command] {
        guard canStartPairingSession else {
            return fail(with: .unexpectedEvent(.startRequestedWhileSessionActive))
        }

        guard flags.isV2ScanningEnabled else {
            return fail(with: .v2ScanningDisabled)
        }

        guard localClient.kind == .ddg else {
            return fail(with: .unsupportedFlow("Pairing V2 code presentation requires a native client"))
        }

        let session = PairingV2Session(localClient: localClient, peerChannelID: nil)
        state = .waitingForPeerHello(session)
        return [.openV2Channel(channelID: nil)]
    }

    private mutating func handleScannedCode(_ scannedCode: PairingV2ScannedCode,
                                            localClient: PairingV2LocalClient,
                                            flags: PairingV2RolloutFlags) -> [PairingV2Command] {
        guard canStartPairingSession else {
            return fail(with: .unexpectedEvent(.startRequestedWhileSessionActive))
        }

        switch scannedCode {
        case .v1Linking:
            return fail(with: .unsupportedFlow("V1 fallback is handled outside Pairing V2"))

        case .v2Linking(let peerChannelID, let localChannelID):
            guard flags.isV2ScanningEnabled else {
                return fail(with: .v2ScanningDisabled)
            }

            guard localClient.kind == .ddg else {
                return fail(with: .unsupportedFlow("Pairing V2 scanning requires a native client"))
            }

            let session = PairingV2Session(localClient: localClient, peerChannelID: peerChannelID, localChannelID: localChannelID)
            state = .waitingForPeerStatus(session)

            let commands: [PairingV2Command] = [
                .openV2Channel(channelID: nil),
                .sendHello,
                .sendRecoveryCodeStatus(Self.localRecoveryCodeStatus(for: localClient))
            ]
            return commands

        case .unknown:
            return fail(with: .unknownCode)
        }
    }

    private mutating func handleReceivedHello(_ message: PairingV2HelloMessage) -> [PairingV2Command] {
        guard Self.supports(version: message.version) else {
            return fail(with: .unsupportedVersion(message.version))
        }

        switch state {
        case .waitingForPeerHello(let session):
            state = .waitingForPeerStatus(session)
            return [.sendRecoveryCodeStatus(Self.localRecoveryCodeStatus(for: session.localClient))]

        case .waitingForPeerStatus(let session):
            guard !session.localClient.isPresenter, !session.hasReceivedHello else {
                return fail(with: .secondHello)
            }
            guard session.peerStatus == nil else {
                return fail(with: .unexpectedEvent(.helloAfterPeerStatus))
            }
            state = .waitingForPeerStatus(session.withReceivedHello())
            return []

        case .hostWaitingForConfirmation,
                .hostPreparingRecoveryCode,
                .hostSendingRecoveryCode,
                .joinerWaitingForConfirmation,
                .joinerWaitingForRecoveryCode,
                .joinerLoggingIn:
            return fail(with: .unexpectedEvent(.helloAfterPeerStatus))

        default:
            return fail(with: .unexpectedEvent(.helloBeforeChannelHierarchyReady))
        }
    }

    private mutating func handleReceivedPeerStatus(_ peerStatus: PairingV2PeerStatus) -> [PairingV2Command] {
        guard case .waitingForPeerStatus(let session) = state else {
            return fail(with: .unexpectedEvent(.peerStatusBeforeChannelHierarchyReady))
        }

        if peerStatus.hasAccount, let peerUserId = peerStatus.userId, let localUserId = session.localClient.userId, peerUserId == localUserId {
            state = .completed(.alreadyConnected)
            return [.stopPolling]
        }

        let updatedSession = session.withPeerStatus(peerStatus)
        let raceLocalChannelID = updatedSession.hasReceivedHello ? updatedSession.localChannelID : nil
        let racePeerChannelID = updatedSession.hasReceivedHello ? updatedSession.peerChannelID : nil
        switch PairingV2RoleElection.decideRole(localClient: updatedSession.localClient,
                                                peerStatus: peerStatus,
                                                localChannelID: raceLocalChannelID,
                                                peerChannelID: racePeerChannelID) {
        case .host(let joinerKind):
            let credentialKind = Self.recoveryCredentialKind(hostKind: updatedSession.localClient.kind, joinerKind: joinerKind)
            guard updatedSession.localClient.kind == .ddg else {
                return fail(with: .unsupportedFlow("Pairing V2 native host requires a native client"))
            }

            state = .hostWaitingForConfirmation(updatedSession, credentialKind: credentialKind)
            return [
                .sendRecoveryCodeAwaitingConfirmation,
                .requestHostConfirmation(peerName: peerStatus.name, peerKind: peerStatus.kind)
            ]

        case .joiner(let hostKind):
            guard updatedSession.localClient.kind == .ddg, [PairingV2DeviceKind.ddg, .thirdParty].contains(hostKind) else {
                return fail(with: .unsupportedFlow("Pairing V2 native joiner currently supports only native or 3party recovery codes"))
            }

            state = .joinerWaitingForConfirmation(updatedSession)
            return [.requestJoinerConfirmation(peerName: peerStatus.name, peerKind: peerStatus.kind)]
        }
    }

    private mutating func handleHostConfirmationAccepted() -> [PairingV2Command] {
        guard case .hostWaitingForConfirmation(let session, let credentialKind) = state else {
            return fail(with: .unexpectedEvent(.hostConfirmationAcceptedWhileNotAwaitingConfirmation))
        }

        state = .hostPreparingRecoveryCode(session, credentialKind: credentialKind)
        return [.sendRecoveryCodeConfirmed, .prepareRecoveryCode(credentialKind: credentialKind, purpose: session.purpose)]
    }

    private mutating func handleHostConfirmationDenied() -> [PairingV2Command] {
        guard case .hostWaitingForConfirmation = state else {
            return fail(with: .unexpectedEvent(.hostConfirmationDeniedWhileNotAwaitingConfirmation))
        }

        state = .failed(.cancelled)
        return [.sendRecoveryCodeDenied, .abort(.cancelled)]
    }

    private mutating func handleJoinerConfirmationAccepted() -> [PairingV2Command] {
        guard case .joinerWaitingForConfirmation(let session) = state else {
            return fail(with: .unexpectedEvent(.joinerConfirmationAcceptedWhileNotAwaitingConfirmation))
        }

        state = .joinerWaitingForRecoveryCode(session)
        return []
    }

    private mutating func handleJoinerConfirmationDenied() -> [PairingV2Command] {
        guard case .joinerWaitingForConfirmation = state else {
            return fail(with: .unexpectedEvent(.joinerConfirmationDeniedWhileNotAwaitingConfirmation))
        }

        state = .failed(.cancelled)
        return [.abort(.cancelled)]
    }

    private mutating func handleRecoveryCodePrepared(_ recoveryCode: String) -> [PairingV2Command] {
        guard case .hostPreparingRecoveryCode(let session, let credentialKind) = state else {
            return fail(with: .unexpectedEvent(.recoveryCodePreparedWhileNotHosting))
        }

        state = .hostSendingRecoveryCode(session, credentialKind: credentialKind, recoveryCode: recoveryCode)
        return [.sendRecoveryCode(recoveryCode)]
    }

    private mutating func handleReceivedRecoveryCode(_ recoveryCode: String) -> [PairingV2Command] {
        guard case .joinerWaitingForRecoveryCode(let session) = state else {
            return fail(with: .unexpectedEvent(.recoveryCodeMessageReceivedWhileNotJoining(.response)))
        }

        state = .joinerLoggingIn(session, recoveryCode: recoveryCode)
        if session.peerStatus?.kind == .thirdParty {
            return [.upgradeThirdPartyAccountWithRecoveryCode(recoveryCode)]
        }
        return [.loginWithRecoveryCode(recoveryCode)]
    }

    private mutating func handleRecoveryCodeProgress(message: PairingV2RecoveryCodeMessage) -> [PairingV2Command] {
        switch state {
        case .joinerWaitingForConfirmation,
             .joinerWaitingForRecoveryCode:
            return []
        default:
            return fail(with: .unexpectedEvent(.recoveryCodeMessageReceivedWhileNotJoining(message)))
        }
    }

    private mutating func handleRecoveryCodeTerminalAbort(message: PairingV2RecoveryCodeMessage, error: PairingV2Error) -> [PairingV2Command] {
        switch state {
        case .joinerWaitingForConfirmation,
             .joinerWaitingForRecoveryCode:
            return fail(with: error)
        default:
            return fail(with: .unexpectedEvent(.recoveryCodeMessageReceivedWhileNotJoining(message)))
        }
    }

    private mutating func handleRecoveryCodeSent() -> [PairingV2Command] {
        guard case .hostSendingRecoveryCode(_, let credentialKind, _) = state else {
            return fail(with: .unexpectedEvent(.recoveryCodeSentWhileNotSending))
        }

        state = .completed(.recoveryCodeSent(credentialKind: credentialKind))
        return [.stopPolling]
    }

    private mutating func handleLoginSucceeded() -> [PairingV2Command] {
        guard case .joinerLoggingIn = state else {
            return fail(with: .unexpectedEvent(.loginSucceededWhileNotLoggingIn))
        }

        state = .completed(.loggedIn)
        return [.stopPolling]
    }

    private mutating func fail(with error: PairingV2Error) -> [PairingV2Command] {
        let commands: [PairingV2Command]
        if case .hostPreparingRecoveryCode = state, error == .recoveryCodePreparationFailed {
            commands = [.sendRecoveryCodeUnavailable, .abort(error)]
        } else {
            commands = [.abort(error)]
        }
        state = .failed(error)
        return commands
    }

    private static func localRecoveryCodeStatus(for localClient: PairingV2LocalClient) -> PairingV2PeerStatus {
        localClient.hasAccount
            ? .recoveryCodeAvailable(name: localClient.name, kind: localClient.kind, userId: localClient.userId)
            : .recoveryCodeRequest(name: localClient.name, kind: localClient.kind)
    }

    private static func recoveryCredentialKind(hostKind: PairingV2DeviceKind, joinerKind: PairingV2DeviceKind) -> PairingV2DeviceKind {
        if hostKind == .ddg && joinerKind == .thirdParty {
            return .thirdParty
        }
        return hostKind
    }

    private static func supports(version: String) -> Bool {
        PairingV2ProtocolVersion.supports(version)
    }

}

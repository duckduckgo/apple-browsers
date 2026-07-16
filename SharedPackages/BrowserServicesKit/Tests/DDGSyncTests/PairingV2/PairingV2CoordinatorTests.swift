//
//  PairingV2CoordinatorTests.swift
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

import Security
import XCTest

@testable import DDGSync

private enum PairingV2CoordinatorTestError: Error {
    case expectedLocalHello
}

private typealias NativeJoinerThirdPartyUpgradeSetup = (coordinator: PairingV2Coordinator, upgradeCoordinator: ThirdPartyAccountUpgradeCoordinatingMock)

private final class PairingV2ConfirmationDelegateMock: PairingV2ConfirmationDelegate {
    var shouldAllowPeerToJoin = true
    var shouldJoinPeer = true
    var allowPeerToJoinCalls: [(peerName: String?, peerKind: PairingV2DeviceKind)] = []
    var joinPeerCalls: [(peerName: String?, peerKind: PairingV2DeviceKind)] = []
    var didCreateSyncAccountCalls: [PairingV2DeviceKind] = []

    func pairingV2CoordinatorShouldAllowPeerToJoin(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        allowPeerToJoinCalls.append((peerName, peerKind))
        return shouldAllowPeerToJoin
    }

    func pairingV2CoordinatorShouldJoinPeer(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        joinPeerCalls.append((peerName, peerKind))
        return shouldJoinPeer
    }

    func pairingV2CoordinatorDidCreateSyncAccount(credentialKind: PairingV2DeviceKind) async {
        didCreateSyncAccountCalls.append(credentialKind)
    }
}

private actor PairingV2CoordinatorTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

final class PairingV2CoordinatorTests: XCTestCase {

    private static let cachedPeerKeyPair: Result<PairingV2KeyPair, Error> = Result {
        try PairingV2KeyPairFactory.makeKeyPair(channelID: "peer-channel")
    }

    func testWhenStartPresentingThenOpensLocalChannelAndReturnsQRCodePayload() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger)

        let payload = try await coordinator.startPresenting()

        XCTAssertEqual(payload.version, PairingV2ProtocolVersion.current)
        XCTAssertFalse(payload.channelId.isEmpty)
        XCTAssertFalse(payload.publicKey.isEmpty)
        XCTAssertEqual(messageExchanger.openChannelCalls, [payload.channelId])
        XCTAssertEqual(
            coordinator.state,
            .waitingForPeerHello(.init(localClient: .init(name: "Mac", kind: .ddg, hasAccount: false, isPresenter: true), peerChannelID: nil))
        )
    }

    func testWhenPresenterReceivesHelloThenSendsRecoveryCodeStatusToPeerChannel() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger, messageCrypto: messageCrypto)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )

        try await coordinator.pollOnce()

        XCTAssertEqual(messageExchanger.fetchMessagesCalls.map(\.channelID), [payload.channelId])
        XCTAssertEqual(messageExchanger.sendCalls.map(\.channelID), [peerKeyPair.channelID])
        XCTAssertEqual(
            try decryptSentMessage(at: 0, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest, name: "Mac", kind: .ddg))
        )
        XCTAssertEqual(
            coordinator.state,
            .waitingForPeerStatus(.init(localClient: .init(name: "Mac", kind: .ddg, hasAccount: false, isPresenter: true), peerChannelID: nil))
        )
    }

    func testWhenScannerReceivesMatchingRedundantHelloThenKeepsWaitingForPeerStatus() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger, messageCrypto: messageCrypto)

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)
        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]

        try await coordinator.pollOnce()

        XCTAssertEqual(
            coordinator.state,
            .waitingForPeerStatus(
                .init(localClient: .init(name: "Mac", kind: .ddg, hasAccount: false, isPresenter: false),
                      peerChannelID: peerKeyPair.channelID,
                      localChannelID: hello.channelId,
                      hasReceivedHello: true)
            )
        )
        XCTAssertTrue(messageExchanger.closeChannelCalls.isEmpty)
    }

    func testWhenScannerReceivesMismatchedRedundantHelloThenFlowAborts() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger, messageCrypto: messageCrypto)
        let error = PairingV2Error.secondHello

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)
        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .hello(.init(channelId: peerKeyPair.channelID, publicKey: "mismatched-public-key")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]

        try await coordinator.pollOnce()

        XCTAssertEqual(coordinator.state, .failed(error))
        XCTAssertEqual(messageExchanger.closeChannelCalls, [hello.channelId])
    }

    func testWhenPollReceivesRelayChannelUnavailableThenFailsImmediately() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesError = PairingV2Error.relayChannelUnavailable

        do {
            try await coordinator.pollOnce()
            XCTFail("Expected PairingV2Error.relayChannelUnavailable")
        } catch PairingV2Error.relayChannelUnavailable {
        } catch {
            XCTFail("Expected PairingV2Error.relayChannelUnavailable, got \(error)")
        }

        XCTAssertEqual(messageExchanger.fetchMessagesCalls.map(\.channelID), [payload.channelId])
        XCTAssertEqual(messageExchanger.closeChannelCalls, [payload.channelId])
        XCTAssertEqual(coordinator.state, .failed(.relayChannelUnavailable))

        await coordinator.cancel()

        XCTAssertEqual(messageExchanger.closeChannelCalls, [payload.channelId])
    }

    func testWhenSendReceivesRelayChannelUnavailableThenThrowsRelayChannelUnavailable() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger, messageCrypto: messageCrypto)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )
        messageExchanger.sendError = PairingV2Error.relayChannelUnavailable

        do {
            try await coordinator.pollOnce()
            XCTFail("Expected PairingV2Error.relayChannelUnavailable")
        } catch PairingV2Error.relayChannelUnavailable {
        } catch {
            XCTFail("Expected PairingV2Error.relayChannelUnavailable, got \(error)")
        }
    }

    func testWhenPresenterHostsNativePeerThenSendsProgressMessagesBeforeRecoveryCodeResponse() async throws {
        let dependencies = MockSyncDependencies()
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          confirmationDelegate: confirmationDelegate)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)),
                .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                             name: "Peer",
                                             kind: .ddg,
                                             userId: "peer-user"))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )

        try await coordinator.pollOnce()

        let account = try XCTUnwrap(syncService.account)
        let recoveryCode = try XCTUnwrap(account.recoveryCodeV2)
        XCTAssertEqual(confirmationDelegate.allowPeerToJoinCalls.map { $0.peerName }, ["Peer"])
        XCTAssertEqual(confirmationDelegate.allowPeerToJoinCalls.map { $0.peerKind }, [.ddg])
        XCTAssertEqual(messageExchanger.sendCalls.map(\.channelID), [
            peerKeyPair.channelID,
            peerKeyPair.channelID,
            peerKeyPair.channelID,
            peerKeyPair.channelID
        ])
        XCTAssertEqual(
            try decryptSentMessage(at: 0, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                         name: "Mac",
                                         kind: .ddg,
                                         userId: SyncAccount.mock.userId))
        )
        XCTAssertEqual(
            try decryptSentMessage(at: 1, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeAwaitingConfirmation(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAwaitingConfirmation))
        )
        XCTAssertEqual(
            try decryptSentMessage(at: 2, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeConfirmed(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed))
        )
        try assertRecoveryCodeResponse(
            try decryptSentMessage(at: 3, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            matches: recoveryCode
        )
        XCTAssertEqual(coordinator.state, .completed(.recoveryCodeSent(credentialKind: .ddg)))
    }

    func testWhenNoAccountPresenterHostsNativePeerThenCreatesAccountAfterConfirmedAndBeforeRecoveryCodeResponse() async throws {
        let dependencies = MockSyncDependencies()
        let accountManager = AccountManagingMock()
        dependencies.account = accountManager
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          confirmationDelegate: confirmationDelegate)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)),
                .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                           name: "Peer",
                                           kind: .ddg))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )

        try await coordinator.pollOnce()

        let account = try XCTUnwrap(syncService.account)
        let recoveryCode = try XCTUnwrap(account.recoveryCodeV2)
        XCTAssertEqual(accountManager.createAccountCalls.map(\.deviceName), ["Mac"])
        XCTAssertEqual(accountManager.createAccountCalls.map(\.deviceType), ["desktop"])
        XCTAssertEqual(confirmationDelegate.didCreateSyncAccountCalls, [.ddg])
        XCTAssertEqual(
            try decryptSentMessage(at: 0, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest, name: "Mac", kind: .ddg))
        )
        XCTAssertEqual(
            try decryptSentMessage(at: 1, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeAwaitingConfirmation(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAwaitingConfirmation))
        )
        XCTAssertEqual(
            try decryptSentMessage(at: 2, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeConfirmed(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed))
        )
        try assertRecoveryCodeResponse(
            try decryptSentMessage(at: 3, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            matches: recoveryCode
        )
        XCTAssertEqual(coordinator.state, .completed(.recoveryCodeSent(credentialKind: .ddg)))
    }

    func testWhenNoAccountPresenterCannotSendRecoveryCodeConfirmedThenDoesNotCreateAccount() async throws {
        let dependencies = MockSyncDependencies()
        let accountManager = AccountManagingMock()
        dependencies.account = accountManager
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          confirmationDelegate: confirmationDelegate)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)),
                .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                           name: "Peer",
                                           kind: .ddg))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )
        messageExchanger.sendHandler = { _, _ in
            if messageExchanger.sendCalls.count == 3 {
                throw PairingV2Error.relayChannelUnavailable
            }
        }

        do {
            try await coordinator.pollOnce()
            XCTFail("Expected PairingV2Error.relayChannelUnavailable")
        } catch PairingV2Error.relayChannelUnavailable {
        } catch {
            XCTFail("Expected PairingV2Error.relayChannelUnavailable, got \(error)")
        }

        XCTAssertTrue(accountManager.createAccountCalls.isEmpty)
        XCTAssertNil(syncService.account)
        XCTAssertTrue(confirmationDelegate.didCreateSyncAccountCalls.isEmpty)
        XCTAssertEqual(messageExchanger.sendCalls.count, 3)
        XCTAssertEqual(
            try decryptSentMessage(at: 2, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeConfirmed(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed))
        )
    }

    func testWhenNoAccountPresenterCannotCreateAccountThenFailsWithAccountCreationError() async throws {
        let dependencies = MockSyncDependencies()
        let accountManager = AccountManagingMock()
        accountManager.createAccountError = SyncError.failedToPrepareForConnect("test failure")
        dependencies.account = accountManager
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          confirmationDelegate: confirmationDelegate)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)),
                .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                           name: "Peer",
                                           kind: .ddg))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )

        do {
            try await coordinator.pollOnce()
            XCTFail("Expected PairingV2Error.accountCreationFailed")
        } catch PairingV2Error.accountCreationFailed {
        } catch {
            XCTFail("Expected PairingV2Error.accountCreationFailed, got \(error)")
        }

        XCTAssertEqual(coordinator.state, .failed(.accountCreationFailed))
        XCTAssertEqual(accountManager.createAccountCalls.map(\.deviceName), ["Mac"])
        XCTAssertNil(syncService.account)
        XCTAssertTrue(confirmationDelegate.didCreateSyncAccountCalls.isEmpty)
        XCTAssertEqual(messageExchanger.closeChannelCalls, [payload.channelId])
        XCTAssertEqual(messageExchanger.sendCalls.count, 4)
        XCTAssertEqual(
            try decryptSentMessage(at: 2, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeConfirmed(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed))
        )
        XCTAssertEqual(
            try decryptSentMessage(at: 3, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeUnavailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeUnavailable))
        )
    }

    func testWhenPresenterCannotPrepareThirdPartyRecoveryCodeThenFailsWithThirdPartyPreparationError() async throws {
        let dependencies = MockSyncDependencies()
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.ensureThirdPartyScopedPasswordError = SyncError.failedToEncryptValue("test failure")
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          confirmationDelegate: confirmationDelegate)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)),
                .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                           name: "Peer",
                                           kind: .thirdParty))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )

        do {
            try await coordinator.pollOnce()
            XCTFail("Expected PairingV2Error.recoveryCodePreparationFailed")
        } catch PairingV2Error.recoveryCodePreparationFailed {
        } catch {
            XCTFail("Expected PairingV2Error.recoveryCodePreparationFailed, got \(error)")
        }

        XCTAssertEqual(coordinator.state, .failed(.recoveryCodePreparationFailed))
        XCTAssertEqual(messageExchanger.closeChannelCalls, [payload.channelId])
        XCTAssertEqual(messageExchanger.sendCalls.count, 4)
        XCTAssertEqual(
            try decryptSentMessage(at: 2, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeConfirmed(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed))
        )
        XCTAssertEqual(
            try decryptSentMessage(at: 3, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeUnavailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeUnavailable))
        )
    }

    func testWhenPresenterHostConfirmationIsDeniedThenSendsRecoveryCodeDeniedAndStops() async throws {
        let dependencies = MockSyncDependencies()
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        confirmationDelegate.shouldAllowPeerToJoin = false
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          confirmationDelegate: confirmationDelegate)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)),
                .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                           name: "Peer",
                                           kind: .ddg))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )

        try await coordinator.pollOnce()

        XCTAssertEqual(confirmationDelegate.allowPeerToJoinCalls.map { $0.peerName }, ["Peer"])
        XCTAssertEqual(confirmationDelegate.allowPeerToJoinCalls.map { $0.peerKind }, [.ddg])
        XCTAssertEqual(
            try decryptSentMessage(at: 2, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeDenied(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeDenied))
        )
        XCTAssertEqual(coordinator.state, .failed(.cancelled))
        XCTAssertEqual(messageExchanger.closeChannelCalls, [payload.channelId])
    }

    func testWhenNativeJoinerReceivesDDGV2RecoveryCodeThenConvertsAndLogsIn() async throws {
        let dependencies = MockSyncDependencies()
        let accountManager = AccountManagingMock()
        dependencies.account = accountManager
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil

        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          confirmationDelegate: confirmationDelegate)
        let userId = "v2-ddg-user"
        let primaryKey = Data((0..<32).map(UInt8.init))
        var loginRecoveryKey: SyncCode.RecoveryKey?
        var loginDeviceName: String?
        var loginDeviceType: String?
        accountManager.loginSpy = { recoveryKey, deviceName, deviceType in
            loginRecoveryKey = recoveryKey
            loginDeviceName = deviceName
            loginDeviceType = deviceType
        }

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .ddg,
                                                 userId: userId)),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()

        let recoveryCode = try Self.makeRecoveryCodeV2(userId: userId,
                                                       secret: Base64URL.encode(primaryKey),
                                                       credentialId: SyncCredentialID.defaultCredential)
        messageExchanger.fetchMessagesStub = [
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeResponse(.init(recoveryCode: recoveryCode)),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()

        XCTAssertEqual(confirmationDelegate.joinPeerCalls.map { $0.peerName }, ["Peer"])
        XCTAssertEqual(confirmationDelegate.joinPeerCalls.map { $0.peerKind }, [.ddg])
        XCTAssertTrue(accountManager.loginCalled)
        XCTAssertEqual(loginRecoveryKey?.userId, userId)
        XCTAssertEqual(loginRecoveryKey?.primaryKey, primaryKey)
        XCTAssertEqual(loginDeviceName, "Mac")
        XCTAssertEqual(loginDeviceType, "desktop")
        XCTAssertEqual(coordinator.pendingRecoveryKey, loginRecoveryKey)
        XCTAssertEqual(coordinator.completedRegisteredDevices?.map(\.id), [RegisteredDevice.mock.id])
        XCTAssertEqual(coordinator.state, .completed(.loggedIn))
    }

    func testWhenNativeJoinerLogsInThenPollUntilFinishedReturnsBeforeLocalChannelCloseCompletes() async throws {
        let dependencies = MockSyncDependencies()
        dependencies.account = AccountManagingMock()
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil

        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          confirmationDelegate: confirmationDelegate)
        let closeStarted = expectation(description: "Local channel close started")
        let pollCompleted = expectation(description: "Polling completed")
        let closeGate = PairingV2CoordinatorTestGate()
        messageExchanger.closeChannelHandler = { _ in
            closeStarted.fulfill()
            await closeGate.wait()
        }

        let userId = "v2-ddg-user"
        let primaryKey = Data((0..<32).map(UInt8.init))
        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)
        let recoveryCode = try Self.makeRecoveryCodeV2(userId: userId,
                                                       secret: Base64URL.encode(primaryKey),
                                                       credentialId: SyncCredentialID.defaultCredential)
        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .ddg,
                                                 userId: userId)),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload),
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeResponse(.init(recoveryCode: recoveryCode)),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]

        let pollingTask = Task {
            try await coordinator.pollUntilFinished(pollInterval: 0)
        }
        let completionTask = Task {
            let completion = try await pollingTask.value
            XCTAssertEqual(completion, .loggedIn)
            pollCompleted.fulfill()
        }

        await fulfillment(of: [closeStarted], timeout: 1)
        await fulfillment(of: [pollCompleted], timeout: 1)
        await closeGate.open()
        try await completionTask.value
        XCTAssertEqual(messageExchanger.closeChannelCalls.count, 1)
    }

    func testWhenNativeJoinerReceivesThirdPartyRecoveryCodeThenDelegatesUpgradeToSyncService() async throws {
        let dependencies = MockSyncDependencies()
        let upgradeCoordinator = ThirdPartyAccountUpgradeCoordinatingMock()
        dependencies.createThirdPartyAccountUpgradeCoordinatorStub = upgradeCoordinator
        let secureStore = try XCTUnwrap(dependencies.secureStore as? SecureStorageStub)
        secureStore.theAccount = nil
        let scopedPasswordCached = expectation(description: "Scoped password cached")
        secureStore.persistScopedPasswordCalled = {
            scopedPasswordCached.fulfill()
        }

        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        let coordinator = PairingV2Coordinator(syncService: syncService,
                                               messageExchanger: messageExchanger,
                                               messageCrypto: messageCrypto,
                                               deviceName: "Mac",
                                               deviceType: "desktop",
                                               flags: PairingV2RolloutFlags(isV2ScanningEnabled: true, isV2CodeEnabled: true),
                                               confirmationDelegate: confirmationDelegate)

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .thirdParty,
                                                 userId: "third-party-user")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()
        XCTAssertEqual(confirmationDelegate.joinPeerCalls.map { $0.peerName }, ["Peer"])
        XCTAssertEqual(confirmationDelegate.joinPeerCalls.map { $0.peerKind }, [.thirdParty])
        XCTAssertEqual(
            coordinator.state,
            .joinerWaitingForRecoveryCode(
                .init(localClient: .init(name: "Mac", kind: .ddg, hasAccount: false, isPresenter: false),
                      peerChannelID: peerKeyPair.channelID,
                      localChannelID: hello.channelId,
                      peerStatus: .recoveryCodeAvailable(name: "Peer", kind: .thirdParty, userId: "third-party-user"))
            )
        )

        let recoveryCode = "third-party-recovery-code"
        messageExchanger.fetchMessagesStub = [
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeResponse(.init(recoveryCode: recoveryCode)),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()

        XCTAssertEqual(upgradeCoordinator.upgradeThirdPartyAccountCalls.map(\.recoveryCode), [recoveryCode])
        XCTAssertEqual(upgradeCoordinator.upgradeThirdPartyAccountCalls.first?.deviceName, "Mac")
        XCTAssertEqual(upgradeCoordinator.upgradeThirdPartyAccountCalls.first?.deviceType, "desktop")
        XCTAssertEqual(coordinator.completedRegisteredDevices?.map(\.id), [RegisteredDevice.mock.id])
        XCTAssertEqual(coordinator.completedRegisteredDevices?.map(\.name), [RegisteredDevice.mock.name])
        XCTAssertEqual(coordinator.completedRegisteredDevices?.map(\.type), [RegisteredDevice.mock.type])
        XCTAssertEqual(coordinator.state, .completed(.loggedIn))
        XCTAssertEqual(secureStore.theAccount?.userId, SyncAccount.mock.userId)

        await fulfillment(of: [scopedPasswordCached], timeout: 5.0)
        XCTAssertEqual(secureStore.theScopedPassword, Data(repeating: 1, count: 32))
    }

    func testWhenThirdPartyUpgradeReportsExistingNativeCredentialThenPairingFailsWithNativeCredentialAlreadyPresent() async throws {
        let setup = try await makeNativeJoinerReadyForThirdPartyUpgrade(upgradeError: ThirdPartyAccountUpgradeError.nativeCredentialAlreadyPresent)

        do {
            try await setup.coordinator.pollOnce()
            XCTFail("Expected native credential conflict to abort pairing")
        } catch PairingV2Error.nativeCredentialAlreadyPresent {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(setup.upgradeCoordinator.upgradeThirdPartyAccountCalls.map(\.recoveryCode), ["third-party-recovery-code"])
        XCTAssertEqual(setup.coordinator.state, .failed(.nativeCredentialAlreadyPresent))
    }

    func testWhenThirdPartyUpgradeHasNoUsableProtectedKeysThenPairingFailsWithMissingThirdPartyKey() async throws {
        let setup = try await makeNativeJoinerReadyForThirdPartyUpgrade(upgradeError: ThirdPartyAccountUpgradeError.noUsableThirdPartyProtectedKeys)

        do {
            try await setup.coordinator.pollOnce()
            XCTFail("Expected missing third-party key to abort pairing")
        } catch PairingV2Error.missingThirdPartyKey {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(setup.upgradeCoordinator.upgradeThirdPartyAccountCalls.map(\.recoveryCode), ["third-party-recovery-code"])
        XCTAssertEqual(setup.coordinator.state, .failed(.missingThirdPartyKey))
    }

    func testWhenNativeJoinerConfirmationIsDeniedThenDoesNotLoginIfRecoveryCodeArrives() async throws {
        let dependencies = MockSyncDependencies()
        let upgradeCoordinator = ThirdPartyAccountUpgradeCoordinatingMock()
        dependencies.createThirdPartyAccountUpgradeCoordinatorStub = upgradeCoordinator
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil

        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        confirmationDelegate.shouldJoinPeer = false
        let coordinator = PairingV2Coordinator(syncService: syncService,
                                               messageExchanger: messageExchanger,
                                               messageCrypto: messageCrypto,
                                               deviceName: "Mac",
                                               deviceType: "desktop",
                                               flags: PairingV2RolloutFlags(isV2ScanningEnabled: true, isV2CodeEnabled: true),
                                               confirmationDelegate: confirmationDelegate)

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .thirdParty,
                                                 userId: "third-party-user")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()

        messageExchanger.fetchMessagesStub = [
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeResponse(.init(recoveryCode: "third-party-recovery-code")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()

        XCTAssertEqual(confirmationDelegate.joinPeerCalls.map { $0.peerName }, ["Peer"])
        XCTAssertEqual(confirmationDelegate.joinPeerCalls.map { $0.peerKind }, [.thirdParty])
        XCTAssertTrue(upgradeCoordinator.upgradeThirdPartyAccountCalls.isEmpty)
        XCTAssertNil(coordinator.completedRegisteredDevices)
        XCTAssertEqual(coordinator.state, .failed(.cancelled))
        XCTAssertEqual(messageExchanger.closeChannelCalls.count, 1)
    }

    private func makeNativeJoinerReadyForThirdPartyUpgrade(upgradeError: Error) async throws -> NativeJoinerThirdPartyUpgradeSetup {
        let dependencies = MockSyncDependencies()
        let upgradeCoordinator = ThirdPartyAccountUpgradeCoordinatingMock()
        upgradeCoordinator.upgradeThirdPartyAccountError = upgradeError
        dependencies.createThirdPartyAccountUpgradeCoordinatorStub = upgradeCoordinator
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil

        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        let coordinator = PairingV2Coordinator(syncService: syncService,
                                               messageExchanger: messageExchanger,
                                               messageCrypto: messageCrypto,
                                               deviceName: "Mac",
                                               deviceType: "desktop",
                                               flags: PairingV2RolloutFlags(isV2ScanningEnabled: true, isV2CodeEnabled: true),
                                               confirmationDelegate: confirmationDelegate)

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .thirdParty,
                                                 userId: "third-party-user")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()

        messageExchanger.fetchMessagesStub = [
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeResponse(.init(recoveryCode: "third-party-recovery-code")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]

        return (coordinator, upgradeCoordinator)
    }

    private func makeCoordinator(syncService: DDGSyncing,
                                 messageExchanger: PairingV2MessageExchanging,
                                 messageCrypto: PairingV2MessageCrypto = PairingV2MessageCrypto(),
                                 confirmationDelegate: PairingV2ConfirmationDelegate? = nil) -> PairingV2Coordinator {
        PairingV2Coordinator(syncService: syncService,
                             messageExchanger: messageExchanger,
                             messageCrypto: messageCrypto,
                             deviceName: "Mac",
                             deviceType: "desktop",
                             flags: PairingV2RolloutFlags(isV2ScanningEnabled: true, isV2CodeEnabled: true),
                             confirmationDelegate: confirmationDelegate)
    }

    private func makePeerKeyPair(channelID: String = "peer-channel") throws -> PairingV2KeyPair {
        let cached = try Self.cachedPeerKeyPair.get()
        return PairingV2KeyPair(channelID: channelID, publicKey: cached.publicKey, privateKey: cached.privateKey)
    }

    private static func makeRecoveryCodeV2(userId: String,
                                           secret: String,
                                           credentialId: String) throws -> String {
        let payload = SyncCode.RecoveryKeyV2(
            userId: userId,
            secret: secret,
            cid: credentialId,
            v: SyncCode.RecoveryKeyV2.currentVersion
        )
        return Base64URL.encode(try SyncCode(recovery: .v2(payload)).toJSON())
    }

    private func encryptedPeerMessages(_ messages: [PairingV2ApplicationMessage],
                                       recipientPublicKey: String,
                                       peerKeyPair: PairingV2KeyPair,
                                       messageCrypto: PairingV2MessageCrypto) throws -> [PairingV2SequencedMessage] {
        try messages.enumerated().map { index, message in
            let encryptedMessage = try messageCrypto.encrypt(message, recipientPublicKey: recipientPublicKey, senderChannelID: peerKeyPair.channelID)
            return PairingV2SequencedMessage(seq: index + 1, version: encryptedMessage.version, payload: encryptedMessage.payload)
        }
    }

    private func decryptSentMessage(at index: Int,
                                    from messageExchanger: PairingV2MessageExchangingMock,
                                    peerPrivateKey: SecKey,
                                    messageCrypto: PairingV2MessageCrypto,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) throws -> PairingV2ApplicationMessage {
        let optionalSendCall: (messages: [PairingV2EncryptedMessage], channelID: String)?
        if messageExchanger.sendCalls.indices.contains(index) {
            optionalSendCall = messageExchanger.sendCalls[index]
        } else {
            optionalSendCall = nil
        }
        let sendCall = try XCTUnwrap(optionalSendCall, file: file, line: line)
        let encryptedMessage = try XCTUnwrap(sendCall.messages.first, file: file, line: line)
        return try XCTUnwrap(try messageCrypto.decrypt(encryptedMessage, privateKey: peerPrivateKey), file: file, line: line)
    }

    private func assertRecoveryCodeResponse(_ message: PairingV2ApplicationMessage,
                                            matches expectedRecoveryCode: String,
                                            file: StaticString = #filePath,
                                            line: UInt = #line) throws {
        guard case .recoveryCodeResponse(let response) = message else {
            XCTFail("Expected recovery code response, got \(message)", file: file, line: line)
            return
        }

        let actual = try SyncCode.decodeBase64String(response.recoveryCode)
        let expected = try SyncCode.decodeBase64String(expectedRecoveryCode)
        XCTAssertEqual(actual.recovery, expected.recovery, file: file, line: line)
    }

    private func localHello(from messageExchanger: PairingV2MessageExchangingMock,
                            peerPrivateKey: SecKey,
                            messageCrypto: PairingV2MessageCrypto) throws -> PairingV2HelloMessage {
        let encryptedHello = try XCTUnwrap(messageExchanger.sendCalls.first?.messages.first)
        let message = try XCTUnwrap(try messageCrypto.decrypt(encryptedHello, privateKey: peerPrivateKey))
        guard case .hello(let hello) = message else {
            XCTFail("Expected local hello")
            throw PairingV2CoordinatorTestError.expectedLocalHello
        }
        return hello
    }
}

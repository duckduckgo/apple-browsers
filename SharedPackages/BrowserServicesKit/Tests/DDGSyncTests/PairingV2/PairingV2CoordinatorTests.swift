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
    case expectedPendingConfirmation
    case keyGenerationFailed
    case loginFailed
    case secretGenerationFailed
}

private typealias NativeJoinerThirdPartyUpgradeSetup = (
    coordinator: PairingV2Coordinator,
    upgradeCoordinator: ThirdPartyAccountUpgradeCoordinatingMock,
    messageExchanger: PairingV2MessageExchangingMock,
    messageCrypto: PairingV2MessageCrypto,
    peerKeyPair: PairingV2KeyPair
)

private final class PairingV2ConfirmationDelegateMock: PairingV2ConfirmationDelegate {
    var shouldAllowPeerToJoin = true
    var shouldJoinPeer = true
    var allowPeerToJoinHandler: (() async -> Bool)?
    var joinPeerHandler: (() async -> Bool)?
    var dismissConfirmationHandler: (() async -> Void)?
    var allowPeerToJoinCalls: [(peerName: String?, peerKind: PairingV2DeviceKind)] = []
    var joinPeerCalls: [(peerName: String?, peerKind: PairingV2DeviceKind)] = []
    var didCreateSyncAccountCalls: [PairingV2DeviceKind] = []
    var dismissConfirmationCallCount = 0

    func pairingV2CoordinatorShouldAllowPeerToJoin(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        allowPeerToJoinCalls.append((peerName, peerKind))
        if let allowPeerToJoinHandler {
            return await allowPeerToJoinHandler()
        }
        return shouldAllowPeerToJoin
    }

    func pairingV2CoordinatorShouldJoinPeer(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        joinPeerCalls.append((peerName, peerKind))
        if let joinPeerHandler {
            return await joinPeerHandler()
        }
        return shouldJoinPeer
    }

    func pairingV2CoordinatorDismissConfirmation() async {
        dismissConfirmationCallCount += 1
        await dismissConfirmationHandler?()
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

    private static let negotiationCases: [(local: PairingV2ProtocolVersion, peer: String, expected: PairingV2ProtocolVersion)] = [
        (.v2Point1, "2.1", .v2Point1),
        (.v2Point1, "2.9", .v2Point1),
        (.v2Point1, "2", .v2),
        (.v2Point1, "2.0", .v2),
        (.v2, "2.1", .v2),
        (.v2, "2", .v2)
    ]

    func testWhenPresentingThenAdvertisesLocalCapabilityAndNegotiatesFromHello() async throws {
        let peerKeyPair = try makePeerKeyPair()
        let crypto = PairingV2MessageCrypto()

        for testCase in Self.negotiationCases {
            let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: MockSyncDependencies())
            let exchanger = PairingV2MessageExchangingMock()
            let coordinator = makeCoordinator(syncService: syncService, messageExchanger: exchanger, advertisedVersion: testCase.local)

            let payload = try await coordinator.startPresenting()
            XCTAssertEqual(payload.version, testCase.local.rawValue)
            XCTAssertEqual(coordinator.negotiatedVersion, .v2)
            exchanger.fetchMessagesStub = try encryptedPeerMessages(
                [.hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey, version: testCase.peer))],
                recipientPublicKey: payload.publicKey,
                peerKeyPair: peerKeyPair,
                messageCrypto: crypto)

            try await coordinator.pollOnce()

            XCTAssertEqual(coordinator.negotiatedVersion, testCase.expected, "Local: \(testCase.local.rawValue), peer: \(testCase.peer)")
            let status = try XCTUnwrap(exchanger.sendCalls.first?.messages.first)
            XCTAssertEqual(status.version, "2")
            await coordinator.cancel()
        }
    }

    func testWhenPresenterReceivesHelloWithMissingOrUnrecognizedCapabilityThenContinuesUsingV2() async throws {
        let peerKeyPair = try makePeerKeyPair()
        let localKeyPair = try makePeerKeyPair(channelID: "local-channel")
        let recipientPublicKey = try XCTUnwrap(SecKeyCopyPublicKey(localKeyPair.privateKey))
        let peerVersions: [String?] = [nil, "", " \t\n", "invalid", "1", "3", "3.1", "2.invalid", "2.-1", "2."]

        for peerVersion in peerVersions {
            let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: MockSyncDependencies())
            let exchanger = PairingV2MessageExchangingMock()
            let coordinator = makeCoordinator(syncService: syncService,
                                              messageExchanger: exchanger,
                                              advertisedVersion: .v2Point1,
                                              makeKeyPair: { localKeyPair })
            _ = try await coordinator.startPresenting()
            var hello = ["type": "hello", "channel_id": peerKeyPair.channelID, "public_key": peerKeyPair.publicKey]
            hello["version"] = peerVersion
            let payload = try JSONSerialization.data(withJSONObject: hello)
            let encrypted = try JWECompactCodec().encryptRSAOAEP256(payload: payload,
                                                                  recipientPublicKey: recipientPublicKey,
                                                                  kid: peerKeyPair.channelID)
            exchanger.fetchMessagesStub = [.init(seq: 1, version: "2", payload: encrypted)]

            try await coordinator.pollOnce()

            XCTAssertEqual(coordinator.negotiatedVersion, .v2, peerVersion ?? "missing")
            XCTAssertEqual(coordinator.state,
                           .waitingForPeerStatus(.init(localClient: .init(name: "Mac", kind: .ddg, hasAccount: false, isPresenter: true),
                                                       peerChannelID: nil)))
            let status = try XCTUnwrap(exchanger.sendCalls.first?.messages.first)
            XCTAssertEqual(status.version, "2")
            XCTAssertEqual(try PairingV2MessageCrypto().decrypt(status, privateKey: peerKeyPair.privateKey),
                           .recoveryCodeRequest(.init(type: "recovery_code_request", name: "Mac", kind: .ddg)))
            await coordinator.cancel()
        }
    }

    func testWhenScanningThenNegotiatesFromQRCodeButHelloAdvertisesLocalCapability() async throws {
        let peerKeyPair = try makePeerKeyPair()
        let crypto = PairingV2MessageCrypto()

        for testCase in Self.negotiationCases {
            let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: MockSyncDependencies())
            let exchanger = PairingV2MessageExchangingMock()
            let coordinator = makeCoordinator(syncService: syncService, messageExchanger: exchanger, advertisedVersion: testCase.local)

            try await coordinator.startScanning(qrPayload: .init(version: testCase.peer,
                                                                channelId: peerKeyPair.channelID,
                                                                publicKey: peerKeyPair.publicKey))

            XCTAssertEqual(coordinator.negotiatedVersion, testCase.expected, "Local: \(testCase.local.rawValue), peer: \(testCase.peer)")
            let hello = try localHello(from: exchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: crypto)
            XCTAssertEqual(hello.version, testCase.local.rawValue)
            XCTAssertEqual(exchanger.sendCalls.flatMap(\.messages).map(\.version), ["2", "2"])
            await coordinator.cancel()
        }
    }

    func testWhenScannerReceivesRedundantHelloThenKeepsVersionNegotiatedFromQRCode() async throws {
        let peerKeyPair = try makePeerKeyPair()
        let crypto = PairingV2MessageCrypto()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: MockSyncDependencies())
        let exchanger = PairingV2MessageExchangingMock()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: exchanger, advertisedVersion: .v2Point1)
        try await coordinator.startScanning(qrPayload: .init(version: "2", channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: exchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: crypto)
        exchanger.fetchMessagesStub = try encryptedPeerMessages(
            [.hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey, version: "2.1"))],
            recipientPublicKey: hello.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: crypto)

        try await coordinator.pollOnce()

        XCTAssertEqual(coordinator.negotiatedVersion, .v2)
        guard case .waitingForPeerStatus = coordinator.state else {
            return XCTFail("Expected redundant hello to be accepted")
        }
        await coordinator.cancel()
    }

    func testWhenStartingNewSessionThenDoesNotReusePreviousNegotiatedVersion() async throws {
        let peerKeyPair = try makePeerKeyPair()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: MockSyncDependencies())
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: PairingV2MessageExchangingMock(),
                                          advertisedVersion: .v2Point1)
        try await coordinator.startScanning(qrPayload: .init(version: "2.1", channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        XCTAssertEqual(coordinator.negotiatedVersion, .v2Point1)
        await coordinator.cancel()

        let payload = try await coordinator.startPresenting()

        XCTAssertEqual(payload.version, "2.1")
        XCTAssertEqual(coordinator.negotiatedVersion, .v2)
        await coordinator.cancel()
    }

    func testWhenStartPresentingThenOpensLocalChannelAndReturnsQRCodePayload() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger)

        let payload = try await coordinator.startPresenting()

        XCTAssertEqual(payload.version, PairingV2ProtocolVersion.v2.rawValue)
        XCTAssertFalse(payload.channelId.isEmpty)
        XCTAssertFalse(payload.publicKey.isEmpty)
        XCTAssertEqual(messageExchanger.openChannelCalls, [payload.channelId])
        XCTAssertEqual(
            coordinator.state,
            .waitingForPeerHello(.init(localClient: .init(name: "Mac", kind: .ddg, hasAccount: false, isPresenter: true), peerChannelID: nil))
        )
    }

    func testWhenPresenterKeyGenerationFailsThenAttachesPresenterGenerateCodeStage() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let coordinator = makeCoordinator(
            syncService: syncService,
            messageExchanger: PairingV2MessageExchangingMock(),
            makeKeyPair: { throw PairingV2CoordinatorTestError.keyGenerationFailed }
        )

        let failure = await pairingFailure {
            _ = try await coordinator.startPresenting()
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .presenterGenerateCode, kind: nil))
        XCTAssertNotNil(failure?.underlyingError as? PairingV2CoordinatorTestError)
    }

    func testWhenScannerKeyGenerationFailsThenAttachesScannerGenerateKeysStage() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let coordinator = makeCoordinator(
            syncService: syncService,
            messageExchanger: PairingV2MessageExchangingMock(),
            makeKeyPair: { throw PairingV2CoordinatorTestError.keyGenerationFailed }
        )

        let failure = await pairingFailure {
            try await coordinator.startScanning(qrPayload: .init(channelId: "peer-channel", publicKey: "peer-key"))
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .scannerGenerateKeys, kind: nil))
        XCTAssertNotNil(failure?.underlyingError as? PairingV2CoordinatorTestError)
    }

    func testRelayCommandsMapToEntryRoleFailureStages() {
        let peerStatus = PairingV2PeerStatus.recoveryCodeRequest(kind: .ddg)
        let testCases: [(command: PairingV2Command, presenter: PairingV2FailureStage?, scanner: PairingV2FailureStage?)] = [
            (.openV2Channel(channelID: nil), .presenterOpenOwnChannel, .scannerOpenOwnChannel),
            (.sendHello, nil, .scannerSendHello),
            (.sendRecoveryCodeStatus(peerStatus), .presenterSendPeerStatus, .scannerSendPeerStatus),
            (.sendRecoveryCodeAwaitingConfirmation, .presenterSendConfirmationStatus, .scannerSendConfirmationStatus),
            (.sendRecoveryCodeConfirmed, .presenterSendConfirmationStatus, .scannerSendConfirmationStatus),
            (.sendRecoveryCodeDenied, .presenterSendRecoveryDenied, .scannerSendRecoveryDenied),
            (.sendRecoveryCode("recovery-code"), .presenterSendRecoveryCode, .scannerSendRecoveryCode),
            (.sendRecoveryCodeUnavailable, .presenterSendRecoveryUnavailable, .scannerSendRecoveryUnavailable)
        ]

        for testCase in testCases {
            XCTAssertEqual(testCase.command.relayFailureStage(for: .presenter), testCase.presenter)
            XCTAssertEqual(testCase.command.relayFailureStage(for: .scanner), testCase.scanner)
        }
    }

    func testWhenPresenterOpenChannelFailsThenAttachesPresenterOpenStageAndKind() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.openChannelHandler = { _ in
            throw PairingV2RelayRequestError(kind: .httpError, underlyingError: SyncError.unexpectedStatusCode(503))
        }
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger)

        let failure = await pairingFailure {
            _ = try await coordinator.startPresenting()
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .presenterOpenOwnChannel, kind: .httpError))
        XCTAssertEqual(failure?.underlyingError as? SyncError, .unexpectedStatusCode(503))
        XCTAssertEqual(messageExchanger.openChannelCalls.count, 1)
    }

    func testWhenExchangeAuthenticationIsEnabledThenUsesOwnSecretForEveryRelayRequest() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let peerKeyPair = try makePeerKeyPair()
        let secret = "local-channel-secret"
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          canSendExchangeChannelSecret: true,
                                          makeChannelSecret: { secret })

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        try await coordinator.pollOnce()
        let closeChannelExpectation = expectation(description: "Local channel closed")
        messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }
        await coordinator.cancel()
        await fulfillment(of: [closeChannelExpectation], timeout: 2)

        XCTAssertEqual(messageExchanger.openChannelAuthorizationSecrets, [secret])
        XCTAssertEqual(messageExchanger.sendAuthorizationSecrets, [secret, secret])
        XCTAssertEqual(messageExchanger.fetchMessagesAuthorizationSecrets, [secret])
        XCTAssertEqual(messageExchanger.closeChannelAuthorizationSecrets, [secret])
    }

    func testWhenAdvertisingV21OrNewerThenAuthenticatesWithChannelSecretFlagDisabled() async throws {
        let peerKeyPair = try makePeerKeyPair()
        let secret = "local-channel-secret"

        for rawVersion in ["2.1", "2.3"] {
            let advertisedVersion = try XCTUnwrap(PairingV2ProtocolVersion(rawValue: rawVersion))
            for isPresenter in [true, false] {
                let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: MockSyncDependencies())
                let messageExchanger = PairingV2MessageExchangingMock()
                let coordinator = makeCoordinator(syncService: syncService,
                                                  messageExchanger: messageExchanger,
                                                  canSendExchangeChannelSecret: false,
                                                  advertisedVersion: advertisedVersion,
                                                  makeChannelSecret: { secret })

                if isPresenter {
                    _ = try await coordinator.startPresenting()
                } else {
                    try await coordinator.startScanning(qrPayload: .init(version: "2",
                                                                        channelId: peerKeyPair.channelID,
                                                                        publicKey: peerKeyPair.publicKey))
                }
                try await coordinator.pollOnce()
                let closeChannelExpectation = expectation(description: "Local channel closed")
                messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }
                await coordinator.cancel()
                await fulfillment(of: [closeChannelExpectation], timeout: 2)

                XCTAssertEqual(coordinator.negotiatedVersion, .v2)
                XCTAssertEqual(messageExchanger.openChannelAuthorizationSecrets, [secret])
                XCTAssertEqual(messageExchanger.sendAuthorizationSecrets, isPresenter ? [] : [secret, secret])
                XCTAssertEqual(messageExchanger.fetchMessagesAuthorizationSecrets, [secret])
                XCTAssertEqual(messageExchanger.closeChannelAuthorizationSecrets, [secret])
            }
        }
    }

    func testWhenExchangeAuthenticationIsDisabledThenDoesNotGenerateOrSendSecret() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let peerKeyPair = try makePeerKeyPair()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          canSendExchangeChannelSecret: false,
                                          makeChannelSecret: { throw PairingV2CoordinatorTestError.secretGenerationFailed })

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        try await coordinator.pollOnce()
        let closeChannelExpectation = expectation(description: "Local channel closed")
        messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }
        await coordinator.cancel()
        await fulfillment(of: [closeChannelExpectation], timeout: 2)

        XCTAssertEqual(messageExchanger.openChannelAuthorizationSecrets, [nil])
        XCTAssertEqual(messageExchanger.sendAuthorizationSecrets, [nil, nil])
        XCTAssertEqual(messageExchanger.fetchMessagesAuthorizationSecrets, [nil])
        XCTAssertEqual(messageExchanger.closeChannelAuthorizationSecrets, [nil])
    }

    func testWhenCancelledDuringChannelCreationThenClosesAcceptedChannelAndStopsStartup() async throws {
        for isPresenter in [true, false] {
            for shouldAuthenticate in [true, false] {
                let dependencies = MockSyncDependencies()
                let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
                let messageExchanger = PairingV2MessageExchangingMock()
                let keyPair = try makePeerKeyPair(channelID: "local-channel")
                let coordinator = makeCoordinator(syncService: syncService,
                                                  messageExchanger: messageExchanger,
                                                  canSendExchangeChannelSecret: shouldAuthenticate,
                                                  makeKeyPair: { keyPair },
                                                  makeChannelSecret: { "local-secret" })
                let openStarted = expectation(description: "Local channel creation started")
                let openGate = PairingV2CoordinatorTestGate()
                messageExchanger.openChannelHandler = { _ in
                    openStarted.fulfill()
                    await openGate.wait()
                }

                let startTask = Task {
                    do {
                        if isPresenter {
                            _ = try await coordinator.startPresenting()
                        } else {
                            try await coordinator.startScanning(qrPayload: .init(channelId: "peer-channel", publicKey: keyPair.publicKey))
                        }
                        XCTFail("Expected cancelled startup")
                    } catch {
                        XCTAssertEqual(error as? PairingV2Error, .cancelled)
                    }
                }

                await fulfillment(of: [openStarted], timeout: 2)
                await coordinator.cancel()
                XCTAssertTrue(messageExchanger.closeChannelCalls.isEmpty)

                await openGate.open()
                await startTask.value
                await coordinator.cancel()

                let expectedSecret: String? = shouldAuthenticate ? "local-secret" : nil
                XCTAssertEqual(coordinator.state, .failed(.cancelled))
                XCTAssertEqual(messageExchanger.openChannelCalls, ["local-channel"])
                XCTAssertEqual(messageExchanger.openChannelAuthorizationSecrets, [expectedSecret])
                XCTAssertEqual(messageExchanger.closeChannelCalls, ["local-channel"])
                XCTAssertEqual(messageExchanger.closeChannelAuthorizationSecrets, [expectedSecret])
                XCTAssertTrue(messageExchanger.sendCalls.isEmpty)
                XCTAssertTrue(messageExchanger.fetchMessagesCalls.isEmpty)
            }
        }
    }

    func testWhenChannelCreationFailsWithAmbiguousNetworkErrorThenAttemptsCleanup() async throws {
        for isPresenter in [true, false] {
            for shouldAuthenticate in [true, false] {
                let dependencies = MockSyncDependencies()
                let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
                let messageExchanger = PairingV2MessageExchangingMock()
                let keyPair = try makePeerKeyPair(channelID: "local-channel")
                let coordinator = makeCoordinator(syncService: syncService,
                                                  messageExchanger: messageExchanger,
                                                  advertisedVersion: shouldAuthenticate ? .v2Point1 : .v2,
                                                  makeKeyPair: { keyPair },
                                                  makeChannelSecret: { "local-secret" })
                messageExchanger.openChannelHandler = { _ in
                    throw PairingV2RelayRequestError(kind: .networkError, underlyingError: URLError(.timedOut))
                }

                let failure = await pairingFailure {
                    if isPresenter {
                        _ = try await coordinator.startPresenting()
                    } else {
                        try await coordinator.startScanning(qrPayload: .init(channelId: "peer-channel", publicKey: keyPair.publicKey))
                    }
                }

                let expectedStage: PairingV2FailureStage = isPresenter ? .presenterOpenOwnChannel : .scannerOpenOwnChannel
                let expectedSecret: String? = shouldAuthenticate ? "local-secret" : nil

                XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: expectedStage, kind: .networkError))
                XCTAssertEqual(messageExchanger.openChannelCalls, ["local-channel"])
                XCTAssertEqual(messageExchanger.openChannelAuthorizationSecrets, [expectedSecret])
                XCTAssertEqual(messageExchanger.closeChannelCalls, ["local-channel"])
                XCTAssertEqual(messageExchanger.closeChannelAuthorizationSecrets, [expectedSecret])

                await coordinator.cancel()
                XCTAssertEqual(messageExchanger.closeChannelCalls, ["local-channel"])
            }
        }
    }

    func testWhenChannelClaimConflictsThenFailsWithoutRetrying() async throws {
        for isPresenter in [true, false] {
            let dependencies = MockSyncDependencies()
            let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
            let messageExchanger = PairingV2MessageExchangingMock()
            messageExchanger.openChannelHandler = { _ in
                throw PairingV2RelayRequestError(kind: .httpError, underlyingError: SyncError.unexpectedStatusCode(409))
            }
            let keyPair = try makePeerKeyPair(channelID: "local-channel")
            let coordinator = makeCoordinator(syncService: syncService,
                                              messageExchanger: messageExchanger,
                                              canSendExchangeChannelSecret: true,
                                              makeKeyPair: { keyPair },
                                              makeChannelSecret: { "local-secret" })

            let failure = await pairingFailure {
                if isPresenter {
                    _ = try await coordinator.startPresenting()
                } else {
                    try await coordinator.startScanning(qrPayload: .init(channelId: "peer-channel", publicKey: keyPair.publicKey))
                }
            }

            let failureStage: PairingV2FailureStage = isPresenter ? .presenterOpenOwnChannel : .scannerOpenOwnChannel
            XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: failureStage, kind: .httpError))
            XCTAssertEqual(failure?.underlyingError as? SyncError, .unexpectedStatusCode(409))
            XCTAssertEqual(messageExchanger.openChannelCalls, ["local-channel"])
            XCTAssertEqual(messageExchanger.openChannelAuthorizationSecrets, ["local-secret"])
            XCTAssertTrue(messageExchanger.sendCalls.isEmpty)

            await coordinator.cancel()
            XCTAssertTrue(messageExchanger.closeChannelCalls.isEmpty)
        }
    }

    func testWhenChannelSecretGenerationFailsThenAttachesGenerateCodeStage() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          canSendExchangeChannelSecret: true,
                                          makeChannelSecret: { throw PairingV2CoordinatorTestError.secretGenerationFailed })

        let failure = await pairingFailure {
            _ = try await coordinator.startPresenting()
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .presenterGenerateCode, kind: nil))
        XCTAssertNotNil(failure?.underlyingError as? PairingV2CoordinatorTestError)
        XCTAssertTrue(messageExchanger.openChannelCalls.isEmpty)
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
                  version: PairingV2ProtocolVersion.v2.rawValue,
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
        let closeChannelExpectation = expectation(description: "Local channel closed")
        messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)
        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.v2.rawValue,
                  payload: try messageCrypto.encrypt(
                    .hello(.init(channelId: peerKeyPair.channelID, publicKey: "mismatched-public-key")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]

        try await coordinator.pollOnce()

        await fulfillment(of: [closeChannelExpectation], timeout: 2)
        XCTAssertEqual(coordinator.state, .failed(error))
        XCTAssertEqual(messageExchanger.closeChannelCalls, [hello.channelId])
    }

    func testWhenPresenterPollReceivesRelayChannelUnavailableThenFailsWithPresenterPollContext() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesError = PairingV2Error.relayChannelUnavailable

        let failure = await pairingFailure {
            try await coordinator.pollOnce()
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .presenterPollOwnChannel, kind: .unavailable))
        XCTAssertEqual(messageExchanger.fetchMessagesCalls.map(\.channelID), [payload.channelId])
        XCTAssertEqual(messageExchanger.closeChannelCalls, [payload.channelId])
        XCTAssertEqual(coordinator.state, .failed(.relayChannelUnavailable))

        await coordinator.cancel()

        XCTAssertEqual(messageExchanger.closeChannelCalls, [payload.channelId])
    }

    func testWhenScannerPollReceivesRelayChannelExpiredThenFailsWithScannerPollContext() async throws {
        let dependencies = MockSyncDependencies()
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let coordinator = makeCoordinator(syncService: syncService, messageExchanger: messageExchanger)
        let peerKeyPair = try makePeerKeyPair()

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        messageExchanger.fetchMessagesError = PairingV2Error.relayChannelExpired

        let failure = await pairingFailure {
            try await coordinator.pollOnce()
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .scannerPollOwnChannel, kind: .expired))
        XCTAssertEqual(coordinator.state, .failed(.relayChannelExpired))
    }

    func testWhenPresenterPeerStatusSendReceivesRelayChannelUnavailableThenAttachesPeerStatusContext() async throws {
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

        let failure = await pairingFailure {
            try await coordinator.pollOnce()
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .presenterSendPeerStatus, kind: .unavailable))
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
        try await settlePendingConfirmation(in: coordinator)

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

    func testWhenV21HostSendsRecoveryCodeThenWaitsForAnyValidJoinStatus() async throws {
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
                                          confirmationDelegate: confirmationDelegate,
                                          advertisedVersion: .v2Point1)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey, version: "2.1")),
                .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                           name: "Peer",
                                           kind: .ddg))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )

        try await coordinator.pollOnce()
        try await settlePendingConfirmation(in: coordinator)

        guard case .hostWaitingForJoinStatus = coordinator.state else {
            XCTFail("Expected host to wait for join status, got \(coordinator.state)")
            return
        }
        let encryptedDone = try messageCrypto.encrypt(
            .recoveryCodeDone(.init(reason: .unknown("future_reason"))),
            recipientPublicKey: payload.publicKey,
            senderChannelID: peerKeyPair.channelID
        )
        messageExchanger.fetchMessagesStub = [
            .init(seq: 3, version: encryptedDone.version, payload: encryptedDone.payload)
        ]

        try await coordinator.pollOnce()

        XCTAssertEqual(coordinator.state, .completed(.recoveryCodeSent(credentialKind: .ddg)))
    }

    func testWhenV21PeerCancelsWhileConfirmationIsPendingThenDismissesAndNeverReleasesRecoveryCode() async throws {
        let confirmationGate = PairingV2CoordinatorTestGate()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        confirmationDelegate.allowPeerToJoinHandler = {
            await confirmationGate.wait()
            return true
        }
        confirmationDelegate.dismissConfirmationHandler = {
            await confirmationGate.open()
        }
        let setup = try await makeHostWithPendingConfirmationAndQueuedBye(confirmationDelegate: confirmationDelegate)
        let closeChannelExpectation = expectation(description: "Local channel closed")
        setup.messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }
        try await setup.coordinator.pollOnce()
        try await setup.coordinator.pollOnce() // A dismissed confirmation must not affect the finished session.
        await fulfillment(of: [closeChannelExpectation], timeout: 2)

        let sentMessages = try decryptedSentMessages(from: setup.messageExchanger,
                                                     peerPrivateKey: setup.peerKeyPair.privateKey,
                                                     messageCrypto: setup.messageCrypto)
        XCTAssertEqual(confirmationDelegate.dismissConfirmationCallCount, 1)
        XCTAssertEqual(setup.coordinator.state, .failed(.peerCancelled))
        XCTAssertFalse(sentMessages.contains { message in
            if case .recoveryCodeResponse = message { return true }
            return false
        })
        XCTAssertEqual(sentMessages.last, .bye(.init(reason: .done)))
        XCTAssertEqual(setup.messageExchanger.closeChannelCalls, [setup.localChannelID])
    }

    func testWhenPeerLeavesDuringConfirmationThenTeardownSendsByeDoneForEveryReason() async throws {
        for reason in [PairingV2ByeReason.done, .cancelled, .error, .unknown("future_reason")] {
            let confirmationGate = PairingV2CoordinatorTestGate()
            let confirmationDelegate = PairingV2ConfirmationDelegateMock()
            confirmationDelegate.allowPeerToJoinHandler = {
                await confirmationGate.wait()
                return false
            }
            confirmationDelegate.dismissConfirmationHandler = {
                await confirmationGate.open()
            }
            let setup = try await makeHostWithPendingConfirmationAndQueuedBye(confirmationDelegate: confirmationDelegate, byeReason: reason)
            let closeChannelExpectation = expectation(description: "Local channel closed")
            setup.messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }

            try await setup.coordinator.pollOnce()
            await fulfillment(of: [closeChannelExpectation], timeout: 2)

            let sentMessages = try decryptedSentMessages(from: setup.messageExchanger,
                                                         peerPrivateKey: setup.peerKeyPair.privateKey,
                                                         messageCrypto: setup.messageCrypto)
            XCTAssertEqual(sentMessages.last, .bye(.init(reason: .done)))
            XCTAssertEqual(setup.messageExchanger.closeChannelCalls, [setup.localChannelID])
        }
    }

    func testWhenConfirmationIsHandledBeforeByeThenReleasesRecoveryCodeOnlyOnce() async throws {
        let confirmationGate = PairingV2CoordinatorTestGate()
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        confirmationDelegate.allowPeerToJoinHandler = {
            await confirmationGate.wait()
            return true
        }
        let setup = try await makeHostWithPendingConfirmationAndQueuedBye(confirmationDelegate: confirmationDelegate)
        let closeChannelExpectation = expectation(description: "Local channel closed")
        setup.messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }
        let byeMessages = setup.messageExchanger.fetchMessagesStub
        setup.messageExchanger.fetchMessagesStub = []

        await confirmationGate.open()
        try await settlePendingConfirmation(in: setup.coordinator)
        guard case .hostWaitingForJoinStatus = setup.coordinator.state else {
            XCTFail("Expected host to await join status, got \(setup.coordinator.state)")
            return
        }

        setup.messageExchanger.fetchMessagesStub = byeMessages
        try await setup.coordinator.pollOnce()
        try await setup.coordinator.pollOnce()
        await fulfillment(of: [closeChannelExpectation], timeout: 2)

        let sentMessages = try decryptedSentMessages(from: setup.messageExchanger,
                                                     peerPrivateKey: setup.peerKeyPair.privateKey,
                                                     messageCrypto: setup.messageCrypto)
        XCTAssertEqual(sentMessages.filter { message in
            if case .recoveryCodeResponse = message { return true }
            return false
        }.count, 1)
        XCTAssertEqual(sentMessages.filter { message in
            if case .bye = message { return true }
            return false
        }.count, 1)
        XCTAssertEqual(confirmationDelegate.dismissConfirmationCallCount, 0)
        XCTAssertEqual(setup.coordinator.state, .failed(.peerCancelled))
        XCTAssertEqual(setup.messageExchanger.closeChannelCalls, [setup.localChannelID])
    }

    func testWhenConfirmationAndByeArriveDuringSamePollThenNeverReleasesRecoveryCode() async throws {
        let confirmationGate = PairingV2CoordinatorTestGate()
        let confirmationAnswered = expectation(description: "UI returns acceptance during the peer message fetch")
        let confirmationDelegate = PairingV2ConfirmationDelegateMock()
        confirmationDelegate.allowPeerToJoinHandler = {
            await confirmationGate.wait()
            confirmationAnswered.fulfill()
            return true
        }
        let setup = try await makeHostWithPendingConfirmationAndQueuedBye(confirmationDelegate: confirmationDelegate)
        let closeChannelExpectation = expectation(description: "Local channel closed")
        setup.messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }
        let byeMessages = setup.messageExchanger.fetchMessagesStub
        setup.messageExchanger.fetchMessagesHandler = { _, _ in
            // This poll has already checked for a confirmation result. Release the UI answer
            // while its fetch is in flight, then deliver bye in the same poll.
            await confirmationGate.open()
            await self.fulfillment(of: [confirmationAnswered], timeout: 1)
            return byeMessages
        }

        try await setup.coordinator.pollOnce()
        try await setup.coordinator.pollOnce()
        await fulfillment(of: [closeChannelExpectation], timeout: 2)

        let sentMessages = try decryptedSentMessages(from: setup.messageExchanger,
                                                     peerPrivateKey: setup.peerKeyPair.privateKey,
                                                     messageCrypto: setup.messageCrypto)
        XCTAssertFalse(sentMessages.contains { message in
            if case .recoveryCodeResponse = message { return true }
            return false
        })
        XCTAssertEqual(sentMessages.filter { message in
            if case .bye = message { return true }
            return false
        }.count, 1)
        XCTAssertEqual(confirmationDelegate.dismissConfirmationCallCount, 1)
        XCTAssertEqual(setup.coordinator.state, .failed(.peerCancelled))
        XCTAssertEqual(setup.messageExchanger.closeChannelCalls, [setup.localChannelID])
    }

    func testWhenV21FinalByeFailsThenStillDeletesChannelOnceWithoutRetrying() async throws {
        let dependencies = MockSyncDependencies()
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        var operations: [String] = []
        let closeChannelExpectation = expectation(description: "Local channel closed")
        messageExchanger.sendHandler = { messages, _ in
            operations.append("send")
            if messages.first?.version == PairingV2ProtocolVersion.v2Point1.rawValue {
                throw PairingV2CoordinatorTestError.loginFailed
            }
        }
        messageExchanger.closeChannelHandler = { _ in
            operations.append("close")
            closeChannelExpectation.fulfill()
        }
        let coordinator = makeCoordinator(syncService: DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies),
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          advertisedVersion: .v2Point1)

        try await coordinator.startScanning(
            qrPayload: .init(version: "2.1", channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        )
        await coordinator.cancel()
        await coordinator.cancel()
        await fulfillment(of: [closeChannelExpectation], timeout: 2)

        let sentMessages = try decryptedSentMessages(from: messageExchanger,
                                                     peerPrivateKey: peerKeyPair.privateKey,
                                                     messageCrypto: messageCrypto)
        XCTAssertEqual(operations.suffix(2), ["send", "close"])
        XCTAssertEqual(sentMessages.filter { message in
            if case .bye = message { return true }
            return false
        }, [.bye(.init(reason: .cancelled))])
        XCTAssertEqual(messageExchanger.closeChannelCalls.count, 1)
        XCTAssertEqual(messageExchanger.sendAuthorizationSecrets.last, messageExchanger.closeChannelAuthorizationSecrets.last)
    }

    func testWhenV2SessionIsCancelledThenClosesWithoutSendingBye() async throws {
        let dependencies = MockSyncDependencies()
        let messageExchanger = PairingV2MessageExchangingMock()
        let peerKeyPair = try makePeerKeyPair()
        let coordinator = makeCoordinator(syncService: DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies),
                                          messageExchanger: messageExchanger,
                                          advertisedVersion: .v2)

        try await coordinator.startScanning(
            qrPayload: .init(version: "2", channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        )
        let closeChannelExpectation = expectation(description: "Local channel closed")
        messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }
        await coordinator.cancel()
        await fulfillment(of: [closeChannelExpectation], timeout: 2)

        XCTAssertEqual(messageExchanger.sendCalls.flatMap(\.messages).map(\.version), ["2", "2"])
        XCTAssertEqual(messageExchanger.closeChannelCalls.count, 1)
    }

    func testWhenV2SessionReceivesByeThenIgnoresIt() async throws {
        let dependencies = MockSyncDependencies()
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let coordinator = makeCoordinator(syncService: DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies),
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          advertisedVersion: .v2)

        try await coordinator.startScanning(
            qrPayload: .init(version: "2", channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        )
        let hello = try localHello(from: messageExchanger,
                                   peerPrivateKey: peerKeyPair.privateKey,
                                   messageCrypto: messageCrypto)
        let encryptedBye = try messageCrypto.encrypt(.bye(.init(reason: .cancelled)),
                                                     recipientPublicKey: hello.publicKey,
                                                     senderChannelID: peerKeyPair.channelID)
        messageExchanger.fetchMessagesStub = [
            .init(seq: 1, version: encryptedBye.version, payload: encryptedBye.payload)
        ]

        try await coordinator.pollOnce()

        guard case .waitingForPeerStatus = coordinator.state else {
            XCTFail("Expected v2 session to ignore bye, got \(coordinator.state)")
            return
        }
        XCTAssertTrue(messageExchanger.closeChannelCalls.isEmpty)
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
        try await settlePendingConfirmation(in: coordinator)

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

        let failure = await pairingFailure {
            try await coordinator.pollOnce()
            try await settlePendingConfirmation(in: coordinator)
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .presenterSendConfirmationStatus, kind: .unavailable))
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
            try await settlePendingConfirmation(in: coordinator)
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

    func testWhenPresenterRecoveryUnavailableSendFailsThenAttachesRecoveryUnavailableContext() async throws {
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
        messageExchanger.sendHandler = { _, _ in
            if messageExchanger.sendCalls.count == 4 {
                throw PairingV2RelayRequestError(kind: .networkError, underlyingError: URLError(.notConnectedToInternet))
            }
        }

        let failure = await pairingFailure {
            try await coordinator.pollOnce()
            try await settlePendingConfirmation(in: coordinator)
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .presenterSendRecoveryUnavailable, kind: .networkError))
        XCTAssertEqual((failure?.underlyingError as? URLError)?.code, .notConnectedToInternet)
        XCTAssertEqual(coordinator.state, .failed(.accountCreationFailed))
        XCTAssertEqual(messageExchanger.sendCalls.count, 4)
        XCTAssertEqual(messageExchanger.closeChannelCalls, [payload.channelId])
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
        let closeChannelExpectation = expectation(description: "Local channel closed")
        messageExchanger.closeChannelHandler = { _ in closeChannelExpectation.fulfill() }

        do {
            try await coordinator.pollOnce()
            try await settlePendingConfirmation(in: coordinator)
            XCTFail("Expected PairingV2Error.recoveryCodePreparationFailed")
        } catch PairingV2Error.recoveryCodePreparationFailed {
        } catch {
            XCTFail("Expected PairingV2Error.recoveryCodePreparationFailed, got \(error)")
        }
        await fulfillment(of: [closeChannelExpectation], timeout: 2)

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
        try await settlePendingConfirmation(in: coordinator)

        XCTAssertEqual(confirmationDelegate.allowPeerToJoinCalls.map { $0.peerName }, ["Peer"])
        XCTAssertEqual(confirmationDelegate.allowPeerToJoinCalls.map { $0.peerKind }, [.ddg])
        XCTAssertEqual(
            try decryptSentMessage(at: 2, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeDenied(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeDenied))
        )
        XCTAssertEqual(coordinator.state, .failed(.cancelled))
        XCTAssertEqual(messageExchanger.closeChannelCalls, [payload.channelId])
    }

    func testWhenScannerHostConfirmationIsDeniedAndNotifyFailsThenAttachesScannerSendRecoveryDeniedContext() async throws {
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

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                           name: "Peer",
                                           kind: .ddg))
            ],
            recipientPublicKey: hello.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )
        messageExchanger.sendHandler = { _, _ in
            if messageExchanger.sendCalls.count == 4 {
                throw PairingV2RelayRequestError(kind: .httpError, underlyingError: SyncError.unexpectedStatusCode(500))
            }
        }

        let failure = await pairingFailure {
            try await coordinator.pollOnce()
            try await settlePendingConfirmation(in: coordinator)
        }

        XCTAssertEqual(failure?.context, PairingV2FailureContext(stage: .scannerSendRecoveryDenied, kind: .httpError))
        XCTAssertEqual(failure?.underlyingError as? SyncError, .unexpectedStatusCode(500))
        XCTAssertEqual(confirmationDelegate.allowPeerToJoinCalls.map { $0.peerName }, ["Peer"])
        XCTAssertEqual(confirmationDelegate.allowPeerToJoinCalls.map { $0.peerKind }, [.ddg])
        XCTAssertEqual(
            try decryptSentMessage(at: 3, from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto),
            .recoveryCodeDenied(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeDenied))
        )
        XCTAssertEqual(coordinator.state, .failed(.cancelled))
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
                  version: PairingV2ProtocolVersion.v2.rawValue,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .ddg,
                                                 userId: userId)),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()
        try await settlePendingConfirmation(in: coordinator)

        let recoveryCode = try Self.makeRecoveryCodeV2(userId: userId,
                                                       secret: Base64URL.encode(primaryKey),
                                                       credentialId: SyncCredentialID.defaultCredential)
        messageExchanger.fetchMessagesStub = [
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.v2.rawValue,
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
        XCTAssertEqual(messageExchanger.sendCalls.count, 2, "V2 joiners must not send recovery_code_done")
    }

    func testWhenV21NativeJoinerLogsInThenReportsSuccessBeforeCompleting() async throws {
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
                                          confirmationDelegate: confirmationDelegate,
                                          advertisedVersion: .v2Point1)
        let userId = "v2-ddg-user"
        let primaryKey = Data((0..<32).map(UInt8.init))

        try await coordinator.startScanning(
            qrPayload: .init(version: "2.1", channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        )
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)
        let recoveryCode = try Self.makeRecoveryCodeV2(userId: userId,
                                                       secret: Base64URL.encode(primaryKey),
                                                       credentialId: SyncCredentialID.defaultCredential)
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                             name: "Peer",
                                             kind: .ddg,
                                             userId: userId)),
                .recoveryCodeResponse(.init(recoveryCode: recoveryCode))
            ],
            recipientPublicKey: hello.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )

        try await coordinator.pollOnce()
        try await settlePendingConfirmation(in: coordinator)

        let sentDone = try decryptSentMessage(at: 2,
                                              from: messageExchanger,
                                              peerPrivateKey: peerKeyPair.privateKey,
                                              messageCrypto: messageCrypto)
        XCTAssertEqual(sentDone, .recoveryCodeDone(.init(reason: .success)))
        XCTAssertEqual(messageExchanger.sendCalls[2].messages.first?.version, "2.1")
        XCTAssertEqual(try recoveryCodeDoneCount(in: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto), 1)
        XCTAssertEqual(try decryptedSentMessages(from: messageExchanger,
                                                 peerPrivateKey: peerKeyPair.privateKey,
                                                 messageCrypto: messageCrypto).last,
                       .bye(.init(reason: .done)))
        XCTAssertEqual(coordinator.state, .completed(.loggedIn))
    }

    func testWhenRecoveryCodeArrivesBeforeConfirmationThenRetainsItAcrossPollsUntilAccepted() async throws {
        let setup = try await makeNativeJoinerReadyForLogin()
        let confirmationGate = PairingV2CoordinatorTestGate()
        setup.confirmationDelegate.joinPeerHandler = {
            await confirmationGate.wait()
            return true
        }

        try await setup.coordinator.pollOnce()
        guard case .joinerWaitingForConfirmation = setup.coordinator.state else {
            XCTFail("Expected pending joiner confirmation, got \(setup.coordinator.state)")
            await confirmationGate.open()
            return
        }
        XCTAssertNil(setup.coordinator.pendingRecoveryKey)

        let hello = try localHello(from: setup.messageExchanger,
                                   peerPrivateKey: setup.peerKeyPair.privateKey,
                                   messageCrypto: setup.messageCrypto)
        let confirmed = try setup.messageCrypto.encrypt(
            .recoveryCodeConfirmed(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed)),
            recipientPublicKey: hello.publicKey,
            senderChannelID: setup.peerKeyPair.channelID)
        setup.messageExchanger.fetchMessagesStub = [.init(seq: 3, version: confirmed.version, payload: confirmed.payload)]
        try await setup.coordinator.pollOnce()
        XCTAssertNil(setup.coordinator.pendingRecoveryKey)

        setup.messageExchanger.fetchMessagesStub = []
        await confirmationGate.open()
        try await settlePendingConfirmation(in: setup.coordinator)

        XCTAssertEqual(setup.coordinator.state, .completed(.loggedIn))
        XCTAssertNotNil(setup.coordinator.pendingRecoveryKey)
        XCTAssertEqual(try recoveryCodeDoneCount(in: setup.messageExchanger,
                                                 peerPrivateKey: setup.peerKeyPair.privateKey,
                                                 messageCrypto: setup.messageCrypto), 1)
    }

    func testWhenPeerDeniesWhileConfirmationIsPendingThenDismissesAndDiscardsBufferedRecoveryCode() async throws {
        let setup = try await makeNativeJoinerReadyForLogin()
        let confirmationGate = PairingV2CoordinatorTestGate()
        setup.confirmationDelegate.joinPeerHandler = {
            await confirmationGate.wait()
            return true
        }
        setup.confirmationDelegate.dismissConfirmationHandler = {
            await confirmationGate.open()
        }

        try await setup.coordinator.pollOnce()
        let hello = try localHello(from: setup.messageExchanger,
                                   peerPrivateKey: setup.peerKeyPair.privateKey,
                                   messageCrypto: setup.messageCrypto)
        let denied = try setup.messageCrypto.encrypt(
            .recoveryCodeDenied(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeDenied)),
            recipientPublicKey: hello.publicKey,
            senderChannelID: setup.peerKeyPair.channelID)
        setup.messageExchanger.fetchMessagesStub = [.init(seq: 3, version: denied.version, payload: denied.payload)]

        try await setup.coordinator.pollOnce()
        try await setup.coordinator.pollOnce()

        XCTAssertEqual(setup.coordinator.state, .failed(.recoveryCodeDenied))
        XCTAssertEqual(setup.confirmationDelegate.dismissConfirmationCallCount, 1)
        XCTAssertNil(setup.coordinator.pendingRecoveryKey)
        XCTAssertEqual(try recoveryCodeDoneCount(in: setup.messageExchanger,
                                                 peerPrivateKey: setup.peerKeyPair.privateKey,
                                                 messageCrypto: setup.messageCrypto), 0)
    }

    func testWhenV21NativeJoinerLoginFailsThenReportsLoginFailedOnce() async throws {
        let testCases: [(name: String, error: Error, expectedError: PairingV2Error)] = [
            ("unauthorized", SyncError.unexpectedStatusCode(401), .invalidCredentials),
            ("secure store", SyncError.failedToWriteSecureStore(status: -1), .localStorageFailed),
            ("generic", PairingV2CoordinatorTestError.loginFailed, .loginFailed)
        ]

        for testCase in testCases {
            let setup = try await makeNativeJoinerReadyForLogin(loginError: testCase.error)

            do {
                try await setup.coordinator.pollOnce()
                try await settlePendingConfirmation(in: setup.coordinator)
                XCTFail("Expected \(testCase.name) login to fail")
            } catch let error as PairingV2Error {
                XCTAssertEqual(error, testCase.expectedError, testCase.name)
            } catch {
                XCTFail("Unexpected \(testCase.name) login error: \(error)")
            }

            XCTAssertEqual(
                try decryptSentMessage(at: 2,
                                       from: setup.messageExchanger,
                                       peerPrivateKey: setup.peerKeyPair.privateKey,
                                       messageCrypto: setup.messageCrypto),
                .recoveryCodeDone(.init(reason: .loginFailed)),
                testCase.name
            )
            XCTAssertEqual(try recoveryCodeDoneCount(in: setup.messageExchanger,
                                                     peerPrivateKey: setup.peerKeyPair.privateKey,
                                                     messageCrypto: setup.messageCrypto), 1,
                           "\(testCase.name) must be reported at most once")
            XCTAssertEqual(try decryptedSentMessages(from: setup.messageExchanger,
                                                     peerPrivateKey: setup.peerKeyPair.privateKey,
                                                     messageCrypto: setup.messageCrypto).last,
                           .bye(.init(reason: .error)),
                           testCase.name)
            XCTAssertEqual(setup.coordinator.state, .failed(testCase.expectedError), testCase.name)
        }
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
                  version: PairingV2ProtocolVersion.v2.rawValue,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .ddg,
                                                 userId: userId)),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload),
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.v2.rawValue,
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
                                               canSendExchangeChannelSecret: false,
                                               advertisedVersion: .v2,
                                               confirmationDelegate: confirmationDelegate)

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.v2.rawValue,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .thirdParty,
                                                 userId: "third-party-user")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()
        try await settlePendingConfirmation(in: coordinator)
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
                  version: PairingV2ProtocolVersion.v2.rawValue,
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

    func testWhenV21ThirdPartyUpgradeSucceedsThenReportsSuccessOnce() async throws {
        let setup = try await makeNativeJoinerReadyForThirdPartyUpgrade(
            advertisedVersion: .v2Point1,
            peerVersion: .v2Point1
        )

        try await setup.coordinator.pollOnce()

        XCTAssertEqual(
            try decryptSentMessage(at: 2,
                                   from: setup.messageExchanger,
                                   peerPrivateKey: setup.peerKeyPair.privateKey,
                                   messageCrypto: setup.messageCrypto),
            .recoveryCodeDone(.init(reason: .success))
        )
        XCTAssertEqual(try recoveryCodeDoneCount(in: setup.messageExchanger,
                                                 peerPrivateKey: setup.peerKeyPair.privateKey,
                                                 messageCrypto: setup.messageCrypto), 1)
        XCTAssertEqual(setup.coordinator.state, .completed(.loggedIn))
    }

    func testWhenV21ThirdPartyUpgradeFailsThenReportsScopeRejectedBeforeFailing() async throws {
        let setup = try await makeNativeJoinerReadyForThirdPartyUpgrade(
            upgradeError: ThirdPartyAccountUpgradeError.noUsableThirdPartyProtectedKeys,
            advertisedVersion: .v2Point1,
            peerVersion: .v2Point1
        )

        do {
            try await setup.coordinator.pollOnce()
            XCTFail("Expected missing third-party key to abort pairing")
        } catch PairingV2Error.missingThirdPartyKey {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            try decryptSentMessage(at: 2,
                                   from: setup.messageExchanger,
                                   peerPrivateKey: setup.peerKeyPair.privateKey,
                                   messageCrypto: setup.messageCrypto),
            .recoveryCodeDone(.init(reason: .scopeRejected))
        )
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
                                               canSendExchangeChannelSecret: false,
                                               advertisedVersion: .v2,
                                               confirmationDelegate: confirmationDelegate)

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.v2.rawValue,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .thirdParty,
                                                 userId: "third-party-user")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()
        try await settlePendingConfirmation(in: coordinator)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.v2.rawValue,
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

    private func makeHostWithPendingConfirmationAndQueuedBye(confirmationDelegate: PairingV2ConfirmationDelegateMock,
                                                             byeReason: PairingV2ByeReason = .cancelled) async throws -> (
        coordinator: PairingV2Coordinator,
        messageExchanger: PairingV2MessageExchangingMock,
        messageCrypto: PairingV2MessageCrypto,
        peerKeyPair: PairingV2KeyPair,
        localChannelID: String
    ) {
        let dependencies = MockSyncDependencies()
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try makePeerKeyPair()
        let coordinator = makeCoordinator(syncService: syncService,
                                          messageExchanger: messageExchanger,
                                          messageCrypto: messageCrypto,
                                          confirmationDelegate: confirmationDelegate,
                                          advertisedVersion: .v2Point1)

        let payload = try await coordinator.startPresenting()
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey, version: "2.1")),
                .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                           name: "Peer",
                                           kind: .ddg))
            ],
            recipientPublicKey: payload.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )
        try await coordinator.pollOnce()
        guard case .hostWaitingForConfirmation = coordinator.state else {
            XCTFail("Expected pending host confirmation, got \(coordinator.state)")
            throw PairingV2CoordinatorTestError.expectedPendingConfirmation
        }

        let encryptedBye = try messageCrypto.encrypt(.bye(.init(reason: byeReason)),
                                                     recipientPublicKey: payload.publicKey,
                                                     senderChannelID: peerKeyPair.channelID)
        messageExchanger.fetchMessagesStub = [
            .init(seq: 3, version: encryptedBye.version, payload: encryptedBye.payload)
        ]
        return (coordinator, messageExchanger, messageCrypto, peerKeyPair, payload.channelId)
    }

    private func makeNativeJoinerReadyForThirdPartyUpgrade(
        upgradeError: Error? = nil,
        advertisedVersion: PairingV2ProtocolVersion = .v2,
        peerVersion: PairingV2ProtocolVersion = .v2
    ) async throws -> NativeJoinerThirdPartyUpgradeSetup {
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
                                               canSendExchangeChannelSecret: false,
                                               advertisedVersion: advertisedVersion,
                                               confirmationDelegate: confirmationDelegate)

        try await coordinator.startScanning(
            qrPayload: .init(version: peerVersion.rawValue, channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        )
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.v2.rawValue,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .thirdParty,
                                                 userId: "third-party-user")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()
        try await settlePendingConfirmation(in: coordinator)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.v2.rawValue,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeResponse(.init(recoveryCode: "third-party-recovery-code")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]

        return (coordinator, upgradeCoordinator, messageExchanger, messageCrypto, peerKeyPair)
    }

    private func makeNativeJoinerReadyForLogin(loginError: Error? = nil) async throws -> (
        coordinator: PairingV2Coordinator,
        messageExchanger: PairingV2MessageExchangingMock,
        messageCrypto: PairingV2MessageCrypto,
        peerKeyPair: PairingV2KeyPair,
        confirmationDelegate: PairingV2ConfirmationDelegateMock
    ) {
        let dependencies = MockSyncDependencies()
        let accountManager = AccountManagingMock()
        accountManager.loginError = loginError
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
                                          confirmationDelegate: confirmationDelegate,
                                          advertisedVersion: .v2Point1)
        let userId = "v2-ddg-user"
        let recoveryCode = try Self.makeRecoveryCodeV2(
            userId: userId,
            secret: Base64URL.encode(Data((0..<32).map(UInt8.init))),
            credentialId: SyncCredentialID.defaultCredential
        )

        try await coordinator.startScanning(
            qrPayload: .init(version: "2.1", channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        )
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)
        messageExchanger.fetchMessagesStub = try encryptedPeerMessages(
            [
                .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                             name: "Peer",
                                             kind: .ddg,
                                             userId: userId)),
                .recoveryCodeResponse(.init(recoveryCode: recoveryCode))
            ],
            recipientPublicKey: hello.publicKey,
            peerKeyPair: peerKeyPair,
            messageCrypto: messageCrypto
        )

        return (coordinator, messageExchanger, messageCrypto, peerKeyPair, confirmationDelegate)
    }

    private func settlePendingConfirmation(in coordinator: PairingV2Coordinator) async throws {
        for _ in 0..<100 {
            switch coordinator.state {
            case .hostWaitingForConfirmation, .joinerWaitingForConfirmation:
                await Task.yield()
                try await coordinator.pollOnce()
            default:
                return
            }
        }

        XCTFail("Confirmation did not settle")
    }

    private func makeCoordinator(syncService: DDGSyncing,
                                 messageExchanger: PairingV2MessageExchanging,
                                 messageCrypto: PairingV2MessageCrypto = PairingV2MessageCrypto(),
                                 confirmationDelegate: PairingV2ConfirmationDelegate? = nil,
                                 canSendExchangeChannelSecret: Bool = false,
                                 advertisedVersion: PairingV2ProtocolVersion = .v2,
                                 makeKeyPair: @escaping () throws -> PairingV2KeyPair = { try PairingV2KeyPairFactory.makeKeyPair() },
                                 makeChannelSecret: @escaping () throws -> String = {
                                     try PairingV2ChannelSecretFactory.makeSecret()
                                 }) -> PairingV2Coordinator {
        PairingV2Coordinator(syncService: syncService,
                             messageExchanger: messageExchanger,
                             messageCrypto: messageCrypto,
                             deviceName: "Mac",
                             deviceType: "desktop",
                             flags: PairingV2RolloutFlags(isV2ScanningEnabled: true, isV2CodeEnabled: true),
                             canSendExchangeChannelSecret: canSendExchangeChannelSecret,
                             advertisedVersion: advertisedVersion,
                             confirmationDelegate: confirmationDelegate,
                             makeKeyPair: makeKeyPair,
                             makeChannelSecret: makeChannelSecret)
    }

    private func pairingFailure(operation: () async throws -> Void) async -> PairingV2OperationFailure? {
        do {
            try await operation()
            XCTFail("Expected PairingV2OperationFailure")
            return nil
        } catch let operationFailure as PairingV2OperationFailure {
            return operationFailure
        } catch {
            XCTFail("Expected PairingV2OperationFailure, got \(error)")
            return nil
        }
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

    private func decryptedSentMessages(from messageExchanger: PairingV2MessageExchangingMock,
                                       peerPrivateKey: SecKey,
                                       messageCrypto: PairingV2MessageCrypto) throws -> [PairingV2ApplicationMessage] {
        try messageExchanger.sendCalls.indices.map {
            try decryptSentMessage(at: $0,
                                   from: messageExchanger,
                                   peerPrivateKey: peerPrivateKey,
                                   messageCrypto: messageCrypto)
        }
    }

    private func recoveryCodeDoneCount(in messageExchanger: PairingV2MessageExchangingMock,
                                       peerPrivateKey: SecKey,
                                       messageCrypto: PairingV2MessageCrypto) throws -> Int {
        try decryptedSentMessages(from: messageExchanger,
                                  peerPrivateKey: peerPrivateKey,
                                  messageCrypto: messageCrypto).count { message in
            if case .recoveryCodeDone = message {
                return true
            }
            return false
        }
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

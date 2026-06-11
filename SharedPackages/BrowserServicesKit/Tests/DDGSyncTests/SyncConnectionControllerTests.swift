//
//  SyncConnectionControllerTests.swift
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

import XCTest
import Combine
import Persistence
import PrivacyConfig
import Common
@testable import DDGSync

// MARK: - Remote Polling Mocks

final class MockRemoteExchangeRecovering: RemoteExchangeRecovering {
    var pollForRecoveryKeyCalled = 0
    var pollForRecoveryKeyResult: SyncCode.RecoveryKey?
    var pollForRecoveryKeyError: Error?
    var stopPollingCalled = 0

    func pollForRecoveryKey() async throws -> SyncCode.RecoveryKey? {
        pollForRecoveryKeyCalled += 1
        if let error = pollForRecoveryKeyError { throw error }
        return pollForRecoveryKeyResult
    }

    func stopPolling() {
        stopPollingCalled += 1
    }
}

// MARK: - Delegate Mock

final class MockSyncConnectionControllerDelegate: SyncConnectionControllerDelegate {
    var didBeginTransmittingRecoveryKeyCalled = { }
    var didFinishTransmittingRecoveryKeyCalled = { }
    var didFinishTransmittingRecoveryKeyShouldWaitForDevicesToChange: Bool?
    var didReceiveRecoveryKeyCalled = { }
    var didRecognizeScannedCodeCalled = { }
    var willPerformServerSyncOperationCalled = { }
    var didCreateSyncAccountCalled = { }
    var didCreateSyncAccountShouldShowSyncEnabled: Bool?
    var didCompleteAccountConnectionValue: Bool?
    var didCompleteLoginDevices: [RegisteredDevice]?
    var didCompletePairingWithAlreadyConnectedAccountCalled = { }
    var didCompletePairingWithAlreadyConnectedAccountSetupRole: SyncSetupRole?
    var didFindTwoAccountsDuringRecoveryCalled: SyncCode.RecoveryKey?
    var didFindTwoAccountsDuringRecoveryShouldPromptBeforeSwitchingAccounts: Bool?
    var didErrorCalled = { }
    var didErrorErrors: (error: SyncConnectionError, underlyingError: Error?)?
    var shouldContinueServerSyncOperation = true
    var shouldAllowPairingV2PeerToJoin = true
    var shouldJoinPairingV2Peer = true
    var willPerformServerSyncOperationCallCount = 0

    func controllerWillBeginTransmittingRecoveryKey() async {
        didBeginTransmittingRecoveryKeyCalled()
    }

    func controllerDidFinishTransmittingRecoveryKey(shouldWaitForDevicesToChange: Bool) {
        didFinishTransmittingRecoveryKeyShouldWaitForDevicesToChange = shouldWaitForDevicesToChange
        didFinishTransmittingRecoveryKeyCalled()
    }

    func controllerDidReceiveRecoveryKey() {
        didReceiveRecoveryKeyCalled()
    }

    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource) async {
        didRecognizeScannedCodeCalled()
    }

    func controllerWillPerformServerSyncOperation(setupRole _: SyncSetupRole) async -> Bool {
        willPerformServerSyncOperationCallCount += 1
        willPerformServerSyncOperationCalled()
        return shouldContinueServerSyncOperation
    }

    func controllerShouldAllowPairingV2PeerToJoin(peerName _: String?, peerKind _: PairingV2DeviceKind) async -> Bool {
        shouldAllowPairingV2PeerToJoin
    }

    func controllerShouldJoinPairingV2Peer(peerName _: String?, peerKind _: PairingV2DeviceKind) async -> Bool {
        shouldJoinPairingV2Peer
    }

    func controllerDidCreateSyncAccount(shouldShowSyncEnabled: Bool) {
        didCreateSyncAccountShouldShowSyncEnabled = shouldShowSyncEnabled
        didCreateSyncAccountCalled()
    }

    func controllerDidCompleteAccountConnection(shouldShowSyncEnabled: Bool, setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        didCompleteAccountConnectionValue = shouldShowSyncEnabled
    }

    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool, setupRole: SyncSetupRole) {
        didCompleteLoginDevices = registeredDevices
    }

    func controllerDidCompletePairingWithAlreadyConnectedAccount(setupRole: SyncSetupRole) {
        didCompletePairingWithAlreadyConnectedAccountSetupRole = setupRole
        didCompletePairingWithAlreadyConnectedAccountCalled()
    }

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey,
                                                    setupRole: SyncSetupRole,
                                                    shouldPromptBeforeSwitchingAccounts: Bool) async {
        didFindTwoAccountsDuringRecoveryCalled = recoveryKey
        didFindTwoAccountsDuringRecoveryShouldPromptBeforeSwitchingAccounts = shouldPromptBeforeSwitchingAccounts
    }

    func controllerDidError(_ error: SyncConnectionError, underlyingError: (any Error)?, setupRole: SyncSetupRole) async {
        didErrorErrors = (error, underlyingError)
        didErrorCalled()
    }
}

// MARK: - Test Suite

import NetworkingTestingUtils

final class SyncConnectionControllerTests: XCTestCase {

    private static let validExchangeCode: String = "eyJleGNoYW5nZV9rZXkiOnsicHVibGljX2tleSI6InlcL2xScDZjOUtUVnNHT0ZXS2djblYrQlE4RlFMUFBxNmplVzRtUzE2OUNRPSIsImtleV9pZCI6IjAwRkY1NDNELUMzMjctNDMzNS1CM0NBLTU1MUQyOTUxOTNGQSJ9fQ=="
    private static let validConnectCode: String = "eyJjb25uZWN0Ijp7ImRldmljZV9pZCI6IjdFMTU2NTIyLTk0MDktNEZFOS1BRkY2LUFBNTM4MzIwRDhENCIsInNlY3JldF9rZXkiOiJsN1MxZFBVNkZXUW5oVkczK0dnVjhmaEY4SVRKbE1KZG1xTTRVYkY3eTNrPSJ9fQ=="
    private static let validRecoveryCode: String = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiMUE0QjBCRUUtMDA2Qy00QjdELUI1MjQtNDBBNzc0RERFNDM0IiwicHJpbWFyeV9rZXkiOiJjU3d1R3FmbTJpbmNcL1JYRW4yTjVxT0x0RllBRU5MY0UwN0lLWFk3ZFI0TT0ifX0="
    private static let cachedPeerKeyPair: Result<PairingV2KeyPair, Error> = Result {
        try PairingV2KeyPairFactory.makeKeyPair(channelID: "peer-channel")
    }
    private static let pairingV2PollingTimeout: TimeInterval = 5
    private static let pairingV2PollIntervalNanoseconds: UInt64 = 1_000_000
    private var controller: SyncConnectionController!
    private var syncService: DDGSync!
    private var delegate: MockSyncConnectionControllerDelegate!
    private var dependencies: MockSyncDependencies!
    private static var deviceName = "TestDeviceName"
    private static var deviceType = "TestDeviceType"

    @MainActor
    override func setUp() {
        super.setUp()
        dependencies = MockSyncDependencies()
        dependencies.isPairingV2CodeEnabled = { false }
        syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        delegate = MockSyncConnectionControllerDelegate()
        controller = SyncConnectionController(deviceName: Self.deviceName,
                                              deviceType: Self.deviceType,
                                              delegate: delegate,
                                              syncService: syncService,
                                              dependencies: dependencies,
                                              pairingV2PollingTimeout: Self.pairingV2PollingTimeout,
                                              pairingV2PollIntervalNanoseconds: Self.pairingV2PollIntervalNanoseconds)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        controller = nil
        syncService = nil
        delegate = nil
        dependencies = nil
        super.tearDown()
    }

    // MARK: startExchangeMode

    func test_startExchangeMode_returnsExpectedPairingInfo() async throws {
        let expectedExchangeCode = "TestExchangerCode"
        let mockRemoteKeyExchanger: MockRemoteKeyExchanging = .init()
        dependencies.createRemoteKeyExchangerStub = mockRemoteKeyExchanger
        mockRemoteKeyExchanger.code = expectedExchangeCode
        let pairingInfo = try await controller.startExchangeMode()

        XCTAssertEqual(pairingInfo.base64Code, expectedExchangeCode)
        XCTAssertEqual(pairingInfo.deviceName, Self.deviceName)
    }

    func test_startExchangeMode_whenPairingV2CodeEnabled_returnsV2PairingInfo() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2Error.cancelled
        dependencies.createPairingV2MessageExchangerStub = messageExchanger

        let pairingInfo = try await controller.startExchangeMode()
        let url = try XCTUnwrap(URL(string: pairingInfo.base64Code))
        let payload = try XCTUnwrap(PairingV2QRCodePayload(url: url))

        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 1)
        XCTAssertEqual(messageExchanger.openChannelCalls, [payload.channelId])
        XCTAssertEqual(pairingInfo.toURL(baseURL: URL(string: "https://example.com")!), url)
    }

    func test_startExchangeMode_whenPairingV2CodeEnabledAndPairingV2ScanningDisabled_returnsLegacyPairingInfo() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        dependencies.isPairingV2ScanningEnabled = { false }
        let expectedExchangeCode = "TestExchangerCode"
        let mockRemoteKeyExchanger: MockRemoteKeyExchanging = .init()
        dependencies.createRemoteKeyExchangerStub = mockRemoteKeyExchanger
        mockRemoteKeyExchanger.code = expectedExchangeCode

        let pairingInfo = try await controller.startExchangeMode()

        XCTAssertEqual(pairingInfo.base64Code, expectedExchangeCode)
        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 0)
    }

    @MainActor
    func test_startExchangeMode_whenPairingV2ScannerIsActive_cancelsScannerCoordinator() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let didOpenScannerChannel = expectation(description: "scanner channel opened")
        let didCloseScannerChannel = expectation(description: "scanner channel closed")
        var scannerChannelID: String?
        messageExchanger.openChannelHandler = { channelID in
            if scannerChannelID == nil {
                scannerChannelID = channelID
                didOpenScannerChannel.fulfill()
            }
        }
        messageExchanger.closeChannelHandler = { channelID in
            if channelID == scannerChannelID {
                didCloseScannerChannel.fulfill()
            }
        }

        let scannerTask = Task {
            await self.controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)
        }
        await fulfillment(of: [didOpenScannerChannel], timeout: 5)
        let openedScannerChannelID = try XCTUnwrap(scannerChannelID)

        _ = try await controller.startExchangeMode()

        await fulfillment(of: [didCloseScannerChannel], timeout: 5)
        XCTAssertTrue(messageExchanger.closeChannelCalls.contains(openedScannerChannelID))
        await controller.cancel()
        _ = await scannerTask.value
    }

    func test_startExchangeMode_whenConnectModeIsActive_stopsConnectPolling() async throws {
        let remoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = remoteConnector
        _ = try await controller.startConnectMode()

        let remoteExchanger = MockRemoteKeyExchanging()
        dependencies.createRemoteKeyExchangerStub = remoteExchanger
        _ = try await controller.startExchangeMode()

        XCTAssertEqual(remoteConnector.stopPollingCalled, 1)
    }

    @MainActor
    func test_startExchangeMode_whenLegacyConnectModeIsActiveAndPairingV2CodeEnabled_stopsConnectPolling() async throws {
        let remoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = remoteConnector
        _ = try await controller.startConnectMode()

        dependencies.isPairingV2CodeEnabled = { true }
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        _ = try await controller.startExchangeMode()

        XCTAssertEqual(remoteConnector.stopPollingCalled, 1)
    }

    @MainActor
    func test_startExchangeMode_whenPairingV2PresenterIsActiveAndPairingV2CodeDisabled_cancelsPresenterCoordinator() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let presenterInfo = try await controller.startExchangeMode()
        let presenterPayload = try XCTUnwrap(PairingV2QRCodePayload(url: try XCTUnwrap(URL(string: presenterInfo.base64Code))))

        dependencies.isPairingV2CodeEnabled = { false }
        let remoteExchanger = MockRemoteKeyExchanging()
        dependencies.createRemoteKeyExchangerStub = remoteExchanger
        _ = try await controller.startExchangeMode()

        XCTAssertTrue(messageExchanger.closeChannelCalls.contains(presenterPayload.channelId))
    }

    func test_startExchangeMode_whenPairingV2CodeEnabledAndScopedAccessDisabled_returnsV2PairingInfo() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        dependencies.isScopedAccessCredentialsEnabled = { false }
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2Error.cancelled
        dependencies.createPairingV2MessageExchangerStub = messageExchanger

        let pairingInfo = try await controller.startExchangeMode()
        let url = try XCTUnwrap(URL(string: pairingInfo.base64Code))
        let payload = try XCTUnwrap(PairingV2QRCodePayload(url: url))

        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 1)
        XCTAssertEqual(messageExchanger.openChannelCalls, [payload.channelId])
        XCTAssertEqual(pairingInfo.toURL(baseURL: URL(string: "https://example.com")!), url)
    }

    @MainActor
    func test_startExchangeMode_whenPairingV2PresenterCompletes_notifiesDelegate() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        var payload: PairingV2QRCodePayload?
        messageExchanger.fetchMessagesHandler = { _, sequence in
            guard let payload else {
                return []
            }
            if sequence == 0 {
                return try Self.encryptedPresenterPeerMessages(messages: [
                    .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
                ], presenterPayload: payload, peerKeyPair: peerKeyPair)
            }
            return try Self.encryptedPresenterPeerMessages(messages: [
                .recoveryCodeRequest(
                    .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                          name: "Peer",
                          kind: .ddg)
                )
            ], presenterPayload: payload, peerKeyPair: peerKeyPair, initialSequence: sequence)
        }

        let willBeginTransmitting = expectation(description: "will begin transmitting")
        delegate.didBeginTransmittingRecoveryKeyCalled = {
            willBeginTransmitting.fulfill()
        }
        let didFinishTransmitting = expectation(description: "did finish transmitting")
        delegate.didFinishTransmittingRecoveryKeyCalled = {
            didFinishTransmitting.fulfill()
        }
        let didCloseChannel = expectation(description: "did close channel")
        messageExchanger.closeChannelHandler = { _ in
            didCloseChannel.fulfill()
        }

        let pairingInfo = try await controller.startExchangeMode()
        payload = try XCTUnwrap(PairingV2QRCodePayload(url: try XCTUnwrap(URL(string: pairingInfo.base64Code))))

        await fulfillment(of: [willBeginTransmitting, didFinishTransmitting], timeout: 5)
        XCTAssertEqual(delegate.didFinishTransmittingRecoveryKeyShouldWaitForDevicesToChange, true)
        await fulfillment(of: [didCloseChannel], timeout: 5)
        XCTAssertFalse(messageExchanger.closeChannelCalls.isEmpty)
    }

    @MainActor
    func test_startExchangeMode_whenPairingV2PresenterCompletesForThirdPartyPeer_doesNotWaitForDeviceListChange() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        var payload: PairingV2QRCodePayload?
        messageExchanger.fetchMessagesHandler = { _, sequence in
            guard let payload else {
                return []
            }
            if sequence == 0 {
                return try Self.encryptedPresenterPeerMessages(messages: [
                    .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
                ], presenterPayload: payload, peerKeyPair: peerKeyPair)
            }
            return try Self.encryptedPresenterPeerMessages(messages: [
                .recoveryCodeRequest(
                    .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                          name: "Peer",
                          kind: .thirdParty)
                )
            ], presenterPayload: payload, peerKeyPair: peerKeyPair, initialSequence: sequence)
        }

        let didFinishTransmitting = expectation(description: "did finish transmitting")
        delegate.didFinishTransmittingRecoveryKeyCalled = {
            didFinishTransmitting.fulfill()
        }
        let didCloseChannel = expectation(description: "did close channel")
        messageExchanger.closeChannelHandler = { _ in
            didCloseChannel.fulfill()
        }

        let pairingInfo = try await controller.startExchangeMode()
        payload = try XCTUnwrap(PairingV2QRCodePayload(url: try XCTUnwrap(URL(string: pairingInfo.base64Code))))

        await fulfillment(of: [didFinishTransmitting], timeout: 5)
        XCTAssertEqual(delegate.didFinishTransmittingRecoveryKeyShouldWaitForDevicesToChange, false)
        await fulfillment(of: [didCloseChannel], timeout: 5)
        XCTAssertFalse(messageExchanger.closeChannelCalls.isEmpty)
    }

    @MainActor
    func test_startExchangeMode_whenPairingV2PresenterDetectsSameAccount_notifiesAlreadyConnected() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        var payload: PairingV2QRCodePayload?
        messageExchanger.fetchMessagesHandler = { _, sequence in
            guard let payload else {
                return []
            }
            if sequence == 0 {
                return try Self.encryptedPresenterPeerMessages(messages: [
                    .hello(.init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
                ], presenterPayload: payload, peerKeyPair: peerKeyPair)
            }
            return try Self.encryptedPresenterPeerMessages(messages: [
                .recoveryCodeAvailable(
                    .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                          name: "Peer",
                          kind: .ddg,
                          userId: SyncAccount.mock.userId)
                )
            ], presenterPayload: payload, peerKeyPair: peerKeyPair, initialSequence: sequence)
        }

        let didCompleteAlreadyConnected = expectation(description: "did complete already connected")
        delegate.didCompletePairingWithAlreadyConnectedAccountCalled = {
            didCompleteAlreadyConnected.fulfill()
        }
        let didCloseChannel = expectation(description: "did close channel")
        messageExchanger.closeChannelHandler = { _ in
            didCloseChannel.fulfill()
        }

        let pairingInfo = try await controller.startExchangeMode()
        payload = try XCTUnwrap(PairingV2QRCodePayload(url: try XCTUnwrap(URL(string: pairingInfo.base64Code))))

        await fulfillment(of: [didCompleteAlreadyConnected], timeout: 5)
        guard case .sharer = delegate.didCompletePairingWithAlreadyConnectedAccountSetupRole else {
            XCTFail("Expected already-connected completion for sharer role")
            return
        }
        XCTAssertNil(delegate.didErrorErrors)
        await fulfillment(of: [didCloseChannel], timeout: 5)
        XCTAssertFalse(messageExchanger.closeChannelCalls.isEmpty)
    }

    @MainActor
    func test_startExchangeMode_pollSucceeds_transmitsRecoveryKey() async throws {
        // Mock exchanger creation
        givenExchangerPollForPublicKeySucceeds()

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter

        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didFinishTransmittingRecoveryKeyCalled = {
            expectation.fulfill()
        }

        _ = try await controller.startExchangeMode()

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(exchangeRecoveryKeyTransmitter.sendCalled, 1)
    }

    @MainActor
    func test_startExchangeMode_pollSucceeds_stopsExchangerPolling() async throws {
        let remoteExchanger = MockRemoteKeyExchanging()
        givenExchangerPollForPublicKeySucceeds(remoteExchanger)

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter

        let expectation = self.expectation(description: "Exchanger poll completes")
        remoteExchanger.stopPollingCallback = {
            expectation.fulfill()
        }

        _ = try await controller.startExchangeMode()

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(remoteExchanger.stopPollingCalled, 1)
    }

    func test_startExchangeMode_pollFails_sendsError() async throws {
        // Mock exchanger creation
        let remoteExchanger = MockRemoteKeyExchanging()
        dependencies.createRemoteKeyExchangerStub = remoteExchanger
        remoteExchanger.pollForPublicKeyError = SyncError.unableToDecodeResponse("")

        let error = try await waitForError {
            _ = try await self.controller.startExchangeMode()
        }

        XCTAssertEqual(error, SyncConnectionError.failedToFetchPublicKey)
    }

    func test_startExchangeMode_recoveryKeyTransmitFails_sendsError() async throws {
        // Mock exchanger creation
        givenExchangerPollForPublicKeySucceeds()

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter
        exchangeRecoveryKeyTransmitter.sendError = SyncError.unableToDecodeResponse("")

        let error = try await waitForError {
            _ = try await self.controller.startExchangeMode()
        }

        XCTAssertEqual(error, SyncConnectionError.failedToTransmitExchangeRecoveryKey)
    }

    @MainActor
    func test_startExchangeMode_recoveryKeyTransmitFails_doesNotNotifyFinish() async throws {
        let remoteExchanger = MockRemoteKeyExchanging()
        givenExchangerPollForPublicKeySucceeds(remoteExchanger)

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        exchangeRecoveryKeyTransmitter.sendError = SyncError.unableToDecodeResponse("")
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter

        let didErrorExpectation = expectation(description: "Delegate receives transmit error")
        delegate.didErrorCalled = {
            didErrorExpectation.fulfill()
        }

        let didFinishExpectation = expectation(description: "Delegate should not report transmit success")
        didFinishExpectation.isInverted = true
        delegate.didFinishTransmittingRecoveryKeyCalled = {
            didFinishExpectation.fulfill()
        }

        _ = try await controller.startExchangeMode()

        await fulfillment(of: [didErrorExpectation], timeout: 5.0)
        await fulfillment(of: [didFinishExpectation], timeout: 0.1)
        XCTAssertEqual(delegate.didErrorErrors?.error, .failedToTransmitExchangeRecoveryKey)
        XCTAssertEqual(remoteExchanger.stopPollingCalled, 1)
    }

    private func givenExchangerPollForPublicKeySucceeds(_ exchanger: MockRemoteKeyExchanging = MockRemoteKeyExchanging()) {
        let expectedMessage = ExchangeMessage(keyId: "keyID", publicKey: .init(), deviceName: "")
        exchanger.pollForPublicKeyResult = expectedMessage
        dependencies.createRemoteKeyExchangerStub = exchanger
    }

    // MARK: startConnectMode

    func test_startConnectMode_returnsExpectedPairingInfo() async throws {
        let expectedConnectorCode = "TestConnectorCode"
        let mockRemoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = mockRemoteConnector
        mockRemoteConnector.code = expectedConnectorCode

        let pairingInfo = try await controller.startConnectMode()

        XCTAssertEqual(pairingInfo.base64Code, expectedConnectorCode)
        XCTAssertEqual(pairingInfo.deviceName, Self.deviceName)
    }

    func test_startConnectMode_whenExchangeModeIsActive_stopsExchangePolling() async throws {
        let remoteExchanger = MockRemoteKeyExchanging()
        dependencies.createRemoteKeyExchangerStub = remoteExchanger
        _ = try await controller.startExchangeMode()

        let remoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = remoteConnector
        _ = try await controller.startConnectMode()

        XCTAssertEqual(remoteExchanger.stopPollingCalled, 1)
    }

    func test_startConnectMode_whenPairingV2CodeEnabled_returnsV2PairingInfo() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2Error.cancelled
        dependencies.createPairingV2MessageExchangerStub = messageExchanger

        let pairingInfo = try await controller.startConnectMode()
        let url = try XCTUnwrap(URL(string: pairingInfo.base64Code))
        let payload = try XCTUnwrap(PairingV2QRCodePayload(url: url))

        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 1)
        XCTAssertEqual(messageExchanger.openChannelCalls, [payload.channelId])
        XCTAssertEqual(pairingInfo.toURL(baseURL: URL(string: "https://example.com")!), url)
    }

    @MainActor
    func test_startConnectMode_pollSucceeds_informsDelegate() async throws {
        let remoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = remoteConnector
        remoteConnector.pollForRecoveryKeyStub = SyncCode.RecoveryKey(userId: "", primaryKey: Data())

        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didReceiveRecoveryKeyCalled = {
            expectation.fulfill()
        }

        _ = try await controller.startConnectMode()

        await fulfillment(of: [expectation], timeout: 5)
    }

    func test_startConnectMode_pollSucceeds_logsIn() async throws {
        let remoteConnector = MockRemoteConnecting()
        let userId = "TestUserId"
        remoteConnector.pollForRecoveryKeyStub = SyncCode.RecoveryKey(userId: userId, primaryKey: Data())
        dependencies.createRemoteConnectorStub = remoteConnector
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        let expectation = self.expectation(description: "Exchanger poll completes")
        var spiedKey: SyncCode.RecoveryKey?
        mockAccountManager.loginSpy = { recoveryKey, _, _ in
            spiedKey = recoveryKey
            expectation.fulfill()
        }

        _ = try await controller.startConnectMode()

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(spiedKey?.userId, userId)
    }

    @MainActor
    func test_startConnectMode_pollSucceeds_whenDelegateBlocksServerOperation_doesNotLogIn() async throws {
        let remoteConnector = MockRemoteConnecting()
        remoteConnector.pollForRecoveryKeyStub = SyncCode.RecoveryKey(userId: "test", primaryKey: Data())
        dependencies.createRemoteConnectorStub = remoteConnector

        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        delegate.shouldContinueServerSyncOperation = false
        let willPerformServerOperation = expectation(description: "Delegate asked whether server operation should continue")
        delegate.willPerformServerSyncOperationCalled = {
            willPerformServerOperation.fulfill()
        }

        _ = try await controller.startConnectMode()

        await fulfillment(of: [willPerformServerOperation], timeout: 5)

        XCTAssertEqual(delegate.willPerformServerSyncOperationCallCount, 1)
        XCTAssertFalse(mockAccountManager.loginCalled)
    }

    func test_startConnectMode_pollingFails_sendsError() async throws {
        let remoteConnector = MockRemoteConnecting()
        remoteConnector.pollForRecoveryKeyError = SyncError.failedToPrepareForConnect("")
        dependencies.createRemoteConnectorStub = remoteConnector

        let error = try await waitForError {
            _ = try await self.controller.startConnectMode()
        }

        XCTAssertEqual(error, SyncConnectionError.failedToFetchConnectRecoveryKey)
    }

    func test_startConnectMode_loginFails_sendsError() async throws {
        let remoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = remoteConnector
        remoteConnector.pollForRecoveryKeyStub = SyncCode.RecoveryKey(userId: "", primaryKey: Data())

        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager
        mockAccountManager.loginError = SyncError.failedToDecryptValue("")

        let error = try await waitForError {
            _ = try await self.controller.startConnectMode()
        }

        XCTAssertEqual(error, SyncConnectionError.failedToLogIn)
    }

    // MARK: - Helper Functions

    private func createPairingInfo(code: String, deviceName: String = "Test") -> PairingInfo {
        PairingInfo(base64Code: code, deviceName: deviceName)
    }

    private func makePeerKeyPair(channelID: String = "peer-channel") throws -> PairingV2KeyPair {
        let cached = try Self.cachedPeerKeyPair.get()
        return PairingV2KeyPair(channelID: channelID, publicKey: cached.publicKey, privateKey: cached.privateKey)
    }

    private static func makeRecoveryCodeV2(credentialId: String,
                                           secret: String = "rUzlGqLLlbonAC_zIeh1nrCmuDsDAn6UooUUDz-6x3o",
                                           version: String = SyncCode.RecoveryKeyV2.currentVersion) throws -> String {
        let payload = SyncCode.RecoveryKeyV2(
            userId: "test-user-id",
            secret: secret,
            cid: credentialId,
            v: version
        )
        return Base64URL.encode(try SyncCode(recovery: .v2(payload)).toJSON())
    }

    // MARK: - startPairingMode Tests

    func test_startPairingMode_whenAlreadyInFlight_returnsFalse() async {
        // Simulate in-flight operation
        _ = await controller.startPairingMode(PairingInfo(base64Code: Self.validExchangeCode, deviceName: "Test"))

        let result = await controller.startPairingMode(PairingInfo(base64Code: Self.validExchangeCode, deviceName: "Test"))
        XCTAssertEqual(result, false)
    }

    @MainActor
    func test_startPairingMode_withInvalidCode_returnsFailure() async throws {
        let result = await controller.startPairingMode(PairingInfo(base64Code: "invalid_base64", deviceName: "Test"))
        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(result, false)
        XCTAssertEqual(error, .unableToRecognizeCode)
    }

    @MainActor
    func test_startPairingMode_withValidExchangeCode_notifiesDelegate() async {
        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didRecognizeScannedCodeCalled = {
            expectation.fulfill()
        }

        _ = await controller.startPairingMode(PairingInfo(base64Code: Self.validExchangeCode, deviceName: "Test"))

        await fulfillment(of: [expectation], timeout: 5)
    }

    @MainActor
    func test_startPairingMode_withRecoveryCode_returnsFailure() async throws {
        let result = await controller.startPairingMode(createPairingInfo(code: Self.validRecoveryCode))
        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(result, false)
        XCTAssertEqual(error, .unableToRecognizeCode)
    }

    // MARK: - startPairingMode exchange

    func test_startPairingMode_withExchangeCode_transmitsGeneratedExchangeInfo() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validExchangeCode))

        XCTAssertEqual(mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoCalled, 1)
    }

    @MainActor
    func test_startPairingMode_withExchangeCode_whenTransmitFails_notifiesError() async throws {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoError = SyncError.unableToDecodeResponse("")
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validExchangeCode))

        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(error, .failedToTransmitExchangeKey)
    }

    func test_startPairingMode_withExchangeCode_createsExchangeRecoverer() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        let exchangeInfo = ExchangeInfo(keyId: "test", publicKey: Data(), secretKey: Data())
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoStub = exchangeInfo
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        let mockExchangeRecoverer = MockRemoteExchangeRecovering()
        dependencies.createRemoteExchangeRecoverer = mockExchangeRecoverer

        await controller.startPairingMode(createPairingInfo(code: Self.validExchangeCode))

        XCTAssertEqual(mockExchangeRecoverer.pollForRecoveryKeyCalled, 1)
    }

    // MARK: - startPairingMode connect

    @MainActor
    func test_startPairingMode_withConnectCode_whenNoAccount_createsAccount() async throws {
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didCreateSyncAccountCalled = {
            expectation.fulfill()
        }

        await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        await fulfillment(of: [expectation], timeout: 5)
    }

    @MainActor
    func test_startPairingMode_withConnectCode_whenAccountCreationThrows_notifiesError() async throws {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.createAccountError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager

        let error = try await waitForError {
            await self.controller.startPairingMode(self.createPairingInfo(code: Self.validConnectCode))
        }
        XCTAssertEqual(error, .failedToCreateAccount)
    }

    @MainActor
    func test_startPairingMode_withConnectCode_whenDelegateBlocksServerOperation_doesNotTransmitRecoveryKey() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter
        delegate.shouldContinueServerSyncOperation = false

        let result = await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        XCTAssertFalse(result)
        XCTAssertEqual(delegate.willPerformServerSyncOperationCallCount, 1)
        XCTAssertEqual(mockRecoveryKeyTransmitter.sendCalled, 0)
        XCTAssertNil(delegate.didCompleteAccountConnectionValue)
    }

    func test_startPairingMode_withConnectCode_transmitsRecoveryKey() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        XCTAssertEqual(mockRecoveryKeyTransmitter.sendCalled, 1)
    }

    @MainActor
    func test_startPairingMode_withConnectCode_whenTransmitFails_notifiesError() async throws {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        mockRecoveryKeyTransmitter.sendError = SyncError.unableToDecodeResponse("")
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        let error = delegate.didErrorErrors?.error
        XCTAssertEqual(error, .failedToTransmitConnectRecoveryKey)
    }

    func test_startPairingMode_withConnectCode_whenSuccessful_notifiesCompletion() async throws {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        let didComplete = await delegate.didCompleteAccountConnectionValue
        XCTAssertNotNil(didComplete)
    }

    // MARK: - syncCodeEntered Tests

    func test_syncCodeEntered_whenAlreadyInFlight_returnsFalse() async {
        // Simulate in-flight operation
        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        let result = await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)
        XCTAssertEqual(result, false)
    }

    @MainActor
    func test_syncCodeEntered_withInvalidCode_returnsFailure() async throws {
        let result = await controller.syncCodeEntered(code: "invalid_base64", canScanLegacyURLBarcodes: true, codeSource: .pastedCode)
        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(result, false)
        XCTAssertEqual(error, .unableToRecognizeCode)
    }

    @MainActor
    func test_syncCodeEntered_withV2UrlAndUrlScanningDisabled_startsPairingV2() async throws {
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2Error.cancelled
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: false, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 1)
        XCTAssertNil(delegate.didErrorErrors)
    }

    @MainActor
    func test_syncCodeEntered_withV2UrlAndNoAccount_startsPairingV2() async throws {
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2Error.cancelled
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 1)
        XCTAssertNil(delegate.didErrorErrors)
    }

    @MainActor
    func test_syncCodeEntered_withV2UrlWhenPresenterIsActive_cancelsPresenterCoordinator() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let presenterInfo = try await controller.startExchangeMode()
        let presenterPayload = try XCTUnwrap(PairingV2QRCodePayload(url: try XCTUnwrap(URL(string: presenterInfo.base64Code))))
        let peerKeyPair = try makePeerKeyPair()
        let scannerPayload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let scannerURL = try scannerPayload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        messageExchanger.fetchMessagesError = PairingV2Error.cancelled
        let result = await controller.syncCodeEntered(code: scannerURL.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertTrue(messageExchanger.closeChannelCalls.contains(presenterPayload.channelId))
        XCTAssertNil(delegate.didErrorErrors)
    }

    @MainActor
    func test_syncCodeEntered_withLegacyExchangeCodeWhenPairingV2PresenterIsActive_cancelsPresenterCoordinator() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let presenterInfo = try await controller.startExchangeMode()
        let presenterPayload = try XCTUnwrap(PairingV2QRCodePayload(url: try XCTUnwrap(URL(string: presenterInfo.base64Code))))

        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter
        let result = await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertTrue(messageExchanger.closeChannelCalls.contains(presenterPayload.channelId))
    }

    @MainActor
    func test_syncCodeEntered_withV2UrlAndPairingV2ScanningDisabled_returnsUnableToRecognizeCodeBeforeStartingPairingV2() async throws {
        dependencies.isPairingV2ScanningEnabled = { false }
        let payload = PairingV2QRCodePayload(channelId: "channel-1", publicKey: "public-key")
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 0)
        XCTAssertEqual(delegate.didErrorErrors?.error, .unableToRecognizeCode)
        XCTAssertNil(delegate.didErrorErrors?.underlyingError)
    }

    @MainActor
    func test_syncCodeEntered_withUnsupportedMajorPairingV2Url_returnsUpdateRequiredBeforeStartingPairingV2() async throws {
        let payload = PairingV2QRCodePayload(version: "3.0", channelId: "channel-1", publicKey: "public-key")
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 0)
        XCTAssertEqual(delegate.didErrorErrors?.error, .updateRequired)
        XCTAssertEqual(delegate.didErrorErrors?.underlyingError as? PairingV2Error, .unsupportedVersion("3.0"))
    }

    @MainActor
    func test_syncCodeEntered_withUnsupportedMajorPairingV2UrlAndPairingV2ScanningDisabled_returnsUnableToRecognizeCode() async throws {
        dependencies.isPairingV2ScanningEnabled = { false }
        let payload = PairingV2QRCodePayload(version: "3.0", channelId: "channel-1", publicKey: "public-key")
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 0)
        XCTAssertEqual(delegate.didErrorErrors?.error, .unableToRecognizeCode)
        XCTAssertNil(delegate.didErrorErrors?.underlyingError)
    }

    @MainActor
    func test_syncCodeEntered_withV2UrlAndScopedAccessCredentialsDisabled_startsPairingV2() async throws {
        dependencies.isScopedAccessCredentialsEnabled = { false }
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2Error.cancelled
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair(channelID: "channel-1")
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(dependencies.createPairingV2MessageExchangerCallCount, 1)
        XCTAssertEqual(messageExchanger.openChannelCalls.count, 1)
        XCTAssertNil(delegate.didErrorErrors)
    }

    @MainActor
    func test_syncCodeEntered_withV2UrlAndPairingV2Cancelled_returnsFailureWithoutError() async throws {
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2Error.cancelled
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertNil(delegate.didErrorErrors)
    }

    @MainActor
    func test_syncCodeEntered_withV2UrlAndRelayUnavailableOnSend_notifiesFetchError() async throws {
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.sendError = PairingV2Error.relayChannelUnavailable
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(delegate.didErrorErrors?.error, .failedToFetchExchangeRecoveryKey)
        XCTAssertNil(delegate.didErrorErrors?.underlyingError)
    }

    @MainActor
    func test_syncCodeEntered_withV2UrlAndRelayExpired_notifiesFetchError() async throws {
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2Error.relayChannelExpired
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(delegate.didErrorErrors?.error, .failedToFetchExchangeRecoveryKey)
        XCTAssertNil(delegate.didErrorErrors?.underlyingError)
    }

    @MainActor
    func test_syncCodeEntered_withV2SameAccount_notifiesAlreadyConnected() async throws {
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        messageExchanger.fetchMessagesHandler = { _, _ in
            try self.encryptedPeerMessages(
                [
                    .recoveryCodeAvailable(
                        .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                              name: "Peer",
                              kind: .ddg,
                              userId: SyncAccount.mock.userId)
                    )
                ],
                messageExchanger: messageExchanger,
                peerKeyPair: peerKeyPair
            )
        }
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)
        let didCloseChannel = expectation(description: "did close channel")
        messageExchanger.closeChannelHandler = { _ in
            didCloseChannel.fulfill()
        }

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertTrue(result)
        guard case .receiver(.exchange, .pastedCode) = delegate.didCompletePairingWithAlreadyConnectedAccountSetupRole else {
            XCTFail("Expected already-connected completion for exchange receiver role")
            return
        }
        XCTAssertNil(delegate.didErrorErrors)
        XCTAssertNil(delegate.didCompleteLoginDevices)
        XCTAssertNil(delegate.didCompleteAccountConnectionValue)
        await fulfillment(of: [didCloseChannel], timeout: 5)
        XCTAssertFalse(messageExchanger.closeChannelCalls.isEmpty)
    }

    @MainActor
    func test_syncCodeEntered_withV2ThirdPartyRecoveryCodeRequestAndNoAccount_defersSyncEnabledUIUntilTransmitCompletion() async throws {
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        messageExchanger.fetchMessagesHandler = { _, _ in
            try self.encryptedPeerMessages(
                [
                    .recoveryCodeRequest(
                        .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                              name: "Peer",
                              kind: .thirdParty)
                    )
                ],
                messageExchanger: messageExchanger,
                peerKeyPair: peerKeyPair
            )
        }
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .qrCode)

        XCTAssertTrue(result)
        XCTAssertEqual(delegate.didCreateSyncAccountShouldShowSyncEnabled, false)
        XCTAssertEqual(delegate.didFinishTransmittingRecoveryKeyShouldWaitForDevicesToChange, false)
        XCTAssertNil(delegate.didErrorErrors)
    }

    @MainActor
    func test_syncCodeEntered_withV2MessageCryptoError_notifiesUnableToRecognizeCode() async throws {
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2MessageCryptoError.unsupportedProtectedHeader
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(delegate.didErrorErrors?.error, .unableToRecognizeCode)
        XCTAssertEqual(delegate.didErrorErrors?.underlyingError as? PairingV2MessageCryptoError, .unsupportedProtectedHeader)
    }

    @MainActor
    func test_syncCodeEntered_withUnsupportedMajorV2MessageCryptoError_notifiesUpdateRequired() async throws {
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2MessageCryptoError.unsupportedVersion("3.0")
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(delegate.didErrorErrors?.error, .updateRequired)
        XCTAssertEqual(delegate.didErrorErrors?.underlyingError as? PairingV2MessageCryptoError, .unsupportedVersion("3.0"))
    }

    @MainActor
    func test_syncCodeEntered_withMalformedVersionV2MessageCryptoError_notifiesUnableToRecognizeCode() async throws {
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.fetchMessagesError = PairingV2MessageCryptoError.unsupportedVersion("not-a-version")
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(delegate.didErrorErrors?.error, .unableToRecognizeCode)
        XCTAssertEqual(delegate.didErrorErrors?.underlyingError as? PairingV2MessageCryptoError, .unsupportedVersion("not-a-version"))
    }

    @MainActor
    func test_syncCodeEntered_withV2RecoveryCodePreparationFailure_notifiesTransmitError() async throws {
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.ensureThirdPartyScopedPasswordError = SyncError.failedToEncryptValue("")
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        messageExchanger.fetchMessagesHandler = { _, _ in
            try self.encryptedPeerMessages(
                [
                    .recoveryCodeAvailable(
                        .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                              name: "Peer",
                              kind: .thirdParty,
                              userId: "other-user")
                    )
                ],
                messageExchanger: messageExchanger,
                peerKeyPair: peerKeyPair
            )
        }
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(delegate.didErrorErrors?.error, .failedToTransmitExchangeRecoveryKey)
        XCTAssertNil(delegate.didErrorErrors?.underlyingError)
    }

    @MainActor
    func test_syncCodeEntered_withV2RecoveryCodeSendFailure_notifiesTransmitError() async throws {
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        messageExchanger.sendHandler = { _, _ in
            if messageExchanger.sendCalls.count > 4 {
                throw SyncError.failedToEncryptValue("")
            }
        }
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        messageExchanger.fetchMessagesHandler = { _, _ in
            try self.encryptedPeerMessages(
                [
                    .recoveryCodeAvailable(
                        .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                              name: "Peer",
                              kind: .thirdParty,
                              userId: "other-user")
                    )
                ],
                messageExchanger: messageExchanger,
                peerKeyPair: peerKeyPair
            )
        }
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(delegate.didErrorErrors?.error, .failedToTransmitExchangeRecoveryKey)
        XCTAssertNil(delegate.didErrorErrors?.underlyingError)
    }

    @MainActor
    func test_syncCodeEntered_withV2DifferentNativeAccount_notifiesTwoAccountsDuringRecovery() async throws {
        try dependencies.secureStore.persistAccount(SyncAccount.mock)
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let peerKeyPair = try makePeerKeyPair()
        messageExchanger.fetchMessagesHandler = { _, _ in
            try self.encryptedPeerMessages(
                [
                    .recoveryCodeAvailable(
                        .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                              name: "Peer",
                              kind: .ddg,
                              userId: "other-user")
                    ),
                    .recoveryCodeResponse(.init(recoveryCode: Self.validRecoveryCode))
                ],
                messageExchanger: messageExchanger,
                peerKeyPair: peerKeyPair
            )
        }
        let payload = PairingV2QRCodePayload(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey)
        let url = try payload.toURL(baseURL: URL(string: "https://duckduckgo.com")!)

        let result = await controller.syncCodeEntered(code: url.absoluteString, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertNotNil(delegate.didFindTwoAccountsDuringRecoveryCalled)
        XCTAssertEqual(delegate.didFindTwoAccountsDuringRecoveryShouldPromptBeforeSwitchingAccounts, false)
        XCTAssertNil(delegate.didErrorErrors)
    }

    @MainActor
    func test_syncCodeEntered_withValidExchangeCode_notifiesDelegate() async {
        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didRecognizeScannedCodeCalled = {
            expectation.fulfill()
        }

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        await fulfillment(of: [expectation], timeout: 5)
    }

    @MainActor
    func test_syncCodeEntered_withValidURL_extractsAndUsesCode() async {
        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didRecognizeScannedCodeCalled = {
            expectation.fulfill()
        }

        let url = "https://duckduckgo.com/sync/pairing/#&code=\(Self.validExchangeCode)&deviceName=TestDevice"
        await controller.syncCodeEntered(code: url, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        await fulfillment(of: [expectation], timeout: 5)
    }

    // MARK: - syncCodeEntered exchange

    func test_syncCodeEntered_withExchangeCode_transmitsGeneratedExchangeInfo() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertEqual(mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoCalled, 1)
    }

    @MainActor
    func test_syncCodeEntered_withExchangeCode_whenTransmitFails_notifiesError() async throws {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoError = SyncError.unableToDecodeResponse("")
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        let error = delegate.didErrorErrors?.error
        XCTAssertEqual(error, .failedToTransmitExchangeKey)
    }

    func test_syncCodeEntered_withExchangeCode_createsExchangeRecoverer() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        let exchangeInfo = ExchangeInfo(keyId: "test", publicKey: Data(), secretKey: Data())
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoStub = exchangeInfo
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        let mockExchangeRecoverer = MockRemoteExchangeRecovering()
        dependencies.createRemoteExchangeRecoverer = mockExchangeRecoverer

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertEqual(mockExchangeRecoverer.pollForRecoveryKeyCalled, 1)
    }

    func test_syncCodeEntered_withExchangeCode_whenRecoveryKeyReceived_logsIn() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        let exchangeInfo = ExchangeInfo(keyId: "test", publicKey: Data(), secretKey: Data())
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoStub = exchangeInfo
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        let mockExchangeRecoverer = MockRemoteExchangeRecovering()
        let recoveryKey = SyncCode.RecoveryKey(userId: "testUser", primaryKey: Data())
        mockExchangeRecoverer.pollForRecoveryKeyResult = recoveryKey
        dependencies.createRemoteExchangeRecoverer = mockExchangeRecoverer

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        let devices = await delegate.didCompleteLoginDevices
        XCTAssertNotNil(devices)
    }

    @MainActor
    func test_syncCodeEntered_withExchangeCode_whenRecoveryKeyPollFails_notifiesError() async throws {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        let exchangeInfo = ExchangeInfo(keyId: "test", publicKey: Data(), secretKey: Data())
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoStub = exchangeInfo
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        let mockExchangeRecoverer = MockRemoteExchangeRecovering()
        mockExchangeRecoverer.pollForRecoveryKeyError = SyncError.unableToDecodeResponse("")
        dependencies.createRemoteExchangeRecoverer = mockExchangeRecoverer

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(error, .failedToFetchExchangeRecoveryKey)
    }

    @MainActor
    func test_syncCodeEntered_withExchangeCode_whenLoginFails_notifiesError() async throws {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        let exchangeInfo = ExchangeInfo(keyId: "test", publicKey: Data(), secretKey: Data())
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoStub = exchangeInfo
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        let mockExchangeRecoverer = MockRemoteExchangeRecovering()
        let recoveryKey = SyncCode.RecoveryKey(userId: "testUser", primaryKey: Data())
        mockExchangeRecoverer.pollForRecoveryKeyResult = recoveryKey
        dependencies.createRemoteExchangeRecoverer = mockExchangeRecoverer

        let mockAccountManager = AccountManagingMock()
        mockAccountManager.loginError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(error, .failedToLogIn)
    }

    // MARK: - syncCodeEntered recovery

    func test_syncCodeEntered_withRecoveryCode_attemptsLogin() async {
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertTrue(mockAccountManager.loginCalled)
    }

    func test_syncCodeEntered_withDefaultCredentialV2RecoveryCode_attemptsLogin() async throws {
        let secret = Data("default credential primary key".utf8)
        let recoveryCode = try Self.makeRecoveryCodeV2(credentialId: SyncCredentialID.defaultCredential,
                                                       secret: Base64URL.encode(secret))
        let mockAccountManager = AccountManagingMock()
        var receivedRecoveryKey: SyncCode.RecoveryKey?
        mockAccountManager.loginSpy = { recoveryKey, _, _ in
            receivedRecoveryKey = recoveryKey
        }
        dependencies.account = mockAccountManager

        let result = await controller.syncCodeEntered(code: recoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertTrue(result)
        XCTAssertTrue(mockAccountManager.loginCalled)
        XCTAssertEqual(receivedRecoveryKey?.userId, "test-user-id")
        XCTAssertEqual(receivedRecoveryKey?.primaryKey, secret)
    }

    @MainActor
    func test_syncCodeEntered_withDefaultCredentialV2RecoveryCodeWhenPairingV2ScanningDisabled_returnsUnableToRecognizeCode() async throws {
        dependencies.isPairingV2ScanningEnabled = { false }
        let recoveryCode = try Self.makeRecoveryCodeV2(credentialId: SyncCredentialID.defaultCredential)
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        let result = await controller.syncCodeEntered(code: recoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertFalse(mockAccountManager.loginCalled)
        XCTAssertEqual(delegate.didErrorErrors?.error, .unableToRecognizeCode)
    }

    @MainActor
    func test_syncCodeEntered_withUnsupportedDefaultCredentialV2RecoveryCodeVersion_returnsUpdateRequired() async throws {
        let recoveryCode = try Self.makeRecoveryCodeV2(credentialId: SyncCredentialID.defaultCredential, version: "3.0")
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        let result = await controller.syncCodeEntered(code: recoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertFalse(mockAccountManager.loginCalled)
        XCTAssertEqual(delegate.didErrorErrors?.error, .updateRequired)
        XCTAssertEqual(delegate.didErrorErrors?.underlyingError as? SyncCode.RecoveryCodeVersionError, .unsupported("3.0"))
    }

    @MainActor
    func test_syncCodeEntered_withUnsupportedDefaultCredentialV2RecoveryCodeVersionWhenPairingV2ScanningDisabled_returnsUnableToRecognizeCode() async throws {
        dependencies.isPairingV2ScanningEnabled = { false }
        let recoveryCode = try Self.makeRecoveryCodeV2(credentialId: SyncCredentialID.defaultCredential, version: "3.0")
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        let result = await controller.syncCodeEntered(code: recoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertFalse(mockAccountManager.loginCalled)
        XCTAssertEqual(delegate.didErrorErrors?.error, .unableToRecognizeCode)
    }

    @MainActor
    func test_syncCodeEntered_withMalformedDefaultCredentialV2RecoveryCodeVersion_returnsUnableToRecognizeCode() async throws {
        let recoveryCode = try Self.makeRecoveryCodeV2(credentialId: SyncCredentialID.defaultCredential, version: "invalid")
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        let result = await controller.syncCodeEntered(code: recoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertFalse(mockAccountManager.loginCalled)
        XCTAssertEqual(delegate.didErrorErrors?.error, .unableToRecognizeCode)
        XCTAssertEqual(delegate.didErrorErrors?.underlyingError as? SyncCode.RecoveryCodeVersionError, .malformed("invalid"))
    }

    @MainActor
    func test_syncCodeEntered_withDefaultCredentialV2RecoveryCodeWhenScopedAccessCredentialsDisabled_attemptsLogin() async throws {
        let secret = Data("default credential primary key".utf8)
        dependencies.isScopedAccessCredentialsEnabled = { false }
        let recoveryCode = try Self.makeRecoveryCodeV2(credentialId: SyncCredentialID.defaultCredential,
                                                       secret: Base64URL.encode(secret))
        let mockAccountManager = AccountManagingMock()
        var receivedRecoveryKey: SyncCode.RecoveryKey?
        mockAccountManager.loginSpy = { recoveryKey, _, _ in
            receivedRecoveryKey = recoveryKey
        }
        dependencies.account = mockAccountManager

        let result = await controller.syncCodeEntered(code: recoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertTrue(result)
        XCTAssertTrue(mockAccountManager.loginCalled)
        XCTAssertEqual(receivedRecoveryKey?.userId, "test-user-id")
        XCTAssertEqual(receivedRecoveryKey?.primaryKey, secret)
    }

    @MainActor
    func test_syncCodeEntered_withRecoveryCodeWhenPairingV2PresenterIsActive_cancelsPresenterCoordinator() async throws {
        dependencies.isPairingV2CodeEnabled = { true }
        let messageExchanger = PairingV2MessageExchangingMock()
        dependencies.createPairingV2MessageExchangerStub = messageExchanger
        let presenterInfo = try await controller.startExchangeMode()
        let presenterPayload = try XCTUnwrap(PairingV2QRCodePayload(url: try XCTUnwrap(URL(string: presenterInfo.base64Code))))

        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager
        let result = await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertTrue(result)
        XCTAssertTrue(messageExchanger.closeChannelCalls.contains(presenterPayload.channelId))
    }

    @MainActor
    func test_syncCodeEntered_withRecoveryCode_whenDelegateBlocksServerOperation_doesNotAttemptLogin() async {
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager
        delegate.shouldContinueServerSyncOperation = false

        let result = await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertEqual(delegate.willPerformServerSyncOperationCallCount, 1)
        XCTAssertFalse(mockAccountManager.loginCalled)
    }

    @MainActor
    func test_syncCodeEntered_withRecoveryCode_whenLoginFails_notifiesError() async throws {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.loginError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(error, .failedToLogIn)
    }

    func test_syncCodeEntered_withRecoveryCode_whenAccountExists_notifiesTwoAccounts() async {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.loginError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager
        try? dependencies.secureStore.persistAccount(SyncAccount.mock)

        await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        let twoAccountsKey = await delegate.didFindTwoAccountsDuringRecoveryCalled
        let shouldPromptBeforeSwitchingAccounts = await delegate.didFindTwoAccountsDuringRecoveryShouldPromptBeforeSwitchingAccounts
        XCTAssertNotNil(twoAccountsKey)
        XCTAssertEqual(shouldPromptBeforeSwitchingAccounts, true)
    }

    @MainActor
    func test_syncCodeEntered_withThirdPartyV2RecoveryCode_returnsFailure() async throws {
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        let recoveryCode = try Self.makeRecoveryCodeV2(credentialId: SyncCode.RecoveryKeyV2.thirdPartyCredentialId)
        let result = await controller.syncCodeEntered(code: recoveryCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertFalse(result)
        XCTAssertFalse(mockAccountManager.loginCalled)
        XCTAssertEqual(delegate.didErrorErrors?.error, .unsupportedThirdPartyRecoveryCode)
    }

    // MARK: - syncCodeEntered connect

    @MainActor
    func test_syncCodeEntered_withConnectCode_whenNoAccount_createsAccount() async {
        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didCreateSyncAccountCalled = {
            expectation.fulfill()
        }

        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        await fulfillment(of: [expectation], timeout: 5)
    }

    @MainActor
    func test_syncCodeEntered_withConnectCode_whenAccountCreationThrows_notifiesError() async throws {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.createAccountError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager

        let error = try await waitForError {
            await self.controller.syncCodeEntered(code: Self.validConnectCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)
        }
        XCTAssertEqual(error, .failedToCreateAccount)
    }

    func test_syncCodeEntered_withConnectCode_transmitsRecoveryKey() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertEqual(mockRecoveryKeyTransmitter.sendCalled, 1)
    }

    @MainActor
    func test_syncCodeEntered_withConnectCode_whenTransmitFails_notifiesError() async throws {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        mockRecoveryKeyTransmitter.sendError = SyncError.unableToDecodeResponse("")
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        let error = delegate.didErrorErrors?.error
        XCTAssertEqual(error, .failedToTransmitConnectRecoveryKey)
    }

    @MainActor
    func test_syncCodeEntered_withConnectCode_whenSuccessful_notifiesCompletion() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanLegacyURLBarcodes: true, codeSource: .pastedCode)

        let didComplete = delegate.didCompleteAccountConnectionValue
        XCTAssertNotNil(didComplete)
    }

    enum TestError: Error {
        case nilValue
    }

    private static func encryptedPresenterPeerMessages(messages: [PairingV2ApplicationMessage],
                                                       presenterPayload: PairingV2QRCodePayload,
                                                       peerKeyPair: PairingV2KeyPair,
                                                       initialSequence: Int = 0) throws -> [PairingV2SequencedMessage] {
        let crypto = PairingV2MessageCrypto()
        return try messages.enumerated().map { index, message in
            let encryptedMessage = try crypto.encrypt(message, recipientPublicKey: presenterPayload.publicKey, senderChannelID: peerKeyPair.channelID)
            return PairingV2SequencedMessage(seq: initialSequence + index + 1, version: encryptedMessage.version, payload: encryptedMessage.payload)
        }
    }

    private func encryptedPeerMessages(_ messages: [PairingV2ApplicationMessage],
                                       messageExchanger: PairingV2MessageExchangingMock,
                                       peerKeyPair: PairingV2KeyPair,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) throws -> [PairingV2SequencedMessage] {
        let crypto = PairingV2MessageCrypto()
        let encryptedHello = try XCTUnwrap(messageExchanger.sendCalls.first?.messages.first, file: file, line: line)
        let decryptedHello = try XCTUnwrap(try crypto.decrypt(encryptedHello, privateKey: peerKeyPair.privateKey), file: file, line: line)
        guard case .hello(let hello) = decryptedHello else {
            XCTFail("Expected initial Pairing V2 hello message", file: file, line: line)
            return []
        }

        return try messages.enumerated().map { index, message in
            let encryptedMessage = try crypto.encrypt(message, recipientPublicKey: hello.publicKey, senderChannelID: peerKeyPair.channelID)
            return PairingV2SequencedMessage(seq: index + 1, version: encryptedMessage.version, payload: encryptedMessage.payload)
        }
    }

    @MainActor
    private func waitForError(
        performing action: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> SyncConnectionError {
        let errorExpectation = expectation(description: "didError called")
        delegate.didErrorCalled = {
            errorExpectation.fulfill()
        }
        try await action()
        await fulfillment(of: [errorExpectation], timeout: 5)
        return try XCTUnwrap(delegate.didErrorErrors?.error, file: file, line: line)
    }
}

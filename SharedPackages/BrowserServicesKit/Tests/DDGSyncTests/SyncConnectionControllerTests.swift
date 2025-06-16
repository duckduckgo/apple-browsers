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
import BrowserServicesKit
import Persistence
import Common
@testable import DDGSync
@testable import BrowserServicesKitTestsUtils

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
    @Published var didBeginTransmittingRecoveryKeyCalled = false
    @Published var didFinishTransmittingRecoveryKeyCalled = false
    @Published var didReceiveRecoveryKeyCalled = false
    @Published var didRecognizeScannedCodeCalled = false
    @Published var didCreateSyncAccountCalled = false
    @Published var didCompleteAccountConnectionValue: Bool?
    @Published var didCompleteLoginDevices: [RegisteredDevice]?
    @Published var didFindTwoAccountsDuringRecoveryCalled: SyncCode.RecoveryKey?
    @Published var didErrorCalled: Bool = false
    var didErrorErrors: (error: SyncConnectionError, underlyingError: Error?)?

    func controllerWillBeginTransmittingRecoveryKey() async {
        didBeginTransmittingRecoveryKeyCalled = true
    }

    func controllerDidFinishTransmittingRecoveryKey() {
        didFinishTransmittingRecoveryKeyCalled = true
    }

    func controllerDidReceiveRecoveryKey() {
        didReceiveRecoveryKeyCalled = true
    }

    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource) async {
        didRecognizeScannedCodeCalled = true
    }

    func controllerDidCreateSyncAccount() {
        didCreateSyncAccountCalled = true
    }

    func controllerDidCompleteAccountConnection(shouldShowSyncEnabled: Bool, setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        didCompleteAccountConnectionValue = shouldShowSyncEnabled
    }

    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool, setupRole: SyncSetupRole) {
        didCompleteLoginDevices = registeredDevices
    }

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey, setupRole: SyncSetupRole) async {
        didFindTwoAccountsDuringRecoveryCalled = recoveryKey
    }

    func controllerDidError(_ error: SyncConnectionError, underlyingError: (any Error)?, setupRole: SyncSetupRole) async {
        didErrorCalled = true
        didErrorErrors = (error, underlyingError)
    }
}

// MARK: - Test Suite

import NetworkingTestingUtils

final class SyncConnectionControllerTests: XCTestCase {

    private static let validExchangeCode: String = "eyJleGNoYW5nZV9rZXkiOnsicHVibGljX2tleSI6InlcL2xScDZjOUtUVnNHT0ZXS2djblYrQlE4RlFMUFBxNmplVzRtUzE2OUNRPSIsImtleV9pZCI6IjAwRkY1NDNELUMzMjctNDMzNS1CM0NBLTU1MUQyOTUxOTNGQSJ9fQ=="
    private static let validConnectCode: String = "eyJjb25uZWN0Ijp7ImRldmljZV9pZCI6IjdFMTU2NTIyLTk0MDktNEZFOS1BRkY2LUFBNTM4MzIwRDhENCIsInNlY3JldF9rZXkiOiJsN1MxZFBVNkZXUW5oVkczK0dnVjhmaEY4SVRKbE1KZG1xTTRVYkY3eTNrPSJ9fQ=="
    private static let validRecoveryCode: String = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiMUE0QjBCRUUtMDA2Qy00QjdELUI1MjQtNDBBNzc0RERFNDM0IiwicHJpbWFyeV9rZXkiOiJjU3d1R3FmbTJpbmNcL1JYRW4yTjVxT0x0RllBRU5MY0UwN0lLWFk3ZFI0TT0ifX0="
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
        syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        delegate = MockSyncConnectionControllerDelegate()
        controller = SyncConnectionController(deviceName: Self.deviceName, deviceType: Self.deviceType, delegate: delegate, syncService: syncService, dependencies: dependencies)
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

    func test_startExchangeMode_pollSucceeds_transmitsRecoveryKey() async throws {
        // Mock exchanger creation
        givenExchangerPollForPublicKeySucceeds()

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter

        _ = try await controller.startExchangeMode()

        let publisher = await delegate.$didFinishTransmittingRecoveryKeyCalled
        try await waitForPublisher(publisher, timeout: 5, toEmit: true)

        XCTAssertEqual(exchangeRecoveryKeyTransmitter.sendCalled, 1)
    }

    func test_startExchangeMode_pollSucceeds_stopsExchangerPolling() async throws {
        throw XCTSkip("This is failing on CI but passing locally.")
        let remoteExchanger = MockRemoteKeyExchanging()
        givenExchangerPollForPublicKeySucceeds(remoteExchanger)

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter

        _ = try await controller.startExchangeMode()

        let publisher = await delegate.$didFinishTransmittingRecoveryKeyCalled
        try await waitForPublisher(publisher, timeout: 5, toEmit: true)

        XCTAssertEqual(remoteExchanger.stopPollingCalled, 1)
    }

    func test_startExchangeMode_pollFails_sendsError() async throws {
        // Mock exchanger creation
        let remoteExchanger = MockRemoteKeyExchanging()
        dependencies.createRemoteKeyExchangerStub = remoteExchanger
        remoteExchanger.pollForPublicKeyError = SyncError.unableToDecodeResponse("")

        _ = try await controller.startExchangeMode()

        let error = try await waitForError()

        XCTAssertEqual(error, SyncConnectionError.failedToFetchPublicKey)
    }

    func test_startExchangeMode_recoveryKeyTransmitFails_sendsError() async throws {
        // Mock exchanger creation
        givenExchangerPollForPublicKeySucceeds()

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter
        exchangeRecoveryKeyTransmitter.sendError = SyncError.unableToDecodeResponse("")

        _ = try await controller.startExchangeMode()

        let error = try await waitForError()

        XCTAssertEqual(error, SyncConnectionError.failedToTransmitExchangeRecoveryKey)
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

    func test_startConnectMode_pollSucceeds_informsDelegate() async throws {
        let remoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = remoteConnector
        remoteConnector.pollForRecoveryKeyStub = SyncCode.RecoveryKey(userId: "", primaryKey: Data())

        _ = try await controller.startConnectMode()

        let publisher = await delegate.$didReceiveRecoveryKeyCalled
        try await waitForPublisher(publisher, timeout: 5, toEmit: true)
    }

    func test_startConnectMode_pollSucceeds_logsIn() async throws {
        let remoteConnector = MockRemoteConnecting()
        let userId = "TestUserId"
        remoteConnector.pollForRecoveryKeyStub = SyncCode.RecoveryKey(userId: userId, primaryKey: Data())
        dependencies.createRemoteConnectorStub = remoteConnector
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        _ = try await controller.startConnectMode()

        try await waitForPublisher(mockAccountManager.$loginCalled, timeout: 5, toEmit: true)

        XCTAssertEqual(mockAccountManager.loginSpy?.recoveryKey.userId, userId)
    }

    func test_startConnectMode_pollingFails_sendsError() async throws {
        let remoteConnector = MockRemoteConnecting()
        remoteConnector.pollForRecoveryKeyError = SyncError.failedToPrepareForConnect("")
        dependencies.createRemoteConnectorStub = remoteConnector

        _ = try await controller.startConnectMode()

        let error = try await waitForError()

        XCTAssertEqual(error, SyncConnectionError.failedToFetchConnectRecoveryKey)
    }

    func test_startConnectMode_loginFails_sendsError() async throws {
        let remoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = remoteConnector
        remoteConnector.pollForRecoveryKeyStub = SyncCode.RecoveryKey(userId: "", primaryKey: Data())

        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager
        mockAccountManager.loginError = SyncError.failedToDecryptValue("")

        _ = try await controller.startConnectMode()

        let error = try await waitForError()

        XCTAssertEqual(error, SyncConnectionError.failedToLogIn)
    }

    // MARK: - Helper Functions

    private func createPairingInfo(code: String, deviceName: String = "Test") -> PairingInfo {
        PairingInfo(base64Code: code, deviceName: deviceName)
    }

    // MARK: - startPairingMode Tests

    func test_startPairingMode_whenAlreadyInFlight_returnsFalse() async {
        // Simulate in-flight operation
        _ = await controller.startPairingMode(PairingInfo(base64Code: Self.validExchangeCode, deviceName: "Test"))

        let result = await controller.startPairingMode(PairingInfo(base64Code: Self.validExchangeCode, deviceName: "Test"))
        XCTAssertEqual(result, false)
    }

    func test_startPairingMode_withInvalidCode_returnsFailure() async {
        let result = await controller.startPairingMode(PairingInfo(base64Code: "invalid_base64", deviceName: "Test"))
        let didError = await delegate.didErrorCalled
        let errorType = await delegate.didErrorErrors?.error

        XCTAssertEqual(result, false)
        XCTAssertTrue(didError)
        XCTAssertEqual(errorType, .unableToRecognizeCode)
    }

    func test_startPairingMode_withValidExchangeCode_notifiesDelegate() async {
        _ = await controller.startPairingMode(PairingInfo(base64Code: Self.validExchangeCode, deviceName: "Test"))
        let didRecognizeCode = await delegate.didRecognizeScannedCodeCalled

        XCTAssertTrue(didRecognizeCode)
    }

    func test_startPairingMode_withRecoveryCode_returnsFailure() async {
        let result = await controller.startPairingMode(createPairingInfo(code: Self.validRecoveryCode))
        let didError = await delegate.didErrorCalled
        let errorType = await delegate.didErrorErrors?.error

        XCTAssertEqual(result, false)
        XCTAssertTrue(didError)
        XCTAssertEqual(errorType, .unableToRecognizeCode)
    }

    // MARK: - startPairingMode exchange

    func test_startPairingMode_withExchangeCode_transmitsGeneratedExchangeInfo() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validExchangeCode))

        XCTAssertEqual(mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoCalled, 1)
    }

    func test_startPairingMode_withExchangeCode_whenTransmitFails_notifiesError() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoError = SyncError.unableToDecodeResponse("")
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validExchangeCode))

        let didError = await delegate.didErrorCalled
        let errorType = await delegate.didErrorErrors?.error

        XCTAssertTrue(didError)
        XCTAssertEqual(errorType, .failedToTransmitExchangeKey)
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

    func test_startPairingMode_withConnectCode_whenNoAccount_createsAccount() async {
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        let didCreateAccount = await delegate.didCreateSyncAccountCalled
        XCTAssertTrue(didCreateAccount)
    }

    func test_startPairingMode_withConnectCode_whenAccountCreationThrows_notifiesError() async {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.createAccountError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager

        await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        let error = try? await waitForError()
        XCTAssertEqual(error, .failedToCreateAccount)
    }

    func test_startPairingMode_withConnectCode_transmitsRecoveryKey() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        XCTAssertEqual(mockRecoveryKeyTransmitter.sendCalled, 1)
    }

    func test_startPairingMode_withConnectCode_whenTransmitFails_notifiesError() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        mockRecoveryKeyTransmitter.sendError = SyncError.unableToDecodeResponse("")
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        let error = try? await waitForError()
        XCTAssertEqual(error, .failedToTransmitConnectRecoveryKey)
    }

    func test_startPairingMode_withConnectCode_whenSuccessful_notifiesCompletion() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))

        let didComplete = await delegate.didCompleteAccountConnectionValue
        XCTAssertNotNil(didComplete)
    }

    // MARK: - syncCodeEntered Tests

    func test_syncCodeEntered_whenAlreadyInFlight_returnsFalse() async {
        // Simulate in-flight operation
        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let result = await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)
        XCTAssertEqual(result, false)
    }

    func test_syncCodeEntered_withInvalidCode_returnsFailure() async {
        let result = await controller.syncCodeEntered(code: "invalid_base64", canScanURLBarcodes: true, codeSource: .pastedCode)
        let didError = await delegate.didErrorCalled
        let errorType = await delegate.didErrorErrors?.error

        XCTAssertEqual(result, false)
        XCTAssertTrue(didError)
        XCTAssertEqual(errorType, .unableToRecognizeCode)
    }

    func test_syncCodeEntered_withValidExchangeCode_notifiesDelegate() async {
        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)
        let didRecognizeCode = await delegate.didRecognizeScannedCodeCalled

        XCTAssertTrue(didRecognizeCode)
    }

    func test_syncCodeEntered_withValidURL_extractsAndUsesCode() async {
        let url = "https://duckduckgo.com/sync/pairing/#&code=\(Self.validExchangeCode)&deviceName=TestDevice"
        await controller.syncCodeEntered(code: url, canScanURLBarcodes: true, codeSource: .pastedCode)
        let didRecognizeCode = await delegate.didRecognizeScannedCodeCalled

        XCTAssertTrue(didRecognizeCode)
    }

    // MARK: - syncCodeEntered exchange

    func test_syncCodeEntered_withExchangeCode_transmitsGeneratedExchangeInfo() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertEqual(mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoCalled, 1)
    }

    func test_syncCodeEntered_withExchangeCode_whenTransmitFails_notifiesError() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoError = SyncError.unableToDecodeResponse("")
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let didError = await delegate.didErrorCalled
        let errorType = await delegate.didErrorErrors?.error

        XCTAssertTrue(didError)
        XCTAssertEqual(errorType, .failedToTransmitExchangeKey)
    }

    func test_syncCodeEntered_withExchangeCode_createsExchangeRecoverer() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        let exchangeInfo = ExchangeInfo(keyId: "test", publicKey: Data(), secretKey: Data())
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoStub = exchangeInfo
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        let mockExchangeRecoverer = MockRemoteExchangeRecovering()
        dependencies.createRemoteExchangeRecoverer = mockExchangeRecoverer

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

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

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let devices = await delegate.didCompleteLoginDevices
        XCTAssertNotNil(devices)
    }

    func test_syncCodeEntered_withExchangeCode_whenRecoveryKeyPollFails_notifiesError() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        let exchangeInfo = ExchangeInfo(keyId: "test", publicKey: Data(), secretKey: Data())
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoStub = exchangeInfo
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        let mockExchangeRecoverer = MockRemoteExchangeRecovering()
        mockExchangeRecoverer.pollForRecoveryKeyError = SyncError.unableToDecodeResponse("")
        dependencies.createRemoteExchangeRecoverer = mockExchangeRecoverer

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let didError = await delegate.didErrorCalled
        let errorType = await delegate.didErrorErrors?.error

        XCTAssertTrue(didError)
        XCTAssertEqual(errorType, .failedToFetchExchangeRecoveryKey)
    }

    func test_syncCodeEntered_withExchangeCode_whenLoginFails_notifiesError() async {
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

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let didError = await delegate.didErrorCalled
        let errorType = await delegate.didErrorErrors?.error

        XCTAssertTrue(didError)
        XCTAssertEqual(errorType, .failedToLogIn)
    }

    // MARK: - syncCodeEntered recovery

    func test_syncCodeEntered_withRecoveryCode_attemptsLogin() async {
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertTrue(mockAccountManager.loginCalled)
    }

    func test_syncCodeEntered_withRecoveryCode_whenLoginFails_notifiesError() async {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.loginError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let didError = await delegate.didErrorCalled
        let errorType = await delegate.didErrorErrors?.error

        XCTAssertTrue(didError)
        XCTAssertEqual(errorType, .failedToLogIn)
    }

    func test_syncCodeEntered_withRecoveryCode_whenAccountExists_notifiesTwoAccounts() async {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.loginError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager
        try? dependencies.secureStore.persistAccount(SyncAccount.mock)

        await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let twoAccountsKey = await delegate.didFindTwoAccountsDuringRecoveryCalled
        XCTAssertNotNil(twoAccountsKey)
    }

    // MARK: - syncCodeEntered connect

    func test_syncCodeEntered_withConnectCode_whenNoAccount_createsAccount() async {
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let didCreateAccount = await delegate.didCreateSyncAccountCalled
        XCTAssertTrue(didCreateAccount)
    }

    func test_syncCodeEntered_withConnectCode_whenAccountCreationThrows_notifiesError() async {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.createAccountError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let error = try? await waitForError()
        XCTAssertEqual(error, .failedToCreateAccount)
    }

    func test_syncCodeEntered_withConnectCode_transmitsRecoveryKey() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertEqual(mockRecoveryKeyTransmitter.sendCalled, 1)
    }

    func test_syncCodeEntered_withConnectCode_whenTransmitFails_notifiesError() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        mockRecoveryKeyTransmitter.sendError = SyncError.unableToDecodeResponse("")
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let error = try? await waitForError()
        XCTAssertEqual(error, .failedToTransmitConnectRecoveryKey)
    }

    func test_syncCodeEntered_withConnectCode_whenSuccessful_notifiesCompletion() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let didComplete = await delegate.didCompleteAccountConnectionValue
        XCTAssertNotNil(didComplete)
    }

    private func waitForError() async throws -> SyncConnectionError? {
        let publisher = await delegate.$didErrorCalled
        try await waitForPublisher(publisher, timeout: 5, toEmit: true)
        let errors = await delegate.didErrorErrors
        return try XCTUnwrap(errors).error
    }
}

//
//  CombineTestHelpers.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

/*
 Code based on snippet from https://www.swiftbysundell.com/articles/unit-testing-combine-based-swift-code/
 */
public extension XCTestCase {
    func waitForPublisher<T: Publisher>(
        _ publisher: T,
        timeout: TimeInterval = 10,
        waitForFinish: Bool = true,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> T.Output {
        // This time, we use Swift's Result type to keep track
        // of the result of our Combine pipeline:
        var result: Result<T.Output, Error>?
        let expectation = self.expectation(description: "Awaiting publisher")
        expectation.assertForOverFulfill = false

        let cancellable = publisher.sink(
            receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    result = .failure(error)
                case .finished:
                    break
                }

                expectation.fulfill()
            },
            receiveValue: { value in
                result = .success(value)
                if !waitForFinish {
                    expectation.fulfill()
                }
            }
        )

        // Just like before, we await the expectation that we
        // created at the top of our test, and once done, we
        // also cancel our cancellable to avoid getting any
        // unused variable warnings:
        await fulfillment(of: [expectation], timeout: timeout)
        cancellable.cancel()

        // Here we pass the original file and line number that
        // our utility was called at, to tell XCTest to report
        // any encountered errors at that original call site:
        let unwrappedResult = try XCTUnwrap(
            result,
            "Awaited publisher did not produce any output",
            file: file,
            line: line
        )

        return try unwrappedResult.get()
    }

    @discardableResult
    func waitForPublisher<T: Publisher>(
        _ publisher: T,
        timeout: TimeInterval = 10,
        file: StaticString = #file,
        line: UInt = #line,
        toEmit value: T.Output
    ) async throws -> T.Output where T.Output: Equatable {
        try await waitForPublisher(
            publisher.first {
                value == $0
            },
            timeout: timeout,
            waitForFinish: false
        )
    }
}

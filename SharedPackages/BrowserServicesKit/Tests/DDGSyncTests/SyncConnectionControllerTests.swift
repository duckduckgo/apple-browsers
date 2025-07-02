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
    var didBeginTransmittingRecoveryKeyCalled = { }
    var didFinishTransmittingRecoveryKeyCalled = { }
    var didReceiveRecoveryKeyCalled = { }
    var didRecognizeScannedCodeCalled = { }
    var didCreateSyncAccountCalled = { }
    var didCompleteAccountConnectionValue: Bool?
    var didCompleteLoginDevices: [RegisteredDevice]?
    var didFindTwoAccountsDuringRecoveryCalled: SyncCode.RecoveryKey?
    var didErrorCalled = { }
    var didErrorErrors: (error: SyncConnectionError, underlyingError: Error?)?

    func controllerWillBeginTransmittingRecoveryKey() async {
        didBeginTransmittingRecoveryKeyCalled()
    }

    func controllerDidFinishTransmittingRecoveryKey() {
        didFinishTransmittingRecoveryKeyCalled()
    }

    func controllerDidReceiveRecoveryKey() {
        didReceiveRecoveryKeyCalled()
    }

    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource) async {
        didRecognizeScannedCodeCalled()
    }

    func controllerDidCreateSyncAccount() {
        didCreateSyncAccountCalled()
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
        didErrorCalled()
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
        let pairingInfo = try controller.startExchangeMode()

        XCTAssertEqual(pairingInfo.base64Code, expectedExchangeCode)
        XCTAssertEqual(pairingInfo.deviceName, Self.deviceName)
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

        _ = try controller.startExchangeMode()

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
        delegate.didFinishTransmittingRecoveryKeyCalled = {
            expectation.fulfill()
        }

        _ = try controller.startExchangeMode()

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(remoteExchanger.stopPollingCalled, 1)
    }

    func test_startExchangeMode_pollFails_sendsError() async throws {
        // Mock exchanger creation
        let remoteExchanger = MockRemoteKeyExchanging()
        dependencies.createRemoteKeyExchangerStub = remoteExchanger
        remoteExchanger.pollForPublicKeyError = SyncError.unableToDecodeResponse("")

        _ = try controller.startExchangeMode()

        let error = try await waitForError()

        XCTAssertEqual(error, SyncConnectionError.failedToFetchPublicKey)
    }

    func test_startExchangeMode_recoveryKeyTransmitFails_sendsError() async throws {
        // Mock exchanger creation
        givenExchangerPollForPublicKeySucceeds()

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter
        exchangeRecoveryKeyTransmitter.sendError = SyncError.unableToDecodeResponse("")

        _ = try controller.startExchangeMode()

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

        let pairingInfo = try controller.startConnectMode()

        XCTAssertEqual(pairingInfo.base64Code, expectedConnectorCode)
        XCTAssertEqual(pairingInfo.deviceName, Self.deviceName)
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

        _ = try controller.startConnectMode()

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

        _ = try controller.startConnectMode()

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(spiedKey?.userId, userId)
    }

    func test_startConnectMode_pollingFails_sendsError() async throws {
        let remoteConnector = MockRemoteConnecting()
        remoteConnector.pollForRecoveryKeyError = SyncError.failedToPrepareForConnect("")
        dependencies.createRemoteConnectorStub = remoteConnector

        _ = try controller.startConnectMode()

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

        _ = try controller.startConnectMode()

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

        Task {
            await controller.startPairingMode(createPairingInfo(code: Self.validConnectCode))
        }

        let error = try await waitForError()
        XCTAssertEqual(error, .failedToCreateAccount)
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
        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let result = await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)
        XCTAssertEqual(result, false)
    }

    @MainActor
    func test_syncCodeEntered_withInvalidCode_returnsFailure() async throws {
        let result = await controller.syncCodeEntered(code: "invalid_base64", canScanURLBarcodes: true, codeSource: .pastedCode)
        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(result, false)
        XCTAssertEqual(error, .unableToRecognizeCode)
    }

    @MainActor
    func test_syncCodeEntered_withValidExchangeCode_notifiesDelegate() async {
        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didRecognizeScannedCodeCalled = {
            expectation.fulfill()
        }

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        await fulfillment(of: [expectation], timeout: 5)
    }

    @MainActor
    func test_syncCodeEntered_withValidURL_extractsAndUsesCode() async {
        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didRecognizeScannedCodeCalled = {
            expectation.fulfill()
        }

        let url = "https://duckduckgo.com/sync/pairing/#&code=\(Self.validExchangeCode)&deviceName=TestDevice"
        await controller.syncCodeEntered(code: url, canScanURLBarcodes: true, codeSource: .pastedCode)

        await fulfillment(of: [expectation], timeout: 5)
    }

    // MARK: - syncCodeEntered exchange

    func test_syncCodeEntered_withExchangeCode_transmitsGeneratedExchangeInfo() async {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertEqual(mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoCalled, 1)
    }

    @MainActor
    func test_syncCodeEntered_withExchangeCode_whenTransmitFails_notifiesError() async throws {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoError = SyncError.unableToDecodeResponse("")
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

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

    @MainActor
    func test_syncCodeEntered_withExchangeCode_whenRecoveryKeyPollFails_notifiesError() async throws {
        let mockExchangePublicKeyTransmitter = MockExchangePublicKeyTransmitting()
        let exchangeInfo = ExchangeInfo(keyId: "test", publicKey: Data(), secretKey: Data())
        mockExchangePublicKeyTransmitter.sendGeneratedExchangeInfoStub = exchangeInfo
        dependencies.createExchangePublicKeyTransmitterStub = mockExchangePublicKeyTransmitter

        let mockExchangeRecoverer = MockRemoteExchangeRecovering()
        mockExchangeRecoverer.pollForRecoveryKeyError = SyncError.unableToDecodeResponse("")
        dependencies.createRemoteExchangeRecoverer = mockExchangeRecoverer

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

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

        await controller.syncCodeEntered(code: Self.validExchangeCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(error, .failedToLogIn)
    }

    // MARK: - syncCodeEntered recovery

    func test_syncCodeEntered_withRecoveryCode_attemptsLogin() async {
        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertTrue(mockAccountManager.loginCalled)
    }

    @MainActor
    func test_syncCodeEntered_withRecoveryCode_whenLoginFails_notifiesError() async throws {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.loginError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validRecoveryCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let error = delegate.didErrorErrors?.error

        XCTAssertEqual(error, .failedToLogIn)
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

    @MainActor
    func test_syncCodeEntered_withConnectCode_whenNoAccount_createsAccount() async {
        let expectation = self.expectation(description: "Exchanger poll completes")
        delegate.didCreateSyncAccountCalled = {
            expectation.fulfill()
        }

        let mockAccountManager = AccountManagingMock()
        dependencies.account = mockAccountManager

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        await fulfillment(of: [expectation], timeout: 5)
    }

    @MainActor
    func test_syncCodeEntered_withConnectCode_whenAccountCreationThrows_notifiesError() async throws {
        let mockAccountManager = AccountManagingMock()
        mockAccountManager.createAccountError = SyncError.failedToDecryptValue("")
        dependencies.account = mockAccountManager

        Task {
            await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)
        }

        let error = try await waitForError()
        XCTAssertEqual(error, .failedToCreateAccount)
    }

    func test_syncCodeEntered_withConnectCode_transmitsRecoveryKey() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        XCTAssertEqual(mockRecoveryKeyTransmitter.sendCalled, 1)
    }

    @MainActor
    func test_syncCodeEntered_withConnectCode_whenTransmitFails_notifiesError() async throws {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        mockRecoveryKeyTransmitter.sendError = SyncError.unableToDecodeResponse("")
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let error = delegate.didErrorErrors?.error
        XCTAssertEqual(error, .failedToTransmitConnectRecoveryKey)
    }

    @MainActor
    func test_syncCodeEntered_withConnectCode_whenSuccessful_notifiesCompletion() async {
        let mockRecoveryKeyTransmitter = MockRecoveryKeyTransmitting()
        dependencies.createRecoveryTransmitterStub = mockRecoveryKeyTransmitter

        await controller.syncCodeEntered(code: Self.validConnectCode, canScanURLBarcodes: true, codeSource: .pastedCode)

        let didComplete = delegate.didCompleteAccountConnectionValue
        XCTAssertNotNil(didComplete)
    }

    enum TestError: Error {
        case nilValue
    }

    @MainActor
    private func waitForError() async throws -> SyncConnectionError? {
        let expectation = expectation(description: "didError called")
        delegate.didErrorCalled = {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5)
        return try XCTUnwrap(delegate.didErrorErrors?.error)
    }
}

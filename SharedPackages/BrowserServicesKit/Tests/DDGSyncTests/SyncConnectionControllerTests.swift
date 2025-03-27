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

    func controllerDidRecognizeScannedCode() async {
        didRecognizeScannedCodeCalled = true
    }

    func controllerDidCreateSyncAccount() {
        didCreateSyncAccountCalled = true
    }

    func controllerDidCompleteAccountConnection(shouldShowSyncEnabled: Bool) {
        didCompleteAccountConnectionValue = shouldShowSyncEnabled
    }

    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool) {
        didCompleteLoginDevices = registeredDevices
    }

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey) async {
        didFindTwoAccountsDuringRecoveryCalled = recoveryKey
    }

    func controllerDidError(_ error: SyncConnectionError, underlyingError: (any Error)?) {
        didErrorCalled = true
        didErrorErrors = (error, underlyingError)
    }
}

// MARK: - Test Suite

import NetworkingTestingUtils

final class SyncConnectionControllerTests: XCTestCase {

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

    func test_startExchangeMode_returnsExchangerCode() throws {
        let expectedExchangerCode = "TestExchangerCode"
        let mockRemoteKeyExchanger: MockRemoteKeyExchanging = .init()
        dependencies.createRemoteKeyExchangerStub = mockRemoteKeyExchanger
        mockRemoteKeyExchanger.code = expectedExchangerCode

        XCTAssertEqual(try controller.startExchangeMode(), expectedExchangerCode)
    }

    func test_startExchangeMode_pollSucceeds_transmitsRecoveryKey() async throws {
        // Mock exchanger creation
        givenExchangerPollForPublicKeySucceeds()

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter

        _ = try controller.startExchangeMode()

        let publisher = await delegate.$didFinishTransmittingRecoveryKeyCalled
        try await waitForPublisher(publisher, timeout: 5, toEmit: true)

        XCTAssertEqual(exchangeRecoveryKeyTransmitter.sendCalled, 1)
    }

    func test_startExchangeMode_pollSucceeds_stopsExchangerPolling() async throws {
        let remoteExchanger = MockRemoteKeyExchanging()
        givenExchangerPollForPublicKeySucceeds(remoteExchanger)

        let exchangeRecoveryKeyTransmitter = MockExchangeRecoveryKeyTransmitting()
        dependencies.createExchangeRecoveryKeyTransmitterStub = exchangeRecoveryKeyTransmitter

        _ = try controller.startExchangeMode()

        let publisher = await delegate.$didFinishTransmittingRecoveryKeyCalled
        try await waitForPublisher(publisher, timeout: 5, toEmit: true)

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

    func test_startConnectMode_returnsConnectorCode() throws {
        let expectedConnectorCode = "TestConnectorCode"
        let mockRemoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = mockRemoteConnector
        mockRemoteConnector.code = expectedConnectorCode

        XCTAssertEqual(try controller.startConnectMode(), expectedConnectorCode)
    }

    func test_startConnectMode_pollSucceeds_informsDelegate() async throws {
        let remoteConnector = MockRemoteConnecting()
        dependencies.createRemoteConnectorStub = remoteConnector
        remoteConnector.pollForRecoveryKeyStub = SyncCode.RecoveryKey(userId: "", primaryKey: Data())

        _ = try controller.startConnectMode()

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

        _ = try controller.startConnectMode()

        try await waitForPublisher(mockAccountManager.$loginCalled, timeout: 5, toEmit: true)

        XCTAssertEqual(mockAccountManager.loginSpy?.recoveryKey.userId, userId)
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

    // MARK: syncCodeEntered

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

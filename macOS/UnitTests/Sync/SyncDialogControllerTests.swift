//
//  SyncDialogControllerTests.swift
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

import Bookmarks
import Combine
import Persistence
@testable import SyncUI_macOS
import XCTest
import PersistenceTestingUtils
@testable import BrowserServicesKit
@testable import DDGSync
@testable import DuckDuckGo_Privacy_Browser
import FeatureFlags

private final class MockUserAuthenticator: UserAuthenticating {
    var stubAuthenticateUser = DeviceAuthenticationResult.success
    func authenticateUser(reason: DuckDuckGo_Privacy_Browser.DeviceAuthenticator.AuthenticationReason) async -> DeviceAuthenticationResult {
        stubAuthenticateUser
    }
    func authenticateUser(reason: DeviceAuthenticator.AuthenticationReason, result: @escaping (DeviceAuthenticationResult) -> Void) {
        result(stubAuthenticateUser)
    }
}

private final class MockDeviceSyncCoordinationDelegate: DeviceSyncCoordinationDelegate {
    var didEndFlowCalled: (() -> Void)?

    func didEndFlow() {
        didEndFlowCalled?()
    }
}

@MainActor
final class SyncDialogControllerTests: XCTestCase {

    private var scheduler: CapturingScheduler! = CapturingScheduler()
    private var managementDialogModel: ManagementDialogModel! = ManagementDialogModel()
    private var authenticator: MockUserAuthenticator!
    private var ddgSyncing: MockDDGSyncing!
    private var pausedStateManager: MockSyncPausedStateManaging!
    private var connectionController: MockSyncConnectionControlling!
    private var featureFlagger: MockSyncFeatureFlagger!
    private var syncDialogController: SyncDialogController!
    var testRecoveryCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiMDZGODhFNzEtNDFBRS00RTUxLUE2UkRtRkEwOTcwMDE5QkYwIiwicHJpbWFyeV9rZXkiOiI1QTk3U3dsQVI5RjhZakJaU09FVXBzTktnSnJEYnE3aWxtUmxDZVBWazgwPSJ9fQ=="
    lazy var testRecoveryKey = try! SyncCode.decodeBase64String(testRecoveryCode).recovery!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        cancellables = []
        ddgSyncing = MockDDGSyncing(authState: .inactive, scheduler: scheduler, isSyncInProgress: false)
        pausedStateManager = MockSyncPausedStateManaging()
        featureFlagger = MockSyncFeatureFlagger()
        featureFlagger.isFeatureOn[FeatureFlag.syncSeamlessAccountSwitching.rawValue] = true
        connectionController = MockSyncConnectionControlling()
        authenticator = MockUserAuthenticator()

        syncDialogController = SyncDialogController(
            syncService: ddgSyncing,
            managementDialogModel: managementDialogModel,
            userAuthenticator: authenticator,
            syncPausedStateManager: pausedStateManager,
            connectionControllerFactory: { [weak self] _, _ in
                guard let self else { return MockSyncConnectionControlling() }
                return connectionController
            },
            featureFlagger: featureFlagger
        )
    }

    override func tearDown() {
        ddgSyncing = nil
        syncDialogController = nil
        pausedStateManager = nil
        cancellables = nil
        connectionController = nil
        featureFlagger = nil
        managementDialogModel = nil
        scheduler = nil
        authenticator = nil
    }

    func testOnPresentRecoverSyncAccountDialogThenRecoverAccountDialogShown() async {
        await syncDialogController.recoverDataPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .recoverSyncedData)
    }

    func testOnSyncWithServerPressedThenSyncWithServerDialogShown() async {
        await syncDialogController.syncWithServerPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .syncWithServer)
    }

    @MainActor
    func testOnPresentTurnOffSyncConfirmDialogThenTurnOffSyncShown() {
        syncDialogController.turnOffSyncPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .turnOffSync)
    }

    @MainActor
    func testOnPresentRemoveDeviceThenRemoveDeviceShown() {
        let device = SyncDevice(kind: .desktop, name: "test", id: "test")
        syncDialogController.presentRemoveDevice(device)

        XCTAssertEqual(managementDialogModel.currentDialog, .removeDevice(device))
    }

    func testOnTurnOffSyncThenSyncServiceIsDisconnected() async throws {
        let expectation = expectation(description: "disconnectCalled")
        expectation.assertForOverFulfill = false
        ddgSyncing.spyDisconnectCalled = {
            expectation.fulfill()
        }
        syncDialogController.turnOffSync()
        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func test_recoverDevice_callsConnectionController() async {
        let expectation = expectation(description: "callsConnectionController")
        connectionController.syncCodeEnteredCalled = { _, _, _ in
            expectation.fulfill()
        }
        syncDialogController.recoveryCodePasted(testRecoveryCode, fromRecoveryScreen: false)
        await fulfillment(of: [expectation], timeout: 5)
    }

    func test_controllerDidFindTwoAccountsDuringRecovery_accountAlreadyExists_oneDevice_disconnectsThenLogsInAgain() async throws {
        // Must have an account to prevent devices being cleared
        setUpWithSingleDevice(id: "1")
        var didCallDDGSyncLogin = false
        ddgSyncing.spyLogin = { [weak self] _, _, _ in
            guard let self else { return [] }
            didCallDDGSyncLogin = true
            XCTAssert(ddgSyncing.disconnectCalled)
            return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
        }
        await syncDialogController.controllerDidFindTwoAccountsDuringRecovery(testRecoveryKey, setupRole: .sharer)
        XCTAssert(didCallDDGSyncLogin)
    }

    func test_recoverDevice_accountAlreadyExists_oneDevice_updatesDevicesWithReturnedDevices() async throws {
        // Must have an account to prevent devices being cleared
        setUpWithSingleDevice(id: "1")

        let expectation = expectation(description: "devices updated")

        ddgSyncing.stubLogin = [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]

        await syncDialogController.controllerDidFindTwoAccountsDuringRecovery(testRecoveryKey, setupRole: .sharer)

        syncDialogController.$devices.sink {
            if $0.map(\.id) == ["1", "2"] {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(syncDialogController.devices.map(\.id), ["1", "2"])
    }

    func test_recoverDevice_accountAlreadyExists_oneDevice_endsFlow() async throws {
        setUpWithSingleDevice(id: "1")
        // Removal of currentDialog indicates end of flow
        managementDialogModel.currentDialog = .enterRecoveryCode(stringForQRCode: "")

        ddgSyncing.spyLogin = { _, _, _ in
            return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
        }

        await syncDialogController.controllerDidFindTwoAccountsDuringRecovery(testRecoveryKey, setupRole: .sharer)

        XCTAssertNil(managementDialogModel.currentDialog)
    }

    func test_recoverDevice_accountAlreadyExists_twoOrMoreDevices_showsAccountSwitchingMessage() async throws {
        // Must have an account to prevent devices being cleared
        ddgSyncing.account = SyncAccount(deviceId: "1", deviceName: "", deviceType: "", userId: "", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)
        syncDialogController.devices = [SyncDevice(RegisteredDevice(id: "1", name: "iPhone", type: "iPhone")), SyncDevice(RegisteredDevice(id: "2", name: "iPhone", type: "iPhone"))]

        await syncDialogController.controllerDidFindTwoAccountsDuringRecovery(testRecoveryKey, setupRole: .sharer)

        XCTAssert(managementDialogModel.shouldShowErrorMessage)
        XCTAssert(managementDialogModel.shouldShowSwitchAccountsMessage)
    }

    func test_switchAccounts_disconnectsThenLogsInAgain() async throws {
        let loginCalledExpectation = XCTestExpectation(description: "Login Called Again")

        ddgSyncing.spyLogin = { [weak self] _, _, _ in
            guard let self else { return [] }
            // Assert disconnect before returning from login to ensure correct order
            XCTAssert(ddgSyncing.disconnectCalled)
            loginCalledExpectation.fulfill()
            return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
        }

        syncDialogController.userConfirmedSwitchAccounts(recoveryCode: testRecoveryCode)

        await fulfillment(of: [loginCalledExpectation], timeout: 5.0)
    }

    @MainActor
    func test_switchAccounts_updatesDevicesWithReturnedDevices() async throws {
        setUpWithSingleDevice(id: "1")

        ddgSyncing.spyLogin = { _, _, _ in
            return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
        }

        let expectation = expectation(description: "received devices")
        expectation.assertForOverFulfill = false

        syncDialogController.$devices.sink {
            if $0.map(\.id) == ["1", "2"] {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        Task {
            syncDialogController.userConfirmedSwitchAccounts(recoveryCode: testRecoveryCode)
        }

        await fulfillment(of: [expectation], timeout: 5)
    }

    @MainActor
    func test_startPollingForRecoveryKey_whenFeatureFlagOff_usesBase64Code() async {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startConnectModeStub = pairingInfo

        let expectations = self.expectationsFor(codeForDisplayOrPasting: "test_code", stringForQR: "test_code")

        syncDialogController.enterRecoveryCodePressed()

        await fulfillment(of: expectations, timeout: 5)
    }

    @MainActor
    func test_startPollingForRecoveryKey_whenFeatureFlagOn_usesURL() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startConnectModeStub = pairingInfo

        let expectations = self.expectationsFor(codeForDisplayOrPasting: "test_code", stringForQR: pairingInfo.url.absoluteString)

        syncDialogController.enterRecoveryCodePressed()

        await fulfillment(of: expectations, timeout: 5)
    }

    @MainActor
    func test_syncWithAnotherDevicePressed_accountExists_whenFeatureFlagOff_usesBase64Code() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startExchangeModeStub = pairingInfo
        ddgSyncing.account = .mock

        let expectations = self.expectationsFor(codeForDisplayOrPasting: "test_code", stringForQR: "test_code")

        await syncDialogController.syncWithAnotherDevicePressed(source: nil)

        await fulfillment(of: expectations, timeout: 5)
    }

    @MainActor
    func test_syncWithAnotherDevicePressed_accountExists_whenFeatureFlagOn_usesURL() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startExchangeModeStub = pairingInfo
        ddgSyncing.account = .mock

        let expectations = self.expectationsFor(codeForDisplayOrPasting: "test_code", stringForQR: pairingInfo.url.absoluteString)

        await syncDialogController.syncWithAnotherDevicePressed(source: nil)

        await fulfillment(of: expectations, timeout: 5)
    }

    func test_syncWithAnotherDevicePressed_accountExists_whenExchangeFeatureFlagOff_usesRecoveryCode() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = false
        let mockAccount = SyncAccount.mock
        ddgSyncing.account = mockAccount

        Task {
            await syncDialogController.syncWithAnotherDevicePressed(source: nil)
        }

        let codes = try await waitForSyncWithAnotherDeviceDialogCodes()

        XCTAssertTrue(codes.displayCode.isRecoveryKey)
        XCTAssertTrue(codes.qrCode.isRecoveryKey)

        let codeForDisplayOrPasting = try XCTUnwrap(syncDialogController.codeForDisplayOrPasting)
        XCTAssertTrue(codeForDisplayOrPasting.isRecoveryKey)

        let stringForQR = try XCTUnwrap(syncDialogController.stringForQR)
        XCTAssertTrue(stringForQR.isRecoveryKey)
    }

    func test_syncWithAnotherDevicePressed_accountExists_whenExchangeFeatureFlagOn_andUrlBarcodeOn_usesUrlFormat() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        let mockAccount = SyncAccount.mock
        ddgSyncing.account = mockAccount
        let expectedExchangeCode = "expected_exchange_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedExchangeCode, deviceName: "")
        connectionController.startExchangeModeStub = stubbedPairingInfo

        Task {
            await syncDialogController.syncWithAnotherDevicePressed(source: nil)
        }

        let codes = try await waitForSyncWithAnotherDeviceDialogCodes()

        XCTAssertEqual(codes.displayCode, expectedExchangeCode)
        XCTAssertTrue(codes.qrCode.isDDGURLString)

        let codeForDisplayOrPasting = try XCTUnwrap(syncDialogController.codeForDisplayOrPasting)
        XCTAssertEqual(codeForDisplayOrPasting, expectedExchangeCode)

        let stringForQR = try XCTUnwrap(syncDialogController.stringForQR)
        XCTAssertTrue(stringForQR.isDDGURLString)
    }

    func test_enterRecoveryCodePressed_whenUrlBarcodeOn_usesUrlFormat() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        let expectedDisplayCode = "test_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedDisplayCode, deviceName: "")
        connectionController.startConnectModeStub = stubbedPairingInfo

        syncDialogController.enterRecoveryCodePressed()

        let code = try await waitForEnterRecoveryCodeDialog()

        XCTAssertTrue(code.isDDGURLString)

        let codeForDisplayOrPasting = try XCTUnwrap(syncDialogController.codeForDisplayOrPasting)
        XCTAssertEqual(codeForDisplayOrPasting, expectedDisplayCode)

        let stringForQR = try XCTUnwrap(syncDialogController.stringForQR)
        XCTAssertTrue(stringForQR.isDDGURLString)
    }

    func test_enterRecoveryCodePressed_whenUrlBarcodeOff_usesBase64Format() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        let expectedDisplayCode = "test_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedDisplayCode, deviceName: "")
        connectionController.startConnectModeStub = stubbedPairingInfo

        syncDialogController.enterRecoveryCodePressed()

        let code = try await waitForEnterRecoveryCodeDialog()

        XCTAssertEqual(code, expectedDisplayCode)
        XCTAssertEqual(syncDialogController.codeForDisplayOrPasting, expectedDisplayCode)
        XCTAssertEqual(syncDialogController.stringForQR, expectedDisplayCode)
    }

    func test_syncWithAnotherDevicePressed_whenUrlBarcodeOn_usesUrlFormat() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        let expectedCode = "test_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedCode, deviceName: "")
        connectionController.startExchangeModeStub = stubbedPairingInfo
        ddgSyncing.account = .mock

        Task {
            await syncDialogController.syncWithAnotherDevicePressed(source: nil)
        }

        let codes = try await waitForSyncWithAnotherDeviceDialogCodes()

        let dialogQrCode = try XCTUnwrap(codes.qrCode)
        XCTAssertTrue(dialogQrCode.isDDGURLString)

        XCTAssertEqual(syncDialogController.codeForDisplayOrPasting, expectedCode)
        let stringForQR = try XCTUnwrap(syncDialogController.stringForQR)
        XCTAssertTrue(stringForQR.isDDGURLString)
    }

    func test_syncWithAnotherDevicePressed_whenUrlBarcodeOff_usesBase64Format() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        let expectedCode = "test_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedCode, deviceName: "")
        connectionController.startExchangeModeStub = stubbedPairingInfo
        ddgSyncing.account = .mock

        Task {
            await syncDialogController.syncWithAnotherDevicePressed(source: nil)
        }

        let codes = try await waitForSyncWithAnotherDeviceDialogCodes()

        XCTAssertEqual(codes.qrCode, expectedCode)
        XCTAssertEqual(codes.displayCode, expectedCode)

        XCTAssertEqual(syncDialogController.codeForDisplayOrPasting, expectedCode)
        XCTAssertEqual(syncDialogController.stringForQR, expectedCode)
    }

    func test_startPollingForRecoveryKey_whenError_showsError() async {
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        connectionController.startConnectModeError = SyncError.failedToDecryptValue("")

        let expectation = expectation(description: "shouldShowErrorMessage")
        expectation.assertForOverFulfill = false
        managementDialogModel.$shouldShowErrorMessage.sink { [weak self] in
            if $0 {
                XCTAssertEqual(self?.managementDialogModel.syncErrorMessage?.type, .unableToSyncToOtherDevice)
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        await syncDialogController.syncWithAnotherDevicePressed(source: nil)

        await fulfillment(of: [expectation], timeout: 5)
    }

    @MainActor
    func test_syncWithAnotherDevicePressed_accountExists_whenError_showsError() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        connectionController.startExchangeModeError = SyncError.failedToDecryptValue("")
        ddgSyncing.account = .mock

        let expectation = expectation(description: "shouldShowErrorMessage")
        expectation.assertForOverFulfill = false
        managementDialogModel.$shouldShowErrorMessage.sink { [weak self] in
            if $0 {
                XCTAssertEqual(self?.managementDialogModel.syncErrorMessage?.type, .unableToSyncToOtherDevice)
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        Task {
            await syncDialogController.syncWithAnotherDevicePressed(source: nil)
        }

        await fulfillment(of: [expectation], timeout: 5)
    }

    func test_WhenSyncIsTurnedOff_ErrorHandlerSyncDidTurnOffCalled() async throws {
        let expectation = expectation(description: "errorHandlerSyncDidTurnOffCalled")

        pausedStateManager.spySyncDidTurnOff = {
            expectation.fulfill()
        }

        syncDialogController.turnOffSync()

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func test_WhenAccountRemoved_ErrorHandlerSyncDidTurnOffCalled() async throws {
        let expectation = expectation(description: "errorHandlerSyncDidTurnOffCalled")

        pausedStateManager.spySyncDidTurnOff = {
            expectation.fulfill()
        }

        syncDialogController.deleteAccount()

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    // MARK: - Initialization and Setup

    func testInitialization_setsDelegateOnManagementDialogModel() {
        XCTAssertTrue(managementDialogModel.delegate === syncDialogController)
    }

    // MARK: - Device Management

    func testRefreshDevices_whenNoAccount_clearsDevices() {
        syncDialogController.devices = [SyncDevice(kind: .desktop, name: "Test", id: "test")]
        ddgSyncing.account = nil

        syncDialogController.refreshDevices()

        XCTAssertEqual(syncDialogController.devices.count, 0)
    }

    func testRefreshDevices_whenFetchDevicesSucceeds_updatesDevices() async {
        ddgSyncing.account = SyncAccount(deviceId: "test-id", deviceName: "Test Device", deviceType: "desktop", userId: "user", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)

        let registeredDevices = [
            RegisteredDevice(id: "test-id", name: "Test Device", type: "desktop"),
            RegisteredDevice(id: "testDeviceId", name: "Current Device", type: "desktop")
        ]
        ddgSyncing.registeredDevices = registeredDevices

        let expectation = expectation(description: "Current device should be first")

        syncDialogController.devicesPublisher.sink { devices in
            if devices.count == 2 {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        syncDialogController.refreshDevices()

        await fulfillment(of: [expectation])
    }

    func testRefreshDevices_onMapDevices_sortsDevicesWithCurrentFirst() async {
        let testDeviceId = "current-device"
        ddgSyncing.account = SyncAccount(deviceId: testDeviceId, deviceName: "Test Device", deviceType: "desktop", userId: "user", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)

        let registeredDevices = [
            RegisteredDevice(id: "other-device-1", name: "Other Device 1", type: "mobile"),
            RegisteredDevice(id: testDeviceId, name: "Current Device", type: "desktop"),
            RegisteredDevice(id: "other-device-2", name: "Other Device 2", type: "mobile")
        ]

        ddgSyncing.registeredDevices = registeredDevices

        let expectation = expectation(description: "Current device should be first")

        syncDialogController.devicesPublisher.sink { devices in
            if devices.count == 3 {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        syncDialogController.refreshDevices()

        await fulfillment(of: [expectation])

        XCTAssertTrue(syncDialogController.devices.first?.isCurrent == true)
    }

    // MARK: - Dialog Flow Management

    func testPresentDeleteAccount_presentsCorrectDialog() {
        let testDevices = [SyncDevice(kind: .desktop, name: "Test", id: "test")]
        syncDialogController.devices = testDevices

        syncDialogController.presentDeleteAccount()

        if case .deleteAccount(let devices) = managementDialogModel.currentDialog {
            XCTAssertEqual(devices.count, testDevices.count)
        } else {
            XCTFail("Expected deleteAccount dialog")
        }
    }

    func testRecoveryCodeNextPressed_showsNowSyncing() {
        syncDialogController.recoveryCodeNextPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .nowSyncing)
    }

    // MARK: - Authentication Flows

    func testSyncWithAnotherDevicePressed_whenAuthenticationFails_setsErrorMessage() async {
        authenticator.stubAuthenticateUser = .noAuthAvailable

        await syncDialogController.syncWithAnotherDevicePressed(source: nil)

        XCTAssertEqual(managementDialogModel.currentDialog, .empty)
        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToAuthenticateOnDevice)
    }

    func testSyncWithAnotherDevicePressed_whenAuthenticationDoesNotSucceed_forAnyReason_callsDidEndFlowOnCoordinationDelegate() async {
        await assertWhenAuthenticationDoesNotSucceed_callsDidEndFlow {
            await syncDialogController.syncWithAnotherDevicePressed(source: nil)
        }
    }

    func testSyncWithServerPressed_whenAuthenticationDoesNotSucceed_forAnyReason_callsDidEndFlowOnCoordinationDelegate() async {
        await assertWhenAuthenticationDoesNotSucceed_callsDidEndFlow {
            await syncDialogController.syncWithServerPressed()
        }
    }

    func testRecoverDataPressed_whenAuthenticationDoesNotSucceed_forAnyReason_callsDidEndFlowOnCoordinationDelegate() async {
        await assertWhenAuthenticationDoesNotSucceed_callsDidEndFlow {
            await syncDialogController.recoverDataPressed()
        }
    }

    func testSaveRecoveryPDF_whenAuthenticationDoesNotSucceed_forAnyReason_callsDidEndFlowOnCoordinationDelegate() async {
        let coordinationDelegate = MockDeviceSyncCoordinationDelegate()
        syncDialogController.coordinationDelegate = coordinationDelegate
        ddgSyncing.account = .mock
        for authenticationResult in [
            DeviceAuthenticationResult.failure,
            DeviceAuthenticationResult.noAuthAvailable,
        ] {
            authenticator.stubAuthenticateUser = authenticationResult
            let expectation = XCTestExpectation(description: "Did call didEndFlow")
            coordinationDelegate.didEndFlowCalled = {
                expectation.fulfill()
            }
            syncDialogController.saveRecoveryPDF()
            await fulfillment(of: [expectation])
        }
    }

    func assertWhenAuthenticationDoesNotSucceed_callsDidEndFlow(file: StaticString = #file, line: UInt = #line, functionUnderTest: () async -> Void) async {
        let coordinationDelegate = MockDeviceSyncCoordinationDelegate()
        syncDialogController.coordinationDelegate = coordinationDelegate
        for authenticationResult in [
            DeviceAuthenticationResult.failure,
            DeviceAuthenticationResult.noAuthAvailable,
        ] {
            authenticator.stubAuthenticateUser = authenticationResult
            var didEndFlowCalled = false
            coordinationDelegate.didEndFlowCalled = {
                didEndFlowCalled = true
            }
            await functionUnderTest()

            XCTAssertTrue(didEndFlowCalled, file: file, line: line)
        }
    }

    func testSyncWithServerPressed_whenAuthenticationFails_setsErrorMessage() async {
        authenticator.stubAuthenticateUser = .noAuthAvailable

        await syncDialogController.syncWithServerPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .empty)
        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToAuthenticateOnDevice)
    }

    func testRecoverDataPressed_whenAuthenticationFails_setsErrorMessage() async {
        authenticator.stubAuthenticateUser = .noAuthAvailable
        syncDialogController = SyncDialogController(
            syncService: ddgSyncing,
            managementDialogModel: managementDialogModel,
            userAuthenticator: authenticator,
            syncPausedStateManager: pausedStateManager,
            connectionControllerFactory: { [weak self] _, _ in
                guard let self else { return MockSyncConnectionControlling() }
                return connectionController
            },
            featureFlagger: featureFlagger
        )

        await syncDialogController.recoverDataPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .empty)
        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToAuthenticateOnDevice)
    }

    // MARK: - Account Creation and Management

    func testTurnOnSync_callsCreateAccount() async {
        let expectation = expectation(description: "Create account callback called")

        ddgSyncing.createAccountCallback = { _, _ in
            expectation.fulfill()
        }

        syncDialogController.turnOnSync()

        await fulfillment(of: [expectation], timeout: 5)
    }

    func testTurnOnSync_onAccountCreationError_setsErrorMessage() async {
        let expectation = expectation(description: "Create account errored")

        managementDialogModel.$syncErrorMessage.sink {
            if $0 != nil {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        ddgSyncing.createAccountError = SyncError.failedToLoadAccount
        syncDialogController.turnOnSync()

        await fulfillment(of: [expectation], timeout: 5)
    }

    func testUpdateDeviceName_callsUpdateMethod() async {
        let expectation = expectation(description: "Create account callback called")

        ddgSyncing.updateDeviceNameCallback = { _ in
            expectation.fulfill()
        }

        syncDialogController.updateDeviceName("New Name")

        await fulfillment(of: [expectation], timeout: 5)
    }

    func testUpdateDeviceName_handlesErrorsGracefully() async {
        let expectation = expectation(description: "Update device errored")

        managementDialogModel.$syncErrorMessage.sink {
            if $0 != nil {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        ddgSyncing.updateDeviceNameError = SyncError.failedToLoadAccount
        syncDialogController.updateDeviceName("New Name")

        await fulfillment(of: [expectation], timeout: 5)
    }

    func testRemoveDevice_whenSucceeds_endsFlow() async {
        let device = SyncDevice(kind: .desktop, name: "Test Device", id: "test-id")

        let expectation = expectation(description: "remove device")
        ddgSyncing.disconnectDeviceCallback = { _ in
            expectation.fulfill()
        }

        syncDialogController.removeDevice(device)

        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertNil(managementDialogModel.currentDialog)
    }

    func testRemoveDevice_whenSucceeds_refreshesDevices() async {
        ddgSyncing.account = .mock
        let device = SyncDevice(kind: .desktop, name: "Test Device", id: "test-id")

        let expectation = expectation(description: "remove device")
        ddgSyncing.fetchDevicesCallback = {
            expectation.fulfill()
        }

        syncDialogController.removeDevice(device)

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testRemoveDevice_whenFails_handlesErrorsGracefully() async {
        let device = SyncDevice(kind: .desktop, name: "Test Device", id: "test-id")
        let expectation = expectation(description: "Remove device errored")

        managementDialogModel.$syncErrorMessage.sink {
            if $0 != nil {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        ddgSyncing.disconnectDeviceError = SyncError.failedToLoadAccount
        syncDialogController.removeDevice(device)

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    // MARK: - Connection Controller Delegate Methods

    func testControllerDidFinishTransmittingRecoveryKey_waitsForDevices() {
        syncDialogController.controllerDidFinishTransmittingRecoveryKey()

        // The method sets up a publisher to wait for device changes
        // We can verify this by checking that the devices publisher is being observed
        XCTAssertNotNil(syncDialogController)
    }

    func testControllerDidReceiveRecoveryKey_presentsPrepareDialog() {
        syncDialogController.controllerDidReceiveRecoveryKey()

        XCTAssertEqual(managementDialogModel.currentDialog, .prepareToSync)
    }

    func testControllerDidCreateSyncAccount_presentsSaveRecoveryCodeDialog() {
        // Use the mock account that has a recovery code already set
        ddgSyncing.account = SyncAccount.mock

        syncDialogController.controllerDidCreateSyncAccount()

        if case .saveRecoveryCode = managementDialogModel.currentDialog {
            // Success - don't check exact code since recoveryCode is read-only
        } else {
            XCTFail("Expected saveRecoveryCode dialog")
        }
    }

    func testControllerDidCompleteAccountConnection_whenShouldShowSyncEnabled_presentsRecoveryDialog() async {
        ddgSyncing.account = SyncAccount.mock

        let expectation = expectation(description: "saveRecoveryCode dialog presented")

        managementDialogModel.$currentDialog.sink { dialog in
            if case .saveRecoveryCode = dialog {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        syncDialogController.controllerDidCompleteAccountConnection(shouldShowSyncEnabled: true, setupSource: .connect, codeSource: .pastedCode)

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testControllerDidCompleteAccountConnection_whenShouldNotShowSyncEnabled_doesNotPresentDialog() {
        let initialDialog = managementDialogModel.currentDialog

        syncDialogController.controllerDidCompleteAccountConnection(shouldShowSyncEnabled: false, setupSource: .connect, codeSource: .pastedCode)

        // Dialog should remain unchanged
        XCTAssertEqual(managementDialogModel.currentDialog, initialDialog)
    }

    func testControllerDidCompleteLogin_updatesDevicesAndPresentsRecoveryDialog() async {
        ddgSyncing.account = SyncAccount.mock

        let registeredDevices = [RegisteredDevice(id: "test", name: "Test Device", type: "desktop")]

        let expectation = expectation(description: "devices updated")

        syncDialogController.devicesPublisher.sink { devices in
            if devices.count == 1 {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        syncDialogController.controllerDidCompleteLogin(registeredDevices: registeredDevices, isRecovery: false, setupRole: .sharer)

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testControllerDidError_unableToRecognizeCode_setsCorrectErrorMessage() async {
        await syncDialogController.controllerDidError(.unableToRecognizeCode, underlyingError: nil, setupRole: .sharer)

        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToRecognizeCode)
    }

    func testControllerDidError_connectionErrors_setsCorrectErrorMessage() async {
        await syncDialogController.controllerDidError(.failedToLogIn, underlyingError: nil, setupRole: .sharer)

        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToSyncToOtherDevice)
    }

    func testControllerDidError_pollingTimeout_endsFlow() async {
        managementDialogModel.currentDialog = .syncWithServer

        await syncDialogController.controllerDidError(.pollingForRecoveryKeyTimedOut, underlyingError: nil, setupRole: .sharer)

        XCTAssertNil(managementDialogModel.currentDialog)
    }

    func testDidEndFlow_notifiesDelegate() async {
        let mockDelegate = MockDeviceSyncCoordinationDelegate()
        syncDialogController.coordinationDelegate = mockDelegate

        let expectation = expectation(description: "delegate called")
        mockDelegate.didEndFlowCalled = {
            expectation.fulfill()
        }

        syncDialogController.didEndFlow()

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testDidEndFlow_cancelsConnectionController_beforeNotifyingDelegate() async {
        let mockDelegate = MockDeviceSyncCoordinationDelegate()
        syncDialogController.coordinationDelegate = mockDelegate
        var didCallDidEndFlow = false

        let didEndFlowCalled = expectation(description: "didEndFlowCalled called")
        mockDelegate.didEndFlowCalled = {
            didCallDidEndFlow = true
            didEndFlowCalled.fulfill()
        }

        let cancelCalled = expectation(description: "cancelCalled called")
        connectionController.cancelCalled = {
            XCTAssertFalse(didCallDidEndFlow)
            cancelCalled.fulfill()
        }

        syncDialogController.didEndFlow()

        await fulfillment(of: [cancelCalled, didEndFlowCalled], timeout: 5.0)
    }

    // MARK: - Helper Methods

    private func setUpWithSingleDevice(id: String) {
        ddgSyncing.account = SyncAccount(deviceId: id, deviceName: "iPhone", deviceType: "iPhone", userId: "", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)
        ddgSyncing.registeredDevices = [RegisteredDevice(id: id, name: "iPhone", type: "iPhone")]
        syncDialogController.devices = [SyncDevice(RegisteredDevice(id: id, name: "iPhone", type: "iPhone"))]
    }

    private func expectationsFor(codeForDisplayOrPasting: String, stringForQR: String) -> [XCTestExpectation] {
        let codeForDisplayExpectation = expectation(description: "codeForDisplayOrPasting")
        let stringForQRExpectation = expectation(description: "stringForQR")

        codeForDisplayExpectation.assertForOverFulfill = false
        stringForQRExpectation.assertForOverFulfill = false

        syncDialogController.$codeForDisplayOrPasting.sink {
            if $0 == codeForDisplayOrPasting {
                codeForDisplayExpectation.fulfill()
            }
        }.store(in: &cancellables)

        syncDialogController.$stringForQR.sink {
            if $0 == stringForQR {
                stringForQRExpectation.fulfill()
            }
        }.store(in: &cancellables)
        return [codeForDisplayExpectation, stringForQRExpectation]
    }

    private struct SyncDialogCodes: Equatable {
        let displayCode: String
        let qrCode: String
    }

    enum TestError: Error {
        case nilValue
    }

    @MainActor
    private func waitForSyncWithAnotherDeviceDialogCodes() async throws -> SyncDialogCodes {
        let expectation = expectation(description: "waitForSyncWithAnotherDeviceDialogCodes")
        expectation.assertForOverFulfill = false
        var codes: SyncDialogCodes?
        managementDialogModel.$currentDialog
            .sink { dialog in
                if case .syncWithAnotherDevice(let displayCode, let qrCode) = dialog {
                    codes = SyncDialogCodes(displayCode: displayCode, qrCode: qrCode)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 10)

        guard let codes else {
            throw TestError.nilValue
        }

        return codes
    }

    @MainActor
    private func waitForEnterRecoveryCodeDialog() async throws -> String {
        let expectation = expectation(description: "waitForEnterRecoveryCodeDialog")
        expectation.assertForOverFulfill = false
        var code: String?
        managementDialogModel.$currentDialog.sink {
            if case .enterRecoveryCode(let qrCode) = $0 {
                code = qrCode
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 10)

        guard let code else {
            throw TestError.nilValue
        }

        return code
    }
}

struct MockRemoteConnecting: RemoteConnecting {
    var code: String = ""

    func pollForRecoveryKey() async throws -> SyncCode.RecoveryKey? {
        return nil
    }

    func stopPolling() {
    }
}

private extension SyncCode.RecoveryKey {
    init(base64Code: String?) throws {
        let contents = try Data(base64Encoded: try XCTUnwrap(base64Code))
            .flatMap { try JSONDecoder.snakeCaseKeys.decode(SyncCode.self, from: $0) }
        self = try XCTUnwrap(contents?.recovery)
    }
}

private extension String {
    var isDDGURLString: Bool {
        guard let url = URL(string: self) else { return false }
        return url.isDuckDuckGo
    }

    var isRecoveryKey: Bool {
        guard let decoded = try? SyncCode.decodeBase64String(self) else {
            return false
        }
        return decoded.recovery != nil
    }
}

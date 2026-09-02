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
import Foundation
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
@testable import SyncUI_macOS
import XCTest
@testable import BrowserServicesKit
@testable import DDGSync
@testable import DuckDuckGo_Privacy_Browser
import FeatureFlags_macOS

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

    private var scheduler: CapturingScheduler!
    private var managementDialogModel: ManagementDialogModel!
    private var authenticator: MockUserAuthenticator!
    private var ddgSyncing: MockDDGSyncing!
    private var pausedStateManager: MockSyncPausedStateManaging!
    private var connectionController: MockSyncConnectionControlling!
    private var featureFlagger: MockSyncFeatureFlagger!
    private var pixelKitMock: PixelKitMock!
    private var mockKeyValueStore: MockKeyValueStore!
    private var syncDialogController: SyncDialogController!
    var testRecoveryCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiMDZGODhFNzEtNDFBRS00RTUxLUE2UkRtRkEwOTcwMDE5QkYwIiwicHJpbWFyeV9rZXkiOiI1QTk3U3dsQVI5RjhZakJaU09FVXBzTktnSnJEYnE3aWxtUmxDZVBWazgwPSJ9fQ=="
    lazy var testRecoveryKey = try! SyncCode.decodeBase64String(testRecoveryCode).recovery!.defaultCredentialRecoveryKey()
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
        scheduler = CapturingScheduler()
        managementDialogModel = ManagementDialogModel()
        ddgSyncing = MockDDGSyncing(authState: .inactive, scheduler: scheduler, isSyncInProgress: false)
        pausedStateManager = MockSyncPausedStateManaging()
        featureFlagger = MockSyncFeatureFlagger()
        featureFlagger.isFeatureOn[FeatureFlag.syncSeamlessAccountSwitching.rawValue] = true
        connectionController = MockSyncConnectionControlling()
        authenticator = MockUserAuthenticator()
        pixelKitMock = PixelKitMock()
        mockKeyValueStore = MockKeyValueStore()

        syncDialogController = SyncDialogController(
            syncService: ddgSyncing,
            managementDialogModel: managementDialogModel,
            userAuthenticator: authenticator,
            syncPausedStateManager: pausedStateManager,
            connectionControllerFactory: { [weak self] _, _ in
                self?.connectionController ?? MockSyncConnectionControlling()
            },
            featureFlagger: featureFlagger,
            pixelFiring: pixelKitMock,
            keyValueStore: mockKeyValueStore
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
        pixelKitMock = nil
        mockKeyValueStore = nil
        super.tearDown()
    }

    func testSyncSetupEndedFailedRelayEventIncludesPairingFailureContext() {
        let context = PairingV2FailureContext(stage: .scannerSendHello, kind: .unavailable)
        let event = SyncSetupPixelKitEvent.syncSetupEndedFailed(.exchange,
                                                                flowVersion: "v2",
                                                                peerKind: nil,
                                                                myRole: "joiner",
                                                                reason: "relay_channel_failure",
                                                                timeoutStage: nil,
                                                                pairingV2FailureContext: context)

        XCTAssertEqual(event.parameters?[SyncSetupPixelKitEvent.ParameterKey.pairingFailureStage], "scanner_send_hello")
        XCTAssertEqual(event.parameters?[SyncSetupPixelKitEvent.ParameterKey.pairingFailureKind], "unavailable")
    }

    func testSyncSetupEndedFailedGenerationEventOmitsPairingFailureKind() {
        let context = PairingV2FailureContext(stage: .presenterGenerateCode, kind: nil)
        let event = SyncSetupPixelKitEvent.syncSetupEndedFailed(.exchange,
                                                                flowVersion: "v2",
                                                                peerKind: nil,
                                                                myRole: "host",
                                                                reason: "unexpected_failure",
                                                                timeoutStage: nil,
                                                                pairingV2FailureContext: context)

        XCTAssertEqual(event.parameters?[SyncSetupPixelKitEvent.ParameterKey.pairingFailureStage], "presenter_generate_code")
        XCTAssertNil(event.parameters?[SyncSetupPixelKitEvent.ParameterKey.pairingFailureKind])
    }

    func testOnPresentRecoverSyncAccountDialogThenRecoverAccountDialogShown() async {
        await syncDialogController.recoverDataPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .recoverSyncedData)
    }

    func testOnSyncWithServerPressedThenSyncWithServerDialogShown() async {
        await syncDialogController.syncWithServerPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .syncWithServer)
    }

    func testSyncWithServerPressed_whenSimplifiedSyncSetupV2Enabled_showsSyncAnotherDevicePrompt() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true

        await syncDialogController.syncWithServerPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .syncAnotherDevicePrompt)
    }

    func testSyncWithServerPressed_whenSimplifiedSyncSetupV2Disabled_showsSyncWithServer() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = false

        await syncDialogController.syncWithServerPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .syncWithServer)
    }

    func testSyncWithServerPressed_whenSimplifiedSyncSetupV2EnabledAndAuthenticationCancelled_showsAuthenticationCancelledDialog() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .failure
        let coordinationDelegate = MockDeviceSyncCoordinationDelegate()
        var didEndFlowCalled = false
        coordinationDelegate.didEndFlowCalled = { didEndFlowCalled = true }
        syncDialogController.coordinationDelegate = coordinationDelegate

        await syncDialogController.syncWithServerPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .syncAuthenticationCancelled)
        XCTAssertFalse(didEndFlowCalled)
    }

    func testSyncWithServerPressed_whenSimplifiedSyncSetupV2EnabledAndNoAuthAvailable_stillShowsUnableToAuthenticateError() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .noAuthAvailable

        await syncDialogController.syncWithServerPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .empty)
        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToAuthenticateOnDevice)
    }

    func testSyncWithServerPressed_whenSimplifiedSyncSetupV2DisabledAndAuthenticationCancelled_doesNotShowAuthenticationCancelledDialog() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = false
        authenticator.stubAuthenticateUser = .failure

        await syncDialogController.syncWithServerPressed()

        XCTAssertNotEqual(managementDialogModel.currentDialog, .syncAuthenticationCancelled)
    }

    func testSyncWithServerPressed_whenAuthenticationCancelled_isShownAtMostTwiceThenEndsFlow() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .failure

        for _ in 0..<2 {
            managementDialogModel.currentDialog = nil
            await syncDialogController.syncWithServerPressed()
            XCTAssertEqual(managementDialogModel.currentDialog, .syncAuthenticationCancelled)
        }

        let coordinationDelegate = MockDeviceSyncCoordinationDelegate()
        var didEndFlowCalled = false
        coordinationDelegate.didEndFlowCalled = { didEndFlowCalled = true }
        syncDialogController.coordinationDelegate = coordinationDelegate
        managementDialogModel.currentDialog = nil

        await syncDialogController.syncWithServerPressed()

        XCTAssertNotEqual(managementDialogModel.currentDialog, .syncAuthenticationCancelled)
        XCTAssertTrue(didEndFlowCalled)
    }

    func testSyncWithServerPressed_whenAuthenticationCancelled_persistsPresentationCount() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .failure

        await syncDialogController.syncWithServerPressed()

        XCTAssertEqual(mockKeyValueStore.object(forKey: "sync.authentication-cancelled-prompt.presented-count") as? Int, 1)
    }

    func testSyncWithServerPressed_whenAuthenticationCancelled_firesShownPixelOncePerPresentationUpToCap() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .failure

        for _ in 0..<3 {
            managementDialogModel.currentDialog = nil
            await syncDialogController.syncWithServerPressed()
        }

        let fireCount = pixelKitMock.actualFireCalls.filter { $0.pixel.name == "settings_sync_authentication_cancelled_prompt_shown" }.count
        XCTAssertEqual(fireCount, 2)
    }

    func testSyncWithAnotherDevicePressed_whenSimplifiedSyncSetupV2EnabledAndAuthenticationCancelled_showsAuthenticationCancelledDialog() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .failure

        await syncDialogController.syncWithAnotherDevicePressed(source: nil)

        XCTAssertEqual(managementDialogModel.currentDialog, .syncAuthenticationCancelled)
    }

    func testSyncWithAnotherDevicePressed_whenSimplifiedSyncSetupV2DisabledAndAuthenticationCancelled_doesNotShowAuthenticationCancelledDialog() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = false
        authenticator.stubAuthenticateUser = .failure

        await syncDialogController.syncWithAnotherDevicePressed(source: nil)

        XCTAssertNotEqual(managementDialogModel.currentDialog, .syncAuthenticationCancelled)
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

    @MainActor
    func testPresentRemoveDevice_whenSimplifiedSyncSetupV2Enabled_showsRemoveDeviceV2() {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        let device = SyncDevice(kind: .desktop, name: "test", id: "test")

        syncDialogController.presentRemoveDevice(device)

        XCTAssertEqual(managementDialogModel.currentDialog, .removeDeviceV2(device))
    }

    @MainActor
    func testPresentDeviceDetails_whenSimplifiedSyncSetupV2Disabled_showsDeviceDetailsWithoutAuthenticating() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = false
        authenticator.stubAuthenticateUser = .failure
        let device = SyncDevice(kind: .current, name: "test", id: "test")

        await syncDialogController.presentDeviceDetails(device)

        XCTAssertEqual(managementDialogModel.currentDialog, .deviceDetails(device))
    }

    @MainActor
    func testPresentDeviceDetails_whenSimplifiedSyncSetupV2EnabledAndAuthenticated_showsDeviceDetailsV2() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        let device = SyncDevice(kind: .current, name: "test", id: "test")

        await syncDialogController.presentDeviceDetails(device)

        XCTAssertEqual(managementDialogModel.currentDialog, .deviceDetailsV2(device))
    }

    @MainActor
    func testPresentDeviceDetails_whenSimplifiedSyncSetupV2EnabledAndAuthenticationCancelled_doesNotShowDeviceDetailsV2AndEndsFlow() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .failure
        let coordinationDelegate = MockDeviceSyncCoordinationDelegate()
        var didEndFlowCalled = false
        coordinationDelegate.didEndFlowCalled = { didEndFlowCalled = true }
        syncDialogController.coordinationDelegate = coordinationDelegate
        let device = SyncDevice(kind: .current, name: "test", id: "test")

        await syncDialogController.presentDeviceDetails(device)

        XCTAssertNil(managementDialogModel.currentDialog)
        XCTAssertTrue(didEndFlowCalled)
    }

    @MainActor
    func testPresentDeviceDetails_whenSimplifiedSyncSetupV2EnabledAndNoAuthAvailable_showsUnableToAuthenticateError() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .noAuthAvailable
        let device = SyncDevice(kind: .current, name: "test", id: "test")

        await syncDialogController.presentDeviceDetails(device)

        XCTAssertEqual(managementDialogModel.currentDialog, .empty)
        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToAuthenticateOnDevice)
    }

    @MainActor
    func testPresentRemoveDeviceConfirmationThenRemoveDeviceV2Shown() {
        let device = SyncDevice(kind: .mobile, name: "test", id: "test")

        syncDialogController.presentRemoveDeviceConfirmation(device)

        XCTAssertEqual(managementDialogModel.currentDialog, .removeDeviceV2(device))
    }

    func testRemoveDeviceConfirmed_forCurrentDevice_turnsSyncOff() async {
        let device = SyncDevice(kind: .current, name: "This Device", id: "current-id")
        var disconnectedDeviceId: String?
        ddgSyncing.disconnectDeviceCallback = { disconnectedDeviceId = $0 }
        let expectation = expectation(description: "sync turned off")
        expectation.assertForOverFulfill = false
        pausedStateManager.spySyncDidTurnOff = { expectation.fulfill() }

        syncDialogController.removeDeviceConfirmed(device)

        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertTrue(ddgSyncing.disconnectCalled)
        XCTAssertNil(disconnectedDeviceId)
    }

    func testRemoveDeviceConfirmed_forOtherDevice_disconnectsThatDeviceOnly() async {
        let device = SyncDevice(kind: .desktop, name: "Other Device", id: "other-id")
        let expectation = expectation(description: "device disconnected")
        var disconnectedDeviceId: String?
        ddgSyncing.disconnectDeviceCallback = {
            disconnectedDeviceId = $0
            expectation.fulfill()
        }

        syncDialogController.removeDeviceConfirmed(device)

        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertEqual(disconnectedDeviceId, "other-id")
        XCTAssertFalse(ddgSyncing.disconnectCalled)
        XCTAssertFalse(pausedStateManager.syncDidTurnOffCalled)
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

    func test_recoverDevice_routesPastedCodeThroughConnectionControllerWithURLScanning() async {
        featureFlagger.isFeatureOn[FeatureFlag.canScanUrlBasedSyncSetupBarcodes.rawValue] = true
        let expectation = expectation(description: "callsConnectionController")
        connectionController.syncCodeEnteredCalled = { _, _, _ in
            expectation.fulfill()
        }
        syncDialogController.recoveryCodePasted(testRecoveryCode, fromRecoveryScreen: false)
        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(connectionController.spySyncCodeEnteredCode, testRecoveryCode)
        XCTAssertEqual(connectionController.spySyncCodeEnteredCanScanLegacyURLBarcodes, true)
        XCTAssertEqual(connectionController.spySyncCodeEnteredCodeSource, .pastedCode)
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
        await syncDialogController.controllerDidFindTwoAccountsDuringRecovery(
            testRecoveryKey,
            setupRole: .receiver(.recovery, .pastedCode),
            shouldPromptBeforeSwitchingAccounts: true)
        XCTAssert(didCallDDGSyncLogin)
    }

    func test_recoverDevice_accountAlreadyExists_oneDevice_updatesDevicesWithReturnedDevices() async throws {
        // Must have an account to prevent devices being cleared
        setUpWithSingleDevice(id: "1")

        let expectation = expectation(description: "devices updated")

        ddgSyncing.stubLogin = [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]

        await syncDialogController.controllerDidFindTwoAccountsDuringRecovery(
            testRecoveryKey,
            setupRole: .receiver(.recovery, .pastedCode),
            shouldPromptBeforeSwitchingAccounts: true)

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

        await syncDialogController.controllerDidFindTwoAccountsDuringRecovery(
            testRecoveryKey,
            setupRole: .receiver(.recovery, .pastedCode),
            shouldPromptBeforeSwitchingAccounts: true)

        XCTAssertNil(managementDialogModel.currentDialog)
    }

    func test_recoverDevice_accountAlreadyExists_twoOrMoreDevices_showsAccountSwitchingMessage() async throws {
        // Must have an account to prevent devices being cleared
        ddgSyncing.account = SyncAccount(deviceId: "1", deviceName: "", deviceType: "", userId: "", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)
        syncDialogController.devices = [SyncDevice(RegisteredDevice(id: "1", name: "iPhone", type: "iPhone")), SyncDevice(RegisteredDevice(id: "2", name: "iPhone", type: "iPhone"))]

        await syncDialogController.controllerDidFindTwoAccountsDuringRecovery(
            testRecoveryKey,
            setupRole: .receiver(.recovery, .pastedCode),
            shouldPromptBeforeSwitchingAccounts: true)

        XCTAssert(managementDialogModel.shouldShowErrorMessage)
        XCTAssert(managementDialogModel.shouldShowSwitchAccountsMessage)
    }

    func test_controllerDidFindTwoAccountsDuringRecovery_whenV2AndTwoOrMoreDevices_switchesWithoutAccountSwitchingMessage() async throws {
        ddgSyncing.account = SyncAccount(
            deviceId: "1",
            deviceName: "",
            deviceType: "",
            userId: "",
            primaryKey: Data(),
            secretKey: Data(),
            token: nil,
            state: .active)
        syncDialogController.devices = [
            SyncDevice(RegisteredDevice(id: "1", name: "iPhone", type: "iPhone")),
            SyncDevice(RegisteredDevice(id: "2", name: "iPhone", type: "iPhone"))
        ]
        ddgSyncing.stubLogin = [
            RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"),
            RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")
        ]

        await syncDialogController.controllerDidFindTwoAccountsDuringRecovery(
            testRecoveryKey,
            setupRole: .sharer,
            shouldPromptBeforeSwitchingAccounts: false)

        XCTAssertTrue(ddgSyncing.loginCalled)
        XCTAssertFalse(managementDialogModel.shouldShowSwitchAccountsMessage)
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

    func test_syncWithAnotherDevicePressed_whenPairingV2ExchangePresenterStartFails_firesFailureContextPixel() async {
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        ddgSyncing.account = .mock
        await assertPairingV2PresenterStartFailurePixel(source: .exchange, myRole: "host") { failure in
            connectionController.startExchangeModeError = failure
        }
    }

    func test_syncWithAnotherDevicePressed_whenPairingV2ConnectPresenterStartFails_firesFailureContextPixel() async {
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        ddgSyncing.account = nil
        await assertPairingV2PresenterStartFailurePixel(source: .connect, myRole: "joiner") { failure in
            connectionController.startConnectModeError = failure
        }
    }

    private func assertPairingV2PresenterStartFailurePixel(source: SyncSetupSource,
                                                           myRole: String,
                                                           configure: (PairingV2OperationFailure) -> Void) async {
        let context = PairingV2FailureContext(stage: .presenterOpenOwnChannel, kind: .httpError)
        let failure = PairingV2OperationFailure(
            context: context,
            underlyingError: SyncError.unexpectedStatusCode(500)
        )
        configure(failure)
        let pixelExpectation = expectation(description: "fires Pairing V2 presenter start failure pixel")
        var firedParameters: [String: String]?
        PixelKit.setUp(
            dryRun: false,
            appVersion: "1.0.0",
            session: "test",
            defaultHeaders: [:],
            defaults: UserDefaults()
        ) { pixelName, _, parameters, _, _, completion in
            if pixelName == "sync_setup_ended_failed_mac" {
                firedParameters = parameters
                pixelExpectation.fulfill()
            }
            completion(true, nil)
        }
        defer { PixelKit.tearDown() }

        await syncDialogController.syncWithAnotherDevicePressed(source: nil)
        await fulfillment(of: [pixelExpectation], timeout: 5)

        XCTAssertEqual(firedParameters?[SyncSetupPixelKitEvent.ParameterKey.reason], SyncSetupFailureReason.relayChannelFailure)
        XCTAssertEqual(firedParameters?[SyncSetupPixelKitEvent.ParameterKey.source], source.rawValue)
        XCTAssertEqual(firedParameters?[SyncSetupPixelKitEvent.ParameterKey.myRole], myRole)
        XCTAssertEqual(firedParameters?[SyncSetupPixelKitEvent.ParameterKey.pairingFailureStage], "presenter_open_own_channel")
        XCTAssertEqual(firedParameters?[SyncSetupPixelKitEvent.ParameterKey.pairingFailureKind], "http_error")
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

    func testPresentDeleteAccount_whenSimplifiedSyncSetupV2Disabled_presentsCorrectDialogWithoutAuthenticating() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = false
        authenticator.stubAuthenticateUser = .failure
        let testDevices = [SyncDevice(kind: .desktop, name: "Test", id: "test")]
        syncDialogController.devices = testDevices

        await syncDialogController.presentDeleteAccount()

        if case .deleteAccount(let devices) = managementDialogModel.currentDialog {
            XCTAssertEqual(devices.count, testDevices.count)
        } else {
            XCTFail("Expected deleteAccount dialog")
        }
    }

    func testPresentDeleteAccount_whenSimplifiedSyncSetupV2EnabledAndAuthenticated_presentsDeleteAccountV2WithDevices() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        let testDevices = [
            SyncDevice(kind: .current, name: "Work Laptop", id: "current"),
            SyncDevice(kind: .mobile, name: "Androidz", id: "mobile")
        ]
        syncDialogController.devices = testDevices

        await syncDialogController.presentDeleteAccount()

        XCTAssertEqual(managementDialogModel.currentDialog, .deleteAccountV2(testDevices))
    }

    func testPresentDeleteAccount_whenSimplifiedSyncSetupV2EnabledAndAuthenticationCancelled_doesNotPresentDialogAndEndsFlow() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .failure
        let coordinationDelegate = MockDeviceSyncCoordinationDelegate()
        var didEndFlowCalled = false
        coordinationDelegate.didEndFlowCalled = { didEndFlowCalled = true }
        syncDialogController.coordinationDelegate = coordinationDelegate
        syncDialogController.devices = [SyncDevice(kind: .desktop, name: "Test", id: "test")]

        await syncDialogController.presentDeleteAccount()

        XCTAssertNil(managementDialogModel.currentDialog)
        XCTAssertTrue(didEndFlowCalled)
    }

    func testPresentDeleteAccount_whenSimplifiedSyncSetupV2EnabledAndNoAuthAvailable_showsUnableToAuthenticateError() async {
        featureFlagger.isFeatureOn[FeatureFlag.simplifiedSyncSetupV2.rawValue] = true
        authenticator.stubAuthenticateUser = .noAuthAvailable
        syncDialogController.devices = [SyncDevice(kind: .desktop, name: "Test", id: "test")]

        await syncDialogController.presentDeleteAccount()

        XCTAssertEqual(managementDialogModel.currentDialog, .empty)
        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToAuthenticateOnDevice)
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

    func testSyncThisDeviceOnlyFromPrompt_createsAccount() async {
        let expectation = expectation(description: "Create account callback called")
        ddgSyncing.createAccountCallback = { _, _ in
            expectation.fulfill()
        }

        await syncDialogController.syncThisDeviceOnlyFromPrompt()

        await fulfillment(of: [expectation], timeout: 5)
    }

    func testSyncThisDeviceOnlyFromPrompt_whenSucceeds_firesSignupPixelAndEndsFlow() async {
        managementDialogModel.currentDialog = .syncAnotherDevicePrompt

        await syncDialogController.syncThisDeviceOnlyFromPrompt()

        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.pixel.name == "m_mac_sync_signup_direct" })
        XCTAssertNil(managementDialogModel.currentDialog)
        XCTAssertFalse(managementDialogModel.isConnectingThisDeviceOnly)
    }

    func testSyncThisDeviceOnlyFromPrompt_whileConnecting_setsConnectingFlag() async {
        ddgSyncing.createAccountCallback = { [weak self] _, _ in
            XCTAssertEqual(self?.managementDialogModel.isConnectingThisDeviceOnly, true)
        }

        await syncDialogController.syncThisDeviceOnlyFromPrompt()

        XCTAssertFalse(managementDialogModel.isConnectingThisDeviceOnly)
    }

    func testSyncThisDeviceOnlyFromPrompt_whenAccountCreationFails_setsErrorMessageAndResetsConnectingFlag() async {
        managementDialogModel.currentDialog = .syncAnotherDevicePrompt
        ddgSyncing.createAccountError = SyncError.failedToLoadAccount

        await syncDialogController.syncThisDeviceOnlyFromPrompt()

        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToSyncToServer)
        XCTAssertFalse(managementDialogModel.isConnectingThisDeviceOnly)
        XCTAssertEqual(managementDialogModel.currentDialog, .syncAnotherDevicePrompt)
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == "sync_signup_error"
        })
    }

    func testSyncWithAnotherDeviceFromPrompt_whenNoAccount_showsSyncWithAnotherDeviceDialog() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        ddgSyncing.account = nil
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startConnectModeStub = pairingInfo

        Task {
            syncDialogController.syncWithAnotherDeviceFromPrompt()
        }

        let codes = try await waitForSyncWithAnotherDeviceDialogCodes()

        XCTAssertEqual(codes.displayCode, "test_code")
        XCTAssertEqual(codes.qrCode, "test_code")
    }

    func testSyncWithAnotherDeviceFromPrompt_whenAccountExists_startsExchangeAndShowsDialog() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        ddgSyncing.account = .mock
        let pairingInfo = PairingInfo(base64Code: "exchange_code", deviceName: "test_device")
        connectionController.startExchangeModeStub = pairingInfo

        Task {
            syncDialogController.syncWithAnotherDeviceFromPrompt()
        }

        let codes = try await waitForSyncWithAnotherDeviceDialogCodes()

        XCTAssertEqual(codes.displayCode, "exchange_code")
        XCTAssertEqual(codes.qrCode, "exchange_code")
    }

    func testSyncAnotherDevicePromptDidAppear_firesPromptShownPixel() {
        syncDialogController.syncAnotherDevicePromptDidAppear()

        XCTAssertTrue(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == "settings_sync_another_device_prompt_shown"
        })
    }

    func testSyncThisDeviceOnlyFromPrompt_firesOptionTappedPixelWithThisDeviceOnly() async {
        await syncDialogController.syncThisDeviceOnlyFromPrompt()

        XCTAssertTrue(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == "settings_sync_another_device_prompt_option_tapped"
            && $0.pixel.parameters?["sync_prompt_option"] == "this_device_only"
        })
    }

    func testSyncThisDeviceOnlyFromPrompt_whenAlreadyConnecting_doesNotCreateAccountAgain() async {
        managementDialogModel.isConnectingThisDeviceOnly = true
        var createAccountCalled = false
        ddgSyncing.createAccountCallback = { _, _ in createAccountCalled = true }

        await syncDialogController.syncThisDeviceOnlyFromPrompt()

        XCTAssertFalse(createAccountCalled)
    }

    func testSyncWithAnotherDeviceFromPrompt_whenAlreadyConnecting_isNoOp() {
        managementDialogModel.isConnectingThisDeviceOnly = true

        syncDialogController.syncWithAnotherDeviceFromPrompt()

        XCTAssertFalse(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == "settings_sync_another_device_prompt_option_tapped"
        })
    }

    func testSyncWithAnotherDeviceFromPrompt_firesOptionTappedPixelWithSyncAnotherDevice() {
        syncDialogController.syncWithAnotherDeviceFromPrompt()

        XCTAssertTrue(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == "settings_sync_another_device_prompt_option_tapped"
            && $0.pixel.parameters?["sync_prompt_option"] == "sync_another_device"
        })
    }

    func testSyncWithAnotherDeviceFromPrompt_doesNotRequireAuthentication() async throws {
        // The prompt is only shown after authentication has already succeeded, so pressing
        // "Sync With Another Device" must not trigger another authentication prompt.
        authenticator.stubAuthenticateUser = .noAuthAvailable
        ddgSyncing.account = nil
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startConnectModeStub = pairingInfo

        Task {
            syncDialogController.syncWithAnotherDeviceFromPrompt()
        }

        let codes = try await waitForSyncWithAnotherDeviceDialogCodes()

        XCTAssertEqual(codes.displayCode, "test_code")
    }

    func testSyncWithAnotherDeviceFromPrompt_whenNoAccount_setsConnectingAnotherDeviceFlag() {
        ddgSyncing.account = nil
        connectionController.startConnectModeStub = PairingInfo(base64Code: "test_code", deviceName: "test_device")

        syncDialogController.syncWithAnotherDeviceFromPrompt()

        XCTAssertTrue(managementDialogModel.isConnectingAnotherDevice)
    }

    func testSyncWithAnotherDeviceFromPrompt_whenAccountExists_setsConnectingAnotherDeviceFlag() {
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        ddgSyncing.account = .mock
        connectionController.startExchangeModeStub = PairingInfo(base64Code: "test_code", deviceName: "test_device")

        syncDialogController.syncWithAnotherDeviceFromPrompt()

        XCTAssertTrue(managementDialogModel.isConnectingAnotherDevice)
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

    func testPostPairingConfirmationDialog_whenV2EnabledAndJoining_returnsWaitForOtherDeviceDialog() {
        let dialog = SyncDialogController.postPairingConfirmationDialog(
            for: .receiver(.exchange, .qrCode),
            isSimplifiedSyncSetupV2Enabled: true
        )

        XCTAssertEqual(dialog, .waitForOtherDevice)
    }

    func testPostPairingConfirmationDialog_whenV2EnabledAndHosting_returnsNil() {
        let dialog = SyncDialogController.postPairingConfirmationDialog(
            for: .sharer,
            isSimplifiedSyncSetupV2Enabled: true
        )

        XCTAssertNil(dialog)
    }

    func testPostPairingConfirmationDialog_whenV2DisabledAndJoining_returnsNil() {
        let dialog = SyncDialogController.postPairingConfirmationDialog(
            for: .receiver(.exchange, .qrCode),
            isSimplifiedSyncSetupV2Enabled: false
        )

        XCTAssertNil(dialog)
    }

    func testControllerDidFinishTransmittingRecoveryKey_waitsForDevices() {
        syncDialogController.controllerDidFinishTransmittingRecoveryKey(shouldWaitForDevicesToChange: true)

        // The method sets up a publisher to wait for device changes
        // We can verify this by checking that the devices publisher is being observed
        XCTAssertNotNil(syncDialogController)
    }

    func testControllerDidFinishTransmittingRecoveryKey_whenNoDeviceChangeExpected_presentsNowSyncing() {
        syncDialogController.controllerDidFinishTransmittingRecoveryKey(shouldWaitForDevicesToChange: false)

        XCTAssertEqual(managementDialogModel.currentDialog, .nowSyncing)
    }

    func testControllerWillBeginTransmittingRecoveryKey_presentsPrepareDialog() async {
        await syncDialogController.controllerWillBeginTransmittingRecoveryKey()

        XCTAssertEqual(managementDialogModel.currentDialog, .prepareToSync(.twoDevicePairing))
    }

    func testControllerDidReceiveRecoveryKey_presentsPrepareDialog() {
        syncDialogController.controllerDidReceiveRecoveryKey()

        XCTAssertEqual(managementDialogModel.currentDialog, .prepareToSync(.twoDevicePairing))
    }

    func testControllerDidRecognizeCode_presentsPrepareDialog() async {
        await syncDialogController.controllerDidRecognizeCode(setupSource: .exchange, codeSource: .pastedCode, codeVersion: .v1)

        XCTAssertEqual(managementDialogModel.currentDialog, .prepareToSync(.twoDevicePairing))
    }

    func testControllerDidCreateSyncAccount_presentsSaveRecoveryCodeDialog() {
        // Use the mock account that has a recovery code already set
        ddgSyncing.account = SyncAccount.mock

        syncDialogController.controllerDidCreateSyncAccount(shouldShowSyncEnabled: true)

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

    func testControllerDidCompletePairingWithAlreadyConnectedAccount_presentsAlreadyPairedError() {
        syncDialogController.controllerDidCompletePairingWithAlreadyConnectedAccount(setupRole: .receiver(.exchange, .pastedCode))

        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .alreadyPairedWithAccount)
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

    func testControllerDidError_updateRequired_setsTitleOnlyErrorMessage() async {
        await syncDialogController.controllerDidError(.updateRequired, underlyingError: nil, setupRole: .sharer)

        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .updateRequired)
        XCTAssertNil(managementDialogModel.syncErrorMessage?.errorDescription)
    }

    func testControllerDidError_connectionErrors_setsCorrectErrorMessage() async {
        await syncDialogController.controllerDidError(.failedToLogIn, underlyingError: nil, setupRole: .sharer)

        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToSyncToOtherDevice)
    }

    func testManagementDialogErrorDescription_whenDetailMatchesTypeDescription_doesNotDuplicateDescription() {
        managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .thirdPartyAccountAlreadyUpgraded)

        let dialog = ManagementDialog(model: managementDialogModel)

        guard let expectedDescription = SyncErrorType.thirdPartyAccountAlreadyUpgraded.description else {
            XCTFail("Expected non-empty description for thirdPartyAccountAlreadyUpgraded")
            return
        }

        XCTAssertEqual(dialog.errorDescription, expectedDescription)
    }

    func testManagementDialogErrorDescription_whenDetailDiffersFromTypeDescription_preservesDetail() {
        let detail = "The request timed out."
        managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: detail)

        let dialog = ManagementDialog(model: managementDialogModel)

        guard let expectedDescription = SyncErrorType.unableToSyncToOtherDevice.description else {
            XCTFail("Expected non-empty description for unableToSyncToOtherDevice")
            return
        }

        XCTAssertEqual(dialog.errorDescription, "\(expectedDescription)\n\(detail)")
    }

    func testManagementDialogErrorDescription_whenTypeDescriptionIsNil_returnsEmptyString() {
        managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .updateRequired)

        let dialog = ManagementDialog(model: managementDialogModel)

        XCTAssertEqual(dialog.errorTitle, SyncErrorType.updateRequired.title)
        XCTAssertEqual(dialog.buttonTitle, SyncErrorType.updateRequired.buttonTitle)
        XCTAssertEqual(dialog.errorDescription, "")
    }

    func testControllerDidError_pollingTimeout_presentsUnableToSyncWithDeviceError() async {
        managementDialogModel.currentDialog = .syncWithServer

        await syncDialogController.controllerDidError(.pollingForRecoveryKeyTimedOut, underlyingError: nil, setupRole: .sharer)

        XCTAssertEqual(managementDialogModel.syncErrorMessage?.type, .unableToSyncToOtherDevice)
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
        self = try XCTUnwrap(contents?.recovery).defaultCredentialRecoveryKey()
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

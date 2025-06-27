//
//  SyncPreferencesTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
    func authenticateUser(reason: DuckDuckGo_Privacy_Browser.DeviceAuthenticator.AuthenticationReason) async -> DeviceAuthenticationResult {
        .success
    }
    func authenticateUser(reason: DeviceAuthenticator.AuthenticationReason, result: @escaping (DeviceAuthenticationResult) -> Void) {
        result(.success)
    }
}

class MockSyncFeatureFlagger: FeatureFlagger {
    var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring())
    var localOverrides: FeatureFlagLocalOverriding?
    var cohort: (any FeatureFlagCohortDescribing)?

    public init() { }

    public init(internalUserDecider: InternalUserDecider) {
        self.internalUserDecider = internalUserDecider
    }

    var isFeatureOn: [String: Bool] = [:]
    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        return isFeatureOn[featureFlag.rawValue] ?? false
    }

    func getCohortIfEnabled(_ subfeature: any PrivacySubfeature) -> CohortID? {
        return nil
    }

    func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        return cohort
    }

    var allActiveExperiments: Experiments = [:]
}

final class SyncPreferencesTests: XCTestCase {

    let scheduler = CapturingScheduler()
    let managementDialogModel = ManagementDialogModel()
    var ddgSyncing: MockDDGSyncing!
    var syncBookmarksAdapter: SyncBookmarksAdapter!
    var syncCredentialsAdapter: SyncCredentialsAdapter!
    var appearancePersistor = MockAppearancePreferencesPersistor()
    var appearancePreferences: AppearancePreferences!
    var syncPreferences: SyncPreferences!
    var pausedStateManager: MockSyncPausedStateManaging!
    var connectionController: MockSyncConnectionControlling!
    var featureFlagger: MockSyncFeatureFlagger!
    var testRecoveryCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiMDZGODhFNzEtNDFBRS00RTUxLUE2UkRtRkEwOTcwMDE5QkYwIiwicHJpbWFyeV9rZXkiOiI1QTk3U3dsQVI5RjhZakJaU09FVXBzTktnSnJEYnE3aWxtUmxDZVBWazgwPSJ9fQ=="
    lazy var testRecoveryKey = try! SyncCode.decodeBase64String(testRecoveryCode).recovery!
    var cancellables: Set<AnyCancellable>!

    var bookmarksDatabase: CoreDataDatabase!
    var location: URL!

    override func setUp() {
        cancellables = []
        setUpDatabase()
        appearancePreferences = AppearancePreferences(persistor: appearancePersistor, privacyConfigurationManager: MockPrivacyConfigurationManager())
        ddgSyncing = MockDDGSyncing(authState: .inactive, scheduler: scheduler, isSyncInProgress: false)
        pausedStateManager = MockSyncPausedStateManaging()

        syncBookmarksAdapter = SyncBookmarksAdapter(database: bookmarksDatabase, bookmarkManager: MockBookmarkManager(), appearancePreferences: appearancePreferences, syncErrorHandler: SyncErrorHandler())
        syncCredentialsAdapter = SyncCredentialsAdapter(secureVaultFactory: AutofillSecureVaultFactory, syncErrorHandler: SyncErrorHandler())
        featureFlagger = MockSyncFeatureFlagger()
        featureFlagger.isFeatureOn[FeatureFlag.syncSeamlessAccountSwitching.rawValue] = true
        connectionController = MockSyncConnectionControlling()

        syncPreferences = SyncPreferences(
            syncService: ddgSyncing,
            syncBookmarksAdapter: syncBookmarksAdapter,
            syncCredentialsAdapter: syncCredentialsAdapter,
            appearancePreferences: appearancePreferences,
            managementDialogModel: managementDialogModel,
            userAuthenticator: MockUserAuthenticator(),
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
        syncPreferences = nil
        pausedStateManager = nil
        tearDownDatabase()
    }

    private func setUpDatabase() {
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: className, containerLocation: location, model: model)
        bookmarksDatabase.loadStore()
    }

    private func tearDownDatabase() {
        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testOnInitDelegateIsSet() {
        XCTAssertNotNil(managementDialogModel.delegate)
    }

    func testSyncIsEnabledReturnsCorrectValue() {
        XCTAssertFalse(syncPreferences.isSyncEnabled)

        ddgSyncing.account = SyncAccount(deviceId: "some device", deviceName: "", deviceType: "", userId: "", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)

        XCTAssertTrue(syncPreferences.isSyncEnabled)
    }

    func testCorrectRecoveryCodeIsReturned() throws {
        let account = SyncAccount(deviceId: "some device", deviceName: "", deviceType: "", userId: "", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)
        ddgSyncing.account = account

        try XCTAssertEqual(SyncCode.RecoveryKey(base64Code: syncPreferences.recoveryCode), SyncCode.RecoveryKey(base64Code: account.recoveryCode))
    }

    func testOnPresentRecoverSyncAccountDialogThenRecoverAccountDialogShown() async {
        await syncPreferences.recoverDataPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .recoverSyncedData)
    }

    func testOnSyncWithServerPressedThenSyncWithServerDialogShown() async {
        await syncPreferences.syncWithServerPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .syncWithServer)
    }

    @MainActor
    func testOnPresentTurnOffSyncConfirmDialogThenTurnOffSyncShown() {
        syncPreferences.turnOffSyncPressed()

        XCTAssertEqual(managementDialogModel.currentDialog, .turnOffSync)
    }

    @MainActor
    func testOnPresentRemoveDeviceThenRemoveDEviceShown() {
        let device = SyncDevice(kind: .desktop, name: "test", id: "test")
        syncPreferences.presentRemoveDevice(device)

        XCTAssertEqual(managementDialogModel.currentDialog, .removeDevice(device))
    }

    func testOnTurnOffSyncThenSyncServiceIsDisconnected() async throws {
        syncPreferences.turnOffSync()
        try await ddgSyncing.$disconnectCalled.async(waitFor: true)
    }

    // MARK: - SYNC ERRORS
    func test_WhenSyncPausedIsTrue_andChangePublished_isSyncPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncPaused published")
        syncPreferences.$isSyncPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            pausedStateManager.isSyncPaused = true
            pausedStateManager.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    func test_WhenSyncBookmarksPausedIsTrue_andChangePublished_isSyncBookmarksPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncBookmarksPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncBookmarksPaused published")
        syncPreferences.$isSyncBookmarksPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            pausedStateManager.isSyncBookmarksPaused = true
            pausedStateManager.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    func test_WhenSyncCredentialsPausedIsTrue_andChangePublished_isSyncCredentialsPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncCredentialsPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncCredentialsPaused published")
        syncPreferences.$isSyncCredentialsPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            pausedStateManager.isSyncCredentialsPaused = true
            pausedStateManager.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    func test_WhenSyncIsTurnedOff_ErrorHandlerSyncDidTurnOffCalled() async throws {
        syncPreferences.turnOffSync()

        try await pausedStateManager.$syncDidTurnOffCalled.async(waitFor: true)
    }

    func test_WhenAccountRemoved_ErrorHandlerSyncDidTurnOffCalled() async throws {
        syncPreferences.deleteAccount()

        try await pausedStateManager.$syncDidTurnOffCalled.async(waitFor: true)
    }

    func test_ErrorHandlerReturnsExpectedSyncBookmarksPausedMetadata() {
        XCTAssertEqual(syncPreferences.syncBookmarksPausedTitle, MockSyncPausedStateManaging.syncBookmarksPausedData.title)
        XCTAssertEqual(syncPreferences.syncBookmarksPausedMessage, MockSyncPausedStateManaging.syncBookmarksPausedData.description)
        XCTAssertEqual(syncPreferences.syncBookmarksPausedButtonTitle, MockSyncPausedStateManaging.syncBookmarksPausedData.buttonTitle)
        XCTAssertNotNil(syncPreferences.syncBookmarksPausedButtonAction)
    }

    func test_ErrorHandlerReturnsExpectedSyncCredentialsPausedMetadata() {
        XCTAssertEqual(syncPreferences.syncCredentialsPausedTitle, MockSyncPausedStateManaging.syncCredentialsPausedData.title)
        XCTAssertEqual(syncPreferences.syncCredentialsPausedMessage, MockSyncPausedStateManaging.syncCredentialsPausedData.description)
        XCTAssertEqual(syncPreferences.syncCredentialsPausedButtonTitle, MockSyncPausedStateManaging.syncCredentialsPausedData.buttonTitle)
        XCTAssertNotNil(syncPreferences.syncCredentialsPausedButtonAction)
    }

    func test_ErrorHandlerReturnsExpectedSyncIsPausedMetadata() {
        XCTAssertEqual(syncPreferences.syncPausedTitle, MockSyncPausedStateManaging.syncIsPausedData.title)
        XCTAssertEqual(syncPreferences.syncPausedMessage, MockSyncPausedStateManaging.syncIsPausedData.description)
        XCTAssertEqual(syncPreferences.syncPausedButtonTitle, MockSyncPausedStateManaging.syncIsPausedData.buttonTitle)
        XCTAssertNil(syncPreferences.syncPausedButtonAction)
    }

    func test_recoverDevice_callsConnectionController() async throws {
        syncPreferences.recoverDevice(recoveryCode: testRecoveryCode, fromRecoveryScreen: false, codeSource: .qrCode)
        try await connectionController.$syncCodeEnteredCalled.async(waitFor: true)
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
        await syncPreferences.controllerDidFindTwoAccountsDuringRecovery(testRecoveryKey, setupRole: .sharer)
        XCTAssert(didCallDDGSyncLogin)
    }

    func test_recoverDevice_accountAlreadyExists_oneDevice_updatesDevicesWithReturnedDevices() async throws {
        // Must have an account to prevent devices being cleared
        setUpWithSingleDevice(id: "1")

        ddgSyncing.spyLogin = { _, _, _ in
            return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
        }

        await syncPreferences.controllerDidFindTwoAccountsDuringRecovery(testRecoveryKey, setupRole: .sharer)

        let deviceIDsPublisher = syncPreferences.$devices.map { $0.map { $0.id } }
        try await deviceIDsPublisher.async(waitFor: ["1", "2"])
    }

    func test_recoverDevice_accountAlreadyExists_oneDevice_endsFlow() async throws {
        setUpWithSingleDevice(id: "1")
        // Removal of currentDialog indicates end of flow
        managementDialogModel.currentDialog = .enterRecoveryCode(stringForQRCode: "")

        ddgSyncing.spyLogin = { _, _, _ in
            return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
        }

        await syncPreferences.controllerDidFindTwoAccountsDuringRecovery(testRecoveryKey, setupRole: .sharer)

        try await managementDialogModel.$currentDialog.async(waitFor: nil)
    }

    func test_recoverDevice_accountAlreadyExists_twoOrMoreDevices_showsAccountSwitchingMessage() async throws {
        // Must have an account to prevent devices being cleared
        ddgSyncing.account = SyncAccount(deviceId: "1", deviceName: "", deviceType: "", userId: "", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)
        syncPreferences.devices = [SyncDevice(RegisteredDevice(id: "1", name: "iPhone", type: "iPhone")), SyncDevice(RegisteredDevice(id: "2", name: "iPhone", type: "iPhone"))]

        await syncPreferences.controllerDidFindTwoAccountsDuringRecovery(testRecoveryKey, setupRole: .sharer)

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

        syncPreferences.userConfirmedSwitchAccounts(recoveryCode: testRecoveryCode)

        await fulfillment(of: [loginCalledExpectation], timeout: 5.0)
    }

    func test_switchAccounts_updatesDevicesWithReturnedDevices() async throws {
        setUpWithSingleDevice(id: "1")

        ddgSyncing.spyLogin = { _, _, _ in
            return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
        }

        syncPreferences.userConfirmedSwitchAccounts(recoveryCode: testRecoveryCode)
        let deviceIDsPublisher = syncPreferences.$devices.map { $0.map { $0.id } }
        try await deviceIDsPublisher.async(waitFor: ["1", "2"])
    }

    private func setUpWithSingleDevice(id: String)  {
        ddgSyncing.account = SyncAccount(deviceId: id, deviceName: "iPhone", deviceType: "iPhone", userId: "", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)
        ddgSyncing.registeredDevices = [RegisteredDevice(id: id, name: "iPhone", type: "iPhone")]
        syncPreferences.devices = [SyncDevice(RegisteredDevice(id: id, name: "iPhone", type: "iPhone"))]
    }

    func test_startPollingForRecoveryKey_whenFeatureFlagOff_usesBase64Code() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startConnectModeStub = pairingInfo

        syncPreferences.startPollingForRecoveryKey(isRecovery: false)

        try await syncPreferences.$codeForDisplayOrPasting.async(waitFor: "test_code")
        try await syncPreferences.$stringForQR.async(waitFor: "test_code")
    }

    func test_startPollingForRecoveryKey_whenFeatureFlagOn_usesURL() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startConnectModeStub = pairingInfo

        syncPreferences.startPollingForRecoveryKey(isRecovery: false)

        try await syncPreferences.$codeForDisplayOrPasting.async(waitFor: "test_code")
        try await syncPreferences.$stringForQR.async(waitFor: pairingInfo.url.absoluteString)
    }

    func test_syncWithAnotherDevicePressed_accountExists_whenFeatureFlagOff_usesBase64Code() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startExchangeModeStub = pairingInfo
        ddgSyncing.account = .mock

        await syncPreferences.syncWithAnotherDevicePressed()

        try await syncPreferences.$codeForDisplayOrPasting.async(waitFor: "test_code")
        try await syncPreferences.$stringForQR.async(waitFor: "test_code")
    }

    func test_syncWithAnotherDevicePressed_accountExists_whenFeatureFlagOn_usesURL() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        let pairingInfo = PairingInfo(base64Code: "test_code", deviceName: "test_device")
        connectionController.startExchangeModeStub = pairingInfo
        ddgSyncing.account = .mock

        await syncPreferences.syncWithAnotherDevicePressed()

        try await syncPreferences.$codeForDisplayOrPasting.async(waitFor: "test_code")
        try await syncPreferences.$stringForQR.async(waitFor: pairingInfo.url.absoluteString)
    }

    func test_syncWithAnotherDevicePressed_accountExists_whenExchangeFeatureFlagOff_usesRecoveryCode() async throws {
        throw XCTSkip("Flakey test")
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = false
        let mockAccount = SyncAccount.mock
        ddgSyncing.account = mockAccount

        await syncPreferences.syncWithAnotherDevicePressed()

        let codes = try await waitForSyncWithAnotherDeviceDialog().async()

        XCTAssertTrue(codes.displayCode.isRecoveryKey)
        XCTAssertTrue(codes.qrCode.isRecoveryKey)

        let codeForDisplayOrPasting = try XCTUnwrap(syncPreferences.codeForDisplayOrPasting)
        XCTAssertTrue(codeForDisplayOrPasting.isRecoveryKey)

        let stringForQR = try XCTUnwrap(syncPreferences.stringForQR)
        XCTAssertTrue(stringForQR.isRecoveryKey)
    }

    func test_syncWithAnotherDevicePressed_accountExists_whenExchangeFeatureFlagOn_andUrlBarcodeOn_usesUrlFormat() async throws {
        throw XCTSkip("Flakey test")
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        let mockAccount = SyncAccount.mock
        ddgSyncing.account = mockAccount
        let expectedExchangeCode = "expected_exchange_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedExchangeCode, deviceName: "")
        connectionController.startExchangeModeStub = stubbedPairingInfo

        await syncPreferences.syncWithAnotherDevicePressed()

        let codes = try await waitForSyncWithAnotherDeviceDialog().async()

        XCTAssertEqual(codes.displayCode, expectedExchangeCode)
        XCTAssertTrue(codes.qrCode.isDDGURLString)

        let codeForDisplayOrPasting = try XCTUnwrap(syncPreferences.codeForDisplayOrPasting)
        XCTAssertEqual(codeForDisplayOrPasting, expectedExchangeCode)

        let stringForQR = try XCTUnwrap(syncPreferences.stringForQR)
        XCTAssertTrue(stringForQR.isDDGURLString)
    }

    func test_enterRecoveryCodePressed_whenUrlBarcodeOn_usesUrlFormat() async throws {
        throw XCTSkip("Flakey test")
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        let expectedDisplayCode = "test_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedDisplayCode, deviceName: "")
        connectionController.startConnectModeStub = stubbedPairingInfo

        await syncPreferences.enterRecoveryCodePressed()

        let code = try await waitForEnterRecoveryCodeDialog().async()

        XCTAssertTrue(code.isDDGURLString)

        let codeForDisplayOrPasting = try XCTUnwrap(syncPreferences.codeForDisplayOrPasting)
        XCTAssertEqual(codeForDisplayOrPasting, expectedDisplayCode)

        let stringForQR = try XCTUnwrap(syncPreferences.stringForQR)
        XCTAssertTrue(stringForQR.isDDGURLString)
    }

    func test_enterRecoveryCodePressed_whenUrlBarcodeOff_usesBase64Format() async throws {
        throw XCTSkip("Flakey test")
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        let expectedDisplayCode = "test_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedDisplayCode, deviceName: "")
        connectionController.startConnectModeStub = stubbedPairingInfo

        await syncPreferences.enterRecoveryCodePressed()

        let code = try await waitForEnterRecoveryCodeDialog().async()

        XCTAssertEqual(code, expectedDisplayCode)
        XCTAssertEqual(syncPreferences.codeForDisplayOrPasting, expectedDisplayCode)
        XCTAssertEqual(syncPreferences.stringForQR, expectedDisplayCode)
    }

    func test_syncWithAnotherDevicePressed_whenUrlBarcodeOn_usesUrlFormat() async throws {
        throw XCTSkip("Flakey test")
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = true
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        let expectedCode = "test_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedCode, deviceName: "")
        connectionController.startExchangeModeStub = stubbedPairingInfo
        ddgSyncing.account = .mock

        await syncPreferences.syncWithAnotherDevicePressed()

        let dialog = try await waitForSyncWithAnotherDeviceDialog().async()

        let dialogQrCode = try XCTUnwrap(dialog.qrCode)
        XCTAssertTrue(dialogQrCode.isDDGURLString)

        XCTAssertEqual(syncPreferences.codeForDisplayOrPasting, expectedCode)
        let stringForQR = try XCTUnwrap(syncPreferences.stringForQR)
        XCTAssertTrue(stringForQR.isDDGURLString)
    }

    func test_syncWithAnotherDevicePressed_whenUrlBarcodeOff_usesBase64Format() async throws {
        throw XCTSkip("Flakey test")
        featureFlagger.isFeatureOn[FeatureFlag.syncSetupBarcodeIsUrlBased.rawValue] = false
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        let expectedCode = "test_code"
        let stubbedPairingInfo = PairingInfo(base64Code: expectedCode, deviceName: "")
        connectionController.startExchangeModeStub = stubbedPairingInfo
        ddgSyncing.account = .mock

        await syncPreferences.syncWithAnotherDevicePressed()

        let dialog = try await waitForSyncWithAnotherDeviceDialog().async()

        XCTAssertEqual(dialog.qrCode, expectedCode)
        XCTAssertEqual(dialog.displayCode, expectedCode)

        XCTAssertEqual(syncPreferences.codeForDisplayOrPasting, expectedCode)
        XCTAssertEqual(syncPreferences.stringForQR, expectedCode)
    }

    func test_startPollingForRecoveryKey_whenError_showsError() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        connectionController.startConnectModeError = SyncError.failedToDecryptValue("")

        syncPreferences.startPollingForRecoveryKey(isRecovery: false)

        try await managementDialogModel.$shouldShowErrorMessage.async(waitFor: true)
        try await managementDialogModel.$syncErrorMessage.compactMap { $0 }.map(\.type).async(waitFor: .unableToSyncToOtherDevice)
    }

    func test_syncWithAnotherDevicePressed_accountExists_whenError_showsError() async throws {
        featureFlagger.isFeatureOn[FeatureFlag.exchangeKeysToSyncWithAnotherDevice.rawValue] = true
        connectionController.startExchangeModeError = SyncError.failedToDecryptValue("")
        ddgSyncing.account = .mock

        await syncPreferences.syncWithAnotherDevicePressed()

        try await managementDialogModel.$shouldShowErrorMessage.async(waitFor: true)
        try await managementDialogModel.$syncErrorMessage.compactMap { $0 }.map(\.type).async(waitFor: .unableToSyncToOtherDevice)
    }

    private struct SyncDialogCodes: Equatable {
        let displayCode: String
        let qrCode: String
    }

    private func waitForSyncWithAnotherDeviceDialog() -> AnyPublisher<SyncDialogCodes, Never> {
        managementDialogModel.$currentDialog
            .compactMap { $0 }
            .map { dialog -> SyncDialogCodes? in
                if case .syncWithAnotherDevice(let displayCode, let qrCode) = dialog {
                    return SyncDialogCodes(displayCode: displayCode, qrCode: qrCode)
                }
                return nil
            }
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    private func waitForEnterRecoveryCodeDialog() -> AnyPublisher<String, Never> {
        managementDialogModel.$currentDialog
            .compactMap { $0 }
            .map { dialog -> String? in
                if case .enterRecoveryCode(let qrCode) = dialog {
                    return qrCode
                }
                return nil
            }
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
}

class CapturingScheduler: Scheduling {
    var notifyDataChangedCalled = false

    func notifyDataChanged() {
        notifyDataChangedCalled = true
    }

    func notifyAppLifecycleEvent() {
    }

    func requestSyncImmediately() {
    }

    func cancelSyncAndSuspendSyncQueue() {
    }

    func resumeSyncQueue() {
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

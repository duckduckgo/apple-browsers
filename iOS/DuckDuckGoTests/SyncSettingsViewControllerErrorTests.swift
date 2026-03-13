//
//  SyncSettingsViewControllerErrorTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo
import Core
import Combine
@testable import DDGSync
import Persistence
import Common
import SyncUI_iOS
import SecureStorage

final class SyncSettingsViewControllerErrorTests: XCTestCase {

    var cancellables: Set<AnyCancellable>!
    var vc: SyncSettingsViewController!
    var errorHandler: CapturingSyncPausedStateManager!
    var ddgSyncing: MockDDGSyncing!
    var syncAutoRestoreHandler: MockSyncAutoRestoreHandler!
    var testRecoveryCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiMDZGODhFNzEtNDFBRS00RTUxLUE2UkRtRkEwOTcwMDE5QkYwIiwicHJpbWFyeV9rZXkiOiI1QTk3U3dsQVI5RjhZakJaU09FVXBzTktnSnJEYnE3aWxtUmxDZVBWazgwPSJ9fQ=="

    @MainActor
    override func setUpWithError() throws {
        try super.setUpWithError()
        cancellables = []
        errorHandler = CapturingSyncPausedStateManager()
        let bundle = DDGSync.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "SyncMetadata") else {
            XCTFail("Failed to load model")
            return
        }
        let database = CoreDataDatabase(name: "",
                                        containerLocation: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                        model: model,
                                        readOnly: true,
                                        options: [:])
        ddgSyncing = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        let bookmarksAdapter = SyncBookmarksAdapter(
            database: database,
            favoritesDisplayModeStorage: MockFavoritesDisplayModeStoring(),
            syncErrorHandler: CapturingAdapterErrorHandler(),
            faviconStoring: MockFaviconStore())
        let credentialsAdapter = SyncCredentialsAdapter(
            secureVaultErrorReporter: MockSecureVaultReporting(),
            syncErrorHandler: CapturingAdapterErrorHandler(),
            tld: TLD())
        let creditCardsAdapter = SyncCreditCardsAdapter(
            secureVaultErrorReporter: MockSecureVaultReporting(),
            syncErrorHandler: CapturingAdapterErrorHandler())
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.syncSeamlessAccountSwitching])
        syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        syncAutoRestoreHandler.isAutoRestoreFeatureEnabled = true
        vc = SyncSettingsViewController(
            syncService: ddgSyncing,
            syncBookmarksAdapter: bookmarksAdapter,
            syncCredentialsAdapter: credentialsAdapter,
            syncCreditCardsAdapter: creditCardsAdapter,
            syncPausedStateManager: errorHandler,
            featureFlagger: featureFlagger,
            syncAutoRestoreHandler: syncAutoRestoreHandler
        )
    }

    override func tearDown() {
        cancellables = nil
        errorHandler = nil
        vc = nil
        syncAutoRestoreHandler = nil
        super.tearDown()
    }

    @MainActor
    func test_WhenSyncPausedIsTrue_andChangePublished_isSyncPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncPaused published")
        vc.viewModel.$isSyncPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            errorHandler.isSyncPaused = true
            errorHandler.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    @MainActor
    func test_WhenSyncBookmarksPausedIsTrue_andChangePublished_isSyncBookmarksPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncBookmarksPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncBookmarksPaused published")
        vc.viewModel.$isSyncBookmarksPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            errorHandler.isSyncBookmarksPaused = true
            errorHandler.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    @MainActor
    func test_WhenSyncCredentialsPausedIsTrue_andChangePublished_isSyncCredentialsPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncCredentialsPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncCredentialsPaused published")
        vc.viewModel.$isSyncCredentialsPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            errorHandler.isSyncCredentialsPaused = true
            errorHandler.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    @MainActor
    func test_WhenSyncCreditCardsPausedIsTrue_andChangePublished_isSyncCreditCardsPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncCreditCardsPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncCreditCardsPaused published")
        vc.viewModel.$isSyncCreditCardsPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            errorHandler.isSyncCreditCardsPaused = true
            errorHandler.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    @MainActor
    func test_WhenSyncIsTurnedOff_ErrorHandlerSyncDidTurnOffCalled() async {
        let turnOff = Task { await vc.confirmAndDisableSync() }
        await Task.yield()

        vc.onConfirmSyncDisable?()
        let didTurnOff = await turnOff.value

        XCTAssertTrue(didTurnOff)
        XCTAssertTrue(errorHandler.syncDidTurnOffCalled)
    }

    @MainActor
    func test_WhenAccountRemoved_ErrorHandlerSyncDidTurnOffCalled() async {
        let deletion = Task { await vc.confirmAndDeleteAllData() }
        await Task.yield()

        vc.onConfirmAndDeleteAllData?()
        let didDelete = await deletion.value

        XCTAssertTrue(didDelete)
        XCTAssertTrue(errorHandler.syncDidTurnOffCalled)
    }

    @MainActor
    func testWhenShowRecoveryPDFAndAutoRestoreFeatureEnabledAndNoExistingDecisionThenPersistsDefaultEnabledDecision() {
        syncAutoRestoreHandler.isAutoRestoreFeatureEnabled = true
        syncAutoRestoreHandler.existingAutoRestoreDecision = nil

        vc.showRecoveryPDF()

        XCTAssertEqual(syncAutoRestoreHandler.persistedDecisions, [true])
    }

    @MainActor
    func testWhenShowRecoveryPDFAndExistingAutoRestoreDecisionThenDoesNotPersistDefaultDecision() {
        syncAutoRestoreHandler.isAutoRestoreFeatureEnabled = true
        syncAutoRestoreHandler.existingAutoRestoreDecision = false

        vc.showRecoveryPDF()

        XCTAssertTrue(syncAutoRestoreHandler.persistedDecisions.isEmpty)
    }

    @MainActor
    func testWhenViewWillAppearThenAutoRestoreDecisionIsRefreshedFromHandler() {
        syncAutoRestoreHandler.isAutoRestoreFeatureEnabled = true
        syncAutoRestoreHandler.existingAutoRestoreDecision = false
        vc.loadViewIfNeeded()

        syncAutoRestoreHandler.existingAutoRestoreDecision = true
        vc.viewWillAppear(false)

        XCTAssertEqual(vc.viewModel.isAutoRestoreEnabled, true)
    }

    @MainActor
    func testWhenAutoRestoreIsEligibleThenHasPreservedSyncAccountConflictForSetupIsTrue() {
        syncAutoRestoreHandler.isEligibleForAutoRestoreValue = true

        XCTAssertTrue(vc.isPreservedAccountPromptNeeded())
    }

    @MainActor
    func testWhenAutoRestoreIsNotEligibleThenHasPreservedSyncAccountConflictForSetupIsFalse() {
        syncAutoRestoreHandler.isEligibleForAutoRestoreValue = false

        XCTAssertFalse(vc.isPreservedAccountPromptNeeded())
    }

    @MainActor
    func testWhenContinueSyncSetupAfterPreservedAccountRemovalThenLocalRemovalIsDeferredForBackupFlow() async {
        ddgSyncing.account = SyncAccount(
            deviceId: "device-id",
            deviceName: "iPhone",
            deviceType: "iPhone",
            userId: "user-id",
            primaryKey: Data(),
            secretKey: Data(),
            token: "token",
            state: .inactive
        )

        vc.continueAfterPreservedAccountRemoval(.setup(.backup))

        await Task.yield()

        XCTAssertEqual(ddgSyncing.disconnectedDeviceIDs, [])
        XCTAssertEqual(ddgSyncing.removePreservedSyncAccountCallCount, 0)
        XCTAssertEqual(vc.viewModel.isSyncWithSetUpSheetVisible, true)
    }

    @MainActor
    func testWhenContinueAfterPreservedAccountRemovalForRecoverThenLocalRemovalIsDeferred() async {
        ddgSyncing.account = SyncAccount(
            deviceId: "device-id",
            deviceName: "iPhone",
            deviceType: "iPhone",
            userId: "user-id",
            primaryKey: Data(),
            secretKey: Data(),
            token: "token",
            state: .inactive
        )

        vc.continueAfterPreservedAccountRemoval(.recover)

        await Task.yield()

        XCTAssertEqual(ddgSyncing.disconnectedDeviceIDs, [])
        XCTAssertEqual(ddgSyncing.removePreservedSyncAccountCallCount, 0)
        XCTAssertEqual(vc.viewModel.isSyncWithSetUpSheetVisible, false)
    }

    @MainActor
    func testWhenDeferredCleanupIsPendingThenConnectionFlowTreatsAccountAsNotReadyForReuse() {
        ddgSyncing.account = SyncAccount(
            deviceId: "device-id",
            deviceName: "iPhone",
            deviceType: "iPhone",
            userId: "user-id",
            primaryKey: Data(),
            secretKey: Data(),
            token: "token",
            state: .inactive
        )

        XCTAssertTrue(vc.shouldUsePreservedAccountForConnectionFlow)

        vc.continueAfterPreservedAccountRemoval(.recover)

        XCTAssertFalse(vc.shouldUsePreservedAccountForConnectionFlow)
    }

    @MainActor
    func testWhenDeferredCleanupIsPendingThenPreServerHookRunsCleanupOnlyOnce() async {
        ddgSyncing.account = SyncAccount(
            deviceId: "device-id",
            deviceName: "iPhone",
            deviceType: "iPhone",
            userId: "user-id",
            primaryKey: Data(),
            secretKey: Data(),
            token: "token",
            state: .inactive
        )

        vc.continueAfterPreservedAccountRemoval(.setup(.backup))

        let firstAttemptAllowed = await vc.controllerWillPerformServerSyncOperation(setupRole: .receiver(.connect, .qrCode))
        let secondAttemptAllowed = await vc.controllerWillPerformServerSyncOperation(setupRole: .receiver(.connect, .qrCode))

        XCTAssertTrue(firstAttemptAllowed)
        XCTAssertTrue(secondAttemptAllowed)
        XCTAssertEqual(ddgSyncing.disconnectedDeviceIDs, ["device-id"])
        XCTAssertEqual(ddgSyncing.removePreservedSyncAccountCallCount, 1)
    }

    @MainActor
    func testWhenDeferredCleanupFailsThenPreServerHookBlocksAndRetriesOnNextAttempt() async {
        ddgSyncing.account = SyncAccount(
            deviceId: "device-id",
            deviceName: "iPhone",
            deviceType: "iPhone",
            userId: "user-id",
            primaryKey: Data(),
            secretKey: Data(),
            token: "token",
            state: .inactive
        )
        ddgSyncing.removePreservedSyncAccountError = NSError(domain: "test.local-remove", code: 1)

        vc.continueAfterPreservedAccountRemoval(.setup(.backup))

        let firstAttemptAllowed = await vc.controllerWillPerformServerSyncOperation(setupRole: .receiver(.recovery, .pastedCode))

        XCTAssertFalse(firstAttemptAllowed)
        XCTAssertEqual(ddgSyncing.disconnectedDeviceIDs, ["device-id"])
        XCTAssertEqual(ddgSyncing.removePreservedSyncAccountCallCount, 1)

        ddgSyncing.removePreservedSyncAccountError = nil

        let secondAttemptAllowed = await vc.controllerWillPerformServerSyncOperation(setupRole: .receiver(.recovery, .pastedCode))

        XCTAssertTrue(secondAttemptAllowed)
        XCTAssertEqual(ddgSyncing.disconnectedDeviceIDs, ["device-id", "device-id"])
        XCTAssertEqual(ddgSyncing.removePreservedSyncAccountCallCount, 2)
    }

    func x_test_syncCodeEntered_accountAlreadyExists_oneDevice_disconnectsThenLogsInAgain() async {
        await setUpWithSingleDevice(id: "1")

        var secondLoginCalled = false

        ddgSyncing.spyLogin = { [weak self] _, _, _ in
            guard let self else { return [] }
            ddgSyncing.spyLogin = { [weak self] _, _, _ in
                secondLoginCalled = true
                guard let self else { return [] }
                // Assert disconnect was called first
                XCTAssert(ddgSyncing.disconnectCalled)
                return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
            }
            throw SyncError.accountAlreadyExists
        }

        _ = await vc.syncCodeEntered(code: testRecoveryCode, source: .qrCode)

        XCTAssert(secondLoginCalled)
    }

    func x_test_syncCodeEntered_accountAlreadyExists_oneDevice_updatesDevicesWithReturnedDevices() async throws {
        await setUpWithSingleDevice(id: "1")

        ddgSyncing.spyLogin = { [weak self] _, _, _ in
            self?.ddgSyncing.spyLogin = { _, _, _ in
                return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
            }
            throw SyncError.accountAlreadyExists
        }

        _ = await vc.syncCodeEntered(code: testRecoveryCode, source: .qrCode)

        let deviceIDs = await vc.viewModel.devices.flatMap(\.id)
        XCTAssertEqual(deviceIDs, ["1", "2"])
    }

    func x_test_switchAccounts_disconnectsThenLogsInAgain() async throws {
        var loginCalled = false

        ddgSyncing.spyLogin = { [weak self] _, _, _ in
            guard let self else { return [] }
            // Assert disconnect before returning from login to ensure correct order
            XCTAssert(ddgSyncing.disconnectCalled)
            loginCalled = true
            return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
        }

        guard let syncCode = try? SyncCode.decodeBase64String(testRecoveryCode),
            let recoveryKey = syncCode.recovery else {
            XCTFail("Could not create RecoveryKey from code")
            return
        }

        await vc.switchAccounts(recoveryKey: recoveryKey)

        XCTAssert(loginCalled)
    }

    func x_test_switchAccounts_updatesDevicesWithReturnedDevices() async throws {
        ddgSyncing.spyLogin = { [weak self] _, _, _ in
            guard let self else { return [] }
            // Assert disconnect before returning from login to ensure correct order
            XCTAssert(ddgSyncing.disconnectCalled)
            return [RegisteredDevice(id: "1", name: "iPhone", type: "iPhone"), RegisteredDevice(id: "2", name: "Macbook Pro", type: "Macbook Pro")]
        }

        guard let syncCode = try? SyncCode.decodeBase64String(testRecoveryCode),
              let recoveryKey = syncCode.recovery else {
            XCTFail("Could not create RecoveryKey from code")
            return
        }

        await vc.switchAccounts(recoveryKey: recoveryKey)

        let deviceIDs = await vc.viewModel.devices.flatMap(\.id)
        XCTAssertEqual(deviceIDs, ["1", "2"])
    }

    @MainActor
    private func setUpWithSingleDevice(id: String) {
        ddgSyncing.account = SyncAccount(deviceId: id, deviceName: "iPhone", deviceType: "iPhone", userId: "", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)
        ddgSyncing.registeredDevices = [RegisteredDevice(id: id, name: "iPhone", type: "iPhone")]
        vc.viewModel.devices = [SyncSettingsViewModel.Device(id: id, name: "iPhone", type: "iPhone", isThisDevice: true)]
    }
}

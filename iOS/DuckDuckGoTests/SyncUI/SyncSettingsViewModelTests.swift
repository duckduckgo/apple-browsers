//
//  SyncSettingsViewModelTests.swift
//  DuckDuckGoTests
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

import Combine
import CoreGraphics
import XCTest
@testable import SyncUI_iOS

@MainActor
final class SyncSettingsViewModelTests: XCTestCase {

    func testWhenAutoRestoreFeatureEnabledAndExistingDecisionThenInitialStateMatchesProvider() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = true

        let sut = makeSut(autoRestoreProvider: autoRestoreProvider)

        XCTAssertTrue(sut.isAutoRestoreFeatureAvailable)
        XCTAssertTrue(sut.isAutoRestoreEnabled)
        XCTAssertEqual(sut.autoRestoreStatusText, UserText.autoRestoreStatusOn)
    }

    func testWhenRequestAutoRestoreUpdateAndDecisionUnchangedThenDoesNothing() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = false
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        sut.requestAutoRestoreUpdate(enabled: false)

        XCTAssertFalse(sut.isAutoRestoreUpdating)
        XCTAssertTrue(autoRestoreProvider.persistedDecisions.isEmpty)
    }

    func testWhenRequestAutoRestoreUpdateAndAuthenticationSucceedsThenPersistsAndUpdatesState() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = false
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let completionExpectation = expectation(description: "Auto-restore update completes")
        var sawUpdatingState = false
        let cancellable = sut.$isAutoRestoreUpdating
            .dropFirst()
            .sink { isUpdating in
                if isUpdating {
                    sawUpdatingState = true
                } else if sawUpdatingState {
                    completionExpectation.fulfill()
                }
            }

        sut.requestAutoRestoreUpdate(enabled: true)
        await fulfillment(of: [completionExpectation], timeout: 1.0)
        _ = cancellable

        XCTAssertEqual(autoRestoreProvider.persistedDecisions, [true])
        XCTAssertTrue(sut.isAutoRestoreEnabled)
        XCTAssertFalse(sut.isAutoRestoreUpdating)
    }

    func testWhenRequestAutoRestoreUpdateAndAuthenticationFailsThenDoesNotPersistOrUpdateState() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = false
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.authenticationError = SyncSettingsViewModel.UserAuthenticationError.authFailed
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let completionExpectation = expectation(description: "Auto-restore update ends after auth failure")
        var sawUpdatingState = false
        let cancellable = sut.$isAutoRestoreUpdating
            .dropFirst()
            .sink { isUpdating in
                if isUpdating {
                    sawUpdatingState = true
                } else if sawUpdatingState {
                    completionExpectation.fulfill()
                }
            }

        sut.requestAutoRestoreUpdate(enabled: true)
        await fulfillment(of: [completionExpectation], timeout: 1.0)
        _ = cancellable

        XCTAssertTrue(autoRestoreProvider.persistedDecisions.isEmpty)
        XCTAssertFalse(sut.isAutoRestoreEnabled)
        XCTAssertFalse(sut.isAutoRestoreUpdating)
    }

    func testWhenRequestAutoRestoreUpdateAndPersistFailsThenDoesNotUpdateState() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = false
        autoRestoreProvider.persistError = SyncSettingsViewModelTestsError.expected
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let completionExpectation = expectation(description: "Auto-restore update ends after persist failure")
        var sawUpdatingState = false
        let cancellable = sut.$isAutoRestoreUpdating
            .dropFirst()
            .sink { isUpdating in
                if isUpdating {
                    sawUpdatingState = true
                } else if sawUpdatingState {
                    completionExpectation.fulfill()
                }
            }

        sut.requestAutoRestoreUpdate(enabled: true)
        await fulfillment(of: [completionExpectation], timeout: 1.0)
        _ = cancellable

        XCTAssertTrue(autoRestoreProvider.persistedDecisions.isEmpty)
        XCTAssertFalse(sut.isAutoRestoreEnabled)
        XCTAssertFalse(sut.isAutoRestoreUpdating)
    }

    func testWhenRefreshAutoRestoreDecisionStateAndFeatureUnavailableThenStateResetsToFalse() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = false
        autoRestoreProvider.existingAutoRestoreDecision = true
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider)
        sut.isAutoRestoreEnabled = true

        sut.refreshAutoRestoreDecisionState()

        XCTAssertFalse(sut.isAutoRestoreEnabled)
    }

    func testWhenRefreshAutoRestoreDecisionStateAndDecisionChangesThenStateUpdates() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = false
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider)

        autoRestoreProvider.existingAutoRestoreDecision = true
        sut.refreshAutoRestoreDecisionState()

        XCTAssertTrue(sut.isAutoRestoreEnabled)
        XCTAssertEqual(sut.autoRestoreStatusText, UserText.autoRestoreStatusOn)
    }

    func testWhenStartAutoRestoreAndAuthenticationSucceedsThenRecoveringDataAutoRestoreIsShown() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let expectation = expectation(description: "Recovering data auto-restore flow shown")
        delegate.onShowRecoveringDataAutoRestore = {
            expectation.fulfill()
        }

        sut.startAutoRestore()

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(delegate.showRecoveringDataAutoRestoreCallCount, 1)
    }

    func testWhenStartAutoRestoreAndAuthenticationFailsThenRecoveringDataAutoRestoreIsNotShown() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.authenticationError = SyncSettingsViewModel.UserAuthenticationError.authFailed
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let finishedExpectation = expectation(description: "Authentication flow finished")
        delegate.onAuthenticateUserFinished = {
            finishedExpectation.fulfill()
        }

        sut.startAutoRestore()

        await fulfillment(of: [finishedExpectation], timeout: 1.0)
        XCTAssertEqual(delegate.showRecoveringDataAutoRestoreCallCount, 0)
        XCTAssertFalse(sut.shouldShowPasscodeRequiredAlert)
    }

    func testWhenStartAutoRestoreAndAuthenticationUnavailableThenPasscodeAlertIsShown() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.authenticationError = SyncSettingsViewModel.UserAuthenticationError.authUnavailable
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let passcodeExpectation = expectation(description: "Passcode alert shown")
        let cancellable = sut.$shouldShowPasscodeRequiredAlert
            .dropFirst()
            .sink { isShown in
                if isShown {
                    passcodeExpectation.fulfill()
                }
            }

        sut.startAutoRestore()

        await fulfillment(of: [passcodeExpectation], timeout: 1.0)
        _ = cancellable
        XCTAssertEqual(delegate.showRecoveringDataAutoRestoreCallCount, 0)
        XCTAssertTrue(sut.shouldShowPasscodeRequiredAlert)
    }

    func testWhenStartRecoveryCodeEntryAndAuthenticationSucceedsThenRecoveryCodeEntryIsShown() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let expectation = expectation(description: "Recovery code entry flow shown")
        delegate.onShowRecoveryCodeEntry = {
            expectation.fulfill()
        }

        sut.startRecoveryCodeEntry()

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(delegate.showRecoveryCodeEntryCallCount, 1)
    }

    func testWhenStartRecoveryCodeEntryAndAuthenticationFailsThenRecoveryCodeEntryIsNotShown() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.authenticationError = SyncSettingsViewModel.UserAuthenticationError.authFailed
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let finishedExpectation = expectation(description: "Authentication flow finished")
        delegate.onAuthenticateUserFinished = {
            finishedExpectation.fulfill()
        }

        sut.startRecoveryCodeEntry()

        await fulfillment(of: [finishedExpectation], timeout: 1.0)
        XCTAssertEqual(delegate.showRecoveryCodeEntryCallCount, 0)
        XCTAssertFalse(sut.shouldShowPasscodeRequiredAlert)
    }

    func testWhenStartRecoveryCodeEntryAndAuthenticationUnavailableThenPasscodeAlertIsShown() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.authenticationError = SyncSettingsViewModel.UserAuthenticationError.authUnavailable
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let passcodeExpectation = expectation(description: "Passcode alert shown")
        let cancellable = sut.$shouldShowPasscodeRequiredAlert
            .dropFirst()
            .sink { isShown in
                if isShown {
                    passcodeExpectation.fulfill()
                }
            }

        sut.startRecoveryCodeEntry()

        await fulfillment(of: [passcodeExpectation], timeout: 1.0)
        _ = cancellable
        XCTAssertEqual(delegate.showRecoveryCodeEntryCallCount, 0)
        XCTAssertTrue(sut.shouldShowPasscodeRequiredAlert)
    }

    func testWhenScanQRCodeAndPreservedAccountConflictExistsThenConflictPromptIsShownInsteadOfPairing() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.isPreservedAccountPromptNeededValue = true
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let expectation = expectation(description: "Auto-restore ready prompt shown for pairing flow")
        delegate.onShowAutoRestoreReady = {
            expectation.fulfill()
        }

        sut.beginPairingFlow()

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(delegate.showSyncWithAnotherDeviceCallCount, 0)
        XCTAssertEqual(delegate.showAutoRestoreReadyCallCount, 1)
        XCTAssertEqual(delegate.showAutoRestoreReadyContinuations, [.setup(.pairing)])
        XCTAssertTrue(delegate.continueAfterPreservedAccountRemovalContinuations.isEmpty)

        sut.startAutoRestoreSecondaryAction()
        XCTAssertEqual(delegate.continueAfterPreservedAccountRemovalContinuations, [.setup(.pairing)])
        XCTAssertEqual(delegate.showRecoveryCodeEntryCallCount, 0)
    }

    func testWhenBeginBackupFlowAndNoConflictThenSetupSheetIsVisible() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let setupSheetExpectation = expectation(description: "Sync setup sheet is shown")
        let cancellable = sut.$isSyncWithSetUpSheetVisible
            .dropFirst()
            .sink { isVisible in
                if isVisible {
                    setupSheetExpectation.fulfill()
                }
            }

        sut.beginBackupFlow()
        await fulfillment(of: [setupSheetExpectation], timeout: 1.0)
        _ = cancellable

        XCTAssertTrue(sut.isSyncWithSetUpSheetVisible)
        XCTAssertEqual(delegate.showAutoRestoreReadyCallCount, 0)
        XCTAssertTrue(delegate.continueAfterPreservedAccountRemovalContinuations.isEmpty)
    }

    func testWhenBeginBackupFlowAndPreservedAccountConflictExistsThenConflictPromptIsShown() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.isPreservedAccountPromptNeededValue = true
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let promptShownExpectation = expectation(description: "Auto-restore ready prompt shown for backup flow")
        delegate.onShowAutoRestoreReady = {
            promptShownExpectation.fulfill()
        }

        sut.beginBackupFlow()
        await fulfillment(of: [promptShownExpectation], timeout: 1.0)

        XCTAssertFalse(sut.isSyncWithSetUpSheetVisible)
        XCTAssertEqual(delegate.showAutoRestoreReadyCallCount, 1)
        XCTAssertEqual(delegate.showAutoRestoreReadyContinuations, [.setup(.backup)])
        XCTAssertTrue(delegate.continueAfterPreservedAccountRemovalContinuations.isEmpty)

        sut.startAutoRestoreSecondaryAction()
        XCTAssertEqual(delegate.continueAfterPreservedAccountRemovalContinuations, [.setup(.backup)])
        XCTAssertEqual(delegate.showRecoveryCodeEntryCallCount, 0)
    }

    func testWhenBeginRecoverFlowAndPreservedAccountPromptNeededThenSecondaryActionContinuesRecoverFlow() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.isPreservedAccountPromptNeededValue = true
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let promptShownExpectation = expectation(description: "Auto-restore ready prompt shown for recover flow")
        delegate.onShowAutoRestoreReady = {
            promptShownExpectation.fulfill()
        }

        sut.beginRecoverFlow()

        await fulfillment(of: [promptShownExpectation], timeout: 1.0)
        XCTAssertEqual(delegate.showAutoRestoreReadyContinuations, [.recover])
        XCTAssertTrue(delegate.continueAfterPreservedAccountRemovalContinuations.isEmpty)

        sut.startAutoRestoreSecondaryAction()

        XCTAssertEqual(delegate.continueAfterPreservedAccountRemovalContinuations, [.recover])
        XCTAssertEqual(delegate.showRecoveryCodeEntryCallCount, 0)
    }

    func testWhenBeginRecoverFlowAndNoPreservedAccountPromptNeededThenRecoverSheetIsShown() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        let recoverSheetExpectation = expectation(description: "Recover synced data sheet is shown")
        let cancellable = sut.$isRecoverSyncedDataSheetVisible
            .dropFirst()
            .sink { isVisible in
                if isVisible {
                    recoverSheetExpectation.fulfill()
                }
            }

        sut.beginRecoverFlow()

        await fulfillment(of: [recoverSheetExpectation], timeout: 1.0)
        _ = cancellable
        XCTAssertEqual(delegate.showAutoRestoreReadyCallCount, 0)
    }

    func testWhenContinueRecoverFlowThenRecoveryCodeEntryIsShownWithoutAuthentication() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        sut.continueRecoverFlow()

        XCTAssertEqual(delegate.showRecoveryCodeEntryCallCount, 1)
        XCTAssertEqual(delegate.authenticateUserCallCount, 0)
    }

    func testWhenBeginPairingFlowAndConnectingDevicesUnavailableThenNoAuthenticationOrRoutingOccurs() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)
        sut.isConnectingDevicesAvailable = false

        sut.beginPairingFlow()
        await Task.yield()

        XCTAssertEqual(delegate.authenticateUserCallCount, 0)
        XCTAssertEqual(delegate.showSyncWithAnotherDeviceCallCount, 0)
        XCTAssertEqual(delegate.showAutoRestoreReadyCallCount, 0)
    }

    func testWhenBeginPairingFlowAndLoggedOutAccountCreationUnavailableThenNoAuthenticationOrRoutingOccurs() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)
        sut.isSyncEnabled = false
        sut.isAccountCreationAvailable = false

        sut.beginPairingFlow()
        await Task.yield()

        XCTAssertEqual(delegate.authenticateUserCallCount, 0)
        XCTAssertEqual(delegate.showSyncWithAnotherDeviceCallCount, 0)
        XCTAssertEqual(delegate.showAutoRestoreReadyCallCount, 0)
    }

    private func makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler,
                         delegate: MockSyncSettingsViewModelDelegate? = nil) -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: autoRestoreProvider
        )
        model.delegate = delegate
        return model
    }
}

private final class MockSyncSettingsViewModelDelegate: SyncManagementViewModelDelegate {

    var authenticateUserCallCount = 0
    var authenticationError: Error?
    var isPreservedAccountPromptNeededValue = false
    var continueAfterPreservedAccountRemovalContinuations: [SyncSettingsViewModel.PreservedAccountContinuation] = []
    var showAutoRestoreReadyContinuations: [SyncSettingsViewModel.PreservedAccountContinuation] = []
    var showAutoRestoreReadyCallCount = 0
    var showRecoveringDataAutoRestoreCallCount = 0
    var showRecoveryCodeEntryCallCount = 0
    var showSyncWithAnotherDeviceCallCount = 0
    var onShowAutoRestoreReady: (() -> Void)?
    var onShowRecoveringDataAutoRestore: (() -> Void)?
    var onShowRecoveryCodeEntry: (() -> Void)?
    var onAuthenticateUserFinished: (() -> Void)?

    var syncBookmarksPausedTitle: String?
    var syncCredentialsPausedTitle: String?
    var syncCreditCardsPausedTitle: String?
    var syncPausedTitle: String?
    var syncBookmarksPausedDescription: String?
    var syncCredentialsPausedDescription: String?
    var syncCreditCardsPausedDescription: String?
    var syncPausedDescription: String?
    var syncBookmarksPausedButtonTitle: String?
    var syncCredentialsPausedButtonTitle: String?
    var syncCreditCardsPausedButtonTitle: String?

    func authenticateUser() async throws {
        authenticateUserCallCount += 1
        defer { onAuthenticateUserFinished?() }
        if let authenticationError {
            throw authenticationError
        }
    }

    func showAutoRestoreReady(for continuation: SyncSettingsViewModel.PreservedAccountContinuation) {
        showAutoRestoreReadyCallCount += 1
        showAutoRestoreReadyContinuations.append(continuation)
        onShowAutoRestoreReady?()
    }
    func isPreservedAccountPromptNeeded() -> Bool {
        isPreservedAccountPromptNeededValue
    }
    func continueAfterPreservedAccountRemoval(_ continuation: SyncSettingsViewModel.PreservedAccountContinuation) {
        continueAfterPreservedAccountRemovalContinuations.append(continuation)
    }
    func showRecoveringDataAutoRestore() {
        showRecoveringDataAutoRestoreCallCount += 1
        onShowRecoveringDataAutoRestore?()
    }
    func showRecoveryCodeEntry() {
        showRecoveryCodeEntryCallCount += 1
        onShowRecoveryCodeEntry?()
    }
    func showSyncWithAnotherDevice() {
        showSyncWithAnotherDeviceCallCount += 1
    }
    func showRecoveryPDF() {}
    func shareRecoveryPDF() {}
    func createAccountAndStartSyncing(optionsViewModel: SyncSettingsViewModel) {}
    func confirmAndDisableSync() async -> Bool { true }
    func confirmAndDeleteAllData() async -> Bool { true }
    func confirmRemoveDevice(_ device: SyncSettingsViewModel.Device) async -> Bool { true }
    func removeDevice(_ device: SyncSettingsViewModel.Device) {}
    func updateDeviceName(_ name: String) {}
    func refreshDevices(clearDevices: Bool) {}
    func updateOptions() {}
    func launchBookmarksViewController() {}
    func launchAutofillViewController() {}
    func launchAutofillCreditCardsViewController() {}
    func showOtherPlatformLinks() {}
    func fireOtherPlatformLinksPixel(event: SyncSettingsViewModel.PlatformLinksPixelEvent, with source: SyncSettingsViewModel.PlatformLinksPixelSource) {}
    func shareLink(for url: URL, with message: String, from rect: CGRect) {}
}

private enum SyncSettingsViewModelTestsError: Error {
    case expected
}

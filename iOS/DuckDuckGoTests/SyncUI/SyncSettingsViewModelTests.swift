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

    func testWhenContinueRecoverFlowThenRecoveryCodeEntryIsShownWithoutAuthentication() async {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: autoRestoreProvider, delegate: delegate)

        await sut.continueRecoverFlow()

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

    func testWhenEnablingSyncWithNoPreservedAccountThenPromptIsShownWithoutCreatingAccount() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)

        let promptShownExpectation = expectation(description: "Sync another device prompt is shown")
        let cancellable = sut.$connectingSheetPhase
            .dropFirst()
            .sink { phase in
                if phase == .syncAnotherDevice(isConnecting: false) {
                    promptShownExpectation.fulfill()
                }
            }

        sut.enableSyncToggleTapped()

        await fulfillment(of: [promptShownExpectation], timeout: 1.0)
        _ = cancellable
        XCTAssertEqual(delegate.authenticateUserCallCount, 1)
        XCTAssertEqual(delegate.simplifiedCreateAccountAndStartSyncingCallCount, 0)
        XCTAssertFalse(sut.isBusy)
    }

    func testWhenEnablingSyncWithPreservedAccountNeededThenAutoRestorePromptIsShown() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.isPreservedAccountPromptNeededValue = true
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)

        let expectation = expectation(description: "Auto-restore ready prompt shown for toggle flow")
        delegate.onShowAutoRestoreReady = {
            expectation.fulfill()
        }

        sut.enableSyncToggleTapped()

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertNil(sut.connectingSheetPhase)
        XCTAssertEqual(delegate.showAutoRestoreReadyContinuations, [.setup(.simplifiedToggle)])
        XCTAssertEqual(delegate.simplifiedCreateAccountAndStartSyncingCallCount, 0)
    }

    func testWhenSyncThisDeviceOnlyFromConnectingSheetThenAccountCreationIsStarted() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: false)

        await sut.syncThisDeviceOnlyFromConnectingSheet()

        XCTAssertEqual(delegate.simplifiedCreateAccountAndStartSyncingCallCount, 1)
        XCTAssertTrue(sut.isBusy)
        XCTAssertTrue(sut.isConnectingThisDeviceOnly)
        XCTAssertEqual(sut.connectingSheetPhase, .syncAnotherDevice(isConnecting: true))
    }

    func testWhenSyncAnotherDeviceFromConnectingSheetThenPairingStartsAfterDismissWithoutReauthentication() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: false)

        await sut.syncAnotherDeviceFromConnectingSheet()

        XCTAssertNil(sut.connectingSheetPhase)
        XCTAssertEqual(delegate.showSyncWithAnotherDeviceCallCount, 0)
        XCTAssertEqual(delegate.authenticateUserCallCount, 0)

        sut.connectingSheetDidDismiss()

        XCTAssertEqual(delegate.showSyncWithAnotherDeviceCallCount, 1)
        XCTAssertEqual(delegate.authenticateUserCallCount, 0)
    }

    func testWhenShowSuccessDuringConnectingThenFinishAnimationIsArmedInsteadOfNavigating() {
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler())
        sut.connectingSheetPhase = .connecting(isRecovery: false)

        sut.showSuccess(recoveryCode: "code", destination: .joiner(isRecovery: false))

        XCTAssertEqual(sut.connectingSheetPhase, .connecting(isRecovery: false, successDestination: .joiner(isRecovery: false)))
        XCTAssertEqual(sut.recoveryCode, "code")
    }

    func testWhenShowSuccessDuringConnectingRecoveryThenFinishAnimationIsArmedWithRecoveryFlag() {
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler())
        sut.connectingSheetPhase = .connecting(isRecovery: true)

        sut.showSuccess(recoveryCode: "code", destination: .joiner(isRecovery: true))

        XCTAssertEqual(sut.connectingSheetPhase, .connecting(isRecovery: true, successDestination: .joiner(isRecovery: true)))
    }

    func testWhenShowSuccessOutsideConnectingThenNavigatesToSuccessImmediately() {
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler())
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: true)

        sut.showSuccess(recoveryCode: "code", destination: .joiner(isRecovery: false))

        XCTAssertEqual(sut.connectingSheetPhase, .success(.joiner(isRecovery: false)))
        XCTAssertEqual(sut.recoveryCode, "code")
    }

    func testWhenShowSuccessWithNoPhaseThenNavigatesToSuccessImmediately() {
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler())
        sut.connectingSheetPhase = nil

        sut.showSuccess(recoveryCode: "code", destination: .joiner(isRecovery: true))

        XCTAssertEqual(sut.connectingSheetPhase, .success(.joiner(isRecovery: true)))
    }

    func testWhenConnectingAnimationFinishesWhileFinishingThenNavigatesToSuccess() {
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler())
        sut.connectingSheetPhase = .connecting(isRecovery: true, successDestination: .joiner(isRecovery: true))

        sut.connectingAnimationDidFinish()

        XCTAssertEqual(sut.connectingSheetPhase, .success(.joiner(isRecovery: true)))
    }

    func testWhenConnectingAnimationFinishesWhileNotFinishingThenPhaseIsUnchanged() {
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler())
        sut.connectingSheetPhase = .connecting(isRecovery: false)

        sut.connectingAnimationDidFinish()

        XCTAssertEqual(sut.connectingSheetPhase, .connecting(isRecovery: false))
    }

    func testWhenConnectingAnimationFinishesOutsideConnectingThenPhaseIsUnchanged() {
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler())
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: true)

        sut.connectingAnimationDidFinish()

        XCTAssertEqual(sut.connectingSheetPhase, .syncAnotherDevice(isConnecting: true))
    }

    func testWhenConnectingCompletesThenAnimationRunsBeforeNavigatingToSuccess() {
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler())
        sut.connectingSheetPhase = .connecting(isRecovery: false)

        sut.showSuccess(recoveryCode: "code", destination: .joiner(isRecovery: false))
        XCTAssertEqual(sut.connectingSheetPhase, .connecting(isRecovery: false, successDestination: .joiner(isRecovery: false)))

        sut.connectingAnimationDidFinish()
        XCTAssertEqual(sut.connectingSheetPhase, .success(.joiner(isRecovery: false)))
    }

    func testWhenAnotherDevicePromptAppearedThenFiresPromptShownPixel() {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)

        sut.anotherDevicePromptAppeared()

        XCTAssertEqual(delegate.firedSyncSetupPixelEvents, [.anotherDevicePromptShown])
    }

    func testWhenSyncAnotherDeviceFromConnectingSheetThenFiresOptionTappedPixelForSyncAnotherDevice() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)

        await sut.syncAnotherDeviceFromConnectingSheet()

        XCTAssertEqual(delegate.firedSyncSetupPixelEvents, [.anotherDevicePromptOptionTapped(.syncAnotherDevice)])
    }

    func testWhenSyncThisDeviceOnlyFromConnectingSheetThenFiresOptionTappedPixelForThisDeviceOnly() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)

        await sut.syncThisDeviceOnlyFromConnectingSheet()

        XCTAssertEqual(delegate.firedSyncSetupPixelEvents, [.anotherDevicePromptOptionTapped(.thisDeviceOnly)])
    }

    func testWhenAnotherDevicePromptIsDismissedWithoutSelectionThenFiresPromptDismissedPixel() {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: false)
        sut.anotherDevicePromptAppeared()

        sut.dismissAnotherDevicePrompt()
        sut.connectingSheetDidDismiss()

        XCTAssertEqual(delegate.firedSyncSetupPixelEvents, [.anotherDevicePromptShown, .anotherDevicePromptDismissed])
    }

    func testWhenSyncAnotherDeviceOptionIsSelectedThenDoesNotFirePromptDismissedPixel() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: false)
        sut.anotherDevicePromptAppeared()

        await sut.syncAnotherDeviceFromConnectingSheet()
        sut.connectingSheetDidDismiss()

        XCTAssertEqual(delegate.firedSyncSetupPixelEvents, [
            .anotherDevicePromptShown,
            .anotherDevicePromptOptionTapped(.syncAnotherDevice)
        ])
    }

    func testWhenThisDeviceOnlyOptionIsSelectedThenDoesNotFirePromptDismissedPixel() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: false)
        sut.anotherDevicePromptAppeared()

        await sut.syncThisDeviceOnlyFromConnectingSheet()
        sut.dismissConnectingSheet()
        sut.connectingSheetDidDismiss()

        XCTAssertEqual(delegate.firedSyncSetupPixelEvents, [
            .anotherDevicePromptShown,
            .anotherDevicePromptOptionTapped(.thisDeviceOnly)
        ])
    }

    func testWhenImprovedPairingFlowOnAndEnablingSyncThenPromptIsShownWithoutAuthentication() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)

        await enableSyncAndWaitForAnotherDevicePrompt(sut)

        XCTAssertEqual(delegate.authenticateUserCallCount, 0)
        XCTAssertFalse(sut.isBusy)
    }

    func testWhenImprovedPairingFlowOnAndThisDeviceOnlyChosenThenAuthenticatesBeforeCreatingAccount() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)

        await sut.syncThisDeviceOnlyFromConnectingSheet()

        XCTAssertEqual(delegate.authenticateUserCallCount, 1)
        XCTAssertEqual(delegate.simplifiedCreateAccountAndStartSyncingCallCount, 1)
        XCTAssertEqual(sut.connectingSheetPhase, .syncAnotherDevice(isConnecting: true))
    }

    func testWhenImprovedPairingFlowOnAndThisDeviceOnlyAuthenticationFailsThenAccountIsNotCreated() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)
        delegate.authenticationError = SyncSettingsViewModel.UserAuthenticationError.authFailed

        await sut.syncThisDeviceOnlyFromConnectingSheet()

        XCTAssertEqual(delegate.authenticateUserCallCount, 1)
        XCTAssertEqual(delegate.simplifiedCreateAccountAndStartSyncingCallCount, 0)
        XCTAssertEqual(sut.connectingSheetPhase, .syncAnotherDevice(isConnecting: false))
        XCTAssertFalse(sut.isBusy)
    }

    func testWhenImprovedPairingFlowOnAndChoiceAuthenticationUnavailableThenPasscodeAlertIsShown() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)
        delegate.authenticationError = SyncSettingsViewModel.UserAuthenticationError.authUnavailable

        await sut.syncThisDeviceOnlyFromConnectingSheet()

        XCTAssertTrue(sut.shouldShowPasscodeRequiredAlert)
        XCTAssertEqual(delegate.simplifiedCreateAccountAndStartSyncingCallCount, 0)
    }

    func testWhenImprovedPairingFlowOnAndThisDeviceOnlyRetriedAfterFailureThenDoesNotReauthenticate() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)
        await sut.syncThisDeviceOnlyFromConnectingSheet()
        sut.isBusy = false
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: false)

        await sut.syncThisDeviceOnlyFromConnectingSheet()

        XCTAssertEqual(delegate.authenticateUserCallCount, 1)
        XCTAssertEqual(delegate.simplifiedCreateAccountAndStartSyncingCallCount, 2)
    }

    func testWhenImprovedPairingFlowOnAndSyncAnotherDeviceChosenThenAuthenticatesBeforePairing() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)

        await sut.syncAnotherDeviceFromConnectingSheet()
        sut.connectingSheetDidDismiss()

        XCTAssertEqual(delegate.authenticateUserCallCount, 1)
        XCTAssertEqual(delegate.showSyncWithAnotherDeviceCallCount, 1)
    }

    func testWhenImprovedPairingFlowOnAndSyncAnotherDeviceAuthenticationFailsThenPromptStaysAndPairingDoesNotStart() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)
        delegate.authenticationError = SyncSettingsViewModel.UserAuthenticationError.authFailed

        await sut.syncAnotherDeviceFromConnectingSheet()
        sut.connectingSheetDidDismiss()

        XCTAssertEqual(sut.connectingSheetPhase, .syncAnotherDevice(isConnecting: false))
        XCTAssertEqual(delegate.showSyncWithAnotherDeviceCallCount, 0)
        XCTAssertFalse(sut.isBusy)
    }

    func testWhenImprovedPairingFlowOnAndThisDeviceOnlyAuthenticationPendingThenPromptInteractionIsDisabled() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)
        var isInteractionDisabledDuringAuthentication = false
        delegate.onAuthenticateUserFinished = { [unowned sut] in
            isInteractionDisabledDuringAuthentication = sut.isAnotherDevicePromptInteractionDisabled
        }

        await sut.syncThisDeviceOnlyFromConnectingSheet()

        XCTAssertTrue(isInteractionDisabledDuringAuthentication)
    }

    func testWhenImprovedPairingFlowOnAndSyncAnotherDeviceAuthenticationPendingThenPromptInteractionIsDisabled() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)
        var isInteractionDisabledDuringAuthentication = false
        delegate.onAuthenticateUserFinished = { [unowned sut] in
            isInteractionDisabledDuringAuthentication = sut.isAnotherDevicePromptInteractionDisabled
        }

        await sut.syncAnotherDeviceFromConnectingSheet()

        XCTAssertTrue(isInteractionDisabledDuringAuthentication)
        XCTAssertFalse(sut.isBusy)
    }

    func testWhenBusyThenSyncAnotherDeviceFromConnectingSheetIsIgnored() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)
        sut.isBusy = true

        await sut.syncAnotherDeviceFromConnectingSheet()
        sut.connectingSheetDidDismiss()

        XCTAssertEqual(delegate.authenticateUserCallCount, 0)
        XCTAssertEqual(delegate.showSyncWithAnotherDeviceCallCount, 0)
        XCTAssertEqual(sut.connectingSheetPhase, .syncAnotherDevice(isConnecting: false))
    }

    func testWhenBusyThenAnotherDevicePromptDismissIsIgnored() {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: false)
        sut.isBusy = true

        sut.dismissAnotherDevicePrompt()

        XCTAssertEqual(sut.connectingSheetPhase, .syncAnotherDevice(isConnecting: false))
        XCTAssertEqual(delegate.firedSyncSetupPixelEvents, [])
    }

    func testWhenImprovedPairingFlowOnAndPreservedAccountPromptNeededThenAuthenticatesUpFrontAndNotAgainOnChoice() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        delegate.isPreservedAccountPromptNeededValue = true
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        let promptShownExpectation = expectation(description: "Auto-restore ready prompt shown")
        delegate.onShowAutoRestoreReady = {
            promptShownExpectation.fulfill()
        }

        sut.enableSyncToggleTapped()
        await fulfillment(of: [promptShownExpectation], timeout: 1.0)
        XCTAssertEqual(delegate.authenticateUserCallCount, 1)

        sut.startAutoRestoreSecondaryAction()
        sut.isBusy = false
        sut.connectingSheetPhase = .syncAnotherDevice(isConnecting: false)
        await sut.syncThisDeviceOnlyFromConnectingSheet()

        XCTAssertEqual(delegate.authenticateUserCallCount, 1)
        XCTAssertEqual(delegate.simplifiedCreateAccountAndStartSyncingCallCount, 1)
    }

    func testWhenImprovedPairingFlowOnAndBeginRecoverFlowThenRecoverSheetIsShownWithoutAuthentication() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)

        await beginRecoverFlowAndWaitForSheet(sut)

        XCTAssertEqual(delegate.authenticateUserCallCount, 0)
    }

    func testWhenImprovedPairingFlowOnAndRecoverCTATappedThenAuthenticatesBeforeRecoveryCodeEntry() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await beginRecoverFlowAndWaitForSheet(sut)

        await sut.continueRecoverFlow()

        XCTAssertEqual(delegate.authenticateUserCallCount, 1)
        XCTAssertEqual(delegate.showRecoveryCodeEntryCallCount, 1)
    }

    func testWhenImprovedPairingFlowOnAndRecoverCTAAuthenticationFailsThenRecoveryCodeEntryIsNotShown() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        await beginRecoverFlowAndWaitForSheet(sut)
        delegate.authenticationError = SyncSettingsViewModel.UserAuthenticationError.authFailed

        await sut.continueRecoverFlow()

        XCTAssertEqual(delegate.showRecoveryCodeEntryCallCount, 0)
    }

    func testWhenImprovedPairingFlowOnAndBeginPairingFlowThenAuthenticatesUpFront() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        let pairingShownExpectation = expectation(description: "Sync with another device is shown")
        delegate.onShowSyncWithAnotherDevice = {
            pairingShownExpectation.fulfill()
        }

        sut.beginPairingFlow()
        await fulfillment(of: [pairingShownExpectation], timeout: 1.0)

        XCTAssertEqual(delegate.authenticateUserCallCount, 1)
        XCTAssertEqual(delegate.showSyncWithAnotherDeviceCallCount, 1)
    }

    func testWhenImprovedPairingFlowOffAndChoiceMadeThenDoesNotReauthenticate() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: false)
        await enableSyncAndWaitForAnotherDevicePrompt(sut)
        XCTAssertEqual(delegate.authenticateUserCallCount, 1)

        await sut.syncThisDeviceOnlyFromConnectingSheet()

        XCTAssertEqual(delegate.authenticateUserCallCount, 1)
        XCTAssertEqual(delegate.simplifiedCreateAccountAndStartSyncingCallCount, 1)
    }

    func testWhenDeviceDetailsShownForThisDeviceThenFiresThisDeviceScreenShownPixel() {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)

        sut.deviceDetailsShown(for: .init(id: "1", name: "iPhone", type: "phone", isThisDevice: true))

        XCTAssertEqual(delegate.firedDeviceDetailsPixelEvents, [.thisDeviceScreenShown])
    }

    func testWhenDeviceDetailsShownForOtherDeviceThenFiresOtherDeviceScreenShownPixel() {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)

        sut.deviceDetailsShown(for: .init(id: "2", name: "Mac", type: "desktop", isThisDevice: false))

        XCTAssertEqual(delegate.firedDeviceDetailsPixelEvents, [.otherDeviceScreenShown])
    }

    func testWhenThisDeviceDetailsTurnOffSyncTappedThenFiresTurnOffPixelAndShowsConfirmation() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)
        let confirmationShown = expectation(description: "Turn off confirmation shown")
        delegate.onSimplifiedConfirmAndDisableSync = { confirmationShown.fulfill() }

        sut.thisDeviceDetailsTurnOffSyncTapped()

        await fulfillment(of: [confirmationShown], timeout: 5)
        XCTAssertEqual(delegate.firedDeviceDetailsPixelEvents, [.thisDeviceTurnOffSyncTapped])
    }

    func testWhenThisDeviceDetailsTurnOffSyncTappedWhileBusyThenDoesNotFireTurnOffPixel() {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)
        sut.isBusy = true

        sut.thisDeviceDetailsTurnOffSyncTapped()

        XCTAssertTrue(delegate.firedDeviceDetailsPixelEvents.isEmpty)
    }

    func testWhenImprovedPairingFlowOnAndThisDeviceDetailsTurnOffSyncTappedThenShowsDeviceConfirmationInsteadOfTurnOffAlert() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        var isTurnOffAlertShown = false
        delegate.onSimplifiedConfirmAndDisableSync = { isTurnOffAlertShown = true }

        sut.thisDeviceDetailsTurnOffSyncTapped()
        await Task.yield()

        XCTAssertTrue(sut.isThisDeviceTurnOffConfirmationVisible)
        XCTAssertFalse(isTurnOffAlertShown)
        XCTAssertEqual(delegate.firedDeviceDetailsPixelEvents, [.thisDeviceTurnOffSyncTapped])
    }

    func testWhenImprovedPairingFlowOffAndThisDeviceDetailsTurnOffSyncTappedThenDeviceConfirmationIsNotShown() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: false)
        let turnOffAlertShown = expectation(description: "Turn off alert shown")
        delegate.onSimplifiedConfirmAndDisableSync = { turnOffAlertShown.fulfill() }

        sut.thisDeviceDetailsTurnOffSyncTapped()

        await fulfillment(of: [turnOffAlertShown], timeout: 5)
        XCTAssertFalse(sut.isThisDeviceTurnOffConfirmationVisible)
    }

    func testWhenThisDeviceDetailsTurnOffSyncConfirmedThenDisablesSyncWithoutFurtherConfirmation() async {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate, isImprovedPairingFlowEnabled: true)
        sut.isSyncEnabled = true
        var isTurnOffAlertShown = false
        delegate.onSimplifiedConfirmAndDisableSync = { isTurnOffAlertShown = true }
        let syncDisabled = expectation(description: "Sync disabled")
        let cancellable = sut.$isSyncEnabled
            .dropFirst()
            .sink { isEnabled in
                if !isEnabled {
                    syncDisabled.fulfill()
                }
            }

        sut.thisDeviceDetailsTurnOffSyncConfirmed()

        await fulfillment(of: [syncDisabled], timeout: 5)
        XCTAssertFalse(isTurnOffAlertShown)
        cancellable.cancel()
    }

    func testWhenOtherDeviceDetailsRemoveDeviceTappedThenFiresRemoveDevicePixel() {
        let delegate = MockSyncSettingsViewModelDelegate()
        let sut = makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler(), delegate: delegate)

        sut.otherDeviceDetailsRemoveDeviceTapped()

        XCTAssertEqual(delegate.firedDeviceDetailsPixelEvents, [.otherDeviceRemoveDeviceTapped])
    }

    private func enableSyncAndWaitForAnotherDevicePrompt(_ sut: SyncSettingsViewModel) async {
        let promptShownExpectation = expectation(description: "Sync another device prompt is shown")
        let cancellable = sut.$connectingSheetPhase
            .dropFirst()
            .sink { phase in
                if phase == .syncAnotherDevice(isConnecting: false) {
                    promptShownExpectation.fulfill()
                }
            }

        sut.enableSyncToggleTapped()

        await fulfillment(of: [promptShownExpectation], timeout: 1.0)
        cancellable.cancel()
    }

    private func beginRecoverFlowAndWaitForSheet(_ sut: SyncSettingsViewModel) async {
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
        cancellable.cancel()
    }

    private func makeSut(autoRestoreProvider: MockSyncAutoRestoreHandler,
                         delegate: MockSyncSettingsViewModelDelegate? = nil,
                         isImprovedPairingFlowEnabled: Bool = false) -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: autoRestoreProvider,
            isImprovedPairingFlowEnabled: isImprovedPairingFlowEnabled
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
    var simplifiedCreateAccountAndStartSyncingCallCount = 0
    var onShowAutoRestoreReady: (() -> Void)?
    var onShowRecoveringDataAutoRestore: (() -> Void)?
    var onShowRecoveryCodeEntry: (() -> Void)?
    var onAuthenticateUserFinished: (() -> Void)?
    var onShowSyncWithAnotherDevice: (() -> Void)?
    var firedSyncSetupPixelEvents: [SyncSettingsViewModel.SyncSetupPixelEvent] = []
    var firedDeviceDetailsPixelEvents: [SyncSettingsViewModel.DeviceDetailsPixelEvent] = []
    var onSimplifiedConfirmAndDisableSync: (() -> Void)?
    var onDisableSync: (() -> Void)?

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
        onShowSyncWithAnotherDevice?()
    }
    func shareRecoveryPDF() {}
    func simplifiedCreateAccountAndStartSyncing(optionsViewModel: SyncSettingsViewModel) {
        simplifiedCreateAccountAndStartSyncingCallCount += 1
    }
    func simplifiedConfirmAndDisableSync() async -> Bool {
        onSimplifiedConfirmAndDisableSync?()
        return true
    }
    func disableSync() async -> Bool {
        onDisableSync?()
        return true
    }
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
    func fireSyncSetupPixel(event: SyncSettingsViewModel.SyncSetupPixelEvent) {
        firedSyncSetupPixelEvents.append(event)
    }
    func fireDeviceDetailsPixel(event: SyncSettingsViewModel.DeviceDetailsPixelEvent) {
        firedDeviceDetailsPixelEvents.append(event)
    }
}

private enum SyncSettingsViewModelTestsError: Error {
    case expected
}

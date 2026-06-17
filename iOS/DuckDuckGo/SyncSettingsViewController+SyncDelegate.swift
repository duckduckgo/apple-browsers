//
//  SyncSettingsViewController+SyncDelegate.swift
//  DuckDuckGo
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

import Core
import UIKit
import SwiftUI
import SyncUI_iOS
import DDGSync
import AVFoundation
import os.log

extension SyncSettingsViewController: SyncManagementViewModelDelegate {

    var syncBookmarksPausedTitle: String? {
        UserText.syncLimitExceededTitle
    }
    
    var syncCredentialsPausedTitle: String? {
        UserText.syncLimitExceededTitle
    }

    var syncCreditCardsPausedTitle: String? {
        UserText.syncLimitExceededTitle
    }

    var syncPausedTitle: String? {
        guard let error = getErrorType(from: syncPausedStateManager.currentSyncAllPausedError) else { return nil }
        switch error {
        case .invalidLoginCredentials:
            return UserText.syncLimitExceededTitle
        case .tooManyRequests:
            return UserText.syncErrorTitle
        default:
            assertionFailure("Sync Paused error should be one of those listed")
            return nil
        }
    }
    
    var syncBookmarksPausedDescription: String? {
        guard let error = getErrorType(from: syncPausedStateManager.currentSyncBookmarksPausedError) else { return nil }
        switch error {
        case .bookmarksCountLimitExceeded, .bookmarksRequestSizeLimitExceeded:
            return UserText.bookmarksLimitExceededDescription
        case .badRequestBookmarks:
            return UserText.badRequestErrorDescriptionBookmarks
        default:
            assertionFailure("Sync Bookmarks Paused error should be one of those listed")
            return nil
        }
    }
    
    var syncCredentialsPausedDescription: String? {
        guard let error = getErrorType(from: syncPausedStateManager.currentSyncCredentialsPausedError) else { return nil }
        switch error {
        case .credentialsCountLimitExceeded, .credentialsRequestSizeLimitExceeded:
            return UserText.credentialsLimitExceededDescription
        case .badRequestCredentials:
            return UserText.badRequestErrorDescriptionPasswords
        default:
            assertionFailure("Sync Bookmarks Paused error should be one of those listed")
            return nil
        }
    }

    var syncCreditCardsPausedDescription: String? {
        guard let error = getErrorType(from: syncPausedStateManager.currentSyncCreditCardsPausedError) else { return nil }
        switch error {
        case .creditCardsCountLimitExceeded, .creditCardsRequestSizeLimitExceeded:
            return UserText.creditCardsLimitExceededDescription
        case .badRequestCreditCards:
            return UserText.badRequestErrorDescriptionCreditCards
        default:
            assertionFailure("Sync Credit Cards Paused error should be one of those listed")
            return nil
        }
    }

    var syncPausedDescription: String? {
        guard let error = getErrorType(from: syncPausedStateManager.currentSyncAllPausedError) else { return nil }
        switch error {
        case .invalidLoginCredentials:
            return UserText.invalidLoginCredentialErrorDescription
        case .tooManyRequests:
            return UserText.tooManyRequestsErrorDescription
        default:
            assertionFailure("Sync Paused error should be one of those listed")
            return nil
        }
    }
    
    var syncBookmarksPausedButtonTitle: String? {
        UserText.bookmarksLimitExceededAction
    }
    
    var syncCredentialsPausedButtonTitle: String? {
        UserText.bookmarksLimitExceededAction
    }

    var syncCreditCardsPausedButtonTitle: String? {
        UserText.creditCardsLimitExceededAction
    }

    func authenticateUser() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            authenticateUser { error in
                if let error {
                    switch error {
                    case .failedToAuthenticate:
                        continuation.resume(throwing: SyncSettingsViewModel.UserAuthenticationError.authFailed)
                    case .noAuthAvailable:
                        continuation.resume(throwing: SyncSettingsViewModel.UserAuthenticationError.authUnavailable)
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func launchAutofillViewController() {
        guard let mainVC = view.window?.rootViewController as? MainViewController else { return }
        dismiss(animated: true)
        mainVC.launchAutofillLogins(source: .sync)
    }

    func launchAutofillCreditCardsViewController() {
        guard let mainVC = view.window?.rootViewController as? MainViewController else { return }
        dismiss(animated: true) {
            mainVC.segueToSettingsAutofillWith(account: nil, card: nil, showCardManagement: true, source: .sync)
        }
    }

    func launchBookmarksViewController() {
        guard let mainVC = view.window?.rootViewController as? MainViewController else { return }
        dismiss(animated: true)
        mainVC.segueToBookmarks()
    }

    func updateDeviceName(_ name: String) {
        Task { @MainActor in
            viewModel.devices = []
            syncService.scheduler.cancelSyncAndSuspendSyncQueue()
            do {
                let devices = try await syncService.updateDeviceName(name)
                mapDevices(devices)
            } catch {
                await handleError(SyncErrorMessage.unableToUpdateDeviceName, error: error, event: .syncUpdateDeviceError)
            }
            syncService.scheduler.resumeSyncQueue()
        }
    }

    func createAccountAndStartSyncing(optionsViewModel: SyncSettingsViewModel) {
        authenticateUser { [weak self] error in
            guard error == nil, let self else { return }
            Task { @MainActor in
                do {
                    guard await self.performDeferredPreservedAccountCleanupIfNeeded() else {
                        return
                    }
                    await self.dismissPresentedViewController()
                    await self.showPreparingSync()
                    try await self.syncService.createAccount(deviceName: self.deviceName, deviceType: self.deviceType)
                    let additionalParameters = self.source.map { ["source": $0] } ?? [:]
                    try await Pixel.fire(pixel: .syncSignupDirect, withAdditionalParameters: additionalParameters, includedParameters: [.appVersion])
                    self.syncSetupExperimentPixels.fireSignupDirect()
                    Pixel.fire(pixel: .syncSetupEndedSuccessful,
                               withAdditionalParameters: [PixelParameters.source: "signup"],
                               includedParameters: [.appVersion],
                               onComplete: { _ in })
                    self.syncSetupExperimentPixels.fireSetupEndedSuccessful()
                    AutofillOnboardingExperimentPixelReporter().fireSyncEnabled(true)
                    self.viewModel.syncEnabled(recoveryCode: self.recoveryCode)
                    self.refreshDevices()
                    self.dismissVCAndShowRecoveryPDF()
                } catch {
                    await self.handleError(SyncErrorMessage.unableToSyncToServer, error: error, event: .syncSignupError)
                }
            }
        }
    }

    func simplifiedCreateAccountAndStartSyncing(optionsViewModel: SyncSettingsViewModel) {
        Task { @MainActor in
            defer { optionsViewModel.isBusy = false }
            do {
                guard await self.performDeferredPreservedAccountCleanupIfNeeded() else {
                    return
                }
                try await self.syncService.createAccount(deviceName: self.deviceName, deviceType: self.deviceType)
                let additionalParameters = self.source.map { ["source": $0] } ?? [:]
                try await Pixel.fire(pixel: .syncSignupDirect, withAdditionalParameters: additionalParameters, includedParameters: [.appVersion])
                self.syncSetupExperimentPixels.fireSignupDirect()
                Pixel.fire(pixel: .syncSetupEndedSuccessful,
                           withAdditionalParameters: [PixelParameters.source: "signup"],
                           includedParameters: [.appVersion],
                           onComplete: { _ in })
                self.syncSetupExperimentPixels.fireSetupEndedSuccessful()
                AutofillOnboardingExperimentPixelReporter().fireSyncEnabled(true)
                optionsViewModel.syncEnabled(recoveryCode: self.recoveryCode)
                self.enableAutoRestoreByDefaultIfNeeded()
                await self.refreshDevicesAfterSimplifiedSyncEnable()

                let didShowPrompt = optionsViewModel.checkAndShowSyncWithAnotherDevicePrompt()
                if didShowPrompt {
                    optionsViewModel.scheduleSyncEnabledToastAfterSyncWithAnotherDevicePromptDismissal()
                } else {
                    self.showSimplifiedSyncEnabledToast()
                }
            } catch {
                self.firePixelIfNeededFor(event: .syncSignupError, error: error)
                ActionMessageView.present(message: UserText.simplifiedSyncSetupFailedToast)
            }
        }
    }

    @MainActor
    func handleError(_ type: SyncErrorMessage, error: Error?, event: Pixel.Event?) async {
        await withCheckedContinuation { continuation in
            if type.shouldSendPixel, let event = event {
                firePixelIfNeededFor(event: event, error: error)
            }
            let alertController = UIAlertController(
                title: type.title,
                message: type.description,
                preferredStyle: .alert)
            let okAction = UIAlertAction(title: type.buttonTitle, style: .default, handler: nil)
            alertController.addAction(okAction)

            if type == .unableToSyncToServer || type == .unableToSyncWithDevice || type == .unableToMergeTwoAccounts {
                // Gives time to the is syncing view to appear
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.dismissPresentedViewController { [weak self] in
                        guard let self else {
                            continuation.resume()
                            return
                        }
                        self.present(alertController, animated: true) {
                            continuation.resume()
                        }
                    }
                }
            } else {
                self.dismissPresentedViewController { [weak self] in
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    self.present(alertController, animated: true) {
                        continuation.resume()
                    }
                }
            }
        }
    }

    @MainActor
    func promptToSwitchAccounts(recoveryKey: SyncCode.RecoveryKey) {
        let alertController = UIAlertController(
            title: UserText.syncAlertSwitchAccountTitle,
            message: UserText.syncAlertSwitchAccountMessage,
            preferredStyle: .alert)
        alertController.addAction(title: UserText.syncAlertSwitchAccountButton, style: .default) { [weak self] in
            Task {
                Pixel.fire(pixel: .syncUserAcceptedSwitchingAccount)
                await self?.switchAccounts(recoveryKey: recoveryKey)
            }
        }
        alertController.addAction(title: UserText.actionCancel, style: .cancel) { [weak self] in
            Pixel.fire(pixel: .syncUserCancelledSwitchingAccount)
            self?.navigationController?.presentedViewController?.dismiss(animated: true)
        }

        let viewControllerToPresentFrom = navigationController?.presentedViewController ?? self
        viewControllerToPresentFrom.present(alertController, animated: true, completion: nil)
        Pixel.fire(pixel: .syncAskUserToSwitchAccount)
    }

    func switchAccounts(recoveryKey: SyncCode.RecoveryKey) async {
        do {
            try await syncService.disconnect()
        } catch {
            Pixel.fire(pixel: .syncUserSwitchedLogoutError)
        }

        do {
            try await loginAndShowDeviceConnected(recoveryKey: recoveryKey)
        } catch {
            Pixel.fire(pixel: .syncUserSwitchedLoginError)
        }
        Pixel.fire(pixel: .syncUserSwitchedAccount)
    }

    private func getErrorType(from errorString: String?) -> AsyncErrorType? {
        guard let errorString = errorString else {
            return nil
        }
        return AsyncErrorType(rawValue: errorString)
    }

    private func firePixelIfNeededFor(event: Pixel.Event, error: Error?) {
        if let syncError = error as? SyncError {
            if !syncError.isServerError {
                Pixel.fire(pixel: event, error: syncError, withAdditionalParameters: syncError.errorParameters)
            }
        } else if let error {
            Pixel.fire(pixel: event, error: error)
        } else {
            Pixel.fire(pixel: event)
        }
    }

    func isPreservedAccountPromptNeeded() -> Bool {
        // Only route through the preserved-account prompt when auto-restore is eligible.
        // If auto-restore is disabled, keep the existing setup behavior.
        syncAutoRestoreHandler.isEligibleForAutoRestore()
    }

    @MainActor
    func showAutoRestoreReady(for continuation: SyncSettingsViewModel.PreservedAccountContinuation) {
        let promptSource = autoRestorePromptSource(for: continuation)
        autoRestorePromptSource = promptSource
        needsPreservedAccountCleanupBeforeServerOperation = false
        dismissPresentedViewController { [weak self] in
            guard let self else { return }
            let readyView = AutoRestoreReadyView(model: self.viewModel, onCancel: { [weak self] in
                Pixel.fire(pixel: .syncAutoRestoreSettingsCancelled, withAdditionalParameters: [PixelParameters.source: promptSource.rawValue])
                self?.viewModel.clearPendingPreservedAccountContinuation()
                self?.viewModel.isBusy = false
                self?.autoRestorePromptSource = nil
                self?.dismissPresentedViewController()
            })
            let controller = DismissibleHostingController(rootView: readyView, onDismiss: { [weak self] in
                self?.viewModel.clearPendingPreservedAccountContinuation()
                self?.viewModel.isBusy = false
                if self?.needsPreservedAccountCleanupBeforeServerOperation == false {
                    self?.autoRestorePromptSource = nil
                }
            })
            self.navigationController?.present(controller, animated: true) {
                Pixel.fire(pixel: .syncAutoRestoreSettingsReadyShown, withAdditionalParameters: [PixelParameters.source: promptSource.rawValue])
            }
        }
    }

    @MainActor
    func continueAfterPreservedAccountRemoval(_ continuation: SyncSettingsViewModel.PreservedAccountContinuation) {
        autoRestorePromptSource = autoRestorePromptSource(for: continuation)
        needsPreservedAccountCleanupBeforeServerOperation = true
        dismissPresentedViewController { [weak self] in
            guard let self else { return }
            switch continuation {
            case .setup(let entryPoint):
                self.continueSyncSetupFlow(entryPoint: entryPoint)
            case .recover:
                self.presentRecoveryCodeScan()
            }
        }
    }

    func showRecoveringDataAutoRestore() {
        autoRestorePromptSource = nil
        needsPreservedAccountCleanupBeforeServerOperation = false
        dismissPresentedViewController { [weak self] in
            self?.navigationController?.present(UIHostingController(rootView: RecoveringDataView()), animated: true) { [weak self] in
                guard let self else { return }
                Task {
                    await self.performAutoRestore()
                }
            }
        }
    }

    func performAutoRestore() async {
        do {
            try await syncAutoRestoreHandler.restoreFromPreservedAccount(source: .settings)
        } catch {
            await handleError(.unableToSyncToServer, error: error, event: .syncLoginError)
        }
    }

    func dismissRecoveringDataViewIfPresented() {
        guard navigationController?.presentedViewController is UIHostingController<RecoveringDataView> else {
            return
        }
        dismissPresentedViewController()
    }

    @MainActor
    func showSyncWithAnotherDevice() {
        collectCode(showQRCode: true)
    }

    func showRecoveryCodeEntry() {
        dismissRecoverSyncedDataSheetIfNeeded { [weak self] in
            self?.presentRecoveryCodeScan()
        }
    }

    func showDeviceConnected() {
        let controller = UIHostingController(rootView: DeviceConnectedView(model: viewModel))
        navigationController?.present(controller, animated: true) { [weak self] in
            guard let self else { return }
            self.viewModel.syncEnabled(recoveryCode: self.recoveryCode)
        }
    }

    func showOtherPlatformLinks() {
        let controller = UIHostingController(rootView: PlatformLinksView(model: viewModel, source: .activating))
        navigationController?.pushViewController(controller, animated: true)
    }

    func fireOtherPlatformLinksPixel(event: SyncSettingsViewModel.PlatformLinksPixelEvent, with source: SyncSettingsViewModel.PlatformLinksPixelSource) {
        let params = ["source": source.rawValue]

        switch event {
        case .appear:
            Pixel.fire(.syncGetOtherDevices, withAdditionalParameters: params)
        case .copy:
            Pixel.fire(.syncGetOtherDevicesCopy, withAdditionalParameters: params)
        case .share:
            Pixel.fire(.syncGetOtherDevicesShare, withAdditionalParameters: params)
        }
    }

    func fireAutoRestorePixel(event: SyncSettingsViewModel.AutoRestorePixelEvent) {
        switch event {
        case .settingsPageShown:
            Pixel.fire(pixel: .syncAutoRestoreSettingsPageShown)
        case .settingsPageToggleChanged(let enabled):
            if enabled {
                Pixel.fire(pixel: .syncAutoRestoreSettingsPageToggleEnabled)
            } else {
                Pixel.fire(pixel: .syncAutoRestoreSettingsPageToggleDisabled)
            }
        case .manualRecoveryShown:
            Pixel.fire(pixel: .syncAutoRestoreSettingsManualRecoveryShown)
        case .readyRestoreTapped:
            Pixel.fire(pixel: .syncAutoRestoreSettingsRestoreTapped, withAdditionalParameters: autoRestorePromptSourceParameters)
        case .readySkipRestoreTapped:
            Pixel.fire(pixel: .syncAutoRestoreSettingsSkipRestoreTapped, withAdditionalParameters: autoRestorePromptSourceParameters)
        }
    }

    func fireSyncSetupPixel(event: SyncSettingsViewModel.SyncSetupPixelEvent) {
        switch event {
        case .backUpThisDeviceTapped:
            Pixel.fire(pixel: .settingsSyncBackUpThisDeviceTapped, includedParameters: [.appVersion])
        case .signupConfirmedTapped:
            Pixel.fire(pixel: .settingsSyncSignupConfirmedTapped, includedParameters: [.appVersion])
        case .signupAbandoned:
            Pixel.fire(pixel: .syncSetupEndedAbandoned,
                       withAdditionalParameters: [PixelParameters.source: "signup"],
                       includedParameters: [.appVersion])
            syncSetupExperimentPixels.fireSetupEndedAbandoned()
        case .recoverSyncedDataTapped:
            Pixel.fire(pixel: .settingsSyncRecoverSyncedDataTapped, includedParameters: [.appVersion])
        case .recoveryConfirmedTapped:
            Pixel.fire(pixel: .settingsSyncRecoveryConfirmedTapped, includedParameters: [.appVersion])
        }
    }

    func showPreparingSync(context: SimplifiedConnectingSheetView.Context = .syncingDevices) async {
        await withCheckedContinuation { continuation in
            showPreparingSync(context: context) {
                continuation.resume()
            }
        }
    }

    func showPreparingSync(context: SimplifiedConnectingSheetView.Context = .syncingDevices, _ completion: (() -> Void)?) {
        if useSimplifiedLayout {
            let controller = UIHostingController(rootView: SimplifiedConnectingSheetView(context: context))
            controller.view.backgroundColor = UIColor(designSystemColor: .backgroundSheets)
            controller.sheetPresentationController?.detents = [.large()]
            navigationController?.present(controller, animated: true, completion: completion)
        } else {
            let controller = UIHostingController(rootView: PreparingToSyncView(isAIChatSyncEnabled: viewModel.isAIChatSyncEnabled))
            navigationController?.present(controller, animated: true, completion: completion)
        }
    }

    @MainActor
    func showRecoveryPDF() {
        let model = SaveRecoveryKeyViewModel(
            key: recoveryCode,
            showRecoveryPDFAction: { [weak self] in
                self?.shareRecoveryPDF()
            },
            onDismiss: { [weak self] in
                self?.refreshAutoRestoreDecisionState()
                self?.showDeviceConnected()
            },
            autoRestoreProvider: syncAutoRestoreHandler,
            onAutoRestoreToggleShown: {
                Pixel.fire(pixel: .syncAutoRestoreToggleShown)
            },
            onAutoRestoreToggleOptedOut: {
                Pixel.fire(pixel: .syncAutoRestoreToggleOptedOut)
            }
        )
        let controller = UIHostingController(rootView: SaveRecoveryKeyView(model: model))
        navigationController?.present(controller, animated: true) { [weak self] in
            guard let self else { return }
            self.viewModel.syncEnabled(recoveryCode: self.recoveryCode)
        }
    }

    @MainActor
    func performDeferredPreservedAccountCleanupIfNeeded() async -> Bool {
        guard needsPreservedAccountCleanupBeforeServerOperation else {
            return true
        }

        if let preservedDeviceId = syncService.account?.deviceId {
            do {
                try await syncService.disconnect(deviceId: preservedDeviceId)
            } catch {
                Logger.sync.error("Best-effort remote disconnect failed for preserved sync account: \(error.localizedDescription, privacy: .public)")
                // Continue with local cleanup so setup can proceed even when remote logout fails.
            }
        }

        do {
            try syncService.removePreservedSyncAccount()
        } catch {
            Pixel.fire(pixel: .syncAutoRestorePreservedAccountClearFailed, error: error, withAdditionalParameters: autoRestorePromptSourceParameters)
            Logger.sync.error("Failed to clear preserved sync account before server operation: \(error.localizedDescription, privacy: .public)")
            presentPreservedAccountCleanupFailureAlert()
            return false
        }

        Pixel.fire(pixel: .syncAutoRestorePreservedAccountCleared, withAdditionalParameters: autoRestorePromptSourceParameters)
        needsPreservedAccountCleanupBeforeServerOperation = false
        autoRestorePromptSource = nil
        return true
    }

    @MainActor
    private func continueSyncSetupFlow(entryPoint: SyncSettingsViewModel.SyncSetupEntryPoint) {
        switch entryPoint {
        case .backup:
            viewModel.showSyncWithSetUpSheet()
        case .pairing:
            showSyncWithAnotherDevice()
        case .simplifiedToggle:
            viewModel.beginSimplifiedSyncSetup()
        }
    }

    @MainActor
    private func presentRecoveryCodeScan() {
        viewModel.isRecoverSyncedDataSheetVisible = false
        collectCode(showQRCode: false)
    }

    @MainActor
    private func dismissRecoverSyncedDataSheetIfNeeded(completion: @escaping () -> Void) {
        viewModel.isRecoverSyncedDataSheetVisible = false
        if let presentedViewController = presentedViewController,
           presentedViewController is UIHostingController<RecoverSyncedDataView> {
            presentedViewController.dismiss(animated: true, completion: completion)
            return
        }

        if let presentedViewController = navigationController?.presentedViewController,
           presentedViewController is UIHostingController<RecoverSyncedDataView> {
            presentedViewController.dismiss(animated: true, completion: completion)
            return
        }

        // Nothing to dismiss in this flow, continue immediately.
        completion()
    }

    private func collectCode(showQRCode: Bool) {
        pairingV2PeerKind = nil
        guard featureFlagger.isFeatureOn(.exchangeKeysToSyncWithAnotherDevice) else {
            legacyCollectCode(showQRCode: showQRCode)
            return
        }
        Task { @MainActor in
            let pairingInfo: PairingInfo
            var source: SyncSetupSource
            if shouldUsePreservedAccountForConnectionFlow {
                do {
                    pairingInfo = try await connectionController.startExchangeMode()
                    source = .exchange
                } catch {
                    await handleError(SyncErrorMessage.unableToSyncWithDevice, error: error, event: .syncLoginError)
                    return
                }
            } else {
                do {
                    pairingInfo = try await connectionController.startConnectMode()
                    source = .connect
                } catch {
                    await handleError(SyncErrorMessage.unableToSyncToServer, error: error, event: .syncLoginError)
                    return
                }
            }
            if !showQRCode {
                source = .recovery
            }
            let stringForQRCode = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
            presentScanOrPasteCodeView(
                codeForDisplayOrPasting: pairingInfo.base64Code,
                stringForQRCode: stringForQRCode,
                showQRCode: showQRCode,
                source: source,
                onPresentPixelInfo: .init(pixel: .syncSetupBarcodeScreenShown, source: source, flowVersion: syncSetupPixelFlowVersion))
        }
    }

    private func legacyCollectCode(showQRCode: Bool) {
        pairingV2PeerKind = nil
        Task {
            let stringForQRCode: String
            let codeForDisplayOrPasting: String
            let onPresentPixelInfo: SyncSetupPixelInfo?
            let source: SyncSetupSource
            if shouldUsePreservedAccountForConnectionFlow {
                stringForQRCode = recoveryCode
                codeForDisplayOrPasting = recoveryCode
                onPresentPixelInfo = nil
                source = showQRCode ? .exchange : .recovery
            } else {
                do {
                    let pairingInfo = try await connectionController.startConnectMode()
                    stringForQRCode = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
                    codeForDisplayOrPasting = pairingInfo.base64Code
                    source = showQRCode ? .connect : .recovery
                    onPresentPixelInfo = .init(pixel: .syncSetupBarcodeScreenShown, source: source, flowVersion: syncSetupPixelFlowVersion)
                } catch {
                    await handleError(SyncErrorMessage.unableToSyncToServer, error: error, event: .syncLoginError)
                    return
                }
            }
            presentScanOrPasteCodeView(
                codeForDisplayOrPasting: codeForDisplayOrPasting,
                stringForQRCode: stringForQRCode,
                showQRCode: showQRCode,
                source: source,
                onPresentPixelInfo: onPresentPixelInfo)
        }
    }

    private func presentScanOrPasteCodeView(codeForDisplayOrPasting: String,
                                            stringForQRCode: String,
                                            showQRCode: Bool,
                                            source: SyncSetupSource,
                                            onPresentPixelInfo: SyncSetupPixelInfo?) {
        let model = ScanOrPasteCodeViewModel(
            codeForDisplayOrPasting: codeForDisplayOrPasting,
            qrCodeString: stringForQRCode,
            source: CodeCollectionSource(syncSetupSource: source))
        model.delegate = self
        
        var controller: UIHostingController<AnyView>
        if useSimplifiedLayout {
            controller = UIHostingController(rootView: AnyView(SimplifiedScanOrShowCodeView(model: model)))
        } else if showQRCode {
            controller = UIHostingController(rootView: AnyView(ScanOrSeeCode(model: model)))
        } else {
            controller = UIHostingController(rootView: AnyView(ScanOrEnterCodeToRecoverSyncedDataView(model: model)))
        }
        
        let navController = UIDevice.current.userInterfaceIdiom == .phone
        ? PortraitNavigationController(rootViewController: controller)
        : UINavigationController(rootViewController: controller)
        
        navController.overrideUserInterfaceStyle = .dark
        if useSimplifiedLayout {
            navController.view.backgroundColor = UIColor(baseColor: .gray90)
            let transparentAppearance = UINavigationBarAppearance()
            transparentAppearance.configureWithTransparentBackground()
            navController.navigationBar.standardAppearance = transparentAppearance
            navController.navigationBar.scrollEdgeAppearance = transparentAppearance
        }
        navController.setNeedsStatusBarAppearanceUpdate()
        if useSimplifiedLayout, UIDevice.current.userInterfaceIdiom == .pad {
            navController.modalPresentationStyle = .formSheet
        } else {
            navController.modalPresentationStyle = .fullScreen
        }
        navigationController?.present(navController, animated: true) {
            self.checkCameraPermission(model: model)
            if let onPresentPixelInfo {
                let pixelSource = self.source ?? onPresentPixelInfo.source.rawValue
                var parameters = [
                    PixelParameters.source: pixelSource,
                    SyncSetupPixelInfo.Parameter.myKind: SyncSetupPixelInfo.Value.ddg
                ]
                parameters[SyncSetupPixelInfo.Parameter.flowVersion] = onPresentPixelInfo.flowVersion
                Pixel.fire(pixel: onPresentPixelInfo.pixel, withAdditionalParameters: parameters, includedParameters: [.appVersion])
                self.syncSetupExperimentPixels.fireBarcodeScreenShown()
            }
        }
    }

    func checkCameraPermission(model: ScanOrPasteCodeViewModel) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            Task { @MainActor in
                _ = await AVCaptureDevice.requestAccess(for: .video)
                self.checkCameraPermission(model: model)
            }
            return
        }

        switch status {
        case .denied: model.videoPermission = .denied
        case .authorized: model.videoPermission = .authorised
        default: assertionFailure("Unexpected status \(status)")
        }
    }

    func controllerShouldAllowPairingV2PeerToJoin(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        await confirmPairingV2Peer(peerName: peerName, peerKind: peerKind, setupRole: .sharer)
    }

    func controllerShouldJoinPairingV2Peer(peerName: String?, peerKind: PairingV2DeviceKind) async -> Bool {
        // codeSource is unused for the abandonment pixel; only the source/role matter.
        await confirmPairingV2Peer(peerName: peerName, peerKind: peerKind, setupRole: .receiver(.exchange, .qrCode))
    }

    private func confirmPairingV2Peer(peerName: String?, peerKind: PairingV2DeviceKind, setupRole: SyncSetupRole) async -> Bool {
        let peerName = pairingV2DisplayName(for: peerName)
        let message = UserText.syncPairingV2ConfirmationMessage(peerName, isThirdPartyPeer: peerKind == .thirdParty)
        let isConfirmed = await presentPairingV2ConfirmationAlert(message: message)
        if !isConfirmed {
            sendSyncConfirmationDeniedSetupEndedAbandonedPixel(setupRole: setupRole)
            dismissPairingV2UIAfterDeniedConfirmation()
        } else {
            pairingV2PeerKind = peerKind
        }
        return isConfirmed
    }

    private func presentPairingV2ConfirmationAlert(message: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: UserText.syncPairingV2ConfirmationTitle, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: UserText.actionCancel, style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: UserText.syncPairingV2ConfirmationAction, style: .default) { _ in
                continuation.resume(returning: true)
            })

            let viewControllerToPresentFrom = navigationController?.presentedViewController ?? presentedViewController ?? self
            viewControllerToPresentFrom.present(alert, animated: true)
        }
    }

    private func pairingV2DisplayName(for peerName: String?) -> String {
        guard let peerName = peerName?.trimmingCharacters(in: .whitespacesAndNewlines), !peerName.isEmpty else {
            return UserText.syncPairingV2UnknownPeerName
        }
        return peerName
    }

    private func dismissPairingV2UIAfterDeniedConfirmation() {
        DispatchQueue.main.async {
            self.dismissPresentedViewController()
        }
    }

    func confirmAndDisableSync() async -> Bool {
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: UserText.syncTurnOffConfirmTitle,
                                          message: UserText.syncTurnOffConfirmMessage,
                                          preferredStyle: .alert)
            self.onConfirmSyncDisable = { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    do {
                        try await self.syncService.disconnect()
                        Pixel.fire(pixel: .syncDisabled)
                        self.syncSetupExperimentPixels.fireSyncDisabled()
                        AutofillOnboardingExperimentPixelReporter().fireSyncEnabled(false)
                        self.viewModel.isSyncEnabled = false
                        self.syncPausedStateManager.syncDidTurnOff()
                        continuation.resume(returning: true)
                    } catch {
                        await self.handleError(SyncErrorMessage.unableToTurnSyncOff, error: error, event: .syncLogoutError)
                        continuation.resume(returning: false)
                    }
                }
            }
            let cancelAction = UIAlertAction(title: UserText.actionCancel, style: .cancel) { _ in
                continuation.resume(returning: false)
            }
            let confirmAction = UIAlertAction(title: UserText.syncTurnOffConfirmAction, style: .destructive) { _ in
                self.onConfirmSyncDisable?()
            }
            alert.addAction(cancelAction)
            alert.addAction(confirmAction)
            self.present(alert, animated: true)
        }
    }

    func simplifiedConfirmAndDisableSync() async -> Bool {
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: UserText.simplifiedSyncTurnOffTitle,
                                          message: UserText.simplifiedSyncTurnOffMessage,
                                          preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: UserText.actionCancel, style: .cancel) { _ in
                continuation.resume(returning: false)
            }
            let turnOffAction = UIAlertAction(title: UserText.simplifiedSyncTurnOffAction, style: .default) { _ in
                Task { @MainActor in
                    do {
                        try await self.syncService.disconnect()
                        Pixel.fire(pixel: .syncDisabled)
                        self.syncSetupExperimentPixels.fireSyncDisabled()
                        AutofillOnboardingExperimentPixelReporter().fireSyncEnabled(false)
                        self.syncPausedStateManager.syncDidTurnOff()
                        continuation.resume(returning: true)
                    } catch {
                        await self.handleError(SyncErrorMessage.unableToTurnSyncOff, error: error, event: .syncLogoutError)
                        continuation.resume(returning: false)
                    }
                }
            }
            alert.addAction(cancelAction)
            alert.addAction(turnOffAction)
            self.present(alert, animated: true)
        }
    }

    func confirmAndDeleteAllData() async -> Bool {
        let deviceCount = viewModel.devices.count
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: UserText.syncDeleteAllConfirmTitle,
                                          message: UserText.syncDeleteAllConfirmMessage,
                                          preferredStyle: .alert)
            alert.addAction(title: UserText.actionCancel, style: .cancel) {
                continuation.resume(returning: false)
            }
            self.onConfirmAndDeleteAllData = { [weak self] in
                Task { @MainActor in
                    do {
                        try await self?.syncService.deleteAccount()
                        Pixel.fire(pixel: .syncDisabledAndDeleted, withAdditionalParameters: [PixelParameters.connectedDevices: "\(deviceCount)"])
                        self?.syncSetupExperimentPixels.fireSyncDisabledAndDeleted()
                        AutofillOnboardingExperimentPixelReporter().fireSyncEnabled(false)
                        self?.viewModel.isSyncEnabled = false
                        self?.syncPausedStateManager.syncDidTurnOff()
                        continuation.resume(returning: true)
                    } catch {
                        await self?.handleError(SyncErrorMessage.unableToDeleteData, error: error, event: .syncDeleteAccountError)
                        continuation.resume(returning: false)
                    }
                }
            }
            alert.addAction(title: UserText.syncDeleteAllConfirmAction, style: .destructive) {
                self.onConfirmAndDeleteAllData?()
            }
            self.present(alert, animated: true)
        }
    }

    func confirmRemoveDevice(_ device: SyncSettingsViewModel.Device) async -> Bool {
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: UserText.syncRemoveDeviceTitle,
                                          message: UserText.syncRemoveDeviceMessage(device.name),
                                          preferredStyle: .alert)
            alert.addAction(title: UserText.actionCancel, style: .cancel) {
                continuation.resume(returning: false)
            }
            alert.addAction(title: UserText.syncRemoveDeviceConfirmAction, style: .destructive) {
                continuation.resume(returning: true)
            }
            self.present(alert, animated: true)
        }
    }

    func removeDevice(_ device: SyncSettingsViewModel.Device) {
        Task { @MainActor in
            do {
                try await syncService.disconnect(deviceId: device.id)
                refreshDevices()
            } catch {
                await handleError(SyncErrorMessage.unableToRemoveDevice, error: error, event: .syncRemoveDeviceError)
            }
        }
    }

    func codeEntryScreenShown() {
        Pixel.fire(pixel: .syncSetupManualCodeEntryScreenShown,
                   withAdditionalParameters: [
                    SyncSetupPixelInfo.Parameter.myKind: SyncSetupPixelInfo.Value.ddg,
                    SyncSetupPixelInfo.Parameter.flowVersion: syncSetupPixelFlowVersion
                   ],
                   includedParameters: [.appVersion])
        syncSetupExperimentPixels.fireManualCodeEntryScreenShown()
    }

    func codeCopied(_ code: String, source: CodeCollectionSource) {
        fireBarcodeCodeCopiedPixel(for: code, sourceHint: source)
    }

    @MainActor
    private func presentPreservedAccountCleanupFailureAlert() {
        let alertController = UIAlertController(title: SyncErrorMessage.unknownError.title, message: SyncErrorMessage.unknownError.description, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: UserText.syncPausedAlertOkButton, style: .default))

        dismissPresentedViewController { [weak self] in
            self?.present(alertController, animated: true)
        }
    }

    private var autoRestorePromptSourceParameters: [String: String] {
        guard let autoRestorePromptSource else {
            return [:]
        }
        return [PixelParameters.source: autoRestorePromptSource.rawValue]
    }

    private func autoRestorePromptSource(for continuation: SyncSettingsViewModel.PreservedAccountContinuation) -> AutoRestorePromptSource {
        switch continuation {
        case .setup(let entryPoint):
            switch entryPoint {
            case .backup:
                return .syncBackup
            case .pairing:
                return .syncPairing
            case .simplifiedToggle:
                return .syncBackup
            }
        case .recover:
            return .syncRecover
        }
    }
}

// MARK: - Simplified Sync

extension SyncSettingsViewController {
    private func refreshDevicesAfterSimplifiedSyncEnable() async {
        do {
            let devices = try await syncService.fetchDevices()
            mapDevices(devices)
        } catch {
            Logger.sync.error("Failed to fetch devices after simplified sync enable: \(error.localizedDescription, privacy: .public)")
        }
    }

    func showSimplifiedSyncEnabledToast() {
        DispatchQueue.main.async {
            ActionMessageView.present(message: UserText.simplifiedSyncEnabledToast)
        }
    }

    func simplifiedCopyRecoveryCode() {
        UIPasteboard.general.string = recoveryCode
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ActionMessageView.present(message: UserText.simplifiedRecoveryCodeCopiedToast)
    }

    private enum SimplifiedSyncSettingsKey: String {
        case hasShownSimplifiedSyncAnotherDevicePrompt = "sync.simplified.sync-another-device-prompt.shown"
    }

    var hasShownSimplifiedSyncAnotherDevicePrompt: Bool {
        get { syncSettingsStore.object(forKey: SimplifiedSyncSettingsKey.hasShownSimplifiedSyncAnotherDevicePrompt.rawValue) as? Bool ?? false }
        set { syncSettingsStore.set(newValue, forKey: SimplifiedSyncSettingsKey.hasShownSimplifiedSyncAnotherDevicePrompt.rawValue) }
    }
}

// MARK: - DismissibleHostingController

private class DismissibleHostingController<Content: View>: UIHostingController<Content> {

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return ThemeManager.shared.currentTheme.statusBarStyle
    }

    let onDismiss: () -> Void

    init(rootView: Content, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(rootView: rootView)
    }

    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDismiss()
    }
}

private class PortraitNavigationController: UINavigationController {

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        [.portrait, .portraitUpsideDown]
    }
}

private extension CodeCollectionSource {

    init(syncSetupSource: SyncSetupSource) {
        switch syncSetupSource {
        case .exchange:
            self = .exchange
        case .recovery:
            self = .recovery
        case .connect, .unknown:
            self = .connect
        }
    }
}

private struct SyncSetupPixelInfo {
    enum Parameter {
        static let flowVersion = "flow_version"
        static let myKind = "my_kind"
    }

    enum Value {
        static let ddg = "ddg"
        static let v1 = "v1"
        static let v2 = "v2"
    }

    let pixel: Pixel.Event
    let source: SyncSetupSource
    let flowVersion: String?
}

extension SyncSettingsViewController {

    var syncSetupPixelFlowVersion: String {
        featureFlagger.isFeatureOn(.syncCanUseV2ConnectFlow) ? SyncSetupPixelInfo.Value.v2 : SyncSetupPixelInfo.Value.v1
    }
}

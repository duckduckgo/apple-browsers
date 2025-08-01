//
//  SyncDialogController.swift
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

import Foundation
import DDGSync
import Combine
import Common
import SystemConfiguration
import SyncUI_macOS
import SwiftUI
import Navigation
import PixelKit
import os.log
import BrowserServicesKit

final class SyncDialogController: ManagementDialogModelDelegate {

    private let syncService: DDGSyncing
    private let syncBookmarksAdapter: SyncBookmarksAdapter
    private let syncCredentialsAdapter: SyncCredentialsAdapter
    private let userAuthenticator: UserAuthenticating
    private let syncPausedStateManager: any SyncPausedStateManaging
    private let featureFlagger: FeatureFlagger
    private let diagnosisHelper: SyncDiagnosisHelper

    let managementDialogModel: ManagementDialogModel

    private static let defaultConnectionControllerFactory: (DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling = { syncService, delegate in
        syncService.createConnectionController(deviceName: deviceInfo().name, deviceType: deviceInfo().type, delegate: delegate)
    }
    private let connectionControllerFactory: (DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling
    private lazy var connectionController: SyncConnectionControlling = connectionControllerFactory(syncService, self)

    private var cancellables = Set<AnyCancellable>()
    private var connector: RemoteConnecting?
    private var onEndFlow: () -> Void = {}
    private var syncPromoSource: String?

    // Properties that need to be accessible
    var devices: [SyncDevice] = []
    var stringForQR: String?
    var codeForDisplayOrPasting: String?
    var recoveryCode: String? {
        syncService.account?.recoveryCode
    }

    // Add device access delegation
    var devicesProvider: (() -> [SyncDevice])?

    init(
        syncService: DDGSyncing,
        syncBookmarksAdapter: SyncBookmarksAdapter,
        syncCredentialsAdapter: SyncCredentialsAdapter,
        managementDialogModel: ManagementDialogModel = ManagementDialogModel(),
        userAuthenticator: UserAuthenticating = DeviceAuthenticator.shared,
        syncPausedStateManager: any SyncPausedStateManaging,
        connectionControllerFactory: ((DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling)? = nil,
        featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger
    ) {
        self.syncService = syncService
        self.syncBookmarksAdapter = syncBookmarksAdapter
        self.syncCredentialsAdapter = syncCredentialsAdapter
        self.userAuthenticator = userAuthenticator
        self.syncPausedStateManager = syncPausedStateManager
        self.connectionControllerFactory = connectionControllerFactory ?? SyncDialogController.defaultConnectionControllerFactory
        self.featureFlagger = featureFlagger
        self.managementDialogModel = managementDialogModel

        diagnosisHelper = SyncDiagnosisHelper(syncService: syncService)
        self.managementDialogModel.delegate = self

        setUpObservables()
    }

    private func setUpObservables() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(launchedFromSyncPromo(_:)),
                                               name: SyncPromoManager.SyncPromoManagerNotifications.didGoToSync,
                                               object: nil)
    }

    @objc
    func launchedFromSyncPromo(_ sender: Notification) {
        syncPromoSource = sender.userInfo?[SyncPromoManager.Constants.syncPromoSourceKey] as? String
    }

    // Update presentDeleteAccount to use devices provider
    @MainActor
    func presentDeleteAccount() {
        let devices = devicesProvider?() ?? self.devices
        presentDialog(for: .deleteAccount(devices))
    }

    @MainActor
    func presentDialog(for currentDialog: ManagementDialogKind) {
        let shouldBeginSheet = managementDialogModel.currentDialog == nil
        managementDialogModel.currentDialog = currentDialog

        guard shouldBeginSheet else {
            return
        }

        guard [AppVersion.AppRunType.normal, .uiTests].contains(AppVersion.runType) else {
            return
        }

        let syncViewController = SyncManagementDialogViewController(managementDialogModel)
        let syncWindowController = syncViewController.wrappedInWindowController()

        guard let syncWindow = syncWindowController.window,
              let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController
        else {
            assertionFailure("Sync: Failed to present SyncManagementDialogViewController")
            return
        }

        onEndFlow = { [weak self] in
            self?.connector?.stopPolling()
            self?.connector = nil

            Task { @MainActor in
                await self?.connectionController.cancel()
                guard let window = syncWindowController.window, let sheetParent = window.sheetParent else {
                    assertionFailure("window or sheet parent not present")
                    return
                }
                sheetParent.endSheet(window)
            }
        }

        parentWindowController.window?.beginSheet(syncWindow)
    }

    static private func deviceInfo() -> (name: String, type: String) {
        let hostname = SCDynamicStoreCopyComputerName(nil, nil) as? String ?? ProcessInfo.processInfo.hostName
        return (name: hostname, type: "desktop")
    }

    @MainActor
    private func mapDevices(_ registeredDevices: [RegisteredDevice]) {
        guard let deviceId = syncService.account?.deviceId else { return }
        self.devices = registeredDevices.map {
            deviceId == $0.id ? SyncDevice(kind: .current, name: $0.name, id: $0.id) : SyncDevice($0)
        }.sorted(by: { item, _ in
            item.isCurrent
        })
    }

    // MARK: - ManagementDialogModelDelegate

    func turnOffSync() {
        Task { @MainActor in
            do {
                try await syncService.disconnect()
                PixelKit.fire(SyncFeatureUsagePixels.syncDisabled)
                managementDialogModel.endFlow()
                syncPausedStateManager.syncDidTurnOff()
                diagnosisHelper.didManuallyDisableSync()
            } catch {
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToTurnSyncOff, description: error.localizedDescription)
                PixelKit.fire(DebugEvent(GeneralPixel.syncLogoutError(error: error)))
            }
        }
    }

    func deleteAccount() {
        Task { @MainActor in
            do {
                let connectedDevices = devices.count
                try await syncService.deleteAccount()
                PixelKit.fire(SyncFeatureUsagePixels.syncDisabledAndDeleted(connectedDevices: connectedDevices))
                managementDialogModel.endFlow()
                syncPausedStateManager.syncDidTurnOff()
                diagnosisHelper.didManuallyDisableSync()
            } catch {
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToDeleteData, description: error.localizedDescription)
                PixelKit.fire(DebugEvent(GeneralPixel.syncDeleteAccountError(error: error)))
            }
        }
    }

    func updateDeviceName(_ name: String) {
        Task { @MainActor in
            self.devices = []
            syncService.scheduler.cancelSyncAndSuspendSyncQueue()
            do {
                let devices = try await syncService.updateDeviceName(name)
                managementDialogModel.endFlow()
                mapDevices(devices)
            } catch {
                if case SyncError.unauthenticatedWhileLoggedIn = error {
                    diagnosisHelper.didManuallyDisableSync()
                }
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToUpdateDeviceName, description: error.localizedDescription)
                PixelKit.fire(DebugEvent(GeneralPixel.syncUpdateDeviceError(error: error)))
            }
            syncService.scheduler.resumeSyncQueue()
        }
    }

    func removeDevice(_ device: SyncDevice) {
        Task { @MainActor in
            do {
                try await syncService.disconnect(deviceId: device.id)
                refreshDevices()
                managementDialogModel.endFlow()
            } catch {
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToRemoveDevice, description: error.localizedDescription)
                PixelKit.fire(DebugEvent(GeneralPixel.syncRemoveDeviceError(error: error)))
            }
        }
    }

    func refreshDevices() {
        guard syncService.account != nil else {
            devices = []
            return
        }
        Task { @MainActor in
            do {
                let registeredDevices = try await syncService.fetchDevices()
                mapDevices(registeredDevices)
            } catch {
                if case SyncError.unauthenticatedWhileLoggedIn = error {
                    diagnosisHelper.didManuallyDisableSync()
                }
                PixelKit.fire(DebugEvent(GeneralPixel.syncRefreshDevicesError(error: error), error: error))
                Logger.sync.debug("Failed to refresh devices: \(error)")
            }
        }
    }

    func recoveryCodePasted(_ code: String, fromRecoveryScreen: Bool) {
        recoverDevice(recoveryCode: code, fromRecoveryScreen: fromRecoveryScreen, codeSource: .pastedCode)
    }

    func saveRecoveryPDF() {
        guard let recoveryCode = syncService.account?.recoveryCode else {
            assertionFailure()
            return
        }

        Task { @MainActor in
            let authenticationResult = await userAuthenticator.authenticateUser(reason: .syncSettings)
            guard authenticationResult.authenticated else {
                if authenticationResult == .noAuthAvailable {
                    presentDialog(for: .empty)
                    managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToAuthenticateOnDevice, description: "")
                }
                return
            }

            let data = RecoveryPDFGenerator()
                .generate(recoveryCode)

            let panel = NSSavePanel.savePanelWithFileTypeChooser(fileTypes: [.pdf], suggestedFilename: "Sync Data Recovery - DuckDuckGo.pdf")
            let response = await panel.begin()

            guard response == .OK,
                  let location = panel.url else { return }

            do {
                try Progress.withPublishedProgress(url: location) {
                    try data.write(to: location)
                }
            } catch {
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableCreateRecoveryPDF, description: error.localizedDescription)
                PixelKit.fire(DebugEvent(GeneralPixel.syncCannotCreateRecoveryPDF))
            }
        }
    }

    func recoveryCodeNextPressed() {
        Task {
            await showDevicesSynced()
        }
    }

    func turnOnSync() {
        Task { @MainActor in
            managementDialogModel.endFlow()
            do {
                let device = Self.deviceInfo()
                presentDialog(for: .prepareToSync)
                try await syncService.createAccount(deviceName: device.name, deviceType: device.type)
                let additionalParameters = syncPromoSource.map { ["source": $0] } ?? [:]
                PixelKit.fire(GeneralPixel.syncSignupDirect, withAdditionalParameters: additionalParameters)
                presentDialog(for: .saveRecoveryCode(recoveryCode ?? ""))
            } catch {
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToServer, description: error.localizedDescription)
                PixelKit.fire(DebugEvent(GeneralPixel.syncSignupError(error: error)))
            }
        }
    }

    func enterRecoveryCodePressed() {
        startPollingForRecoveryKey(isRecovery: true)
    }

    @MainActor
    func syncWithAnotherDevicePressed() async {
        let authenticationResult = await userAuthenticator.authenticateUser(reason: .syncSettings)
        guard authenticationResult.authenticated else {
            if authenticationResult == .noAuthAvailable {
                presentDialog(for: .empty)
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToAuthenticateOnDevice, description: "")
            }
            return
        }
        if syncService.account != nil {
            startExchangeOrRecovery()
        } else {
            startPollingForRecoveryKey(isRecovery: false)
        }
    }

    @MainActor
    func syncWithServerPressed() async {
        let authenticationResult = await userAuthenticator.authenticateUser(reason: .syncSettings)
        guard authenticationResult.authenticated else {
            if authenticationResult == .noAuthAvailable {
                presentDialog(for: .empty)
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToAuthenticateOnDevice, description: "")
            }
            return
        }
        presentDialog(for: .syncWithServer)
    }

    @MainActor
    func recoverDataPressed() async {
        let authenticationResult = await userAuthenticator.authenticateUser(reason: .syncSettings)
        guard authenticationResult.authenticated else {
            if authenticationResult == .noAuthAvailable {
                presentDialog(for: .empty)
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToAuthenticateOnDevice, description: "")
            }
            return
        }
        presentDialog(for: .recoverSyncedData)
    }

    func copyCode() {
        var code: String?
        code = codeForDisplayOrPasting ?? recoveryCode
        guard let code else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(code, forType: .string)
        fireCodeCopiedPixel(code: code)
    }

    func openSystemPasswordSettings() {
        NSWorkspace.shared.open(URL.touchIDAndPassword)
    }

    func userConfirmedSwitchAccounts(recoveryCode: String) {
        PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserAcceptedSwitchingAccount.withoutMacPrefix)
        guard let recoveryKey = try? SyncCode.decodeBase64String(recoveryCode).recovery else {
            return
        }
        Task {
            await switchAccounts(recoveryKey: recoveryKey)
            await managementDialogModel.endFlow()
        }
    }

    func userPressedCancel(from dialog: ManagementDialogKind) {
        switch dialog {
        case .syncWithAnotherDevice(_, let stringForQRCode), .enterRecoveryCode(let stringForQRCode):
            guard let url = URL(string: stringForQRCode),
                  let pairingInfo = PairingInfo(url: url),
                  let syncCode = try? SyncCode.decodeBase64String(pairingInfo.base64Code) else {
                return
            }
            if syncCode.connect != nil {
                PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedAbandoned(.connect).withoutMacPrefix)
            } else if syncCode.exchangeKey != nil {
                PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedAbandoned(.exchange).withoutMacPrefix)
            }
        default:
            break
        }
    }

    func switchAccountsCancelled() {
        PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserCancelledSwitchingAccount.withoutMacPrefix)
    }

    func enterCodeViewDidAppear() {
        PixelKit.fire(SyncSetupPixelKitEvent.syncSetupManualCodeEntryScreenShown.withoutMacPrefix)
    }

    // MARK: - Private Helper Methods

    private func recoverDevice(recoveryCode: String, fromRecoveryScreen: Bool, codeSource: SyncCodeSource) {
        Task {
            await connectionController.syncCodeEntered(code: recoveryCode, canScanURLBarcodes: false, codeSource: codeSource)
        }
    }

    @MainActor
    private func showDevicesSynced() {
        presentDialog(for: .nowSyncing)
    }

    private func startPollingForRecoveryKey(isRecovery: Bool) {
        Task { @MainActor in
            do {
                let pairingInfo = try await connectionController.startConnectMode()
                let codeForDisplayOrPasting = pairingInfo.base64Code
                let stringForQR = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
                self.codeForDisplayOrPasting = codeForDisplayOrPasting
                self.stringForQR = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
                if isRecovery {
                    self.presentDialog(for: .enterRecoveryCode(stringForQRCode: stringForQR))
                } else {
                    self.presentDialog(for: .syncWithAnotherDevice(codeForDisplayOrPasting: codeForDisplayOrPasting, stringForQRCode: stringForQR))
                }
                PixelKit.fire(SyncSetupPixelKitEvent.syncSetupBarcodeScreenShown(.connect).withoutMacPrefix)
            } catch {
                if syncService.account == nil {
                    if isRecovery {
                        managementDialogModel.syncErrorMessage = SyncErrorMessage(
                            type: .unableToSyncToServer,
                            description: error.localizedDescription
                        )
                    } else {
                        managementDialogModel.syncErrorMessage = SyncErrorMessage(
                            type: .unableToSyncToOtherDevice,
                            description: error.localizedDescription
                        )
                    }
                    PixelKit.fire(DebugEvent(GeneralPixel.syncLoginError(error: error)))
                }
            }
        }
    }

    private func switchAccounts(recoveryKey: SyncCode.RecoveryKey) async {
        do {
            try await syncService.disconnect()
        } catch {
            PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserSwitchedLogoutError.withoutMacPrefix)
        }

        do {
            let device = Self.deviceInfo()
            let registeredDevices = try await syncService.login(recoveryKey, deviceName: device.name, deviceType: device.type)
            await mapDevices(registeredDevices)
        } catch {
            PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserSwitchedLoginError.withoutMacPrefix)
        }
        PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserSwitchedAccount.withoutMacPrefix)
    }

    private func fireCodeCopiedPixel(code: String) {
        guard let syncCode = try? SyncCode.decodeBase64String(code) else { return }
        if syncCode.exchangeKey != nil {
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupBarcodeCodeCopied(.exchange).withoutMacPrefix)
        } else if syncCode.connect != nil {
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupBarcodeCodeCopied(.connect).withoutMacPrefix)
        }
    }

    private func waitForDevicesToChangeThenPresentSyncing() {
        // This would need to be implemented if devices change tracking is needed
        Task {
            await presentDialog(for: .nowSyncing)
        }
    }

    private func startExchangeOrRecovery() {
        guard featureFlagger.isFeatureOn(.exchangeKeysToSyncWithAnotherDevice) else {
            startLegacyRecoveryFlow()
            return
        }
        startPollingForPublicKey()
    }

    private func startLegacyRecoveryFlow() {
        let recoveryCode = recoveryCode ?? "" // Only called if Sync enabled therefore will never be blank
        codeForDisplayOrPasting = recoveryCode
        stringForQR = recoveryCode
        Task {
            await presentDialog(for: .syncWithAnotherDevice(codeForDisplayOrPasting: recoveryCode, stringForQRCode: recoveryCode))
        }
    }

    private func startPollingForPublicKey() {
        Task { @MainActor in
            do {
                let pairingInfo = try await connectionController.startExchangeMode()
                let codeForDisplayOrPasting = pairingInfo.base64Code
                let stringForQR = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
                self.codeForDisplayOrPasting = codeForDisplayOrPasting
                self.stringForQR = stringForQR
                self.presentDialog(for: .syncWithAnotherDevice(codeForDisplayOrPasting: codeForDisplayOrPasting, stringForQRCode: stringForQR))
                PixelKit.fire(SyncSetupPixelKitEvent.syncSetupBarcodeScreenShown(.exchange).withoutMacPrefix)
            } catch {
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: error.localizedDescription)
                PixelKit.fire(DebugEvent(GeneralPixel.syncLoginError(error: error)))
            }
        }
    }
}

// MARK: - SyncConnectionControllerDelegate
@MainActor
extension SyncDialogController: SyncConnectionControllerDelegate {

    func controllerWillBeginTransmittingRecoveryKey() async {
        // no-op
    }

    func controllerDidFinishTransmittingRecoveryKey() {
        waitForDevicesToChangeThenPresentSyncing()
    }

    func controllerDidReceiveRecoveryKey() {
        presentDialog(for: .prepareToSync)
    }

    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource) async {
        sendCodeRecognisedPixel(setupSource: setupSource, codeSource: codeSource)
    }

    func controllerDidCreateSyncAccount() {
        let additionalParameters = syncPromoSource.map { ["source": $0] } ?? [:]
        PixelKit.fire(GeneralPixel.syncSignupConnect, withAdditionalParameters: additionalParameters)
        guard let code = recoveryCode else {
            return
        }
        presentDialog(for: .saveRecoveryCode(code))
    }

    func controllerDidCompleteAccountConnection(shouldShowSyncEnabled: Bool, setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        sendSetupEndedSuccessfullyPixel(setupSource: setupSource, codeSource: codeSource)
        guard shouldShowSyncEnabled else { return }
        Task {
            await presentDialog(for: .saveRecoveryCode(recoveryCode ?? ""))
        }
    }

    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool, setupRole: SyncSetupRole) {
        self.codeForDisplayOrPasting = self.recoveryCode
        self.stringForQR = self.recoveryCode
        mapDevices(registeredDevices)
        PixelKit.fire(GeneralPixel.syncLogin)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.presentDialog(for: .saveRecoveryCode(self.recoveryCode ?? ""))
        }
        guard case .receiver(let syncSetupSource, let syncCodeSource) = setupRole else {
            return
        }
        sendSetupEndedSuccessfullyPixel(setupSource: syncSetupSource, codeSource: syncCodeSource)
    }

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey, setupRole: SyncSetupRole) async {
        await handleAccountAlreadyExists(recoveryKey)
    }

    func controllerDidError(_ error: SyncConnectionError, underlyingError: (any Error)?, setupRole: SyncSetupRole) async {
        switch error {
        case .unableToRecognizeCode:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToRecognizeCode)
            sendCodeParsingFailedPixel(setupRole: setupRole)
        case .failedToFetchPublicKey, .failedToTransmitExchangeRecoveryKey, .failedToFetchConnectRecoveryKey, .failedToLogIn, .failedToTransmitExchangeKey, .failedToFetchExchangeRecoveryKey, .failedToTransmitConnectRecoveryKey:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: underlyingError?.localizedDescription)
            PixelKit.fire(DebugEvent(GeneralPixel.syncLoginError(error: underlyingError ?? error)))
        case .failedToCreateAccount:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: underlyingError?.localizedDescription)
            PixelKit.fire(DebugEvent(GeneralPixel.syncSignupError(error: underlyingError ?? error)))
        case .pollingForRecoveryKeyTimedOut:
            managementDialogModel.endFlow()
        }
    }

    private func handleAccountAlreadyExists(_ recoveryKey: SyncCode.RecoveryKey) async {
        if devices.count > 1 {
            managementDialogModel.showSwitchAccountsMessage()
            PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncAskUserToSwitchAccount.withoutMacPrefix)
        } else {
            await switchAccounts(recoveryKey: recoveryKey)
            managementDialogModel.endFlow()
        }
        PixelKit.fire(DebugEvent(GeneralPixel.syncLoginExistingAccountError(error: SyncError.accountAlreadyExists)))
    }

    private func sendCodeRecognisedPixel(setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        guard case .pastedCode = codeSource else {
            // Others not supported by macOS
            return
        }
        guard setupSource != .recovery, setupSource != .unknown else { return }
        PixelKit.fire(SyncSetupPixelKitEvent.syncSetupManualCodeEnteredSuccess(setupSource).withoutMacPrefix)
    }

    private func sendCodeParsingFailedPixel(setupRole: SyncSetupRole) {
        guard case .receiver(_, let codeSource) = setupRole, case .pastedCode = codeSource else {
            return
        }
        PixelKit.fire(SyncSetupPixelKitEvent.syncSetupManualCodeEnteredFailed.withoutMacPrefix)
    }

    private func sendSetupEndedSuccessfullyPixel(setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        guard case .pastedCode = codeSource else {
            // Others not supported by macOS
            return
        }
        guard setupSource != .recovery, setupSource != .unknown else { return }
        PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedSuccessful(setupSource).withoutMacPrefix)
    }
}

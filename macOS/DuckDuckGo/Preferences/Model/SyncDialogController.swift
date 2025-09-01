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

/// Protocol for handling sync settings view interactions and device management.
/// 
/// This protocol defines the interface for managing sync-related user actions,
/// device operations, and data recovery functionality in the sync settings UI.
@MainActor
protocol SyncSettingsViewHandling {
    /// Initiates the process to turn off sync for the current device
    func turnOffSyncPressed()

    /// Presents the device details view for the specified sync device
    /// - Parameter device: The sync device to display details for
    func presentDeviceDetails(_ device: SyncDevice)

    /// Presents the remove device confirmation dialog for the specified device
    /// - Parameter device: The sync device to remove
    func presentRemoveDevice(_ device: SyncDevice)

    /// Presents the delete account confirmation dialog
    func presentDeleteAccount()

    /// Initiates the sync setup flow to connect with another device
    func syncWithAnotherDevicePressed() async

    /// Initiates the sync setup flow to connect with the server
    func syncWithServerPressed() async

    /// Initiates the data recovery flow for restoring sync data
    func recoverDataPressed() async

    /// Saves the recovery code as a PDF document
    func saveRecoveryPDF()

    // These two members should probably be split out / moved to DDGSync
    /// Refreshes the list of connected sync devices
    func refreshDevices()

    /// Publisher that emits updates to the list of connected sync devices
    var devicesPublisher: AnyPublisher<[SyncDevice], Never> { get }
}

@MainActor
final class SyncDialogController {
    private let syncService: DDGSyncing
    private let managementDialogModel: ManagementDialogModel
    private let userAuthenticator: UserAuthenticating
    private let syncPausedStateManager: any SyncPausedStateManaging
    private let featureFlagger: FeatureFlagger
    private let diagnosisHelper: SyncDiagnosisHelper

    private static let defaultConnectionControllerFactory: (DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling = { syncService, delegate in
        syncService.createConnectionController(deviceName: deviceInfo().name, deviceType: deviceInfo().type, delegate: delegate)
    }
    private let connectionControllerFactory: (DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling
    private lazy var connectionController: SyncConnectionControlling = connectionControllerFactory(syncService, self)

    private var cancellables = Set<AnyCancellable>()
    private var syncPromoSource: String?

    @Published var stringForQR: String?
    @Published var codeForDisplayOrPasting: String?
    private var recoveryCode: String? {
        syncService.account?.recoveryCode
    }

    private var isScreenLocked: Bool = false

    @Published var devices: [SyncDevice] = []

    weak var coordinationDelegate: DeviceSyncCoordinationDelegate?

    init(
        syncService: DDGSyncing,
        managementDialogModel: ManagementDialogModel = ManagementDialogModel(),
        userAuthenticator: UserAuthenticating = DeviceAuthenticator.shared,
        syncPausedStateManager: any SyncPausedStateManaging,
        connectionControllerFactory: ((DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling)? = nil,
        featureFlagger: FeatureFlagger? = nil
    ) {
        self.syncService = syncService
        self.userAuthenticator = userAuthenticator
        self.syncPausedStateManager = syncPausedStateManager
        self.connectionControllerFactory = connectionControllerFactory ?? SyncDialogController.defaultConnectionControllerFactory
        self.featureFlagger = featureFlagger ?? Application.appDelegate.featureFlagger
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
        syncService.authStatePublisher
            .removeDuplicates()
            .asVoid()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshDevices()
            }
            .store(in: &cancellables)

        let screenIsLockedPublisher = DistributedNotificationCenter.default
            .publisher(for: .init(rawValue: "com.apple.screenIsLocked"))
            .map { _ in true }
        let screenIsUnlockedPublisher = DistributedNotificationCenter.default
            .publisher(for: .init(rawValue: "com.apple.screenIsUnlocked"))
            .map { _ in false }

        Publishers.Merge(screenIsLockedPublisher, screenIsUnlockedPublisher)
            .receive(on: DispatchQueue.main)
            .assign(to: \.isScreenLocked, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    @objc
    func launchedFromSyncPromo(_ sender: Notification) {
        syncPromoSource = sender.userInfo?[SyncPromoManager.Constants.syncPromoSourceKey] as? String
    }

    @MainActor
    func presentDeleteAccount() {
        presentDialog(for: .deleteAccount(self.devices))
    }

    // MARK: - Private Helper Methods

    @MainActor
    private func presentDialog(for currentDialog: ManagementDialogKind) {
        managementDialogModel.currentDialog = currentDialog
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

    private func recoverDevice(recoveryCode: String, fromRecoveryScreen: Bool, codeSource: SyncCodeSource) {
        Task {
            await connectionController.syncCodeEntered(code: recoveryCode, canScanURLBarcodes: false, codeSource: codeSource)
        }
    }

    @MainActor
    private func showNowSyncing() {
        presentDialog(for: .nowSyncing)
    }

    private func startPollingForRecoveryKey(isRecovery: Bool) {
        Task { @MainActor in
            do {
                let pairingInfo = try await connectionController.startConnectMode()
                let codeForDisplayOrPasting = pairingInfo.base64Code
                let stringForQR = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
                self.codeForDisplayOrPasting = codeForDisplayOrPasting
                self.stringForQR = stringForQR
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
            mapDevices(registeredDevices)
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
        $devices.removeDuplicates()
            .dropFirst()
            .prefix(1)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    self.presentDialog(for: .nowSyncing)
                }
            }.store(in: &cancellables)
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
            presentDialog(for: .syncWithAnotherDevice(codeForDisplayOrPasting: recoveryCode, stringForQRCode: recoveryCode))
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

extension SyncDialogController: ManagementDialogModelDelegate {
    func turnOffSync() {
        Task { @MainActor in
            do {
                try await syncService.disconnect()
                PixelKit.fire(SyncFeatureUsagePixels.syncDisabled)
                syncPausedStateManager.syncDidTurnOff()
                diagnosisHelper.didManuallyDisableSync()
                managementDialogModel.endFlow()
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
                syncPausedStateManager.syncDidTurnOff()
                diagnosisHelper.didManuallyDisableSync()
                managementDialogModel.endFlow()
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
                mapDevices(devices)
                managementDialogModel.endFlow()
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
        guard !isScreenLocked else {
            Logger.sync.debug("Screen is locked, skipping devices refresh")
            return
        }
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
        showNowSyncing()
    }

    func turnOnSync() {
        Task { @MainActor in
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
            managementDialogModel.endFlow()
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

    func didEndFlow() {
        Task { [weak self] in
            await self?.connectionController.cancel()
        }
        coordinationDelegate?.didEndFlow()
    }
}

extension SyncDialogController: SyncSettingsViewHandling {
    var devicesPublisher: AnyPublisher<[SyncDevice], Never> {
        $devices.eraseToAnyPublisher()
    }

    @MainActor
    func turnOffSyncPressed() {
        presentDialog(for: .turnOffSync)
    }

    @MainActor
    func presentDeviceDetails(_ device: SyncDevice) {
        presentDialog(for: .deviceDetails(device))
    }

    @MainActor
    func presentRemoveDevice(_ device: SyncDevice) {
        presentDialog(for: .removeDevice(device))
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
            presentDialog(for: .saveRecoveryCode(recoveryCode ?? ""))
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

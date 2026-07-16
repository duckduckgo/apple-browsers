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

import AppKit
import Foundation
import DDGSync
import Combine
import CombineExtensions
import Common
import FoundationExtensions
import SystemConfiguration
import SyncUI_macOS
import SwiftUI
import Navigation
import PixelKit
import os.log
import PrivacyConfig
import AttributedMetric

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
    func syncWithAnotherDevicePressed(source: SyncDeviceButtonTouchpoint?) async

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
    private var pairingV2PeerKind: PairingV2DeviceKind?
    private var displayedCodeSetupSource: SyncSetupSource?

    @Published var stringForQR: String?
    @Published var codeForDisplayOrPasting: String?
    private var recoveryCode: String? {
        syncService.recoveryCode
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
                guard let self else { return }
                self.refreshDevices()
                self.updateSingleDeviceSyncPromoVisibility()
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

        featureFlagger.updatesPublisher
            .prepend(())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.managementDialogModel.isAIChatSyncEnabled = self.featureFlagger.isFeatureOn(.aiChatSync)
                self.updateSingleDeviceSyncPromoVisibility()
            }
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

    private func updateSingleDeviceSyncPromoVisibility() {
        let isFlagEnabled = featureFlagger.isFeatureOn(.allowSingleDeviceOnConnectScreen)
        let isSyncInactive = syncService.account == nil
        managementDialogModel.shouldShowSingleDeviceSyncPromoOnSyncWithAnotherDeviceScreen = isFlagEnabled && isSyncInactive
    }

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
        NotificationCenter.default.post(name: .syncDevicesUpdate, object: self, userInfo: [AttributedMetricNotificationParameter.syncCount.rawValue: registeredDevices.count])
    }

    private func recoverDevice(recoveryCode: String, fromRecoveryScreen: Bool, codeSource: SyncCodeSource) {
        Task {
            await connectionController.syncCodeEntered(code: recoveryCode, canScanLegacyURLBarcodes: featureFlagger.isFeatureOn(.canScanUrlBasedSyncSetupBarcodes), codeSource: codeSource)
        }
    }

    @MainActor
    private func showNowSyncing() {
        presentDialog(for: .nowSyncing)
    }

    private func startPollingForRecoveryKey(isRecovery: Bool) {
        pairingV2PeerKind = nil
        Task { @MainActor in
            do {
                let pairingInfo = try await connectionController.startConnectMode()
                let codeForDisplayOrPasting = pairingInfo.base64Code
                let stringForQR = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
                self.codeForDisplayOrPasting = codeForDisplayOrPasting
                self.stringForQR = stringForQR
                self.displayedCodeSetupSource = .connect
                if isRecovery {
                    self.presentDialog(for: .enterRecoveryCode(stringForQRCode: stringForQR))
                } else {
                    self.presentDialog(for: .syncWithAnotherDevice(codeForDisplayOrPasting: codeForDisplayOrPasting, stringForQRCode: stringForQR))
                }
                PixelKit.fire(SyncSetupPixelKitEvent.syncSetupBarcodeScreenShown(.connect, flowVersion: syncSetupFlowVersion), doNotEnforcePrefix: true)
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
            PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserSwitchedLogoutError, doNotEnforcePrefix: true)
        }

        do {
            let device = Self.deviceInfo()
            let registeredDevices = try await syncService.login(recoveryKey, deviceName: device.name, deviceType: device.type)
            mapDevices(registeredDevices)
        } catch {
            PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserSwitchedLoginError, doNotEnforcePrefix: true)
        }
        PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserSwitchedAccount, doNotEnforcePrefix: true)
    }

    private func fireCodeCopiedPixel(code: String, sourceHint: SyncSetupSource?) {
        if let url = URL(string: code), PairingInfo.isPairingV2URL(url) {
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupBarcodeCodeCopied(sourceHint ?? .exchange, flowVersion: syncSetupFlowVersion), doNotEnforcePrefix: true)
            return
        }

        guard let syncCode = try? SyncCode.decodeBase64String(code) else { return }
        if syncCode.exchangeKey != nil {
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupBarcodeCodeCopied(.exchange, flowVersion: syncSetupFlowVersion), doNotEnforcePrefix: true)
        } else if syncCode.connect != nil {
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupBarcodeCodeCopied(.connect, flowVersion: syncSetupFlowVersion), doNotEnforcePrefix: true)
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
        displayedCodeSetupSource = .exchange
        Task {
            presentDialog(for: .syncWithAnotherDevice(codeForDisplayOrPasting: recoveryCode, stringForQRCode: recoveryCode))
        }
    }

    private func startPollingForPublicKey() {
        pairingV2PeerKind = nil
        Task { @MainActor in
            do {
                let pairingInfo = try await connectionController.startExchangeMode()
                let codeForDisplayOrPasting = pairingInfo.base64Code
                let stringForQR = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
                self.codeForDisplayOrPasting = codeForDisplayOrPasting
                self.stringForQR = stringForQR
                self.displayedCodeSetupSource = .exchange
                self.presentDialog(for: .syncWithAnotherDevice(codeForDisplayOrPasting: codeForDisplayOrPasting, stringForQRCode: stringForQR))
                PixelKit.fire(SyncSetupPixelKitEvent.syncSetupBarcodeScreenShown(.exchange, flowVersion: syncSetupFlowVersion), doNotEnforcePrefix: true)
            } catch {
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: error.localizedDescription)
                PixelKit.fire(DebugEvent(GeneralPixel.syncLoginError(error: error)))
            }
        }
    }

    private func checkAuthenticated() async -> Bool {
        let authenticationResult = await userAuthenticator.authenticateUser(reason: .syncSettings)
        guard authenticationResult.authenticated else {
            if authenticationResult == .noAuthAvailable {
                presentDialog(for: .empty)
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToAuthenticateOnDevice)
            }
            coordinationDelegate?.didEndFlow()
            return false
        }
        return true
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
        guard let recoveryCode = syncService.recoveryCode else {
            assertionFailure()
            return
        }

        Task { @MainActor in
            guard await checkAuthenticated() else {
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
                presentDialog(for: .prepareToSync(.singleDeviceOrRecovery))
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
        fireCodeCopiedPixel(code: code, sourceHint: displayedCodeSetupSource)
    }

    func openSystemPasswordSettings() {
        NSWorkspace.shared.open(URL.touchIDAndPassword)
    }

    func userConfirmedSwitchAccounts(recoveryCode: String) {
        PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserAcceptedSwitchingAccount, doNotEnforcePrefix: true)
        guard let syncCode = try? SyncCode.decodeBase64String(recoveryCode),
              let recoveryKey = try? syncCode.recovery?.defaultCredentialRecoveryKey() else {
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
            if let source = syncSetupSource(for: stringForQRCode, dialog: dialog, sourceHint: displayedCodeSetupSource) {
                PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedAbandoned(source,
                                                                             flowVersion: syncSetupFlowVersion,
                                                                             reason: SyncSetupPixelKitEvent.ParameterValue.scanningCancelled),
                              doNotEnforcePrefix: true)
            }
        default:
            break
        }
    }

    func switchAccountsCancelled() {
        PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncUserCancelledSwitchingAccount, doNotEnforcePrefix: true)
    }

    func enterCodeViewDidAppear() {
        PixelKit.fire(SyncSetupPixelKitEvent.syncSetupManualCodeEntryScreenShown(flowVersion: syncSetupFlowVersion), doNotEnforcePrefix: true)
    }

    func didEndFlow() {
        let controller = self.connectionController
        let delegate = self.coordinationDelegate

        Task {
            await controller.cancel()
            delegate?.didEndFlow()
        }
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
    func syncWithAnotherDevicePressed(source: SyncDeviceButtonTouchpoint?) async {
        if let source { // Must be if let so as not to override any existing source with nil
            syncPromoSource = source.rawValue
        }

        guard await checkAuthenticated() else {
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
        guard await checkAuthenticated() else {
            return
        }
        presentDialog(for: .syncWithServer)
    }

    @MainActor
    func recoverDataPressed() async {
        guard await checkAuthenticated() else {
            return
        }
        presentDialog(for: .recoverSyncedData)
    }
}

// MARK: - SyncConnectionControllerDelegate
@MainActor
extension SyncDialogController: SyncConnectionControllerDelegate {

    func controllerWillBeginTransmittingRecoveryKey() async {
        presentDialog(for: .prepareToSync(.twoDevicePairing))
    }

    func controllerDidFinishTransmittingRecoveryKey(shouldWaitForDevicesToChange: Bool) {
        PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedSuccessful(.exchange,
                                                                      flowVersion: syncSetupFlowVersion,
                                                                      peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                                                      myRole: SyncSetupPixelKitEvent.ParameterValue.host),
                      doNotEnforcePrefix: true)
        pairingV2PeerKind = nil
        // Temporary handling as devices don't update when 3p device added to account
        if shouldWaitForDevicesToChange {
            waitForDevicesToChangeThenPresentSyncing()
        } else {
            presentDialog(for: .nowSyncing)
        }
    }

    func controllerDidReceiveRecoveryKey() {
        presentDialog(for: .prepareToSync(.twoDevicePairing))
    }

    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource, codeVersion: SyncSetupCodeVersion) async {
        sendCodeRecognisedPixel(setupSource: setupSource, codeSource: codeSource, codeVersion: codeVersion)
        let mode: PreparingToSyncMode = setupSource == .recovery ? .singleDeviceOrRecovery : .twoDevicePairing
        presentDialog(for: .prepareToSync(mode))
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
        let isConfirmed = await showPairingV2Confirmation(message: message)
        if !isConfirmed {
            sendSetupEndedAbandonedPixel(setupRole: setupRole, reason: SyncSetupPixelKitEvent.ParameterValue.syncConfirmationDenied)
            managementDialogModel.endFlow()
        } else {
            pairingV2PeerKind = peerKind
        }
        return isConfirmed
    }

    private func pairingV2DisplayName(for peerName: String?) -> String {
        guard let peerName = peerName?.trimmingCharacters(in: .whitespacesAndNewlines), !peerName.isEmpty else {
            return UserText.syncPairingV2UnknownPeerName
        }
        return peerName
    }

    func controllerDidCreateSyncAccount(shouldShowSyncEnabled: Bool) {
        let additionalParameters = syncPromoSource.map { ["source": $0] } ?? [:]
        PixelKit.fire(GeneralPixel.syncSignupConnect, withAdditionalParameters: additionalParameters)
        guard shouldShowSyncEnabled else {
            return
        }
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
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedSuccessful(.connect,
                                                                          flowVersion: syncSetupFlowVersion,
                                                                          peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                                                          myRole: SyncSetupPixelKitEvent.ParameterValue.joiner),
                          doNotEnforcePrefix: true)
            pairingV2PeerKind = nil
            return
        }
        sendSetupEndedSuccessfullyPixel(setupSource: syncSetupSource, codeSource: syncCodeSource)
    }

    func controllerDidCompletePairingWithAlreadyConnectedAccount(setupRole: SyncSetupRole) {
        managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .alreadyPairedWithAccount)
        sendSetupEndedFailedPixel(setupRole: setupRole, reason: SyncSetupPixelKitEvent.ParameterValue.alreadyPaired)
    }

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey,
                                                    setupRole: SyncSetupRole,
                                                    shouldPromptBeforeSwitchingAccounts: Bool) async {
        await handleAccountAlreadyExists(recoveryKey, shouldPromptBeforeSwitchingAccounts: shouldPromptBeforeSwitchingAccounts)
    }

    func controllerDidError(_ error: SyncConnectionError, underlyingError: (any Error)?, setupRole: SyncSetupRole) async {
        switch error {
        case .unableToRecognizeCode:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToRecognizeCode)
            sendCodeParsingFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
        case .updateRequired:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .updateRequired)
            sendCodeParsingFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
        case .unsupportedThirdPartyRecoveryCode:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unsupportedThirdPartyRecoveryCode)
            sendCodeParsingFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
        case .thirdPartyAccountAlreadyUpgraded:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .thirdPartyAccountAlreadyUpgraded)
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
        case .syncCancelledFromOtherDevice:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .syncCancelledFromOtherDevice)
            sendSetupEndedAbandonedPixel(setupRole: setupRole, reason: SyncSetupPixelKitEvent.ParameterValue.syncConfirmationDenied)
        case .failedToFetchPublicKey,
                .failedToFetchConnectRecoveryKey,
                .failedToLogIn,
                .failedToTransmitExchangeKey,
                .failedToFetchExchangeRecoveryKey,
                .failedToTransmitConnectRecoveryKey:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: underlyingError?.localizedDescription)
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            PixelKit.fire(DebugEvent(GeneralPixel.syncLoginError(error: underlyingError ?? error)))
        case .failedToTransmitExchangeRecoveryKey:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: underlyingError?.localizedDescription)
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            PixelKit.fire(DebugEvent(GeneralPixel.syncLoginError(error: underlyingError ?? error)))
        case .accountUpgradeFailed,
                .transportFailure,
                .protocolError,
                .unexpectedSecondHello,
                .unexpectedEvent,
                .pairingSessionNotReady,
                .relayChannelUnavailable,
                .recoveryCodePreparationFailed,
                .peerRecoveryCodeUnavailable,
                .unexpectedFailure,
                .missingThirdPartyCredential,
                .undecryptableThirdPartyCredential,
                .accountExtendFailed,
                .missingThirdPartyKey,
                .localStorageFailed,
                .invalidCredentials:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: underlyingError?.localizedDescription)
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            PixelKit.fire(DebugEvent(GeneralPixel.syncLoginError(error: underlyingError ?? error)))
        case .failedToCreateAccount:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: underlyingError?.localizedDescription)
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            PixelKit.fire(DebugEvent(GeneralPixel.syncSignupError(error: underlyingError ?? error)))
        case .accountCreationFailed:
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice, description: underlyingError?.localizedDescription)
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            PixelKit.fire(DebugEvent(GeneralPixel.syncSignupError(error: underlyingError ?? error)))
        case .pollingForRecoveryKeyTimedOut:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice)
        case .pairingV2SessionTimedOut:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason, timeoutStage: error.syncSetupTimeoutStage)
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice)
        }
    }

    private func handleAccountAlreadyExists(_ recoveryKey: SyncCode.RecoveryKey, shouldPromptBeforeSwitchingAccounts: Bool) async {
        // For V2 we're intentionally not showing prompt here
        if shouldPromptBeforeSwitchingAccounts && devices.count > 1 {
            managementDialogModel.showSwitchAccountsMessage()
            PixelKit.fire(SyncSwitchAccountPixelKitEvent.syncAskUserToSwitchAccount, doNotEnforcePrefix: true)
        } else {
            await switchAccounts(recoveryKey: recoveryKey)
            managementDialogModel.endFlow()
        }
        PixelKit.fire(DebugEvent(GeneralPixel.syncLoginExistingAccountError(error: SyncError.accountAlreadyExists)))
    }

    private func sendCodeRecognisedPixel(setupSource: SyncSetupSource, codeSource: SyncCodeSource, codeVersion: SyncSetupCodeVersion) {
        guard case .pastedCode = codeSource else {
            // Others not supported by macOS
            return
        }
        guard setupSource != .unknown else { return }
        PixelKit.fire(SyncSetupPixelKitEvent.syncSetupManualCodeEnteredSuccess(setupSource,
                                                                               flowVersion: syncSetupFlowVersion,
                                                                               codeVersion: codeVersion.rawValue),
                      doNotEnforcePrefix: true)
    }

    private func sendCodeParsingFailedPixel(setupRole: SyncSetupRole, reason: String?) {
        guard case .receiver(let setupSource, let codeSource) = setupRole, case .pastedCode = codeSource else {
            return
        }
        PixelKit.fire(SyncSetupPixelKitEvent.syncSetupManualCodeEnteredFailed(setupSource, flowVersion: syncSetupFlowVersion, reason: reason), doNotEnforcePrefix: true)
    }

    private func sendSetupEndedFailedPixel(setupRole: SyncSetupRole, reason: String?, timeoutStage: String? = nil) {
        switch setupRole {
        case .receiver(let setupSource, _):
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedFailed(setupSource,
                                                                      flowVersion: syncSetupFlowVersion,
                                                                      peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                                                      myRole: setupSource.syncSetupMyRole,
                                                                      reason: reason,
                                                                      timeoutStage: timeoutStage),
                          doNotEnforcePrefix: true)
        case .sharer:
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedFailed(.exchange,
                                                                      flowVersion: syncSetupFlowVersion,
                                                                      peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                                                      myRole: SyncSetupPixelKitEvent.ParameterValue.host,
                                                                      reason: reason,
                                                                      timeoutStage: timeoutStage),
                          doNotEnforcePrefix: true)
        }
        pairingV2PeerKind = nil
    }

    private func sendSetupEndedAbandonedPixel(setupRole: SyncSetupRole, reason: String?) {
        switch setupRole {
        case .receiver(let setupSource, _):
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedAbandoned(setupSource, flowVersion: syncSetupFlowVersion, reason: reason), doNotEnforcePrefix: true)
        case .sharer:
            PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedAbandoned(.exchange, flowVersion: syncSetupFlowVersion, reason: reason), doNotEnforcePrefix: true)
        }
        pairingV2PeerKind = nil
    }

    private func sendSetupEndedSuccessfullyPixel(setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        guard case .pastedCode = codeSource else {
            // Others not supported by macOS
            return
        }
        guard setupSource != .unknown else { return }
        PixelKit.fire(SyncSetupPixelKitEvent.syncSetupEndedSuccessful(setupSource,
                                                                      flowVersion: syncSetupFlowVersion,
                                                                      peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                                                      myRole: setupSource.syncSetupMyRole),
                      doNotEnforcePrefix: true)
        pairingV2PeerKind = nil
    }

    private var syncSetupFlowVersion: String {
        featureFlagger.isFeatureOn(.syncCanUseV2ConnectFlow) ? SyncSetupPixelKitEvent.ParameterValue.v2 : SyncSetupPixelKitEvent.ParameterValue.v1
    }

    private func syncSetupSource(for code: String, dialog: ManagementDialogKind, sourceHint: SyncSetupSource?) -> SyncSetupSource? {
        let decodedCode: SyncCode?
        if let url = URL(string: code), PairingInfo.isPairingV2URL(url) {
            return sourceHint ?? .exchange
        } else if let url = URL(string: code), let pairingInfo = PairingInfo(url: url) {
            decodedCode = try? SyncCode.decodeBase64String(pairingInfo.base64Code)
        } else {
            decodedCode = try? SyncCode.decodeBase64String(code)
        }

        guard let decodedCode else {
            return nil
        }
        if decodedCode.connect != nil {
            return .connect
        }
        if decodedCode.exchangeKey != nil {
            return .exchange
        }
        if decodedCode.recovery != nil {
            switch dialog {
            case .syncWithAnotherDevice:
                return .exchange
            case .enterRecoveryCode:
                return .recovery
            default:
                return nil
            }
        }
        return nil
    }

    private func showPairingV2Confirmation(message: String) async -> Bool {
        let alert = NSAlert.syncPairingV2Confirmation(message: message)

        guard let parentWindow = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window else {
            return await alert.runModal() == .alertFirstButtonReturn
        }

        let presentationWindow = parentWindow.attachedSheet ?? parentWindow
        return await alert.beginSheetModal(for: presentationWindow) == .alertFirstButtonReturn
    }
}

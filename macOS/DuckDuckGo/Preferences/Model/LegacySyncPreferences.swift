//
//  LegacySyncPreferences.swift
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

import AppKit
import Foundation
import DDGSync
import Combine
import CombineExtensions
import DesignResourcesKit
import Common
import FoundationExtensions
import SystemConfiguration
import SyncUI_macOS
import SwiftUI
import PDFKit
import Navigation
import PixelKit
import os.log
import PrivacyConfig

final class LegacySyncPreferences: ObservableObject, SyncUI_macOS.ManagementViewModel {

    var syncPausedTitle: String? {
        return syncPausedStateManager.syncPausedMessageData?.title
    }

    var syncPausedMessage: String? {
        return syncPausedStateManager.syncPausedMessageData?.description
    }

    var syncPausedButtonTitle: String? {
        return syncPausedStateManager.syncPausedMessageData?.buttonTitle
    }

    var syncPausedButtonAction: (() -> Void)? {
        return syncPausedStateManager.syncPausedMessageData?.action
    }

    var syncBookmarksPausedTitle: String? {
        return syncPausedStateManager.syncBookmarksPausedMessageData?.title
    }

    var syncBookmarksPausedMessage: String? {
        return syncPausedStateManager.syncBookmarksPausedMessageData?.description
    }

    var syncBookmarksPausedButtonTitle: String? {
        return syncPausedStateManager.syncBookmarksPausedMessageData?.buttonTitle
    }

    var syncBookmarksPausedButtonAction: (() -> Void)? {
        return syncPausedStateManager.syncBookmarksPausedMessageData?.action
    }

    var syncCredentialsPausedTitle: String? {
        return syncPausedStateManager.syncCredentialsPausedMessageData?.title
    }

    var syncCredentialsPausedMessage: String? {
        return syncPausedStateManager.syncCredentialsPausedMessageData?.description
    }

    var syncCredentialsPausedButtonTitle: String? {
        return syncPausedStateManager.syncCredentialsPausedMessageData?.buttonTitle
    }

    var syncCredentialsPausedButtonAction: (() -> Void)? {
        return syncPausedStateManager.syncCredentialsPausedMessageData?.action
    }

    var syncCreditCardsPausedTitle: String? {
        return syncPausedStateManager.syncCreditCardsPausedMessageData?.title
    }

    var syncCreditCardsPausedMessage: String? {
        return syncPausedStateManager.syncCreditCardsPausedMessageData?.description
    }

    var syncCreditCardsPausedButtonTitle: String? {
        return syncPausedStateManager.syncCreditCardsPausedMessageData?.buttonTitle
    }

    var syncCreditCardsPausedButtonAction: (() -> Void)? {
        return syncPausedStateManager.syncCreditCardsPausedMessageData?.action
    }

    var syncIdentitiesPausedTitle: String? {
        return syncPausedStateManager.syncIdentitiesPausedMessageData?.title
    }

    var syncIdentitiesPausedMessage: String? {
        return syncPausedStateManager.syncIdentitiesPausedMessageData?.description
    }

    var syncIdentitiesPausedButtonTitle: String? {
        return syncPausedStateManager.syncIdentitiesPausedMessageData?.buttonTitle
    }

    var syncIdentitiesPausedButtonAction: (() -> Void)? {
        return syncPausedStateManager.syncIdentitiesPausedMessageData?.action
    }

    struct Consts {
        static let syncPausedStateChanged = Notification.Name("com.duckduckgo.app.SyncPausedStateChanged")
    }

    var isSyncEnabled: Bool {
        syncService.account != nil
    }

    @Published var stringForQR: String?
    @Published var codeForDisplayOrPasting: String?

    let managementDialogModel: ManagementDialogModel

    @Published var devices: [SyncDevice] = [] {
        didSet {
            syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding = devices.count > 1
        }
    }

    @Published var shouldShowErrorMessage: Bool = false
    @Published private(set) var syncErrorMessage: SyncErrorMessage?

    @Published var isCreatingAccount: Bool = false

    @Published var isFaviconsFetchingEnabled: Bool {
        didSet {
            syncBookmarksAdapter.isFaviconsFetchingEnabled = isFaviconsFetchingEnabled
            if isFaviconsFetchingEnabled {
                syncService.scheduler.notifyDataChanged()
            }
        }
    }

    @Published var isUnifiedFavoritesEnabled: Bool {
        didSet {
            appearancePreferences.favoritesDisplayMode = isUnifiedFavoritesEnabled ? .displayUnified(native: .desktop) : .displayNative(.desktop)
            if shouldRequestSyncOnFavoritesOptionChange {
                syncService.scheduler.notifyDataChanged()
            } else {
                shouldRequestSyncOnFavoritesOptionChange = true
            }
        }
    }

    @Published var isSyncPaused: Bool = false
    @Published var isSyncBookmarksPaused: Bool = false
    @Published var isSyncCredentialsPaused: Bool = false
    @Published var isSyncCreditCardsPaused: Bool = false
    @Published var isSyncIdentitiesPaused: Bool = false

    @Published var invalidBookmarksTitles: [String] = []
    @Published var invalidCredentialsTitles: [String] = []
    @Published var invalidCreditCardsTitles: [String] = []
    @Published var invalidIdentitiesTitles: [String] = []

    private var shouldRequestSyncOnFavoritesOptionChange: Bool = true
    private var isScreenLocked: Bool = false
    private var recoveryKey: SyncCode.RecoveryKey?

    @Published var syncFeatureFlags: SyncFeatureFlags {
        didSet {
            updateSyncFeatureFlags(syncFeatureFlags)
        }
    }

    @Published var isDataSyncingAvailable: Bool = true
    @Published var isConnectingDevicesAvailable: Bool = true
    @Published var isAccountCreationAvailable: Bool = true
    @Published var isAccountRecoveryAvailable: Bool = true
    @Published var isAppVersionNotSupported: Bool = true
    @Published var isAIChatSyncEnabled: Bool = false
    @Published var isAppRebranded: Bool = false

    private let syncPausedStateManager: any SyncPausedStateManaging

    private func updateSyncFeatureFlags(_ syncFeatureFlags: SyncFeatureFlags) {
        isDataSyncingAvailable = syncFeatureFlags.contains(.dataSyncing)
        isConnectingDevicesAvailable = syncFeatureFlags.contains(.connectFlows)
        isAccountCreationAvailable = syncFeatureFlags.contains(.accountCreation)
        isAccountRecoveryAvailable = syncFeatureFlags.contains(.accountRecovery)
        isAppVersionNotSupported = syncFeatureFlags.unavailableReason == .appVersionNotSupported
    }

    var recoveryCode: String? {
        syncService.recoveryCode
    }

    private let featureFlagger: FeatureFlagger

    private let diagnosisHelper: SyncDiagnosisHelper

    private static let defaultConnectionControllerFactory: (DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling = { syncService, delegate in
        syncService.createConnectionController(deviceName: deviceInfo().name, deviceType: deviceInfo().type, delegate: delegate)
    }
    private let connectionControllerFactory: (DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling
    private lazy var connectionController: SyncConnectionControlling = connectionControllerFactory(syncService, self)

    init(
        syncService: DDGSyncing,
        syncBookmarksAdapter: SyncBookmarksAdapter,
        syncCredentialsAdapter: SyncCredentialsAdapter,
        syncCreditCardsAdapter: SyncCreditCardsAdapter?,
        syncIdentitiesAdapter: SyncIdentitiesAdapter?,
        appearancePreferences: AppearancePreferences = NSApp.delegateTyped.appearancePreferences,
        managementDialogModel: ManagementDialogModel = ManagementDialogModel(),
        userAuthenticator: UserAuthenticating = DeviceAuthenticator.shared,
        syncPausedStateManager: any SyncPausedStateManaging,
        connectionControllerFactory: @escaping (DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling = LegacySyncPreferences.defaultConnectionControllerFactory,
        featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger
    ) {
        self.syncService = syncService
        self.syncBookmarksAdapter = syncBookmarksAdapter
        self.syncCredentialsAdapter = syncCredentialsAdapter
        self.syncCreditCardsAdapter = syncCreditCardsAdapter
        self.syncIdentitiesAdapter = syncIdentitiesAdapter
        self.appearancePreferences = appearancePreferences
        self.syncFeatureFlags = syncService.featureFlags
        self.userAuthenticator = userAuthenticator
        self.syncPausedStateManager = syncPausedStateManager
        self.connectionControllerFactory = connectionControllerFactory
        self.featureFlagger = featureFlagger

        self.isFaviconsFetchingEnabled = syncBookmarksAdapter.isFaviconsFetchingEnabled
        self.isUnifiedFavoritesEnabled = appearancePreferences.favoritesDisplayMode.isDisplayUnified

        self.managementDialogModel = managementDialogModel
        diagnosisHelper = SyncDiagnosisHelper(syncService: syncService)
        self.managementDialogModel.delegate = self

        self.isAppRebranded = DesignSystemRebrand.isAppRebranded()
        self.managementDialogModel.isAppRebranded = self.isAppRebranded

        updateSyncFeatureFlags(self.syncFeatureFlags)
        setUpObservables()
        setUpSyncOptionsObservables(apperancePreferences: appearancePreferences)
        updateSyncPausedState()
    }

    private func updateSyncPausedState() {
        self.isSyncPaused = syncPausedStateManager.isSyncPaused
        self.isSyncBookmarksPaused = syncPausedStateManager.isSyncBookmarksPaused
        self.isSyncCredentialsPaused = syncPausedStateManager.isSyncCredentialsPaused
        self.isSyncCreditCardsPaused = syncPausedStateManager.isSyncCreditCardsPaused
        self.isSyncIdentitiesPaused = syncPausedStateManager.isSyncIdentitiesPaused
    }

    private func updateInvalidObjects() {
        invalidBookmarksTitles = syncBookmarksAdapter.provider?
            .fetchDescriptionsForObjectsThatFailedValidation()
            .map { $0.truncated(to: 15, position: .tail) } ?? []

        let invalidCredentialsObjects: [String] = (try? syncCredentialsAdapter.provider?.fetchDescriptionsForObjectsThatFailedValidation()) ?? []
        invalidCredentialsTitles = invalidCredentialsObjects.map({ $0.truncated(to: 15, position: .tail) })

        if let syncCreditCardsAdapter = syncCreditCardsAdapter {
            let invalidCreditCardsObjects: [String] = (try? syncCreditCardsAdapter.provider?.fetchDescriptionsForObjectsThatFailedValidation()) ?? []
            invalidCreditCardsTitles = invalidCreditCardsObjects
        } else {
            invalidCreditCardsTitles = []
        }

        if let syncIdentitiesAdapter = syncIdentitiesAdapter {
            let invalidIdentitiesObjects: [String] = (try? syncIdentitiesAdapter.provider?.fetchDescriptionsForObjectsThatFailedValidation()) ?? []
            invalidIdentitiesTitles = invalidIdentitiesObjects
        } else {
            invalidIdentitiesTitles = []
        }
    }

    private func updateSingleDeviceSyncPromoVisibility() {
        let isFlagEnabled = featureFlagger.isFeatureOn(.allowSingleDeviceOnConnectScreen)
        let isSyncInactive = syncService.account == nil
        managementDialogModel.shouldShowSingleDeviceSyncPromoOnSyncWithAnotherDeviceScreen = isFlagEnabled && isSyncInactive
    }

    private func setUpObservables() {
        syncService.featureFlagsPublisher
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.syncFeatureFlags, onWeaklyHeld: self)
            .store(in: &cancellables)

        featureFlagger.updatesPublisher
            .prepend(())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                let isEnabled = self.featureFlagger.isFeatureOn(.aiChatSync)
                self.isAIChatSyncEnabled = isEnabled
                self.managementDialogModel.isAIChatSyncEnabled = isEnabled
                self.updateSingleDeviceSyncPromoVisibility()
            }
            .store(in: &cancellables)

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

        syncService.isSyncInProgressPublisher
            .removeDuplicates()
            .filter { !$0 }
            .asVoid()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateInvalidObjects()
            }
            .store(in: &cancellables)

        $syncErrorMessage
            .map { $0 != nil }
            .receive(on: DispatchQueue.main)
            .assign(to: \.shouldShowErrorMessage, onWeaklyHeld: self)
            .store(in: &cancellables)

        managementDialogModel.$currentDialog
            .removeDuplicates()
            .filter { $0 == nil }
            .asVoid()
            .sink { [weak self] _ in
                self?.onEndFlow()
            }
            .store(in: &cancellables)

        syncPausedStateManager.syncPausedChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSyncPausedState()
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

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(launchedFromSyncPromo(_:)),
                                               name: SyncPromoManager.SyncPromoManagerNotifications.didGoToSync,
                                               object: nil)
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
    func manageBookmarks() {
        guard let mainVC = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController else { return }
        mainVC.showManageBookmarks(self)
    }

    @MainActor
    func manageLogins() {
        guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else { return }
        let navigationViewController = parentWindowController.mainViewController.navigationBarViewController
        navigationViewController.showPasswordManagerPopover(selectedCategory: .allItems, source: .sync)
    }

    @MainActor
    func manageCreditCards() {
        guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else { return }
        let navigationViewController = parentWindowController.mainViewController.navigationBarViewController
        navigationViewController.showPasswordManagerPopover(selectedCategory: .cards, source: .sync)
    }

    @MainActor
    func manageIdentities() {
        guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else { return }
        let navigationViewController = parentWindowController.mainViewController.navigationBarViewController
        navigationViewController.showPasswordManagerPopover(selectedCategory: .identities, source: .sync)
    }

    private func setUpSyncOptionsObservables(apperancePreferences: AppearancePreferences) {
        syncBookmarksAdapter.$isFaviconsFetchingEnabled
            .removeDuplicates()
            .sink { [weak self] isFaviconsFetchingEnabled in
                guard let self else {
                    return
                }
                if self.isFaviconsFetchingEnabled != isFaviconsFetchingEnabled {
                    self.isFaviconsFetchingEnabled = isFaviconsFetchingEnabled
                }
            }
            .store(in: &cancellables)
        apperancePreferences.$favoritesDisplayMode
            .map(\.isDisplayUnified)
            .sink { [weak self] isUnifiedFavoritesEnabled in
                guard let self else {
                    return
                }
                if self.isUnifiedFavoritesEnabled != isUnifiedFavoritesEnabled {
                    self.shouldRequestSyncOnFavoritesOptionChange = false
                    self.isUnifiedFavoritesEnabled = isUnifiedFavoritesEnabled
                }
            }
            .store(in: &cancellables)

        apperancePreferences.$favoritesDisplayMode
            .map(\.isDisplayUnified)
            .sink { [weak self] isUnifiedFavoritesEnabled in
                guard let self else {
                    return
                }
                if self.isUnifiedFavoritesEnabled != isUnifiedFavoritesEnabled {
                    self.shouldRequestSyncOnFavoritesOptionChange = false
                    self.isUnifiedFavoritesEnabled = isUnifiedFavoritesEnabled
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Private

    @MainActor
    private func mapDevices(_ registeredDevices: [RegisteredDevice]) {
        guard let deviceId = syncService.account?.deviceId else { return }
        self.devices = registeredDevices.map {
            deviceId == $0.id ? SyncDevice(kind: .current, name: $0.name, id: $0.id) : SyncDevice($0)
        }.sorted(by: { item, _ in
            item.isCurrent
        })
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
                    // Ruling this out as it's a predictable event likely caused by disabling on another device
                    diagnosisHelper.didManuallyDisableSync()
                }
                PixelKit.fire(DebugEvent(GeneralPixel.syncRefreshDevicesError(error: error), error: error))
                Logger.sync.debug("Failed to refresh devices: \(error)")
            }
        }
    }

    @MainActor
    private func presentDialog(for currentDialog: ManagementDialogKind) {
        let shouldBeginSheet = managementDialogModel.currentDialog == nil
        managementDialogModel.currentDialog = currentDialog

        guard shouldBeginSheet else {
            return
        }

        guard [AppVersion.AppRunType.normal, .uiTests].contains(AppVersion.runType) else {
            return
        }

        let syncViewController = LegacySyncManagementDialogViewController(managementDialogModel)
        let syncWindowController = syncViewController.wrappedInWindowController()

        guard let syncWindow = syncWindowController.window,
              let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController
        else {
            assertionFailure("Sync: Failed to present LegacySyncManagementDialogViewController")
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

    @objc
    private func launchedFromSyncPromo(_ sender: Notification) {
        syncPromoSource = sender.userInfo?[SyncPromoManager.Constants.syncPromoSourceKey] as? String
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

    private var onEndFlow: () -> Void = {}

    private let syncService: DDGSyncing
    private let syncBookmarksAdapter: SyncBookmarksAdapter
    private let syncCredentialsAdapter: SyncCredentialsAdapter
    private let syncCreditCardsAdapter: SyncCreditCardsAdapter?
    private let syncIdentitiesAdapter: SyncIdentitiesAdapter?
    private let appearancePreferences: AppearancePreferences
    private var cancellables = Set<AnyCancellable>()
    private var connector: RemoteConnecting?
    private let userAuthenticator: UserAuthenticating
    private var syncPromoSource: String?
    private var pairingV2PeerKind: PairingV2DeviceKind?
    private var displayedCodeSetupSource: SyncSetupSource?
}

extension LegacySyncPreferences: ManagementDialogModelDelegate {
    func didEndFlow() {
        // no-op
    }

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
                    // Ruling this out as it's a predictable event likely caused by disabling on another device
                    diagnosisHelper.didManuallyDisableSync()
                }
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToUpdateDeviceName, description: error.localizedDescription)
                PixelKit.fire(DebugEvent(GeneralPixel.syncUpdateDeviceError(error: error)))
            }
            syncService.scheduler.resumeSyncQueue()
        }
    }

    static private func deviceInfo() -> (name: String, type: String) {
        let hostname = SCDynamicStoreCopyComputerName(nil, nil) as? String ?? ProcessInfo.processInfo.hostName
        return (name: hostname, type: "desktop")
    }

    @MainActor
    private func loginAndShowPresentedDialog(_ recoveryKey: SyncCode.RecoveryKey, isRecovery: Bool) async throws {
        let device = Self.deviceInfo()
        let devices = try await syncService.login(recoveryKey, deviceName: device.name, deviceType: device.type)
        mapDevices(devices)
        PixelKit.fire(GeneralPixel.syncLogin)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if isRecovery {
                self.showDevicesSynced()
            } else {
                self.presentDialog(for: .saveRecoveryCode(self.recoveryCode ?? ""))
            }
            self.stopPollingForRecoveryKey()
        }
    }

    func turnOnSync() {
        Task { @MainActor in
            managementDialogModel.endFlow()
            isCreatingAccount = true
            defer {
                isCreatingAccount = false
            }
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

    func startPollingForRecoveryKey(isRecovery: Bool) {
        newStartPollingForRecoveryKey(isRecovery: isRecovery)
    }

    private func newStartPollingForRecoveryKey(isRecovery: Bool) {
        pairingV2PeerKind = nil
        Task { @MainActor in
            do {
                let pairingInfo = try await connectionController.startConnectMode()
                let codeForDisplayOrPasting = pairingInfo.base64Code
                let stringForQR = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
                self.codeForDisplayOrPasting = codeForDisplayOrPasting
                self.stringForQR = featureFlagger.isFeatureOn(.syncSetupBarcodeIsUrlBased) ? pairingInfo.url.absoluteString : pairingInfo.base64Code
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

    func stopPollingForRecoveryKey() {
        self.connector?.stopPolling()
        self.connector = nil
    }

    func recoverDevice(recoveryCode: String, fromRecoveryScreen: Bool, codeSource: SyncCodeSource) {
        Task {
            await connectionController.syncCodeEntered(code: recoveryCode, canScanLegacyURLBarcodes: featureFlagger.isFeatureOn(.canScanUrlBasedSyncSetupBarcodes), codeSource: codeSource)
        }
    }

    @MainActor
    func presentDeleteAccount() {
        presentDialog(for: .deleteAccount(devices))
    }

    @MainActor
    func saveRecoveryPDF() {
        guard let recoveryCode = syncService.recoveryCode else {
            assertionFailure()
            return
        }

        Task { @MainActor in
            let authenticationResult = await userAuthenticator.authenticateUser(reason: .syncSettings)
            guard authenticationResult.authenticated else {
                if authenticationResult == .noAuthAvailable {
                    presentDialog(for: .empty)
                    managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToAuthenticateOnDevice)
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

    @MainActor
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

    @MainActor
    func enterRecoveryCodePressed() {
        startPollingForRecoveryKey(isRecovery: true)
    }

    @MainActor
    func syncWithAnotherDevicePressed() async {
        let authenticationResult = await userAuthenticator.authenticateUser(reason: .syncSettings)
        guard authenticationResult.authenticated else {
            if authenticationResult == .noAuthAvailable {
                presentDialog(for: .empty)
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToAuthenticateOnDevice)
            }
            return
        }
        if isSyncEnabled {
            self.startExchangeOrRecovery()
        } else {
            self.startPollingForRecoveryKey(isRecovery: false)
        }
    }

    @MainActor
    func syncWithServerPressed() async {
        let authenticationResult = await userAuthenticator.authenticateUser(reason: .syncSettings)
        guard authenticationResult.authenticated else {
            if authenticationResult == .noAuthAvailable {
                presentDialog(for: .empty)
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToAuthenticateOnDevice)
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
                managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToAuthenticateOnDevice)
            }
            return
        }
        presentDialog(for: .recoverSyncedData)
    }

    @MainActor
    func copyCode() {
        var code: String?
        code = codeForDisplayOrPasting ?? recoveryCode
        guard let code else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(code, forType: .string)
        fireCodeCopiedPixel(code: code, sourceHint: displayedCodeSetupSource)
    }

    @MainActor
    func recoveryCodeNextPressed() {
        showDevicesSynced()
    }

    @MainActor
    func openSystemPasswordSettings() {
        NSWorkspace.shared.open(URL.touchIDAndPassword)
    }

    @MainActor
    private func showDevicesSynced() {
        presentDialog(for: .nowSyncing)
    }

    func recoveryCodePasted(_ code: String) {
        recoverDevice(recoveryCode: code, fromRecoveryScreen: true, codeSource: .pastedCode)
    }

    func recoveryCodePasted(_ code: String, fromRecoveryScreen: Bool) {
        recoverDevice(recoveryCode: code, fromRecoveryScreen: fromRecoveryScreen, codeSource: .pastedCode)
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
            await presentDialog(for: .syncWithAnotherDevice(codeForDisplayOrPasting: recoveryCode, stringForQRCode: recoveryCode))
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

    @MainActor
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

    private func handleError(_ syncErrorType: SyncErrorType, error: Error?, pixelEvent: PixelKitEvent?) {
        managementDialogModel.syncErrorMessage = SyncErrorMessage(type: syncErrorType)
        if let pixelEvent {
            PixelKit.fire(DebugEvent(pixelEvent, error: error))
        }
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
}

@MainActor
extension LegacySyncPreferences: SyncConnectionControllerDelegate {

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
        self.$devices
            .removeDuplicates()
            .dropFirst()
            .prefix(1)
            .sink { [weak self] _ in
                guard let self,
                      let code = recoveryCode else { return }
                self.presentDialog(for: .saveRecoveryCode(code))
            }.store(in: &cancellables)
    }

    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool, setupRole: SyncSetupRole) {
        self.codeForDisplayOrPasting = self.recoveryCode
        self.stringForQR = self.recoveryCode
        mapDevices(registeredDevices)
        PixelKit.fire(GeneralPixel.syncLogin)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.presentDialog(for: .saveRecoveryCode(self.recoveryCode ?? ""))
            self.stopPollingForRecoveryKey()
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
            handleError(.unableToRecognizeCode, error: underlyingError, pixelEvent: nil)
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
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            handleError(.unableToSyncToOtherDevice, error: underlyingError, pixelEvent: GeneralPixel.syncLoginError(error: underlyingError ?? error))
        case .failedToTransmitExchangeRecoveryKey:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            handleError(.unableToSyncToOtherDevice, error: underlyingError, pixelEvent: GeneralPixel.syncLoginError(error: underlyingError ?? error))
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
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            handleError(.unableToSyncToOtherDevice, error: underlyingError, pixelEvent: GeneralPixel.syncLoginError(error: underlyingError ?? error))
        case .failedToCreateAccount:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            handleError(.unableToSyncToOtherDevice, error: underlyingError, pixelEvent: GeneralPixel.syncSignupError(error: underlyingError ?? error))
        case .accountCreationFailed:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            handleError(.unableToSyncToOtherDevice, error: underlyingError, pixelEvent: GeneralPixel.syncSignupError(error: underlyingError ?? error))
        case .pollingForRecoveryKeyTimedOut:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice)
        case .pairingV2SessionTimedOut:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason, timeoutStage: error.syncSetupTimeoutStage)
            managementDialogModel.syncErrorMessage = SyncErrorMessage(type: .unableToSyncToOtherDevice)
        }
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

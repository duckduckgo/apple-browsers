//
//  SyncPreferences.swift
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
import PDFKit
import Navigation
import PixelKit
import os.log
import BrowserServicesKit

extension SyncDevice {
    init(_ account: SyncAccount) {
        self.init(kind: .current, name: account.deviceName, id: account.deviceId)
    }

    init(_ device: RegisteredDevice) {
        let kind: Kind = device.type == "desktop" ? .desktop : .mobile
        self.init(kind: kind, name: device.name, id: device.id)
    }
}

final class SyncPreferences: ObservableObject, SyncUI_macOS.ManagementViewModel {

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

    struct Consts {
        static let syncPausedStateChanged = Notification.Name("com.duckduckgo.app.SyncPausedStateChanged")
    }

    var isSyncEnabled: Bool {
        syncService.account != nil
    }

    @Published var devices: [SyncDevice] = [] {
        didSet {
            syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding = devices.count > 1
        }
    }

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

    @Published var invalidBookmarksTitles: [String] = []
    @Published var invalidCredentialsTitles: [String] = []

    private var shouldRequestSyncOnFavoritesOptionChange: Bool = true
    private var isScreenLocked: Bool = false

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

    private let syncPausedStateManager: any SyncPausedStateManaging
    private let syncDialogController: SyncDialogController

    private func updateSyncFeatureFlags(_ syncFeatureFlags: SyncFeatureFlags) {
        isDataSyncingAvailable = syncFeatureFlags.contains(.dataSyncing)
        isConnectingDevicesAvailable = syncFeatureFlags.contains(.connectFlows)
        isAccountCreationAvailable = syncFeatureFlags.contains(.accountCreation)
        isAccountRecoveryAvailable = syncFeatureFlags.contains(.accountRecovery)
        isAppVersionNotSupported = syncFeatureFlags.unavailableReason == .appVersionNotSupported
    }

    private let diagnosisHelper: SyncDiagnosisHelper

    init(
        syncService: DDGSyncing,
        syncBookmarksAdapter: SyncBookmarksAdapter,
        syncCredentialsAdapter: SyncCredentialsAdapter,
        appearancePreferences: AppearancePreferences = NSApp.delegateTyped.appearancePreferences,
        userAuthenticator: UserAuthenticating = DeviceAuthenticator.shared,
        syncPausedStateManager: any SyncPausedStateManaging,
        featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger
    ) {
        self.syncService = syncService
        self.syncBookmarksAdapter = syncBookmarksAdapter
        self.syncCredentialsAdapter = syncCredentialsAdapter
        self.appearancePreferences = appearancePreferences
        self.syncFeatureFlags = syncService.featureFlags
        self.syncPausedStateManager = syncPausedStateManager

        self.isFaviconsFetchingEnabled = syncBookmarksAdapter.isFaviconsFetchingEnabled
        self.isUnifiedFavoritesEnabled = appearancePreferences.favoritesDisplayMode.isDisplayUnified

        // Create SyncDialogController with the same dependencies
        // Using unsafeCreateSync to avoid MainActor isolation issues in init
        self.syncDialogController = SyncDialogController(
            syncService: syncService,
            syncBookmarksAdapter: syncBookmarksAdapter,
            syncCredentialsAdapter: syncCredentialsAdapter,
            userAuthenticator: userAuthenticator,
            syncPausedStateManager: syncPausedStateManager,
            featureFlagger: featureFlagger
        )

        diagnosisHelper = SyncDiagnosisHelper(syncService: syncService)

        Task { @MainActor in
            // Set up devices provider for dialog controller
            self.syncDialogController.devicesProvider = { [weak self] in
                return self?.devices ?? []
            }
        }

        updateSyncFeatureFlags(self.syncFeatureFlags)
        setUpObservables()
        setUpSyncOptionsObservables(apperancePreferences: appearancePreferences)
        updateSyncPausedState()
    }

    private func updateSyncPausedState() {
        self.isSyncPaused = syncPausedStateManager.isSyncPaused
        self.isSyncBookmarksPaused = syncPausedStateManager.isSyncBookmarksPaused
        self.isSyncCredentialsPaused = syncPausedStateManager.isSyncCredentialsPaused
    }

    private func updateInvalidObjects() {
        invalidBookmarksTitles = syncBookmarksAdapter.provider?
            .fetchDescriptionsForObjectsThatFailedValidation()
            .map { $0.truncated(length: 15) } ?? []

        let invalidCredentialsObjects: [String] = (try? syncCredentialsAdapter.provider?.fetchDescriptionsForObjectsThatFailedValidation()) ?? []
        invalidCredentialsTitles = invalidCredentialsObjects.map({ $0.truncated(length: 15) })
    }

    private func setUpObservables() {
        syncService.featureFlagsPublisher
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.syncFeatureFlags, onWeaklyHeld: self)
            .store(in: &cancellables)

        syncService.authStatePublisher
            .removeDuplicates()
            .asVoid()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshDevices()
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

    @objc @MainActor
    private func launchedFromSyncPromo(_ sender: Notification) {
        // Pass through to dialog controller
        syncDialogController.launchedFromSyncPromo(sender)
    }

    // MARK: - Public API (Delegation to SyncDialogController)

    @MainActor
    func turnOnSync() {
        syncDialogController.turnOnSync()
    }

    @MainActor
    func turnOffSyncPressed() {
        syncDialogController.presentDialog(for: .turnOffSync)
    }

    @MainActor
    func presentDeviceDetails(_ device: SyncDevice) {
        syncDialogController.presentDialog(for: .deviceDetails(device))
    }

    @MainActor
    func presentRemoveDevice(_ device: SyncDevice) {
        syncDialogController.presentDialog(for: .removeDevice(device))
    }

    @MainActor
    func presentDeleteAccount() {
        syncDialogController.presentDeleteAccount()
    }

    @MainActor
    func syncWithAnotherDevicePressed() async {
        await syncDialogController.syncWithAnotherDevicePressed()
    }

    @MainActor
    func syncWithServerPressed() async {
        await syncDialogController.syncWithServerPressed()
    }

    @MainActor
    func recoverDataPressed() async {
        await syncDialogController.recoverDataPressed()
    }

    @MainActor
    func saveRecoveryPDF() {
        syncDialogController.saveRecoveryPDF()
    }

    private let syncService: DDGSyncing
    private let syncBookmarksAdapter: SyncBookmarksAdapter
    private let syncCredentialsAdapter: SyncCredentialsAdapter
    private let appearancePreferences: AppearancePreferences
    private var cancellables = Set<AnyCancellable>()
}

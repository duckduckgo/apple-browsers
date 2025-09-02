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

/// View model for sync preferences and device management.
///
/// Manages sync-related preferences, device lists, sync feature flags, and coordinates
/// various sync operations. Acts as the main interface between the sync preferences UI
/// and the underlying sync services.
@MainActor
final class SyncPreferences: ObservableObject, SyncUI_macOS.ManagementViewModel {
    @Published var devices: [SyncDevice] = [] {
        didSet {
            syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding = devices.count > 1
        }
    }

    /// Refreshes the list of connected sync devices
    func refreshDevices() {
        syncSettingsHandler.refreshDevices()
    }

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
    let syncSettingsHandler: SyncSettingsViewHandling

    private func updateSyncFeatureFlags(_ syncFeatureFlags: SyncFeatureFlags) {
        isDataSyncingAvailable = syncFeatureFlags.contains(.dataSyncing)
        isConnectingDevicesAvailable = syncFeatureFlags.contains(.connectFlows)
        isAccountCreationAvailable = syncFeatureFlags.contains(.accountCreation)
        isAccountRecoveryAvailable = syncFeatureFlags.contains(.accountRecovery)
        isAppVersionNotSupported = syncFeatureFlags.unavailableReason == .appVersionNotSupported
    }

    private let syncService: DDGSyncing
    private let syncBookmarksAdapter: SyncBookmarksAdapter
    private let syncCredentialsAdapter: SyncCredentialsAdapter
    private let appearancePreferences: AppearancePreferences
    private var cancellables = Set<AnyCancellable>()

    private let diagnosisHelper: SyncDiagnosisHelper

    init(
        syncService: DDGSyncing,
        syncBookmarksAdapter: SyncBookmarksAdapter,
        syncCredentialsAdapter: SyncCredentialsAdapter,
        appearancePreferences: AppearancePreferences = NSApp.delegateTyped.appearancePreferences,
        userAuthenticator: UserAuthenticating = DeviceAuthenticator.shared,
        syncPausedStateManager: any SyncPausedStateManaging,
        connectionControllerFactory: ((DDGSyncing, SyncConnectionControllerDelegate) -> SyncConnectionControlling)? = nil,
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

        self.syncSettingsHandler = DeviceSyncCoordinator(syncService: syncService, syncPausedStateManager: syncPausedStateManager)

        diagnosisHelper = SyncDiagnosisHelper(syncService: syncService)

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

        syncSettingsHandler.devicesPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.devices, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    /// Presents the bookmarks management interface
    @MainActor
    func manageBookmarks() {
        guard let mainVC = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController else { return }
        mainVC.showManageBookmarks(self)
    }

    /// Presents the password manager interface for managing login credentials
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

    // MARK: - Delegation to syncSettingsHandler

    @MainActor
    func turnOffSyncPressed() {
        syncSettingsHandler.turnOffSyncPressed()
    }

    @MainActor
    func presentDeviceDetails(_ device: SyncDevice) {
        syncSettingsHandler.presentDeviceDetails(device)
    }

    @MainActor
    func presentRemoveDevice(_ device: SyncDevice) {
        syncSettingsHandler.presentRemoveDevice(device)
    }

    @MainActor
    func presentDeleteAccount() {
        syncSettingsHandler.presentDeleteAccount()
    }

    @MainActor
    func syncWithAnotherDevicePressed() async {
        await syncSettingsHandler.syncWithAnotherDevicePressed(source: nil)
    }

    @MainActor
    func syncWithServerPressed() async {
        await syncSettingsHandler.syncWithServerPressed()
    }

    @MainActor
    func recoverDataPressed() async {
        await syncSettingsHandler.recoverDataPressed()
    }

    @MainActor
    func saveRecoveryPDF() {
        syncSettingsHandler.saveRecoveryPDF()
    }
}

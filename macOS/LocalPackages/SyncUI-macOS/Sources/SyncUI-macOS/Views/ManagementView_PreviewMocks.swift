//
//  ManagementView_PreviewMocks.swift
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

#if DEBUG
import Combine

@MainActor
final class PreviewManagementViewModel: ManagementViewModel {
    let isDataSyncingAvailable: Bool
    let isConnectingDevicesAvailable: Bool
    let isAccountCreationAvailable: Bool
    let isAccountRecoveryAvailable = true
    let isAppVersionNotSupported: Bool
    let isAIChatSyncEnabled = true
    let isAppRebranded = true
    let isSimplifiedSyncSetupV2Enabled: Bool

    let isSyncEnabled: Bool
    let isSyncPaused: Bool
    let isSyncBookmarksPaused = false
    let isSyncCredentialsPaused = false
    let isSyncCreditCardsPaused = false
    let isSyncIdentitiesPaused = false
    let syncPausedTitle: String?
    let syncPausedMessage: String?
    let syncPausedButtonTitle: String?
    let syncPausedButtonAction: (() -> Void)? = nil
    let syncBookmarksPausedTitle: String? = nil
    let syncBookmarksPausedMessage: String? = nil
    let syncBookmarksPausedButtonTitle: String? = nil
    let syncBookmarksPausedButtonAction: (() -> Void)? = nil
    let syncCredentialsPausedTitle: String? = nil
    let syncCredentialsPausedMessage: String? = nil
    let syncCredentialsPausedButtonTitle: String? = nil
    let syncCredentialsPausedButtonAction: (() -> Void)? = nil
    let syncCreditCardsPausedTitle: String? = nil
    let syncCreditCardsPausedMessage: String? = nil
    let syncCreditCardsPausedButtonTitle: String? = nil
    let syncCreditCardsPausedButtonAction: (() -> Void)? = nil
    let syncIdentitiesPausedTitle: String? = nil
    let syncIdentitiesPausedMessage: String? = nil
    let syncIdentitiesPausedButtonTitle: String? = nil
    let syncIdentitiesPausedButtonAction: (() -> Void)? = nil

    let invalidBookmarksTitles: [String] = []
    let invalidCredentialsTitles: [String] = []
    let invalidCreditCardsTitles: [String] = []
    let invalidIdentitiesTitles: [String] = []

    let devices: [SyncDevice]
    @Published var isFaviconsFetchingEnabled = true
    @Published var isUnifiedFavoritesEnabled = true

    init(
        isSyncEnabled: Bool,
        isSyncPaused: Bool = false,
        syncPausedTitle: String? = nil,
        syncPausedMessage: String? = nil,
        syncPausedButtonTitle: String? = nil,
        isSimplifiedSyncSetupV2Enabled: Bool = false,
        isDataSyncingAvailable: Bool = true,
        isConnectingDevicesAvailable: Bool = true,
        isAccountCreationAvailable: Bool = true,
        isAppVersionNotSupported: Bool = false,
        devices: [SyncDevice] = []
    ) {
        self.isSyncEnabled = isSyncEnabled
        self.isSyncPaused = isSyncPaused
        self.syncPausedTitle = syncPausedTitle
        self.syncPausedMessage = syncPausedMessage
        self.syncPausedButtonTitle = syncPausedButtonTitle
        self.isSimplifiedSyncSetupV2Enabled = isSimplifiedSyncSetupV2Enabled
        self.isDataSyncingAvailable = isDataSyncingAvailable
        self.isConnectingDevicesAvailable = isConnectingDevicesAvailable
        self.isAccountCreationAvailable = isAccountCreationAvailable
        self.isAppVersionNotSupported = isAppVersionNotSupported
        self.devices = devices
    }

    func presentDeleteAccount() {}
    func presentDeviceDetails(_ device: SyncDevice) {}
    func presentRemoveDevice(_ device: SyncDevice) {}
    func saveRecoveryPDF() {}
    func refreshDevices() {}
    func manageBookmarks() {}
    func manageLogins() {}
    func manageCreditCards() {}
    func manageIdentities() {}
    func syncWithAnotherDevicePressed() async {}
    func syncWithServerPressed() async {}
    func recoverDataPressed() async {}
    func turnOffSyncPressed() {}
}

extension PreviewManagementViewModel {
    static let disabled = PreviewManagementViewModel(
        isSyncEnabled: false,
        isSimplifiedSyncSetupV2Enabled: true,
        devices: previewDevices
    )

    static let enabled = PreviewManagementViewModel(
        isSyncEnabled: true,
        isSimplifiedSyncSetupV2Enabled: true,
        devices: previewDevices
    )

    static let syncPaused = PreviewManagementViewModel(
        isSyncEnabled: true,
        isSyncPaused: true,
        syncPausedTitle: "Sync & Backup is Paused",
        syncPausedMessage: "Your data is not currently syncing. Try again to resume Sync & Backup.",
        syncPausedButtonTitle: "Try Again",
        isSimplifiedSyncSetupV2Enabled: true,
        devices: [SyncDevice(kind: .current, name: "My Mac", id: "current-device")]
    )

    static let enabledSingleDevice = PreviewManagementViewModel(
        isSyncEnabled: true,
        isSimplifiedSyncSetupV2Enabled: true,
        devices: [SyncDevice(kind: .current, name: "My Mac", id: "current-device")]
    )

    static let enabledLoadingDevices = PreviewManagementViewModel(
        isSyncEnabled: true,
        isSimplifiedSyncSetupV2Enabled: true,
        devices: []
    )

    static let enabledSyncUnavailable = PreviewManagementViewModel(
        isSyncEnabled: true,
        isSimplifiedSyncSetupV2Enabled: true,
        isDataSyncingAvailable: false,
        isConnectingDevicesAvailable: false,
        isAccountCreationAvailable: false,
        devices: previewDevices
    )

    static let enabledUpgradeRequired = PreviewManagementViewModel(
        isSyncEnabled: true,
        isSimplifiedSyncSetupV2Enabled: true,
        isDataSyncingAvailable: false,
        isConnectingDevicesAvailable: false,
        isAccountCreationAvailable: false,
        isAppVersionNotSupported: true,
        devices: previewDevices
    )

    private static let previewDevices = [
        SyncDevice(kind: .current, name: "My Mac", id: "current-device"),
        SyncDevice(kind: .desktop, name: "MacBook Pro", id: "desktop-device"),
        SyncDevice(kind: .mobile, name: "iPhone", id: "mobile-device"),
        SyncDevice(kind: .mobile, name: "Android", id: "third-party-device")
    ]
}
#endif

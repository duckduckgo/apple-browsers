//
//  SyncSettingsViewControllerPixelTests.swift
//  DuckDuckGo
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

import Testing
import Foundation
import Core
import FeatureFlags_iOS
@testable import DuckDuckGo
@testable import DDGSync
import Persistence
import Common
import FoundationExtensions
import SyncUI_iOS
import SecureStorage
@_spi(Testing) import PixelKit

@Suite("Sync Settings scan-flow pixels", .serialized)
@MainActor
final class SyncSettingsViewControllerPixelTests {

    private let ddgSyncing: MockDDGSyncing
    private let syncBookmarksAdapter: SyncBookmarksAdapter
    private let syncCredentialsAdapter: SyncCredentialsAdapter
    private let syncCreditCardsAdapter: SyncCreditCardsAdapter
    private let syncPausedStateManager: CapturingSyncPausedStateManager
    private let syncAutoRestoreHandler: MockSyncAutoRestoreHandler
    private let pixelKitMock = PixelKitMock()

    init() throws {
        let bundle = DDGSync.bundle
        let model = try #require(CoreDataDatabase.loadModel(from: bundle, named: "SyncMetadata"))
        let database = CoreDataDatabase(name: "",
                                        containerLocation: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                        model: model,
                                        readOnly: true,
                                        options: [:])
        ddgSyncing = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        syncBookmarksAdapter = SyncBookmarksAdapter(
            database: database,
            favoritesDisplayModeStorage: MockFavoritesDisplayModeStoring(),
            syncErrorHandler: CapturingAdapterErrorHandler(),
            faviconStoring: MockFaviconStore())
        syncCredentialsAdapter = SyncCredentialsAdapter(
            secureVaultErrorReporter: MockSecureVaultReporting(),
            syncErrorHandler: CapturingAdapterErrorHandler(),
            tld: TLD())
        syncCreditCardsAdapter = SyncCreditCardsAdapter(
            secureVaultErrorReporter: MockSecureVaultReporting(),
            syncErrorHandler: CapturingAdapterErrorHandler())
        syncPausedStateManager = CapturingSyncPausedStateManager()
        syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        syncAutoRestoreHandler.isAutoRestoreFeatureEnabled = true
    }

    @available(iOS 16, macOS 13, *)
    @Test("scanQRCodeScreenShown fires the scan-QR screen pixel", .timeLimit(.minutes(1)))
    func scanQRCodeScreenShownFiresScanQRScreenPixel() {
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [])

        vc.scanQRCodeScreenShown()

        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == Pixel.Event.syncSetupScanQRScreenShown.name &&
            $0.additionalParameters == [
                "source": "test_source",
                "my_kind": "ddg",
                "flow_version": "v1",
                "ui_version": "v2"
            ]
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("barcodeScreenShown fires the barcode screen pixel", .timeLimit(.minutes(1)))
    func barcodeScreenShownFiresBarcodeScreenPixel() {
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [])

        vc.barcodeScreenShown()

        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == Pixel.Event.syncSetupBarcodeScreenShown.name &&
            $0.additionalParameters == [
                "source": "test_source",
                "my_kind": "ddg",
                "flow_version": "v1",
                "ui_version": "v2"
            ]
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Another-device prompt dismissal fires the dismissed pixel", .timeLimit(.minutes(1)))
    func anotherDevicePromptDismissalFiresDismissedPixel() {
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [])

        vc.fireSyncSetupPixel(event: .anotherDevicePromptDismissed)

        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == Pixel.Event.settingsSyncAnotherDevicePromptDismissed.name &&
            $0.additionalParameters == ["ui_version": "v2"] &&
            $0.includeAppVersionParameter == true
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Device details events fire the matching device details pixel",
          .timeLimit(.minutes(1)),
          arguments: [
            (SyncSettingsViewModel.DeviceDetailsPixelEvent.thisDeviceScreenShown, "sync_settings_this_device_details_screen_shown"),
            (.thisDeviceTurnOffSyncTapped, "sync_settings_this_device_details_turn_off_sync_tapped"),
            (.otherDeviceScreenShown, "sync_settings_other_device_details_screen_shown"),
            (.otherDeviceRemoveDeviceTapped, "sync_settings_other_device_details_remove_device_tapped")
          ])
    func deviceDetailsEventFiresMatchingPixel(event: SyncSettingsViewModel.DeviceDetailsPixelEvent, expectedName: String) {
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])

        vc.fireDeviceDetailsPixel(event: event)

        #expect(pixelKitMock.actualFireCalls.count == 1)
        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == expectedName &&
            ($0.additionalParameters ?? [:]).isEmpty &&
            $0.includeAppVersionParameter == true
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Updating the device name fires the name updated pixel", .timeLimit(.minutes(1)))
    func updatingDeviceNameFiresNameUpdatedPixel() async throws {
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])

        vc.updateDeviceName("New Name")

        for _ in 0..<200 where pixelKitMock.actualFireCalls.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == SyncDeviceDetailsPixel.thisDeviceNameUpdated.name &&
            ($0.additionalParameters ?? [:]).isEmpty
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Removing another device fires the remove device confirmed pixel", .timeLimit(.minutes(1)))
    func removingDeviceFiresRemoveDeviceConfirmedPixel() async throws {
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])

        vc.removeDevice(.init(id: "2", name: "Mac", type: "desktop", isThisDevice: false))

        for _ in 0..<200 where pixelKitMock.actualFireCalls.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == SyncDeviceDetailsPixel.otherDeviceRemoveDeviceConfirmed.name &&
            ($0.additionalParameters ?? [:]).isEmpty
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed device removal does not fire the remove device confirmed pixel", .timeLimit(.minutes(1)))
    func failedDeviceRemovalDoesNotFireRemoveDeviceConfirmedPixel() async throws {
        ddgSyncing.disconnectDeviceError = SyncError.failedToLoadAccount
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])

        vc.removeDevice(.init(id: "2", name: "Mac", type: "desktop", isThisDevice: false))

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == SyncDeviceDetailsPixel.otherDeviceRemoveDeviceConfirmed.name
        })
    }

    private func makeViewController(source: String?, enabledFeatureFlags: [FeatureFlag]) -> SyncSettingsViewController {
        SyncSettingsViewController(
            syncService: ddgSyncing,
            syncBookmarksAdapter: syncBookmarksAdapter,
            syncCredentialsAdapter: syncCredentialsAdapter,
            syncCreditCardsAdapter: syncCreditCardsAdapter,
            syncPausedStateManager: syncPausedStateManager,
            source: source,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFeatureFlags),
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            pixelFiring: pixelKitMock
        )
    }
}

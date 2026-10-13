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
import AVFoundation

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
    private let cameraAuthorization = MockSyncCameraAuthorization()

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
        cameraAuthorization.authorizationStatus = .authorized
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [])

        vc.scanQRCodeScreenShown()

        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == Pixel.Event.syncSetupScanQRScreenShown.name &&
            $0.additionalParameters == [
                "source": "test_source",
                "my_kind": "ddg",
                "flow_version": "v1",
                "ui_version": "v2",
                "camera_permission": "authorized"
            ]
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("scanQRCodeScreenShown reports the camera permission",
          .timeLimit(.minutes(1)),
          arguments: [
            (AVAuthorizationStatus.authorized, "authorized"),
            (.notDetermined, "not_determined"),
            (.denied, "denied"),
            (.restricted, "denied")
          ])
    func scanQRCodeScreenShownReportsCameraPermission(status: AVAuthorizationStatus, expectedValue: String) {
        cameraAuthorization.authorizationStatus = status
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [])

        vc.scanQRCodeScreenShown()

        let call = pixelKitMock.actualFireCalls.first { $0.pixel.name == Pixel.Event.syncSetupScanQRScreenShown.name }
        #expect(call?.additionalParameters?["camera_permission"] == expectedValue)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Granting the camera prompt fires the authorized result and authorises the scanner", .timeLimit(.minutes(1)))
    func grantingCameraPromptFiresAuthorizedResult() async {
        cameraAuthorization.authorizationStatus = .notDetermined
        cameraAuthorization.requestAccessResult = true
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [])
        let model = makeScanModel()

        await vc.checkCameraPermission(model: model)

        #expect(cameraAuthorization.requestAccessCallCount == 1)
        #expect(model.videoPermission == .authorised)
        #expect(promptResultCalls().map(\.pixel.parameters) == [["result": "authorized"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Denying the camera prompt fires the denied result and shows the denied state", .timeLimit(.minutes(1)))
    func denyingCameraPromptFiresDeniedResult() async {
        cameraAuthorization.authorizationStatus = .notDetermined
        cameraAuthorization.requestAccessResult = false
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [])
        let model = makeScanModel()

        await vc.checkCameraPermission(model: model)

        #expect(cameraAuthorization.requestAccessCallCount == 1)
        #expect(model.videoPermission == .denied)
        #expect(promptResultCalls().map(\.pixel.parameters) == [["result": "denied"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A determined camera permission skips the prompt and its pixel",
          .timeLimit(.minutes(1)),
          arguments: [
            (AVAuthorizationStatus.authorized, ScanOrPasteCodeViewModel.VideoPermission.authorised),
            (.denied, .denied),
            (.restricted, .denied)
          ])
    func determinedCameraPermissionSkipsPrompt(status: AVAuthorizationStatus,
                                               expectedPermission: ScanOrPasteCodeViewModel.VideoPermission) async {
        cameraAuthorization.authorizationStatus = status
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [])
        let model = makeScanModel()

        await vc.checkCameraPermission(model: model)

        #expect(cameraAuthorization.requestAccessCallCount == 0)
        #expect(model.videoPermission == expectedPermission)
        #expect(promptResultCalls().isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A scanned code reports the camera permission from when the scan screen first opened", .timeLimit(.minutes(1)))
    func scannedCodeReportsCameraPermissionFromFirstScanScreen() {
        cameraAuthorization.authorizationStatus = .notDetermined
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])

        vc.scanQRCodeScreenShown()
        cameraAuthorization.authorizationStatus = .authorized
        vc.scanQRCodeScreenShown()
        vc.sendCodeRecognisedPixel(setupSource: .connect, codeSource: .qrCode, codeVersion: .v2)

        let call = pixelKitMock.actualFireCalls.first { $0.pixel.name == Pixel.Event.syncSetupBarcodeScannerSuccess.name }
        #expect(call?.additionalParameters?["camera_permission"] == "not_determined")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A scanned code omits the camera permission when the scan screen wasn't shown", .timeLimit(.minutes(1)))
    func scannedCodeOmitsCameraPermissionWithoutScanScreen() {
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])

        vc.sendCodeRecognisedPixel(setupSource: .connect, codeSource: .qrCode, codeVersion: .v2)

        let call = pixelKitMock.actualFireCalls.first { $0.pixel.name == Pixel.Event.syncSetupBarcodeScannerSuccess.name }
        #expect(call != nil)
        #expect(call?.additionalParameters?["camera_permission"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A pasted code doesn't report the camera permission", .timeLimit(.minutes(1)))
    func pastedCodeOmitsCameraPermission() {
        cameraAuthorization.authorizationStatus = .authorized
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])

        vc.scanQRCodeScreenShown()
        vc.sendCodeRecognisedPixel(setupSource: .connect, codeSource: .pastedCode, codeVersion: .v2)

        let call = pixelKitMock.actualFireCalls.first { $0.pixel.name == Pixel.Event.syncSetupManualCodeEnteredSuccess.name }
        #expect(call != nil)
        #expect(call?.additionalParameters?["camera_permission"] == nil)
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
    @Test("Turn off sheet events fire the matching turn off sheet pixel",
          .timeLimit(.minutes(1)),
          arguments: [
            (SyncSettingsViewModel.TurnOffSyncSheetPixelEvent.sheetShown, "sync_turn_off_sheet_shown", [String: String]?.none),
            (.optionSelected(.thisDevice), "sync_turn_off_option_selected", ["option": "this_device"]),
            (.optionSelected(.allDevicesAndServerData), "sync_turn_off_option_selected", ["option": "all_devices_and_server_data"]),
            (.deleteServerDataConfirmationConfirmed, "sync_delete_server_data_confirmation_confirmed", nil),
            (.deleteServerDataConfirmationDismissed, "sync_delete_server_data_confirmation_dismissed", nil)
          ])
    func turnOffSheetEventFiresMatchingPixel(event: SyncSettingsViewModel.TurnOffSyncSheetPixelEvent,
                                             expectedName: String,
                                             expectedParameters: [String: String]?) {
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])

        vc.fireTurnOffSyncSheetPixel(event: event)

        #expect(pixelKitMock.actualFireCalls.count == 1)
        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == expectedName &&
            $0.pixel.parameters == expectedParameters &&
            ($0.additionalParameters ?? [:]).isEmpty &&
            $0.includeAppVersionParameter == true
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning off sync without a confirmation fires the sync disabled pixel", .timeLimit(.minutes(1)))
    func disablingSyncFiresSyncDisabledPixel() async {
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])

        let didDisable = await vc.disableSync()

        #expect(didDisable)
        #expect(ddgSyncing.disconnectCalled)
        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == Pixel.Event.syncDisabled.name &&
            $0.additionalParameters == ["ui_version": "v2"]
        })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Deleting server data without a confirmation fires the disabled and deleted pixel with the device count", .timeLimit(.minutes(1)))
    func deletingServerDataFiresDisabledAndDeletedPixel() async {
        let vc = makeViewController(source: nil, enabledFeatureFlags: [])
        vc.viewModel.isSyncEnabled = true
        vc.viewModel.devices = [
            .init(id: "1", name: "iPhone", type: "phone", isThisDevice: true),
            .init(id: "2", name: "Mac", type: "desktop", isThisDevice: false)
        ]

        let didDelete = await vc.deleteAllData()

        #expect(didDelete)
        #expect(!vc.viewModel.isSyncEnabled)
        #expect(pixelKitMock.actualFireCalls.contains {
            $0.pixel.name == Pixel.Event.syncDisabledAndDeleted.name &&
            $0.additionalParameters == ["ui_version": "v2", "connected_devices": "2"]
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
            pixelFiring: pixelKitMock,
            cameraAuthorization: cameraAuthorization
        )
    }

    private func makeScanModel() -> ScanOrPasteCodeViewModel {
        ScanOrPasteCodeViewModel(codeForDisplayOrPasting: "code", qrCodeString: "code", source: .connect)
    }

    private func promptResultCalls() -> [ExpectedFireCall] {
        pixelKitMock.actualFireCalls.filter { $0.pixel.name == SyncCameraPermissionPixel.promptResult(granted: true).name }
    }
}

private final class MockSyncCameraAuthorization: SyncCameraAuthorizing {
    var authorizationStatus: AVAuthorizationStatus = .notDetermined
    var requestAccessResult = false
    private(set) var requestAccessCallCount = 0

    func requestAccess() async -> Bool {
        requestAccessCallCount += 1
        authorizationStatus = requestAccessResult ? .authorized : .denied
        return requestAccessResult
    }
}

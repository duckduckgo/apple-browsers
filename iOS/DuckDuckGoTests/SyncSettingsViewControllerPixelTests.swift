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
@testable import DuckDuckGo
@testable import DDGSync
import Persistence
import Common
import FoundationExtensions
import SyncUI_iOS
import SecureStorage

@Suite("Sync Settings scan-flow pixels", .serialized)
@MainActor
final class SyncSettingsViewControllerPixelTests {

    private let ddgSyncing: MockDDGSyncing
    private let syncBookmarksAdapter: SyncBookmarksAdapter
    private let syncCredentialsAdapter: SyncCredentialsAdapter
    private let syncCreditCardsAdapter: SyncCreditCardsAdapter
    private let syncPausedStateManager: CapturingSyncPausedStateManager
    private let syncAutoRestoreHandler: MockSyncAutoRestoreHandler

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

    deinit {
        PixelFiringMock.tearDown()
    }

    @available(iOS 16, macOS 13, *)
    @Test("scanQRCodeScreenShown fires the scan-QR screen pixel", .timeLimit(.minutes(1)))
    func scanQRCodeScreenShownFiresScanQRScreenPixel() {
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [.simplifiedSyncSetupV2])

        vc.scanQRCodeScreenShown()

        #expect(PixelFiringMock.allPixelsFired.contains {
            $0.pixelName == Pixel.Event.syncSetupScanQRScreenShown.name &&
            $0.params == [
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
        let vc = makeViewController(source: "test_source", enabledFeatureFlags: [.simplifiedSyncSetupV2])

        vc.barcodeScreenShown()

        #expect(PixelFiringMock.allPixelsFired.contains {
            $0.pixelName == Pixel.Event.syncSetupBarcodeScreenShown.name &&
            $0.params == [
                "source": "test_source",
                "my_kind": "ddg",
                "flow_version": "v1",
                "ui_version": "v2"
            ]
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
            pixelFiring: PixelFiringMock.self
        )
    }
}

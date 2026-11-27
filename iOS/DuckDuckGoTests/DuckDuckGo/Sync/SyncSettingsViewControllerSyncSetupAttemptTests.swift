//
//  SyncSettingsViewControllerSyncSetupAttemptTests.swift
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
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
@_spi(Testing) import WideEvent
import Common
import SyncUI_iOS

@Suite("Sync Settings sync-setup attempts", .serialized)
@MainActor
final class SyncSettingsViewControllerSyncSetupAttemptTests {

    private typealias Constants = SyncSettingsViewController.SourceConstants

    private let ddgSyncing = MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
    private let syncBookmarksAdapter: SyncBookmarksAdapter
    private let syncCredentialsAdapter: SyncCredentialsAdapter
    private let syncCreditCardsAdapter: SyncCreditCardsAdapter
    private let wideEvent = WideEventMock()
    private var isWideEventEnabled = true

    init() throws {
        let model = try #require(CoreDataDatabase.loadModel(from: DDGSync.bundle, named: "SyncMetadata"))
        let database = CoreDataDatabase(name: "",
                                        containerLocation: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                        model: model,
                                        readOnly: true,
                                        options: [:])
        syncBookmarksAdapter = SyncBookmarksAdapter(database: database,
                                                    favoritesDisplayModeStorage: MockFavoritesDisplayModeStoring(),
                                                    syncErrorHandler: CapturingAdapterErrorHandler(),
                                                    faviconStoring: MockFaviconStore())
        syncCredentialsAdapter = SyncCredentialsAdapter(secureVaultErrorReporter: MockSecureVaultReporting(),
                                                        syncErrorHandler: CapturingAdapterErrorHandler(),
                                                        tld: TLD())
        syncCreditCardsAdapter = SyncCreditCardsAdapter(secureVaultErrorReporter: MockSecureVaultReporting(),
                                                        syncErrorHandler: CapturingAdapterErrorHandler())
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each entry point starts the attempt with its context.name",
          .timeLimit(.minutes(1)),
          arguments: [
            (nil, "unknown"),
            (Constants.settingsPage, "settings_page"),
            (Constants.remoteMessage, "remote_message"),
            (Constants.aiChat, "ai_chat"),
            (Constants.aiChatHistory, "ai_chat_history"),
            (Constants.passwordsImportPromotion, "promotion_passwords_import"),
            (Constants.startSyncFlow, "sync_recovery_prompt"),
            (Constants.startBackupFlow, "sync_recovery_prompt"),
            (Constants.bookmarksPromotion, "promotion_bookmarks"),
            (Constants.passwordsPromotion, "promotion_passwords"),
            (Constants.bookmarksAnotherDevicePromotion, "promotion_bookmarks_multi_device"),
            (Constants.passwordsAnotherDevicePromotion, "promotion_passwords_multi_device"),
            (Constants.aiChatPromotion, "promotion_ai_chat"),
            (Constants.dataImportSummary, "data_import_summary"),
            (Constants.dataImportSummarySyncPromotion, "promotion_data_import_summary")
          ] as [(String?, String)])
    func entryPointSetsContextName(source: String?, expectedContextName: String) throws {
        let vc = makeViewController(source: source)

        vc.startSyncSetupAttempt(for: .setup(.pairing))

        #expect(try startedAttempt().contextData.name == expectedContextName)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each setup action starts the attempt in its mode, with ui_version v2",
          .timeLimit(.minutes(1)),
          arguments: [
            (SyncSettingsViewModel.PreservedAccountContinuation.setup(.simplifiedToggle), SyncSetupWideEventData.SetupMode.singleDevice),
            (.setup(.pairing), .multiDevice),
            (.recover, .recovery)
          ])
    func setupActionSetsMode(continuation: SyncSettingsViewModel.PreservedAccountContinuation,
                             expectedMode: SyncSetupWideEventData.SetupMode) throws {
        let vc = makeViewController(source: Constants.settingsPage)

        vc.startSyncSetupAttempt(for: continuation)

        let attempt = try startedAttempt()
        #expect(attempt.setupMode == expectedMode)
        #expect(attempt.initialSetupMode == expectedMode)
        #expect(attempt.uiVersion == .v2)
        #expect(attempt.steps == [.started])
    }

    @available(iOS 16, macOS 13, *)
    @Test("existing_account reflects whether the device had a Sync account", .timeLimit(.minutes(1)), arguments: [false, true])
    func existingAccountReflectsSyncAccount(hasAccount: Bool) throws {
        ddgSyncing.account = hasAccount ? makeAccount() : nil
        let vc = makeViewController(source: Constants.settingsPage)

        vc.startSyncSetupAttempt(for: .setup(.pairing))

        #expect(try startedAttempt().existingAccount == hasAccount)
    }

    @available(iOS 16, macOS 13, *)
    @Test("flow_version is the newest version the device supports",
          .timeLimit(.minutes(1)),
          arguments: [
            ([], SyncSetupWideEventData.FlowVersion.v1),
            ([.syncCanUseV2ConnectFlow], .v2),
            ([.syncCanUseV2ConnectFlow, .syncCanUseExchangeV2Point1], .v21)
          ] as [([FeatureFlag], SyncSetupWideEventData.FlowVersion)])
    func flowVersionFollowsFlags(enabledFeatureFlags: [FeatureFlag], expectedVersion: SyncSetupWideEventData.FlowVersion) throws {
        let vc = makeViewController(source: Constants.settingsPage, enabledFeatureFlags: enabledFeatureFlags)

        vc.startSyncSetupAttempt(for: .setup(.pairing))

        #expect(try startedAttempt().flowVersion == expectedVersion)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A second setup action ends the open attempt as UNKNOWN duplicated", .timeLimit(.minutes(1)))
    func secondSetupActionReplacesOpenAttempt() throws {
        let vc = makeViewController(source: Constants.settingsPage)

        vc.startSyncSetupAttempt(for: .setup(.pairing))
        vc.startSyncSetupAttempt(for: .recover)

        let completion = try #require(wideEvent.completions.first)
        #expect(completion.1 == .unknown(reason: SyncSetupWideEventData.StatusReason.duplicated))
        #expect(wideEvent.started.count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off, no attempt starts", .timeLimit(.minutes(1)))
    func flagOffStartsNothing() {
        isWideEventEnabled = false
        let vc = makeViewController(source: Constants.settingsPage)

        vc.startSyncSetupAttempt(for: .setup(.pairing))

        #expect(wideEvent.started.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The connection controller reports to the app-wide attempt tracker", .timeLimit(.minutes(1)))
    func connectionControllerUsesAttemptTracker() {
        let tracker = makeTracker()
        let vc = makeViewController(source: nil, tracker: tracker)

        _ = vc.connectionController

        #expect(ddgSyncing.connectionControllerAttemptTracker === tracker)
    }

    private func startedAttempt() throws -> SyncSetupWideEventData {
        try #require(wideEvent.started.last as? SyncSetupWideEventData)
    }

    private func makeTracker() -> SyncSetupAttemptTracker {
        SyncSetupAttemptTracker(wideEvent: wideEvent, isEnabled: { [unowned self] in isWideEventEnabled })
    }

    private func makeViewController(source: String?,
                                    enabledFeatureFlags: [FeatureFlag] = [],
                                    tracker: SyncSetupAttemptTracker? = nil) -> SyncSettingsViewController {
        SyncSettingsViewController(syncService: ddgSyncing,
                                   syncBookmarksAdapter: syncBookmarksAdapter,
                                   syncCredentialsAdapter: syncCredentialsAdapter,
                                   syncCreditCardsAdapter: syncCreditCardsAdapter,
                                   syncPausedStateManager: CapturingSyncPausedStateManager(),
                                   source: source,
                                   featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFeatureFlags),
                                   syncAutoRestoreHandler: MockSyncAutoRestoreHandler(),
                                   pixelFiring: PixelKitMock(),
                                   syncPromoStorage: MockKeyValueStore().keyedStoring(),
                                   syncSetupAttemptTracker: tracker ?? makeTracker())
    }

    private func makeAccount() -> SyncAccount {
        SyncAccount(deviceId: "device-id",
                    deviceName: "iPhone",
                    deviceType: "iPhone",
                    userId: "user-id",
                    primaryKey: Data(),
                    secretKey: Data(),
                    token: "token",
                    state: .active)
    }
}

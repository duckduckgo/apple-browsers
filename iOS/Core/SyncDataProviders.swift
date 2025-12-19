//
//  SyncDataProviders.swift
//  DuckDuckGo
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

import Bookmarks
import BrowserServicesKit
import Combine
import Common
import DDGSync
import Persistence
import PrivacyConfig
import SecureStorage
import SyncDataProviders

public class SyncDataProviders: DataProvidersSource {
    public let bookmarksAdapter: SyncBookmarksAdapter
    public let credentialsAdapter: SyncCredentialsAdapter
    public let creditCardsAdapter: SyncCreditCardsAdapter?
    public let settingsAdapter: SyncSettingsAdapter

    private let featureFlagger: FeatureFlagger

    public func makeDataProviders() -> [DataProviding] {
        initializeMetadataDatabaseIfNeeded()
        guard let syncMetadata else {
            assertionFailure("Sync Metadata not initialized")
            return []
        }

        bookmarksAdapter.setUpProviderIfNeeded(
            database: bookmarksDatabase,
            metadataStore: syncMetadata,
            metricsEventsHandler: metricsEventsHandler
        )
        credentialsAdapter.setUpProviderIfNeeded(
            secureVaultFactory: secureVaultFactory,
            metadataStore: syncMetadata,
            metricsEventsHandler: metricsEventsHandler
        )
        if featureFlagger.isFeatureOn(.syncCreditCards) {
            creditCardsAdapter?.setUpProviderIfNeeded(
                secureVaultFactory: secureVaultFactory,
                metadataStore: syncMetadata,
                metricsEventsHandler: metricsEventsHandler,
                privacyConfigurationManager: privacyConfigurationManager
            )
        }
        settingsAdapter.setUpProviderIfNeeded(
            metadataDatabase: syncMetadataDatabase,
            metadataStore: syncMetadata,
            metricsEventsHandler: metricsEventsHandler
        )

        var providers: [Any] = [
            bookmarksAdapter.provider as Any,
            credentialsAdapter.provider as Any,
            settingsAdapter.provider as Any
        ]

        if featureFlagger.isFeatureOn(.syncCreditCards),
           let creditCardsProvider = creditCardsAdapter?.provider {
            providers.append(creditCardsProvider as Any)
        }

        return providers.compactMap { $0 as? DataProviding }
    }

    public func setUpDatabaseCleanersIfNeeded(syncService: DDGSync) {
        guard !isDatabaseCleanersSetUp else {
            return
        }

        bookmarksAdapter.databaseCleaner.isSyncActive = { [weak syncService] in
            syncService?.authState == .active
        }
        credentialsAdapter.databaseCleaner.isSyncActive = { [weak syncService] in
            syncService?.authState == .active
        }
        if featureFlagger.isFeatureOn(.syncCreditCards) {
            creditCardsAdapter?.databaseCleaner.isSyncActive = { [weak syncService] in
                syncService?.authState == .active
            }
        }

        let syncAuthStateDidChangePublisher = syncService.authStatePublisher
            .dropFirst()
            .map { $0 == .inactive }
            .removeDuplicates()

        syncAuthStateDidChangeCancellable = syncAuthStateDidChangePublisher
            .sink { [weak self] isSyncDisabled in
                self?.credentialsAdapter.cleanUpDatabaseAndUpdateSchedule(shouldEnable: isSyncDisabled)
                self?.bookmarksAdapter.cleanUpDatabaseAndUpdateSchedule(shouldEnable: isSyncDisabled)
                if self?.featureFlagger.isFeatureOn(.syncCreditCards) == true {
                    self?.creditCardsAdapter?.cleanUpDatabaseAndUpdateSchedule(shouldEnable: isSyncDisabled)
                }
            }

        if syncService.authState == .inactive {
            credentialsAdapter.cleanUpDatabaseAndUpdateSchedule(shouldEnable: true)
            bookmarksAdapter.cleanUpDatabaseAndUpdateSchedule(shouldEnable: true)
            if featureFlagger.isFeatureOn(.syncCreditCards) {
                creditCardsAdapter?.cleanUpDatabaseAndUpdateSchedule(shouldEnable: true)
            }
        }

        isDatabaseCleanersSetUp = true
    }

    public init(
        privacyConfigurationManager: PrivacyConfigurationManaging,
        bookmarksDatabase: CoreDataDatabase,
        secureVaultFactory: AutofillVaultFactory = AutofillSecureVaultFactory,
        secureVaultErrorReporter: SecureVaultReporting,
        settingHandlers: [SettingSyncHandler],
        favoritesDisplayModeStorage: FavoritesDisplayModeStoring,
        syncErrorHandler: SyncErrorHandling,
        faviconStoring: FaviconStoring,
        tld: TLD,
        featureFlagger: FeatureFlagger
    ) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.bookmarksDatabase = bookmarksDatabase
        self.secureVaultFactory = secureVaultFactory
        self.secureVaultErrorReporter = secureVaultErrorReporter
        self.featureFlagger = featureFlagger

        bookmarksAdapter = SyncBookmarksAdapter(database: bookmarksDatabase,
                                                favoritesDisplayModeStorage: favoritesDisplayModeStorage,
                                                syncErrorHandler: syncErrorHandler,
                                                faviconStoring: faviconStoring)
        credentialsAdapter = SyncCredentialsAdapter(secureVaultFactory: secureVaultFactory,
                                                    secureVaultErrorReporter: secureVaultErrorReporter,
                                                    syncErrorHandler: syncErrorHandler,
                                                    tld: tld)
        settingsAdapter = SyncSettingsAdapter(settingHandlers: settingHandlers,
                                              syncErrorHandler: syncErrorHandler)
        if featureFlagger.isFeatureOn(.syncCreditCards) {
            creditCardsAdapter = SyncCreditCardsAdapter(secureVaultFactory: secureVaultFactory,
                                                        secureVaultErrorReporter: secureVaultErrorReporter,
                                                        syncErrorHandler: syncErrorHandler)
        } else {
            creditCardsAdapter = nil
        }

    }

    private func initializeMetadataDatabaseIfNeeded() {
        guard !isSyncMetadaDatabaseLoaded else {
            return
        }

        syncMetadataDatabase.loadStore { context, error in
            guard context != nil else {
                if let error = error {
                    Pixel.fire(pixel: .syncMetadataCouldNotLoadDatabase, error: error)
                } else {
                    Pixel.fire(pixel: .syncMetadataCouldNotLoadDatabase)
                }

                Thread.sleep(forTimeInterval: 1)
                fatalError("Could not create Sync Metadata database stack: \(error?.localizedDescription ?? "err")")
            }
        }
        syncMetadata = LocalSyncMetadataStore(database: syncMetadataDatabase)
        isSyncMetadaDatabaseLoaded = true
    }

    private var isSyncMetadaDatabaseLoaded: Bool = false
    private var isDatabaseCleanersSetUp: Bool = false
    private var syncMetadata: SyncMetadataStore?
    private var syncAuthStateDidChangeCancellable: AnyCancellable?
    private let metricsEventsHandler = SyncMetricsEventsHandler()

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let syncMetadataDatabase: CoreDataDatabase = SyncMetadataDatabase.make()
    private let bookmarksDatabase: CoreDataDatabase
    private let secureVaultFactory: AutofillVaultFactory
    private let secureVaultErrorReporter: SecureVaultReporting
}

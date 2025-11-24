//
//  SyncDataProviders.swift
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

import BrowserServicesKit
import Combine
import Common
import DDGSync
import Foundation
import Persistence
import PixelKit
import SyncDataProviders

final class SyncDataProvidersSource: DataProvidersSource {
    public let bookmarksAdapter: SyncBookmarksAdapter
    public let credentialsAdapter: SyncCredentialsAdapter
    public let creditCardsAdapter: SyncCreditCardsAdapter?
    public let identitiesAdapter: SyncIdentitiesAdapter?
    public let settingsAdapter: SyncSettingsAdapter
    public let syncErrorHandler: SyncErrorHandler
    private let featureFlagger: FeatureFlagger

    @MainActor
    func makeDataProviders() -> [DataProviding] {
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

        // Only set up credit cards provider if feature flag is enabled
        if featureFlagger.isFeatureOn(.syncCreditCards) {
            creditCardsAdapter?.setUpProviderIfNeeded(
                secureVaultFactory: secureVaultFactory,
                metadataStore: syncMetadata,
                metricsEventsHandler: metricsEventsHandler
            )
        }

        // Only set up identities provider if feature flag is enabled
        if featureFlagger.isFeatureOn(.syncIdentities) {
            identitiesAdapter?.setUpProviderIfNeeded(
                secureVaultFactory: secureVaultFactory,
                metadataStore: syncMetadata,
                metricsEventsHandler: metricsEventsHandler
            )
        }

        settingsAdapter.setUpProviderIfNeeded(
            metadataDatabase: syncMetadataDatabase.db,
            metadataStore: syncMetadata,
            appearancePreferences: appearancePreferences,
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

        if featureFlagger.isFeatureOn(.syncIdentities),
           let identitiesProvider = identitiesAdapter?.provider {
            providers.append(identitiesProvider as Any)
        }

        return providers.compactMap { $0 as? DataProviding }
    }

    func setUpDatabaseCleaners(syncService: DDGSync) {
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

        if featureFlagger.isFeatureOn(.syncIdentities) {
            identitiesAdapter?.databaseCleaner.isSyncActive = { [weak syncService] in
                syncService?.authState == .active
            }
        }

        let syncAuthStateDidChangePublisher = syncService.authStatePublisher
            .dropFirst()
            .map { $0 == .inactive }
            .removeDuplicates()

        syncAuthStateDidChangeCancellable = syncAuthStateDidChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSyncDisabled in
                self?.bookmarksAdapter.cleanUpDatabaseAndUpdateSchedule(shouldEnable: isSyncDisabled)
                self?.credentialsAdapter.cleanUpDatabaseAndUpdateSchedule(shouldEnable: isSyncDisabled)

                if self?.featureFlagger.isFeatureOn(.syncCreditCards) == true {
                    self?.creditCardsAdapter?.cleanUpDatabaseAndUpdateSchedule(shouldEnable: isSyncDisabled)
                }

                if self?.featureFlagger.isFeatureOn(.syncIdentities) == true {
                    self?.identitiesAdapter?.cleanUpDatabaseAndUpdateSchedule(shouldEnable: isSyncDisabled)
                }
            }

        if syncService.authState == .inactive {
            bookmarksAdapter.cleanUpDatabaseAndUpdateSchedule(shouldEnable: true)
            credentialsAdapter.cleanUpDatabaseAndUpdateSchedule(shouldEnable: true)

            if featureFlagger.isFeatureOn(.syncCreditCards) {
                creditCardsAdapter?.cleanUpDatabaseAndUpdateSchedule(shouldEnable: true)
            }

            if featureFlagger.isFeatureOn(.syncIdentities) {
                identitiesAdapter?.cleanUpDatabaseAndUpdateSchedule(shouldEnable: true)
            }
        }
    }

    init(
        bookmarksDatabase: CoreDataDatabase,
        bookmarkManager: BookmarkManager,
        secureVaultFactory: AutofillVaultFactory = AutofillSecureVaultFactory,
        appearancePreferences: AppearancePreferences,
        syncErrorHandler: SyncErrorHandler,
        featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger
    ) {
        self.bookmarksDatabase = bookmarksDatabase
        self.secureVaultFactory = secureVaultFactory
        self.appearancePreferences = appearancePreferences
        self.syncErrorHandler = syncErrorHandler
        self.featureFlagger = featureFlagger
        bookmarksAdapter = SyncBookmarksAdapter(database: bookmarksDatabase, bookmarkManager: bookmarkManager, appearancePreferences: appearancePreferences, syncErrorHandler: syncErrorHandler)
        credentialsAdapter = SyncCredentialsAdapter(secureVaultFactory: secureVaultFactory, syncErrorHandler: syncErrorHandler)

        if featureFlagger.isFeatureOn(.syncCreditCards) {
            creditCardsAdapter = SyncCreditCardsAdapter(secureVaultFactory: secureVaultFactory, syncErrorHandler: syncErrorHandler)
        } else {
            creditCardsAdapter = nil
        }

        if featureFlagger.isFeatureOn(.syncIdentities) {
            identitiesAdapter = SyncIdentitiesAdapter(secureVaultFactory: secureVaultFactory, syncErrorHandler: syncErrorHandler)
        } else {
            identitiesAdapter = nil
        }

        settingsAdapter = SyncSettingsAdapter(syncErrorHandler: syncErrorHandler)
    }

    private func initializeMetadataDatabaseIfNeeded() {
        guard !isSyncMetadaDatabaseLoaded else {
            return
        }

        syncMetadataDatabase.db.loadStore { context, error in
            guard context != nil else {
                if let error = error {
                    PixelKit.fire(DebugEvent(GeneralPixel.syncMetadataCouldNotLoadDatabase, error: error))
                } else {
                    PixelKit.fire(DebugEvent(GeneralPixel.syncMetadataCouldNotLoadDatabase))
                }

                Thread.sleep(forTimeInterval: 1)
                fatalError("Could not create Sync Metadata database stack: \(error?.localizedDescription ?? "err")")
            }
        }
        syncMetadata = LocalSyncMetadataStore(database: syncMetadataDatabase.db)
        isSyncMetadaDatabaseLoaded = true
    }

    private var isSyncMetadaDatabaseLoaded: Bool = false
    private var syncMetadata: SyncMetadataStore?
    private var syncAuthStateDidChangeCancellable: AnyCancellable?
    private let metricsEventsHandler = SyncMetricsEventsHandler()

    private let syncMetadataDatabase: SyncMetadataDatabase = SyncMetadataDatabase()
    private let bookmarksDatabase: CoreDataDatabase
    private let secureVaultFactory: AutofillVaultFactory
    private let appearancePreferences: AppearancePreferences
}

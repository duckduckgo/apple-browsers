//
//  SettingsProvider.swift
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
import BrowserServicesKit
import Combine
import Common
import CoreData
import DDGSync
import Persistence

/**
 * Error that may occur while updating timestamp when a setting changes.
 *
 * This error should be published via `SettingSyncHandling.errorPublisher`
 * whenever settings metadata database fails to save changes after updating
 * timestamp for a given setting.
 *
 * `underlyingError` should contain the actual Core Data error.
 */
public struct SettingsSyncMetadataSaveError: Error {
    public let underlyingError: Error

    public init(underlyingError: Error) {
        self.underlyingError = underlyingError
    }
}

public final class SettingsProvider: DataProvider, SettingSyncHandlingDelegate {

    public struct Setting: Hashable {
        public let key: String

        public init(key: String) {
            self.key = key
        }
    }

    public convenience init(
        metadataDatabase: CoreDataDatabase,
        metadataStore: SyncMetadataStore,
        settingsHandlers: [SettingSyncHandler],
        metricsEvents: EventMapping<MetricsEvent>? = nil,
        syncDidUpdateData: @escaping () -> Void
    ) {
        let settingsHandlersBySetting = settingsHandlers.reduce(into: [Setting: any SettingSyncHandling]()) { partialResult, handler in
            partialResult[handler.setting] = handler
        }

        let settingsHandlers = settingsHandlersBySetting

        self.init(
            metadataDatabase: metadataDatabase,
            metadataStore: metadataStore,
            settingsHandlersBySetting: settingsHandlers,
            metricsEvents: metricsEvents,
            syncDidUpdateData: syncDidUpdateData
        )

        register(errorPublisher: errorSubject.eraseToAnyPublisher())

        settingsHandlers.values.forEach { handler in
            handler.delegate = self
        }
    }

    init(
        metadataDatabase: CoreDataDatabase,
        metadataStore: SyncMetadataStore,
        settingsHandlersBySetting: [Setting: any SettingSyncHandling],
        metricsEvents: EventMapping<MetricsEvent>? = nil,
        syncDidUpdateData: @escaping () -> Void
    ) {
        self.metadataDatabase = metadataDatabase
        self.settingsHandlers = settingsHandlersBySetting
        self.metricsEvents = metricsEvents
        super.init(feature: .init(name: "settings"), metadataStore: metadataStore, syncDidUpdateData: syncDidUpdateData)
    }

    // MARK: - DataProviding

    public override func prepareForFirstSync() throws {
        var saveError: Error?

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let currentTimestamp = Date()

        context.performAndWait {
            do {
                let allMetadataObjectsRequest = SyncableSettingsMetadata.fetchRequest()
                let allMetadataObjects = try context.fetch(allMetadataObjectsRequest)
                for metadataObject in allMetadataObjects {
                    context.delete(metadataObject)
                }

                for key in settingsHandlers.keys.map(\.key) {
                    SyncableSettingsMetadata.makeSettingsMetadata(with: key, lastModified: currentTimestamp, in: context)
                }
                try context.save()

            } catch {
                saveError = error
            }
        }

        if let saveError {
            throw saveError
        }
    }

    public override func fetchDescriptionsForObjectsThatFailedValidation() throws -> [String] {
        []
    }

    public override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        var syncableSettings = [Syncable]()
        var fetchError: Error?

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let encryptionKey = try crypter.fetchSecretKey()

        context.performAndWait {
            do {
                let modifiedSettings = try SyncableSettingsMetadataUtils.fetchMetadataForSettingsPendingSync(in: context)
                for modifiedSetting in modifiedSettings {
                    let setting = Setting(key: modifiedSetting.key)
                    guard let settingHandler = settingsHandlers[setting] else {
                        // setting metadata object is not supported by the provider
                        continue
                    }
                    let value = try settingHandler.getValue()
                    syncableSettings.append(
                        try Syncable(
                            setting: setting,
                            value: value,
                            lastModified: modifiedSetting.lastModified,
                            encryptedUsing: { try crypter.encryptAndBase64Encode($0, using: encryptionKey) }
                        )
                    )
                }
            } catch {
                fetchError = error
            }
        }

        if let fetchError {
            throw fetchError
        }

        return syncableSettings
    }

    public override func handleInitialSyncResponse(
        received: [Syncable],
        clientTimestamp: Date,
        serverTimestamp: String?,
        crypter: Crypting
    ) async throws {
        try await handleSyncResponse(
            isInitial: true,
            sent: [],
            received: received,
            clientTimestamp: clientTimestamp,
            serverTimestamp: serverTimestamp,
            crypter: crypter
        )
    }

    public override func handleSyncResponse(
        sent: [Syncable],
        received: [Syncable],
        clientTimestamp: Date,
        serverTimestamp: String?,
        crypter: Crypting
    ) async throws {
        try await handleSyncResponse(
            isInitial: false,
            sent: sent,
            received: received,
            clientTimestamp: clientTimestamp,
            serverTimestamp: serverTimestamp,
            crypter: crypter
        )
    }

    // MARK: - Internal

    func handleSyncResponse(
        isInitial: Bool,
        sent: [Syncable],
        received: [Syncable],
        clientTimestamp: Date,
        serverTimestamp: String?,
        crypter: Crypting
    ) async throws {

        var saveError: Error?

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var saveAttemptsLeft = Const.maxContextSaveRetries

        context.performAndWait {
            while true {

                do {
                    let responseHandler = try SettingsResponseHandler(
                        received: received,
                        clientTimestamp: clientTimestamp,
                        settingsHandlers: settingsHandlers,
                        context: context,
                        crypter: crypter,
                        deduplicateEntities: isInitial,
                        metricsEvents: metricsEvents
                    )
                    let idsOfItemsToClearModifiedAt = try cleanUpSentItems(
                        sent,
                        receivedKeys: Set(responseHandler.receivedByKey.keys),
                        clientTimestamp: clientTimestamp,
                        in: context
                    )
                    try responseHandler.processReceivedSettings()

#if DEBUG
                    try willSaveContextAfterApplyingSyncResponse()
#endif
                    let keys = idsOfItemsToClearModifiedAt.union(
                        Set(responseHandler.receivedByKey.keys)
                            .subtracting(responseHandler.idsOfItemsThatRetainModifiedAt)
                    )
                    try clearModifiedAtAndSaveContext(keys: keys, clientTimestamp: clientTimestamp, in: context)
                    break
                } catch {
                    if (error as NSError).code == NSManagedObjectMergeError {
                        context.reset()
                        saveAttemptsLeft -= 1
                        if saveAttemptsLeft == 0 {
                            saveError = error
                            break
                        }
                    } else {
                        saveError = error
                        break
                    }
                }

            }
        }
        if let saveError {
            throw saveError
        }

        if let serverTimestamp {
            updateSyncTimestamps(server: serverTimestamp, local: clientTimestamp)
            syncDidUpdateData()
        } else {
            lastSyncLocalTimestamp = clientTimestamp
        }
        syncDidFinish()
    }

    func cleanUpSentItems(
        _ sent: [Syncable],
        receivedKeys: Set<String>,
        clientTimestamp: Date,
        in context: NSManagedObjectContext
    ) throws -> Set<String> {

        if sent.isEmpty {
            return []
        }
        let keys = sent.compactMap { SyncableSettingAdapter(syncable: $0).uuid }
        let settingsMetadata = try SyncableSettingsMetadataUtils.fetchSettingsMetadata(for: keys, in: context)
        let originalValues: [Setting: String?] = try settingsHandlers.reduce(into: .init()) { partialResult, handler in
            partialResult[handler.key] = try handler.value.getValue()
        }

        var idsOfItemsToClearModifiedAt = Set<String>()

        for metadata in settingsMetadata {
            let setting = Setting(key: metadata.key)
            guard let handler = settingsHandlers[setting] else {
                continue
            }

            if let lastModified = metadata.lastModified, lastModified > clientTimestamp {
                continue
            }
            let hasNewerVersionOnServer: Bool = receivedKeys.contains(metadata.key)
            let isPendingDeletion = originalValues[setting] == nil
            if isPendingDeletion, !hasNewerVersionOnServer {
                try handler.setValue(nil, shouldDetectOverride: false)
            } else {
                idsOfItemsToClearModifiedAt.insert(metadata.key)
            }
            metadata.lastModified = nil
        }

        return idsOfItemsToClearModifiedAt
    }

    func syncHandlerDidUpdateSettingValue(_ handler: SettingSyncHandling) {
        updateMetadataTimestamp(for: handler.setting)
    }

    // MARK: - Private

    private func clearModifiedAtAndSaveContext(keys: Set<String>, clientTimestamp: Date, in context: NSManagedObjectContext) throws {
        let settingsMetadata = try SyncableSettingsMetadataUtils.fetchSettingsMetadata(for: keys, in: context)
        for metadata in settingsMetadata {
            if let lastModified = metadata.lastModified, lastModified < clientTimestamp {
                metadata.lastModified = nil
            }
        }

        try context.save()
    }

    private func updateMetadataTimestamp(for setting: Setting) {
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            do {
                try SyncableSettingsMetadataUtils.setLastModified(Date(), forSettingWithKey: setting.key, in: context)
                try context.save()
            } catch SyncError.settingsMetadataNotPresent {
                SyncableSettingsMetadata.makeSettingsMetadata(with: setting.key, lastModified: Date(), in: context)
                do {
                    try context.save()
                } catch {
                    errorSubject.send(SettingsSyncMetadataSaveError(underlyingError: error))
                }
            } catch {
                errorSubject.send(SettingsSyncMetadataSaveError(underlyingError: error))
            }
        }
    }

    private let metadataDatabase: CoreDataDatabase
    private let settingsHandlers: [Setting: any SettingSyncHandling]
    private let errorSubject = PassthroughSubject<Error, Never>()
    private let metricsEvents: EventMapping<MetricsEvent>?

    enum Const {
        static let maxContextSaveRetries = 5
    }

    // MARK: - Test Support

#if DEBUG
    var willSaveContextAfterApplyingSyncResponse: () throws -> Void = {}
#endif
}

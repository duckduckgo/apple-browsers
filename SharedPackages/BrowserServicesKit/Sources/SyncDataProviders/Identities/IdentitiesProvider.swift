//
//  IdentitiesProvider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import DDGSync
import GRDB
import SecureStorage
import os.log

public struct IdentitiesInput {
    public var modifiedIdentities: [SecureVaultModels.Identity]
    public var deletedIdentities: [SecureVaultModels.Identity]
}

public final class IdentitiesProvider: DataProvider, FeatureToggleableProvider {

    public private(set) var identitiesInput: IdentitiesInput = .init(modifiedIdentities: [], deletedIdentities: [])
    private let featureStateLock = NSLock()
    private var featureStateEnabled = true

    public var isSyncFeatureEnabled: Bool {
        featureStateLock.lock()
        let value = featureStateEnabled
        featureStateLock.unlock()
        return value
    }

    public func setSyncFeatureEnabled(_ enabled: Bool) {
        featureStateLock.lock()
        featureStateEnabled = enabled
        featureStateLock.unlock()
    }

    public init(
        secureVaultFactory: AutofillVaultFactory = AutofillSecureVaultFactory,
        secureVaultErrorReporter: SecureVaultReporting,
        metadataStore: SyncMetadataStore,
        metricsEvents: EventMapping<MetricsEvent>? = nil,
        syncDidUpdateData: @escaping () -> Void,
        syncDidFinish: @escaping (IdentitiesInput?) -> Void
    ) throws {
        self.secureVaultFactory = secureVaultFactory
        self.secureVaultErrorReporter = secureVaultErrorReporter
        self.metricsEvents = metricsEvents
        super.init(feature: .init(name: "identities"), metadataStore: metadataStore, syncDidUpdateData: syncDidUpdateData)
        self.syncDidFinish = { [weak self] in
            syncDidFinish(self?.identitiesInput)
        }
    }

    // MARK: - DataProviding

    public override func prepareForFirstSync() throws {
        let secureVault = try secureVaultFactory.makeVault(reporter: secureVaultErrorReporter)
        try secureVault.inDatabaseTransaction { database in

            let identityIds = try Row.fetchAll(
                database,
                sql: "SELECT \(SecureVaultModels.Identity.Columns.id.name) FROM \(SecureVaultModels.Identity.databaseTableName)"
            ).compactMap { row -> Int64? in
                row[SecureVaultModels.Identity.Columns.id.name]
            }

            let identitiesMetadata = try SecureVaultModels.SyncableIdentitiesRecord.fetchAll(database)
            var identityIdsSet = Set(identityIds)
            let currentTimestamp = Date()

            for i in 0..<identitiesMetadata.count {
                var metadataObject = identitiesMetadata[i]
                metadataObject.lastModified = currentTimestamp
                try metadataObject.update(database)

                if let identityId = metadataObject.objectId {
                    identityIdsSet.remove(identityId)
                }
            }

            if identityIdsSet.count > 0 {
                assertionFailure("Syncable Identities metadata objects not present for all Identity objects")

                self.handleSyncError(SyncError.identitiesMetadataMissingBeforeFirstSync)

                for identityId in identityIdsSet {
                    try SecureVaultModels.SyncableIdentitiesRecord(objectId: identityId, lastModified: Date()).insert(database)
                }
            }
        }
    }

    public override func fetchDescriptionsForObjectsThatFailedValidation() throws -> [String] {
        guard let lastSyncLocalTimestamp else {
            return []
        }

        let secureVault = try secureVaultFactory.makeVault(reporter: secureVaultErrorReporter)
        return try secureVault.identityTitlesForSyncableIdentities(modifiedBefore: lastSyncLocalTimestamp)
    }

    public override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        let secureVault = try secureVaultFactory.makeVault(reporter: secureVaultErrorReporter)
        let syncableIdentities = try secureVault.modifiedSyncableIdentities()
        let encryptionKey = try crypter.fetchSecretKey()
        return try syncableIdentities.compactMap { identity in
            do {
                return try Syncable(
                    syncableIdentity: identity,
                    encryptedUsing: { try crypter.encryptAndBase64Encode($0, using: encryptionKey) }
                )
            } catch Syncable.SyncableIdentityError.validationFailed {
                Logger.sync.error("Validation failed for identity \(identity.metadata.uuid) with title: \(identity.identity.map { String($0.title.prefix(100)) } ?? "")")
                return nil
            }
        }
    }

    public override func handleInitialSyncResponse(received: [Syncable],
                                                   clientTimestamp: Date,
                                                   serverTimestamp: String?,
                                                   crypter: Crypting) async throws {
        try await handleSyncResponse(isInitial: true,
                                     sent: [],
                                     received: received,
                                     clientTimestamp: clientTimestamp,
                                     serverTimestamp: serverTimestamp,
                                     crypter: crypter)
    }

    public override func handleSyncResponse(sent: [Syncable],
                                            received: [Syncable],
                                            clientTimestamp: Date,
                                            serverTimestamp: String?,
                                            crypter: Crypting) async throws {
        try await handleSyncResponse(isInitial: false,
                                     sent: sent,
                                     received: received,
                                     clientTimestamp: clientTimestamp,
                                     serverTimestamp: serverTimestamp,
                                     crypter: crypter)
    }

    // MARK: - Internal

    func handleSyncResponse(isInitial: Bool,
                            sent: [Syncable],
                            received: [Syncable],
                            clientTimestamp: Date,
                            serverTimestamp: String?,
                            crypter: Crypting) async throws {
        var saveError: Error?

        let secureVault = try secureVaultFactory.makeVault(reporter: secureVaultErrorReporter)
        let clientTimestampMilliseconds = clientTimestamp.withMillisecondPrecision
        var saveAttemptsLeft = Const.maxContextSaveRetries

        while true {
            do {
                try secureVault.inDatabaseTransaction { database in

                    let responseHandler = try IdentitiesResponseHandler(
                        received: received,
                        clientTimestamp: clientTimestampMilliseconds,
                        secureVault: secureVault,
                        database: database,
                        crypter: crypter,
                        deduplicateEntities: isInitial,
                        metricsEvents: self.metricsEvents
                    )

                    let idsOfItemsToClearModifiedAt = try self.cleanUpSentItems(
                        sent,
                        receivedUUIDs: Set(responseHandler.allReceivedIDs),
                        clientTimestamp: clientTimestampMilliseconds,
                        in: database
                    )

                    try responseHandler.processReceivedIdentities()

                    self.identitiesInput.modifiedIdentities = responseHandler.incomingModifiedIdentities
                    self.identitiesInput.deletedIdentities = responseHandler.incomingDeletedIdentities
#if DEBUG
                    try self.willSaveContextAfterApplyingSyncResponse()
#endif

                    let uuids = idsOfItemsToClearModifiedAt.union(responseHandler.allReceivedIDs)
                    try self.clearModifiedAt(uuids: uuids, clientTimestamp: clientTimestampMilliseconds, in: database)
                }
                break
            } catch {
                if case SecureStorageError.databaseError(let cause) = error, let databaseError = cause as? DatabaseError {
                    switch databaseError {
                    case .SQLITE_BUSY, .SQLITE_LOCKED:
                        saveAttemptsLeft -= 1
                        if saveAttemptsLeft == 0 {
                            saveError = error
                            break
                        }
                    default:
                        saveError = error
                    }
                } else {
                    saveError = error
                    break
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

        if !received.isEmpty {
            NotificationCenter.default.post(name: .autofillSaveEvent, object: nil, userInfo: nil)
        }

        syncDidFinish()
    }

    func cleanUpSentItems(_ sent: [Syncable], receivedUUIDs: Set<String>, clientTimestamp: Date, in database: Database) throws -> Set<String> {
        if sent.isEmpty {
            return []
        }

        let identifiers = sent.compactMap { SyncableIdentitiesAdapter(syncable: $0).uuid }
        var idsOfItemsToClearModifiedAt = Set<String>()

        let syncableIdentitiesRecords = try SecureVaultModels.SyncableIdentitiesRecord
            .filter(identifiers.contains(SecureVaultModels.SyncableIdentitiesRecord.Columns.uuid))
            .fetchAll(database)

        for metadataRecord in syncableIdentitiesRecords {
            if let modifiedAt = metadataRecord.lastModified, modifiedAt.compareWithMillisecondPrecision(to: clientTimestamp) == .orderedDescending {
                continue
            }
            let hasNewerVersionOnServer: Bool = receivedUUIDs.contains(metadataRecord.uuid)
            if metadataRecord.objectId == nil, !hasNewerVersionOnServer {
                try metadataRecord.delete(database)
            } else {
                idsOfItemsToClearModifiedAt.insert(metadataRecord.uuid)
            }
        }

        return idsOfItemsToClearModifiedAt
    }

    private func clearModifiedAt(uuids: Set<String>, clientTimestamp: Date, in database: Database) throws {

        let request = SecureVaultModels.SyncableIdentitiesRecord
            .filter(uuids.contains(SecureVaultModels.SyncableIdentitiesRecord.Columns.uuid))
            .filter(SecureVaultModels.SyncableIdentitiesRecord.Columns.lastModified < clientTimestamp)

        let metadataObjects = try SecureVaultModels.SyncableIdentitiesRecord.fetchAll(database, request)

        for i in 0..<metadataObjects.count {
            var metadata = metadataObjects[i]
            metadata.lastModified = nil
            try metadata.update(database)
        }
    }

    // MARK: - Private

    private let secureVaultFactory: AutofillVaultFactory
    private let secureVaultErrorReporter: SecureVaultReporting
    private let metricsEvents: EventMapping<MetricsEvent>?

    enum Const {
        static let maxContextSaveRetries = 5
    }

    // MARK: - Test support

#if DEBUG
    var willSaveContextAfterApplyingSyncResponse: () throws -> Void = {}
#endif

}

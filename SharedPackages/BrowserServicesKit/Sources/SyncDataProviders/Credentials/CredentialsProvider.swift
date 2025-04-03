//
//  CredentialsProvider.swift
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
import DDGSync
import GRDB
import SecureStorage
import os.log

public struct CredentialsInput {
    public var modifiedAccounts: [SecureVaultModels.WebsiteAccount]
    public var deletedAccounts: [SecureVaultModels.WebsiteAccount]
}

public final class CredentialsProvider: DataProvider {

    public private(set) var credentialsInput: CredentialsInput = .init(modifiedAccounts: [], deletedAccounts: [])

    public init(
        secureVaultFactory: AutofillVaultFactory = AutofillSecureVaultFactory,
        secureVaultErrorReporter: SecureVaultReporting,
        metadataStore: SyncMetadataStore,
        metricsEvents: EventMapping<MetricsEvent>? = nil,
        syncDidUpdateData: @escaping () -> Void,
        syncDidFinish: @escaping (CredentialsInput?) -> Void
    ) throws {
        self.secureVaultFactory = secureVaultFactory
        self.secureVaultErrorReporter = secureVaultErrorReporter
        self.metricsEvents = metricsEvents
        super.init(feature: .init(name: "credentials"), metadataStore: metadataStore, syncDidUpdateData: syncDidUpdateData)
        self.syncDidFinish = { [weak self] in
            syncDidFinish(self?.credentialsInput)
        }
    }

    // MARK: - DataProviding

    public override func prepareForFirstSync() throws {
        let secureVault = try secureVaultFactory.makeVault(reporter: secureVaultErrorReporter)
        try secureVault.inDatabaseTransaction { database in

            let accountIds = try Row.fetchAll(
                database,
                sql: "SELECT \(SecureVaultModels.WebsiteAccount.Columns.id.name) FROM \(SecureVaultModels.WebsiteAccount.databaseTableName)"
            ).compactMap { row -> Int64? in
                row[SecureVaultModels.WebsiteAccount.Columns.id.name]
            }

            let credentialsMetadata = try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database)
            var accountIdsSet = Set(accountIds)
            let currentTimestamp = Date()

            for i in 0..<credentialsMetadata.count {
                var metadataObject = credentialsMetadata[i]
                metadataObject.lastModified = currentTimestamp
                try metadataObject.update(database)

                if let accountId = metadataObject.objectId {
                    accountIdsSet.remove(accountId)
                }
            }

            if accountIdsSet.count > 0 {
                assertionFailure("Syncable Credentials metadata objects not present for all Website Account objects")

                self.handleSyncError(SyncError.credentialsMetadataMissingBeforeFirstSync)

                for accountId in accountIdsSet {
                    try SecureVaultModels.SyncableCredentialsRecord(objectId: accountId, lastModified: Date()).insert(database)
                }
            }
        }
    }

    public override func fetchDescriptionsForObjectsThatFailedValidation() throws -> [String] {
        guard let lastSyncLocalTimestamp else {
            return []
        }

        let secureVault = try secureVaultFactory.makeVault(reporter: secureVaultErrorReporter)
        return try secureVault.accountTitlesForSyncableCredentials(modifiedBefore: lastSyncLocalTimestamp)
    }

    public override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        let secureVault = try secureVaultFactory.makeVault(reporter: secureVaultErrorReporter)
        let syncableCredentials = try secureVault.modifiedSyncableCredentials()
        let encryptionKey = try crypter.fetchSecretKey()
        return try syncableCredentials.compactMap { credentials in
            do {
                return try Syncable(
                    syncableCredentials: credentials,
                    encryptedUsing: { try crypter.encryptAndBase64Encode($0, using: encryptionKey) }
                )
            } catch Syncable.SyncableCredentialError.validationFailed {
                Logger.sync.error("Validation failed for credential \(credentials.metadata.uuid) with title: \(credentials.account?.title.flatMap { String($0.prefix(100)) } ?? "")")
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

                    let responseHandler = try CredentialsResponseHandler(
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

                    try responseHandler.processReceivedCredentials()

                    self.credentialsInput.modifiedAccounts = responseHandler.incomingModifiedAccounts
                    self.credentialsInput.deletedAccounts = responseHandler.incomingDeletedAccounts
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

        let identifiers = sent.compactMap { SyncableCredentialsAdapter(syncable: $0).uuid }
        var idsOfItemsToClearModifiedAt = Set<String>()

        let syncableCredentialsRecords = try SecureVaultModels.SyncableCredentialsRecord
            .filter(identifiers.contains(SecureVaultModels.SyncableCredentialsRecord.Columns.uuid))
            .fetchAll(database)

        for metadataRecord in syncableCredentialsRecords {
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

        let request = SecureVaultModels.SyncableCredentialsRecord
            .filter(uuids.contains(SecureVaultModels.SyncableCredentialsRecord.Columns.uuid))
            .filter(SecureVaultModels.SyncableCredentialsRecord.Columns.lastModified < clientTimestamp)

        let metadataObjects = try SecureVaultModels.SyncableCredentialsRecord.fetchAll(database, request)

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

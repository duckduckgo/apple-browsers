//
//  CredentialsResponseHandler.swift
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
import Common
import DDGSync
import Foundation
import GRDB

final class CredentialsResponseHandler {
    let feature: Feature = .init(name: "credentials")

    let clientTimestamp: Date
    let received: [SyncableCredentialsAdapter]
    let secureVault: any AutofillSecureVault
    let database: Database
    let shouldDeduplicateEntities: Bool

    let allReceivedIDs: Set<String>
    private var credentialsByUUID: [String: SecureVaultModels.SyncableCredentials] = [:]

    var incomingModifiedAccounts = [SecureVaultModels.WebsiteAccount]()
    var incomingDeletedAccounts = [SecureVaultModels.WebsiteAccount]()

    private let decrypt: (String) throws -> String
    private let metricsEvents: EventMapping<MetricsEvent>?

    init(
        received: [Syncable],
        clientTimestamp: Date,
        secureVault: any AutofillSecureVault,
        database: Database,
        crypter: Crypting,
        deduplicateEntities: Bool,
        metricsEvents: EventMapping<MetricsEvent>? = nil
    ) throws {
        self.clientTimestamp = clientTimestamp
        self.received = received.map(SyncableCredentialsAdapter.init)
        self.secureVault = secureVault
        self.database = database
        self.shouldDeduplicateEntities = deduplicateEntities
        self.metricsEvents = metricsEvents

        let secretKey = try crypter.fetchSecretKey()
        self.decrypt = { try crypter.base64DecodeAndDecrypt($0, using: secretKey) }

        var allUUIDs: Set<String> = []

        self.received.forEach { syncable in
            guard let uuid = syncable.uuid else {
                return
            }
            allUUIDs.insert(uuid)
        }

        self.allReceivedIDs = allUUIDs

        credentialsByUUID = try secureVault.syncableCredentialsForSyncIds(allUUIDs, in: database).reduce(into: .init(), { $0[$1.metadata.uuid] = $1 })
    }

    func processReceivedCredentials() throws {
        if received.isEmpty {
            return
        }

        let encryptionKey = try secureVault.getEncryptionKey()
        let hashingSalt = try secureVault.getHashingSalt()

        for syncable in received {
            do {
                try processEntity(with: syncable, secureVaultEncryptionKey: encryptionKey, secureVaultHashingSalt: hashingSalt)
            } catch SyncError.failedToDecryptValue(let message) where message.contains("invalid ciphertext length") {
                continue
            }
        }
    }

    // MARK: - Private

    private func processEntity(with syncable: SyncableCredentialsAdapter, secureVaultEncryptionKey: Data, secureVaultHashingSalt: Data?) throws {
        guard let syncableUUID = syncable.uuid else {
            throw SyncError.receivedCredentialsWithoutUUID
        }

        if shouldDeduplicateEntities,
           var deduplicatedEntity = try deduplicatedCredentials(with: syncable, secureVaultEncryptionKey: secureVaultEncryptionKey) {
            let oldUUID = deduplicatedEntity.metadata.uuid
            deduplicatedEntity.account?.title = try syncable.encryptedTitle.flatMap(decrypt)
            deduplicatedEntity.metadata.uuid = syncableUUID
            try secureVault.storeSyncableCredentials(deduplicatedEntity,
                                                     in: database,
                                                     encryptedUsing: secureVaultEncryptionKey,
                                                     hashedUsing: secureVaultHashingSalt)

            credentialsByUUID.removeValue(forKey: oldUUID)
            credentialsByUUID[syncableUUID] = deduplicatedEntity

        } else if var existingEntity = credentialsByUUID[syncableUUID] {
            let isModifiedAfterSyncTimestamp: Bool = {
                guard let modifiedAt = existingEntity.metadata.lastModified else {
                    return false
                }
                return modifiedAt > clientTimestamp
            }()

            if syncable.isDeleted {
                try secureVault.deleteSyncableCredentials(existingEntity, in: database)
                trackCredentialChange(of: existingEntity, with: syncable)
            } else if isModifiedAfterSyncTimestamp {
                metricsEvents?.fire(.localTimestampResolutionTriggered(feature: feature))
            } else {
                try existingEntity.update(with: syncable, decryptedUsing: decrypt)
                existingEntity.metadata.lastModified = nil
                try secureVault.storeSyncableCredentials(existingEntity,
                                                         in: database,
                                                         encryptedUsing: secureVaultEncryptionKey,
                                                         hashedUsing: secureVaultHashingSalt)
                trackCredentialChange(of: existingEntity, with: syncable)
            }

        } else if !syncable.isDeleted {
            let newEntity = try SecureVaultModels.SyncableCredentials(syncable: syncable, decryptedUsing: decrypt)
            assert(newEntity.metadata.lastModified == nil, "lastModified should be nil for a new metadata entity")
            try secureVault.storeSyncableCredentials(newEntity,
                                                     in: database,
                                                     encryptedUsing: secureVaultEncryptionKey,
                                                     hashedUsing: secureVaultHashingSalt)
            credentialsByUUID[syncableUUID] = newEntity
            trackCredentialChange(of: newEntity, with: syncable)
        }
    }

    private func deduplicatedCredentials(with syncable: SyncableCredentialsAdapter,
                                         secureVaultEncryptionKey: Data) throws -> SecureVaultModels.SyncableCredentials? {

        guard !syncable.isDeleted else {
            return nil
        }

        let domain = try syncable.encryptedDomain.flatMap(decrypt)
        let username = try syncable.encryptedUsername.flatMap(decrypt)
        let password = try syncable.encryptedPassword.flatMap(decrypt)
        let notes = try syncable.encryptedNotes.flatMap(decrypt)

        let accountAlias = TableAlias()
        let credentialsAlias = TableAlias()
        let conditions = [
            !allReceivedIDs.contains(SecureVaultModels.SyncableCredentialsRecord.Columns.uuid),
            accountAlias[SecureVaultModels.WebsiteAccount.Columns.domain] == domain,
            accountAlias[SecureVaultModels.WebsiteAccount.Columns.username] == username,
            accountAlias[SecureVaultModels.WebsiteAccount.Columns.notes] == notes
        ]
        let syncableCredentials = try SecureVaultModels.SyncableCredentialsRecord
            .including(optional: SecureVaultModels.SyncableCredentialsRecord.account.aliased(accountAlias))
            .including(optional: SecureVaultModels.SyncableCredentialsRecord.credentials.aliased(credentialsAlias))
            .filter(conditions.joined(operator: .and))
            .asRequest(of: SecureVaultModels.SyncableCredentials.self)
            .fetchAll(database)

        guard !syncableCredentials.isEmpty else {
            return nil
        }

        if let password, let passwordData = password.data(using: .utf8) {
            var matchingSyncableCredentials = try syncableCredentials.first(where: { credentials in
                let decryptedPassword = try credentials.credentialsRecord?.password
                    .flatMap { try secureVault.decrypt($0, using: secureVaultEncryptionKey) }
                return decryptedPassword == passwordData
            })
            // update matched credentials with decrypted password, as that's what Secure Vault expects
            matchingSyncableCredentials?.credentials?.password = passwordData
            return matchingSyncableCredentials
        }
        return syncableCredentials.first(where: { $0.credentialsRecord?.password == nil })
    }

    private func trackCredentialChange(of entity: SecureVaultModels.SyncableCredentials, with syncable: SyncableCredentialsAdapter) {
        guard let account = entity.account else {
            return
        }

        if syncable.isDeleted {
            incomingDeletedAccounts.append(account)
        } else {
            incomingModifiedAccounts.append(account)
        }
    }
}

extension SecureVaultModels.SyncableCredentials {

    init(syncable: SyncableCredentialsAdapter, decryptedUsing decrypt: (String) throws -> String) throws {
        guard let uuid = syncable.uuid else {
            throw SyncError.accountAlreadyExists
        }

        let title = try syncable.encryptedTitle.flatMap { try decrypt($0) }
        let username = try syncable.encryptedUsername.flatMap { try decrypt($0) }
        let domain = try syncable.encryptedDomain.flatMap { try decrypt($0) }
        let notes = try syncable.encryptedNotes.flatMap { try decrypt($0) }
        let password = try syncable.encryptedPassword.flatMap { try decrypt($0) }

        let account = SecureVaultModels.WebsiteAccount(title: title, username: username, domain: domain, notes: notes)
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password?.data(using: .utf8))
        self.init(uuid: uuid, credentials: credentials, lastModified: nil)
    }

    mutating func update(with syncable: SyncableCredentialsAdapter, decryptedUsing decrypt: (String) throws -> String) throws {
        let title = try syncable.encryptedTitle.flatMap(decrypt)
        let domain = try syncable.encryptedDomain.flatMap(decrypt)
        let username = try syncable.encryptedUsername.flatMap(decrypt)
        let password = try syncable.encryptedPassword.flatMap(decrypt)?.data(using: .utf8)
        let notes = try syncable.encryptedNotes.flatMap(decrypt)

        if account == nil {
            account = .init(title: title, username: username, domain: domain, notes: notes)
        } else {
            account?.title = title
            account?.domain = domain
            account?.username = username
            account?.notes = notes
        }

        assert(account != nil)

        if credentialsRecord == nil {
            credentialsRecord = .init(credentials: .init(account: account!, password: password))
        } else {
            credentialsRecord?.password = password
        }
    }
}

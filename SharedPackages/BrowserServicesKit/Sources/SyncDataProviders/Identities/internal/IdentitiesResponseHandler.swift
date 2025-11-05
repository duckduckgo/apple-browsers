//
//  IdentitiesResponseHandler.swift
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

import BrowserServicesKit
import Common
import DDGSync
import Foundation
import GRDB

final class IdentitiesResponseHandler {
    let feature: Feature = .init(name: "identities")

    let clientTimestamp: Date
    let received: [SyncableIdentitiesAdapter]
    let secureVault: any AutofillSecureVault
    let database: Database
    let shouldDeduplicateEntities: Bool

    let allReceivedIDs: Set<String>
    private var identitiesByUUID: [String: SecureVaultModels.SyncableIdentity] = [:]

    var incomingModifiedIdentities = [SecureVaultModels.Identity]()
    var incomingDeletedIdentities = [SecureVaultModels.Identity]()

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
        self.received = received.map(SyncableIdentitiesAdapter.init)
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

        identitiesByUUID = try secureVault.syncableIdentitiesForSyncIds(allUUIDs, in: database).reduce(into: .init(), { $0[$1.metadata.uuid] = $1 })
    }

    func processReceivedIdentities() throws {
        if received.isEmpty {
            return
        }

        let encryptionKey = try secureVault.getEncryptionKey()

        for syncable in received {
            do {
                try processEntity(with: syncable, secureVaultEncryptionKey: encryptionKey)
            } catch SyncError.failedToDecryptValue(let message) where message.contains("invalid ciphertext length") {
                continue
            }
        }
    }

    // MARK: - Private

    private func processEntity(with syncable: SyncableIdentitiesAdapter, secureVaultEncryptionKey: Data) throws {
        guard let syncableUUID = syncable.uuid else {
            throw SyncError.receivedIdentitiesWithoutUUID
        }

        if shouldDeduplicateEntities,
           var deduplicatedEntity = try deduplicatedIdentity(with: syncable) {
            let oldUUID = deduplicatedEntity.metadata.uuid
            if let decryptedTitle = try syncable.encryptedTitle.flatMap(decrypt) {
                deduplicatedEntity.identity?.title = decryptedTitle
            } else {
                deduplicatedEntity.identity?.title = ""
            }
            deduplicatedEntity.metadata.uuid = syncableUUID
            try secureVault.storeSyncableIdentity(deduplicatedEntity, in: database)

            identitiesByUUID.removeValue(forKey: oldUUID)
            identitiesByUUID[syncableUUID] = deduplicatedEntity

        } else if var existingEntity = identitiesByUUID[syncableUUID] {
            let isModifiedAfterSyncTimestamp: Bool = {
                guard let modifiedAt = existingEntity.metadata.lastModified else {
                    return false
                }
                return modifiedAt > clientTimestamp
            }()

            if syncable.isDeleted {
                try secureVault.deleteSyncableIdentity(existingEntity, in: database)
                trackIdentityChange(of: existingEntity, with: syncable)
            } else if isModifiedAfterSyncTimestamp {
                metricsEvents?.fire(.localTimestampResolutionTriggered(feature: feature))
            } else {
                try existingEntity.update(with: syncable, decryptedUsing: decrypt)
                existingEntity.metadata.lastModified = nil
                try secureVault.storeSyncableIdentity(existingEntity, in: database)
                trackIdentityChange(of: existingEntity, with: syncable)
            }

        } else if !syncable.isDeleted {
            let newEntity = try SecureVaultModels.SyncableIdentity(syncable: syncable, decryptedUsing: decrypt)
            assert(newEntity.metadata.lastModified == nil, "lastModified should be nil for a new metadata entity")
            try secureVault.storeSyncableIdentity(newEntity, in: database)
            identitiesByUUID[syncableUUID] = newEntity
            trackIdentityChange(of: newEntity, with: syncable)
        }
    }

    private func deduplicatedIdentity(with syncable: SyncableIdentitiesAdapter) throws -> SecureVaultModels.SyncableIdentity? {

        guard !syncable.isDeleted else {
            return nil
        }

        let firstName = try syncable.encryptedFirstName.flatMap(decrypt)
        let middleName = try syncable.encryptedMiddleName.flatMap(decrypt)
        let lastName = try syncable.encryptedLastName.flatMap(decrypt)
        let birthday = try syncable.encryptedBirthday.flatMap(decrypt)
        let phone = try syncable.encryptedPhone.flatMap(decrypt)
        let emailAddress = try syncable.encryptedEmailAddress.flatMap(decrypt)

        let addressStreet = try syncable.encryptedAddressStreet.flatMap(decrypt)
        let addressStreet2 = try syncable.encryptedAddressStreet2.flatMap(decrypt)
        let addressCity = try syncable.encryptedAddressCity.flatMap(decrypt)
        let addressProvince = try syncable.encryptedAddressProvince.flatMap(decrypt)
        let addressPostalCode = try syncable.encryptedAddressPostalCode.flatMap(decrypt)
        let addressCountryCode = try syncable.encryptedAddressCountryCode.flatMap(decrypt)

        let birthdayDay: Int?
        let birthdayMonth: Int?
        let birthdayYear: Int?
        if let birthdayString = birthday {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)

            if let date = formatter.date(from: birthdayString) {
                let calendar = Calendar(identifier: .gregorian)
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                birthdayDay = components.day
                birthdayMonth = components.month
                birthdayYear = components.year
            } else {
                birthdayDay = nil
                birthdayMonth = nil
                birthdayYear = nil
            }
        } else {
            birthdayDay = nil
            birthdayMonth = nil
            birthdayYear = nil
        }

        let identityAlias = TableAlias()

        let syncableIdentities = try SecureVaultModels.SyncableIdentitiesRecord
            .including(optional: SecureVaultModels.SyncableIdentitiesRecord.identity.aliased(identityAlias))
            .filter(!allReceivedIDs.contains(SecureVaultModels.SyncableIdentitiesRecord.Columns.uuid))
            .filter(identityAlias[SecureVaultModels.Identity.Columns.firstName] == firstName)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.middleName] == middleName)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.lastName] == lastName)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.birthdayDay] == birthdayDay)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.birthdayMonth] == birthdayMonth)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.birthdayYear] == birthdayYear)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.addressStreet] == addressStreet)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.addressStreet2] == addressStreet2)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.addressCity] == addressCity)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.addressProvince] == addressProvince)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.addressPostalCode] == addressPostalCode)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.addressCountryCode] == addressCountryCode)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.homePhone] == phone)
            .filter(identityAlias[SecureVaultModels.Identity.Columns.emailAddress] == emailAddress)
            .asRequest(of: SecureVaultModels.SyncableIdentity.self)
            .fetchAll(database)

        return syncableIdentities.first
    }

    private func trackIdentityChange(of entity: SecureVaultModels.SyncableIdentity, with syncable: SyncableIdentitiesAdapter) {
        guard let identity = entity.identity else {
            return
        }

        if syncable.isDeleted {
            incomingDeletedIdentities.append(identity)
        } else {
            incomingModifiedIdentities.append(identity)
        }
    }
}

// MARK: - Extensions for SyncableIdentity

extension SecureVaultModels.SyncableIdentity {

    init(syncable: SyncableIdentitiesAdapter, decryptedUsing decrypt: (String) throws -> String) throws {
        guard let uuid = syncable.uuid else {
            throw SyncError.receivedIdentitiesWithoutUUID
        }

        let title = try syncable.encryptedTitle.flatMap { try decrypt($0) }
        let firstName = try syncable.encryptedFirstName.flatMap { try decrypt($0) }
        let middleName = try syncable.encryptedMiddleName.flatMap { try decrypt($0) }
        let lastName = try syncable.encryptedLastName.flatMap { try decrypt($0) }
        let birthday = try syncable.encryptedBirthday.flatMap { try decrypt($0) }
        let phone = try syncable.encryptedPhone.flatMap { try decrypt($0) }
        let emailAddress = try syncable.encryptedEmailAddress.flatMap { try decrypt($0) }

        let addressStreet = try syncable.encryptedAddressStreet.flatMap { try decrypt($0) }
        let addressStreet2 = try syncable.encryptedAddressStreet2.flatMap { try decrypt($0) }
        let addressCity = try syncable.encryptedAddressCity.flatMap { try decrypt($0) }
        let addressProvince = try syncable.encryptedAddressProvince.flatMap { try decrypt($0) }
        let addressPostalCode = try syncable.encryptedAddressPostalCode.flatMap { try decrypt($0) }
        let addressCountryCode = try syncable.encryptedAddressCountryCode.flatMap { try decrypt($0) }

        let birthdayComponents: DateComponents?
        if let birthdayString = birthday {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)

            if let date = formatter.date(from: birthdayString) {
                let calendar = Calendar(identifier: .gregorian)
                birthdayComponents = calendar.dateComponents([.year, .month, .day], from: date)
            } else {
                birthdayComponents = nil
            }
        } else {
            birthdayComponents = nil
        }

        let identity = SecureVaultModels.Identity(
            id: nil,
            title: title ?? "",
            created: Date(),
            lastUpdated: Date(),
            firstName: firstName,
            middleName: middleName,
            lastName: lastName,
            birthdayDay: birthdayComponents?.day,
            birthdayMonth: birthdayComponents?.month,
            birthdayYear: birthdayComponents?.year,
            addressStreet: addressStreet,
            addressStreet2: addressStreet2,
            addressCity: addressCity,
            addressProvince: addressProvince,
            addressPostalCode: addressPostalCode,
            addressCountryCode: addressCountryCode,
            homePhone: phone,
            mobilePhone: nil,
            emailAddress: emailAddress
        )

        self.init(uuid: uuid, identity: identity, lastModified: nil)
    }

    mutating func update(with syncable: SyncableIdentitiesAdapter, decryptedUsing decrypt: (String) throws -> String) throws {
        let title = try syncable.encryptedTitle.flatMap { try decrypt($0) }
        let firstName = try syncable.encryptedFirstName.flatMap { try decrypt($0) }
        let middleName = try syncable.encryptedMiddleName.flatMap { try decrypt($0) }
        let lastName = try syncable.encryptedLastName.flatMap { try decrypt($0) }
        let birthday = try syncable.encryptedBirthday.flatMap { try decrypt($0) }
        let phone = try syncable.encryptedPhone.flatMap { try decrypt($0) }
        let emailAddress = try syncable.encryptedEmailAddress.flatMap { try decrypt($0) }

        let addressStreet = try syncable.encryptedAddressStreet.flatMap { try decrypt($0) }
        let addressStreet2 = try syncable.encryptedAddressStreet2.flatMap { try decrypt($0) }
        let addressCity = try syncable.encryptedAddressCity.flatMap { try decrypt($0) }
        let addressProvince = try syncable.encryptedAddressProvince.flatMap { try decrypt($0) }
        let addressPostalCode = try syncable.encryptedAddressPostalCode.flatMap { try decrypt($0) }
        let addressCountryCode = try syncable.encryptedAddressCountryCode.flatMap { try decrypt($0) }

        let birthdayComponents: DateComponents?
        if let birthdayString = birthday {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)

            if let date = formatter.date(from: birthdayString) {
                let calendar = Calendar(identifier: .gregorian)
                birthdayComponents = calendar.dateComponents([.year, .month, .day], from: date)
            } else {
                birthdayComponents = nil
            }
        } else {
            birthdayComponents = nil
        }

        if identity == nil {
            identity = SecureVaultModels.Identity(
                id: metadata.objectId,
                title: title ?? "",
                created: Date(),
                lastUpdated: Date(),
                firstName: firstName,
                middleName: middleName,
                lastName: lastName,
                birthdayDay: birthdayComponents?.day,
                birthdayMonth: birthdayComponents?.month,
                birthdayYear: birthdayComponents?.year,
                addressStreet: addressStreet,
                addressStreet2: addressStreet2,
                addressCity: addressCity,
                addressProvince: addressProvince,
                addressPostalCode: addressPostalCode,
                addressCountryCode: addressCountryCode,
                homePhone: phone,
                mobilePhone: nil,
                emailAddress: emailAddress
            )
        } else {
            identity?.title = title ?? ""
            identity?.lastUpdated = Date()
            identity?.firstName = firstName
            identity?.middleName = middleName
            identity?.lastName = lastName
            identity?.birthdayDay = birthdayComponents?.day
            identity?.birthdayMonth = birthdayComponents?.month
            identity?.birthdayYear = birthdayComponents?.year
            identity?.addressStreet = addressStreet
            identity?.addressStreet2 = addressStreet2
            identity?.addressCity = addressCity
            identity?.addressProvince = addressProvince
            identity?.addressPostalCode = addressPostalCode
            identity?.addressCountryCode = addressCountryCode
            identity?.homePhone = phone
            identity?.mobilePhone = nil
            identity?.emailAddress = emailAddress
        }
    }

}

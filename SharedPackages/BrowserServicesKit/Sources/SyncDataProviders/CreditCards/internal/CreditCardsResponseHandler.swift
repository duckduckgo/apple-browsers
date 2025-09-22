//
//  CreditCardsResponseHandler.swift
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

final class CreditCardsResponseHandler {
    let feature: Feature = .init(name: "credit-cards")

    let clientTimestamp: Date
    let received: [SyncableCreditCardsAdapter]
    let secureVault: any AutofillSecureVault
    let database: Database
    let shouldDeduplicateEntities: Bool

    let allReceivedIDs: Set<String>
    private var creditCardsByUUID: [String: SecureVaultModels.SyncableCreditCard] = [:]

    var incomingModifiedCreditCards = [SecureVaultModels.CreditCard]()
    var incomingDeletedCreditCards = [SecureVaultModels.CreditCard]()

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
        self.received = received.map(SyncableCreditCardsAdapter.init)
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

        creditCardsByUUID = try secureVault.syncableCreditCardsForSyncIds(allUUIDs, in: database).reduce(into: .init(), { $0[$1.metadata.uuid] = $1 })
    }

    func processReceivedCreditCards() throws {
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

    private func processEntity(with syncable: SyncableCreditCardsAdapter, secureVaultEncryptionKey: Data) throws {
        guard let syncableUUID = syncable.uuid else {
            throw SyncError.receivedCreditCardsWithoutUUID
        }

        if shouldDeduplicateEntities,
           var deduplicatedEntity = try deduplicatedCreditCard(with: syncable, secureVaultEncryptionKey: secureVaultEncryptionKey) {
            let oldUUID = deduplicatedEntity.metadata.uuid
            if let decryptedTitle = try syncable.encryptedTitle.flatMap(decrypt) {
                deduplicatedEntity.creditCard?.title = decryptedTitle
            } else {
                deduplicatedEntity.creditCard?.title = ""
            }
            deduplicatedEntity.metadata.uuid = syncableUUID
            try secureVault.storeSyncableCreditCard(deduplicatedEntity,
                                                    in: database,
                                                    encryptedUsing: secureVaultEncryptionKey)

            creditCardsByUUID.removeValue(forKey: oldUUID)
            creditCardsByUUID[syncableUUID] = deduplicatedEntity

        } else if var existingEntity = creditCardsByUUID[syncableUUID] {
            let isModifiedAfterSyncTimestamp: Bool = {
                guard let modifiedAt = existingEntity.metadata.lastModified else {
                    return false
                }
                return modifiedAt > clientTimestamp
            }()

            if syncable.isDeleted {
                try secureVault.deleteSyncableCreditCard(existingEntity, in: database)
                trackCreditCardChange(of: existingEntity, with: syncable)
            } else if isModifiedAfterSyncTimestamp {
                metricsEvents?.fire(.localTimestampResolutionTriggered(feature: feature))
            } else {
                try existingEntity.update(with: syncable, decryptedUsing: decrypt)
                existingEntity.metadata.lastModified = nil
                try secureVault.storeSyncableCreditCard(existingEntity,
                                                        in: database,
                                                        encryptedUsing: secureVaultEncryptionKey)
                trackCreditCardChange(of: existingEntity, with: syncable)
            }

        } else if !syncable.isDeleted {
            let newEntity = try SecureVaultModels.SyncableCreditCard(syncable: syncable, decryptedUsing: decrypt)
            assert(newEntity.metadata.lastModified == nil, "lastModified should be nil for a new metadata entity")
            try secureVault.storeSyncableCreditCard(newEntity,
                                                    in: database,
                                                    encryptedUsing: secureVaultEncryptionKey)
            creditCardsByUUID[syncableUUID] = newEntity
            trackCreditCardChange(of: newEntity, with: syncable)
        }
    }

    private func deduplicatedCreditCard(with syncable: SyncableCreditCardsAdapter,
                                        secureVaultEncryptionKey: Data) throws -> SecureVaultModels.SyncableCreditCard? {

        guard !syncable.isDeleted else {
            return nil
        }

        let cardholderName = try syncable.encryptedCardholderName.flatMap(decrypt)
        let cardNumber = try syncable.encryptedCardNumber.flatMap(decrypt)
        let cardSecurityCode = try syncable.encryptedCardSecurityCode.flatMap(decrypt)
        let expirationMonth = try syncable.encryptedExpirationMonth.flatMap(decrypt)
        let expirationYear = try syncable.encryptedExpirationYear.flatMap(decrypt)

        let creditCardAlias = TableAlias()
        let conditions = [
            !allReceivedIDs.contains(SecureVaultModels.SyncableCreditCardsRecord.Columns.uuid),
            creditCardAlias[SecureVaultModels.CreditCard.Columns.cardholderName] == cardholderName,
            creditCardAlias[SecureVaultModels.CreditCard.Columns.cardSecurityCode] == cardSecurityCode,
            creditCardAlias[SecureVaultModels.CreditCard.Columns.expirationMonth] == expirationMonth,
            creditCardAlias[SecureVaultModels.CreditCard.Columns.expirationYear] == expirationYear
        ]

        let syncableCreditCards = try SecureVaultModels.SyncableCreditCardsRecord
            .including(optional: SecureVaultModels.SyncableCreditCardsRecord.creditCard.aliased(creditCardAlias))
            .filter(conditions.joined(operator: .and))
            .asRequest(of: SecureVaultModels.SyncableCreditCard.self)
            .fetchAll(database)

        guard !syncableCreditCards.isEmpty else {
            return nil
        }

        if let cardNumber, let cardNumberData = cardNumber.data(using: .utf8) {
            var matchingSyncableCreditCard = try syncableCreditCards.first(where: { creditCard in
                let decryptedCardNumber = try (creditCard.creditCard?.cardNumberData)
                    .flatMap { try secureVault.decrypt($0, using: secureVaultEncryptionKey) }
                return decryptedCardNumber == cardNumberData
            })
            // update matched credit card with decrypted card number, as that's what Secure Vault expects
            matchingSyncableCreditCard?.creditCard?.cardNumberData = cardNumberData
            return matchingSyncableCreditCard
        }
        return syncableCreditCards.first
    }

    private func trackCreditCardChange(of entity: SecureVaultModels.SyncableCreditCard, with syncable: SyncableCreditCardsAdapter) {
        guard let creditCard = entity.creditCard else {
            return
        }

        if syncable.isDeleted {
            incomingDeletedCreditCards.append(creditCard)
        } else {
            incomingModifiedCreditCards.append(creditCard)
        }
    }
}

extension SecureVaultModels.SyncableCreditCard {

    init(syncable: SyncableCreditCardsAdapter, decryptedUsing decrypt: (String) throws -> String) throws {
        guard let uuid = syncable.uuid else {
            throw SyncError.receivedCreditCardsWithoutUUID
        }

        let title = try syncable.encryptedTitle.flatMap { try decrypt($0) }
        let cardholderName = try syncable.encryptedCardholderName.flatMap { try decrypt($0) }
        let cardNumber = try syncable.encryptedCardNumber.flatMap { try decrypt($0) }
        let cardSecurityCode = try syncable.encryptedCardSecurityCode.flatMap { try decrypt($0) }
        let expirationMonth = try syncable.encryptedExpirationMonth.flatMap { try decrypt($0) }
        let expirationYear = try syncable.encryptedExpirationYear.flatMap { try decrypt($0) }

        // Convert string expiration values to Int
        let expirationMonthInt = expirationMonth.flatMap { Int($0) }
        let expirationYearInt = expirationYear.flatMap { Int($0) }

        let creditCard = SecureVaultModels.CreditCard(
            title: title,
            cardNumber: cardNumber ?? "",
            cardholderName: cardholderName,
            cardSecurityCode: cardSecurityCode,
            expirationMonth: expirationMonthInt,
            expirationYear: expirationYearInt
        )

        self.init(uuid: uuid, creditCard: creditCard, lastModified: nil)
    }

    mutating func update(with syncable: SyncableCreditCardsAdapter, decryptedUsing decrypt: (String) throws -> String) throws {
        let title = try syncable.encryptedTitle.flatMap(decrypt)
        let cardholderName = try syncable.encryptedCardholderName.flatMap(decrypt)
        let cardNumber = try syncable.encryptedCardNumber.flatMap(decrypt)
        let cardSecurityCode = try syncable.encryptedCardSecurityCode.flatMap(decrypt)
        let expirationMonth = try syncable.encryptedExpirationMonth.flatMap(decrypt)
        let expirationYear = try syncable.encryptedExpirationYear.flatMap(decrypt)

        // Convert string expiration values to Int
        let expirationMonthInt = expirationMonth.flatMap { Int($0) }
        let expirationYearInt = expirationYear.flatMap { Int($0) }

        if creditCard == nil {
            creditCard = .init(
                title: title,
                cardNumber: cardNumber ?? "",
                cardholderName: cardholderName,
                cardSecurityCode: cardSecurityCode,
                expirationMonth: expirationMonthInt,
                expirationYear: expirationYearInt
            )
        } else {
            creditCard?.title = title ?? ""
            creditCard?.cardholderName = cardholderName
            if let cardNumber, let cardNumberData = cardNumber.data(using: .utf8) {
                creditCard?.cardNumberData = cardNumberData
            }
            creditCard?.cardSecurityCode = cardSecurityCode
            creditCard?.expirationMonth = expirationMonthInt
            creditCard?.expirationYear = expirationYearInt
        }

        assert(creditCard != nil)
    }
}

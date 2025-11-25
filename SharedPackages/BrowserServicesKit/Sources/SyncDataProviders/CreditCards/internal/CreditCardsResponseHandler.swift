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
    private var deduplicatedLocalCardObjectIds: Set<Int64> = []

    var incomingModifiedCreditCards = [SecureVaultModels.CreditCard]()
    var incomingDeletedCreditCards = [SecureVaultModels.CreditCard]()

    private let decrypt: (String) throws -> String
    private let metricsEvents: EventMapping<MetricsEvent>?

    private struct DeduplicationResult {
        let card: SecureVaultModels.SyncableCreditCard
        let oldUUID: String
    }

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

    private func isValidCreditCardData(_ syncable: SyncableCreditCardsAdapter) -> Bool {
        guard let encryptedCardNumber = syncable.encryptedCardNumber,
              let cardNumber = try? decrypt(encryptedCardNumber),
              !cardNumber.isEmpty else {
            return false
        }
        return cardNumber.allSatisfy { $0.isASCII && $0.isWholeNumber }
    }

    private func processEntity(with syncable: SyncableCreditCardsAdapter, secureVaultEncryptionKey: Data) throws {
        guard let syncableUUID = syncable.uuid else {
            throw SyncError.receivedCreditCardsWithoutUUID
        }

        if !syncable.isDeleted {
            guard isValidCreditCardData(syncable) else { return }
        }

        if shouldDeduplicateEntities,
           let deduplicationResult = try deduplicateCreditCard(syncable: syncable,
                                                               incomingUUID: syncableUUID,
                                                               encryptionKey: secureVaultEncryptionKey) {
            try secureVault.storeSyncableCreditCard(deduplicationResult.card,
                                                    in: database,
                                                    encryptedUsing: secureVaultEncryptionKey)
            creditCardsByUUID.removeValue(forKey: deduplicationResult.oldUUID)
            creditCardsByUUID[deduplicationResult.card.metadata.uuid] = deduplicationResult.card

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

    private func deduplicateCreditCard(syncable: SyncableCreditCardsAdapter,
                                       incomingUUID: String,
                                       encryptionKey: Data) throws -> DeduplicationResult? {
        guard !syncable.isDeleted else { return nil }

        let cardNumber = try syncable.encryptedCardNumber.flatMap(decrypt)
        let expirationMonth = try syncable.encryptedExpirationMonth.flatMap(decrypt)
        let expirationYear = try syncable.encryptedExpirationYear.flatMap(decrypt)

        guard let cardNumberString = cardNumber else { return nil }

        // Find local cards (excluding those in the received payload)
        let syncableCreditCards = try SecureVaultModels.SyncableCreditCardsRecord
            .including(optional: SecureVaultModels.SyncableCreditCardsRecord.creditCard)
            .filter(!allReceivedIDs.contains(SecureVaultModels.SyncableCreditCardsRecord.Columns.uuid))
            .asRequest(of: SecureVaultModels.SyncableCreditCard.self)
            .fetchAll(database)

        // Find matches by card number
        guard let matched = try findMatchByCardNumber(cardNumberString,
                                                      in: syncableCreditCards,
                                                      encryptionKey: encryptionKey) else {
            return nil
        }

        // Check if we already deduplicated this local card
        if let objectId = matched.metadata.objectId, deduplicatedLocalCardObjectIds.contains(objectId) {
            return nil
        }

        let incomingExpiration = SecureVaultModels.SyncableCreditCard.normalizedExpirationValues(
            month: expirationMonth,
            year: expirationYear
        )
        let localExpiration = SecureVaultModels.SyncableCreditCard.normalizedExpirationValues(
            month: matched.creditCard?.expirationMonth.flatMap(String.init),
            year: matched.creditCard?.expirationYear.flatMap(String.init)
        )

        let yearComparison = incomingExpiration.value.year > localExpiration.value.year
        let sameYearNewerOrEqualMonth = (incomingExpiration.value.year == localExpiration.value.year &&
                                         incomingExpiration.value.month >= localExpiration.value.month)
        let incomingWins = yearComparison || sameYearNewerOrEqualMonth

        // Mark this local card as processed
        if let objectId = matched.metadata.objectId {
            deduplicatedLocalCardObjectIds.insert(objectId)
        }

        if incomingWins {
            var card = matched
            try card.update(with: syncable, decryptedUsing: decrypt)
            card.metadata.uuid = incomingUUID
            card.metadata.lastModified = nil
            return DeduplicationResult(card: card, oldUUID: matched.metadata.uuid)
        }

        if localExpiration.hasData || incomingExpiration.hasData {
            var card = matched
            // Decrypt card number data since it was fetched directly from database
            if let encryptedCardNumber = card.creditCard?.cardNumberData {
                card.creditCard?.cardNumberData = try secureVault.decrypt(encryptedCardNumber, using: encryptionKey)
            }
            card.metadata.uuid = incomingUUID
            card.metadata.lastModified = Date().withMillisecondPrecision
            return DeduplicationResult(card: card, oldUUID: matched.metadata.uuid)
        }

        // Neither side had usable expiry info – keep the remote data
        var card = matched
        try card.update(with: syncable, decryptedUsing: decrypt)
        card.metadata.uuid = incomingUUID
        card.metadata.lastModified = nil
        return DeduplicationResult(card: card, oldUUID: matched.metadata.uuid)
    }

    private func findMatchByCardNumber(_ cardNumber: String,
                                       in syncableCreditCards: [SecureVaultModels.SyncableCreditCard],
                                       encryptionKey: Data) throws -> SecureVaultModels.SyncableCreditCard? {
        guard let cardNumberData = cardNumber.data(using: .utf8) else { return nil }

        for creditCard in syncableCreditCards {
            guard let encryptedCardNumber = creditCard.creditCard?.cardNumberData else { continue }

            let decryptedCardNumberData = try secureVault.decrypt(encryptedCardNumber, using: encryptionKey)
            if decryptedCardNumberData == cardNumberData {
                return creditCard
            }
        }
        return nil
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

        let (expirationMonthInt, expirationYearInt) = Self.validatedExpirationValues(month: expirationMonth, year: expirationYear)

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

        let (expirationMonthInt, expirationYearInt) = Self.validatedExpirationValues(month: expirationMonth, year: expirationYear)

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

extension SecureVaultModels.SyncableCreditCard {

    static func normalizedExpirationValues(month: String?, year: String?) -> (value: (month: Int, year: Int), hasData: Bool) {
        let monthInt = month.flatMap(Int.init) ?? 0
        let yearInt = year.flatMap(Int.init) ?? 0
        let hasData = (month != nil && !month!.isEmpty) || (year != nil && !year!.isEmpty)
        return ((monthInt, yearInt), hasData)
    }

    static func validatedExpirationValues(month: String?, year: String?) -> (month: Int?, year: Int?) {
        guard let month,
              let year,
              let monthInt = Int(month),
              let yearInt = Int(year) else {
            return (nil, nil)
        }
        return (monthInt, yearInt)
    }
}

//
//  SecureVaultSyncableCreditCardsTests.swift
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

import GRDB
import XCTest
@testable import BrowserServicesKit

class SecureVaultSyncableCreditCardsTests: XCTestCase {

    let simpleL1Key = "simple-key".data(using: .utf8)!
    var databaseLocation: URL!
    var provider: DefaultAutofillDatabaseProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()
        databaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        provider = try DefaultAutofillDatabaseProvider(file: databaseLocation, key: simpleL1Key)
    }

    override func tearDownWithError() throws {
        try deleteDbFile()
        try super.tearDownWithError()
    }

    func testWhenCreditCardsAreInsertedThenSyncableCreditCardsArePopulated() throws {
        let creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "John Doe",
            cardSecurityCode: "123",
            expirationMonth: 12,
            expirationYear: 2025
        )
        let cardId = try provider.storeCreditCard(creditCard)

        let syncableCreditCards = try provider.modifiedSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards[0].metadata.objectId, cardId)
        XCTAssertNotNil(syncableCreditCards[0].metadata.lastModified)
    }

    func testWhenSyncableCreditCardsAreInsertedThenObjectIdIsPopulated() throws {
        let creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "John Doe",
            cardSecurityCode: "123",
            expirationMonth: 12,
            expirationYear: 2025
        )
        let metadata = SecureVaultModels.SyncableCreditCard(uuid: UUID().uuidString, creditCard: creditCard, lastModified: nil)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCreditCard(metadata, in: database)
        }

        let syncableCreditCards = try provider.db.read { database in
            try SecureVaultModels.SyncableCreditCard.query.fetchAll(database)
        }

        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards[0].metadata.objectId, 1)
        XCTAssertNil(syncableCreditCards[0].metadata.lastModified)
    }

    func testWhenSyncableCreditCardsAreInsertedThenNilLastModifiedIsHonored() throws {
        let creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "5555555555554444",
            cardholderName: "Jane Doe",
            cardSecurityCode: "456",
            expirationMonth: 6,
            expirationYear: 2026
        )
        let metadata = SecureVaultModels.SyncableCreditCard(uuid: UUID().uuidString, creditCard: creditCard, lastModified: nil)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCreditCard(metadata, in: database)
        }

        let syncableCreditCards = try provider.db.read { database in
            try SecureVaultModels.SyncableCreditCard.query.fetchAll(database)
        }

        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertNil(syncableCreditCards[0].metadata.lastModified)
    }

    func testWhenSyncableCreditCardsAreInsertedThenNonNilLastModifiedIsHonored() throws {
        let creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "378282246310005",
            cardholderName: "Alice Johnson",
            cardSecurityCode: "1234",
            expirationMonth: 3,
            expirationYear: 2027
        )
        let timestamp = Date().withMillisecondPrecision
        let syncableCreditCard = SecureVaultModels.SyncableCreditCard(uuid: UUID().uuidString, creditCard: creditCard, lastModified: timestamp)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCreditCard(syncableCreditCard, in: database)
        }

        let allSyncableCreditCards = try provider.db.read { database in
            try SecureVaultModels.SyncableCreditCard.query.fetchAll(database)
        }

        XCTAssertEqual(allSyncableCreditCards.count, 1)
        XCTAssertEqual(allSyncableCreditCards[0].metadata.lastModified!.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWhenSyncableCreditCardsAreUpdatedThenNonNilLastModifiedIsHonored() throws {
        let creditCard = SecureVaultModels.CreditCard(
            id: 2,
            title: "Test Card",
            cardNumber: "6011111111111117",
            cardholderName: "Bob Wilson",
            cardSecurityCode: "789",
            expirationMonth: 9,
            expirationYear: 2028
        )
        let timestamp = Date().withMillisecondPrecision
        var syncableCreditCard = SecureVaultModels.SyncableCreditCard(uuid: UUID().uuidString, creditCard: creditCard, lastModified: timestamp)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCreditCard(syncableCreditCard, in: database)
        }

        syncableCreditCard = try provider.db.read { database in
            try XCTUnwrap(
                try SecureVaultModels.SyncableCreditCard.query
                    .filter(SecureVaultModels.SyncableCreditCardsRecord.Columns.objectId == 2)
                    .fetchOne(database)
            )
        }
        syncableCreditCard.creditCard?.cardholderName = "Bob Wilson Jr."

        try provider.inTransaction { database in
            try self.provider.storeSyncableCreditCard(syncableCreditCard, in: database)
        }

        let metadataObjects = try provider.db.read { database in
            try SecureVaultModels.SyncableCreditCard.query.fetchAll(database)
        }

        XCTAssertEqual(metadataObjects.count, 1)
        XCTAssertEqual(metadataObjects[0].metadata.lastModified!.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWhenCreditCardsAreUpdatedThenSyncTimestampIsUpdated() throws {
        let creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "Test User",
            cardSecurityCode: "123",
            expirationMonth: 1,
            expirationYear: 2025
        )
        let cardId = try provider.storeCreditCard(creditCard)

        var metadata = try XCTUnwrap(try provider.db.read { try SecureVaultModels.SyncableCreditCardsRecord.fetchOne($0) })
        metadata.lastModified = nil
        try provider.db.write { try metadata.update($0) }

        var storedCard = try XCTUnwrap(try provider.db.read { try SecureVaultModels.CreditCard.fetchOne($0) })
        storedCard.cardholderName = "Updated User"
        try provider.storeCreditCard(storedCard)

        let syncableCreditCards = try provider.modifiedSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards[0].metadata.objectId, cardId)
        XCTAssertNotNil(syncableCreditCards[0].metadata.lastModified)
    }

    func testWhenSyncableCreditCardsAreDeletedThenCreditCardIsDeleted() throws {
        let creditCard = SecureVaultModels.CreditCard(
            id: 2,
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "John Doe",
            cardSecurityCode: "123",
            expirationMonth: 12,
            expirationYear: 2025
        )
        var syncableCreditCard = SecureVaultModels.SyncableCreditCard(uuid: UUID().uuidString, creditCard: creditCard, lastModified: nil)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCreditCard(syncableCreditCard, in: database)
        }

        syncableCreditCard = try provider.db.read { database in
            try XCTUnwrap(
                try SecureVaultModels.SyncableCreditCard.query
                    .filter(SecureVaultModels.SyncableCreditCardsRecord.Columns.objectId == 2)
                    .fetchOne(database)
            )
        }

        try provider.inTransaction { database in
            try self.provider.deleteSyncableCreditCard(syncableCreditCard, in: database)
        }

        let allSyncableCreditCards = try provider.db.read { database in
            try SecureVaultModels.SyncableCreditCard.query.fetchAll(database)
        }

        let creditCards = try provider.db.read { database in
            try SecureVaultModels.CreditCard.fetchAll(database)
        }

        XCTAssertTrue(allSyncableCreditCards.isEmpty)
        XCTAssertTrue(creditCards.isEmpty)
        XCTAssertNil(try provider.creditCardForCardId(2))
    }

    func testWhenCardNumberIsUpdatedThenSyncableCreditCardsTimestampIsUpdated() throws {
        var creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "Test User",
            cardSecurityCode: "123",
            expirationMonth: 1,
            expirationYear: 2025
        )
        creditCard = try storeAndFetchCreditCard(creditCard)
        let createdTimestamp = try provider.modifiedSyncableCreditCards().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        creditCard.cardNumberData = "5555555555554444".data(using: .utf8)!
        creditCard = try storeAndFetchCreditCard(creditCard)

        let syncableCreditCards = try provider.modifiedSyncableCreditCards()
        XCTAssertGreaterThan(syncableCreditCards[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenCardholderNameIsUpdatedThenSyncableCreditCardsTimestampIsUpdated() throws {
        var creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "Test User",
            cardSecurityCode: "123",
            expirationMonth: 1,
            expirationYear: 2025
        )
        creditCard = try storeAndFetchCreditCard(creditCard)
        let createdTimestamp = try provider.modifiedSyncableCreditCards().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        creditCard.cardholderName = "Updated User"
        creditCard = try storeAndFetchCreditCard(creditCard)

        let syncableCreditCards = try provider.modifiedSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards[0].metadata.objectId, creditCard.id)
        XCTAssertGreaterThan(syncableCreditCards[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenTitleIsUpdatedThenSyncableCreditCardsTimestampIsUpdated() throws {
        var creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "Test User",
            cardSecurityCode: "123",
            expirationMonth: 1,
            expirationYear: 2025
        )
        creditCard = try storeAndFetchCreditCard(creditCard)
        let createdTimestamp = try provider.modifiedSyncableCreditCards().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        creditCard.title = "Updated Card Title"
        creditCard = try storeAndFetchCreditCard(creditCard)

        let syncableCreditCards = try provider.modifiedSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards[0].metadata.objectId, creditCard.id)
        XCTAssertGreaterThan(syncableCreditCards[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenExpirationDateIsUpdatedThenSyncableCreditCardsTimestampIsUpdated() throws {
        var creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "Test User",
            cardSecurityCode: "123",
            expirationMonth: 1,
            expirationYear: 2025
        )
        creditCard = try storeAndFetchCreditCard(creditCard)
        let createdTimestamp = try provider.modifiedSyncableCreditCards().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        creditCard.expirationMonth = 6
        creditCard.expirationYear = 2026
        creditCard = try storeAndFetchCreditCard(creditCard)

        let syncableCreditCards = try provider.modifiedSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards[0].metadata.objectId, creditCard.id)
        XCTAssertGreaterThan(syncableCreditCards[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenSecurityCodeIsUpdatedThenSyncableCreditCardsTimestampIsUpdated() throws {
        var creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "Test User",
            cardSecurityCode: "123",
            expirationMonth: 1,
            expirationYear: 2025
        )
        creditCard = try storeAndFetchCreditCard(creditCard)
        let createdTimestamp = try provider.modifiedSyncableCreditCards().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        creditCard.cardSecurityCode = "456"
        creditCard = try storeAndFetchCreditCard(creditCard)

        let syncableCreditCards = try provider.modifiedSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards[0].metadata.objectId, creditCard.id)
        XCTAssertGreaterThan(syncableCreditCards[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenCreditCardIsDeletedThenSyncableCreditCardIsPersisted() throws {
        var creditCard = SecureVaultModels.CreditCard(
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "Test User",
            cardSecurityCode: "123",
            expirationMonth: 1,
            expirationYear: 2025
        )
        creditCard = try storeAndFetchCreditCard(creditCard)
        let metadata = try provider.modifiedSyncableCreditCards().first!
        let cardId = try XCTUnwrap(metadata.metadata.objectId)
        Thread.sleep(forTimeInterval: 0.001)

        try provider.deleteCreditCardForCreditCardId(cardId)

        let syncableCreditCards = try provider.modifiedSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards[0].metadata.objectId, nil)
        XCTAssertGreaterThan(syncableCreditCards[0].metadata.lastModified!, metadata.metadata.lastModified!)
    }

    // MARK: - Private

    private func storeAndFetchCreditCard(_ creditCard: SecureVaultModels.CreditCard) throws -> SecureVaultModels.CreditCard {
        let cardId = try provider.storeCreditCard(creditCard)
        return try XCTUnwrap(try provider.creditCardForCardId(cardId))
    }

    private func deleteDbFile() throws {
        do {
            let dbFileContainer = databaseLocation.deletingLastPathComponent()
            for file in try FileManager.default.contentsOfDirectory(atPath: dbFileContainer.path) {
                guard ["db", "bak"].contains((file as NSString).pathExtension) else { continue }
                try FileManager.default.removeItem(atPath: dbFileContainer.appendingPathComponent(file).path)
            }

#if os(iOS)
            let sharedDbFileContainer = DefaultAutofillDatabaseProvider.defaultSharedDatabaseURL().deletingLastPathComponent()
            for file in try FileManager.default.contentsOfDirectory(atPath: sharedDbFileContainer.path) {
                guard ["db", "bak"].contains((file as NSString).pathExtension) else { continue }
                try FileManager.default.removeItem(atPath: sharedDbFileContainer.appendingPathComponent(file).path)
            }
#endif
        } catch let error as NSError {
            // File not found
            if error.domain != NSCocoaErrorDomain || error.code != 4 {
                throw error
            }
        }
    }
}

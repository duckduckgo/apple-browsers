//
//  CreditCardsProviderTests.swift
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

import XCTest
import Common
import DDGSync
import GRDB
import Persistence
@testable import BrowserServicesKit
@testable import SyncDataProviders

final class CreditCardsProviderTests: CreditCardsProviderTestsBase {

    func testThatLastSyncTimestampIsNilByDefault() {
        XCTAssertNil(provider.lastSyncTimestamp)
        XCTAssertNil(provider.lastSyncLocalTimestamp)
    }

    func testThatLastSyncTimestampIsPersisted() throws {
        try provider.registerFeature(withState: .readyToSync)
        let date = Date()
        provider.updateSyncTimestamps(server: "12345", local: date)
        XCTAssertEqual(provider.lastSyncTimestamp, "12345")
        XCTAssertEqual(provider.lastSyncLocalTimestamp, date)
    }

    func testThatPrepareForFirstSyncClearsLastSyncTimestampAndSetsModifiedAtForAllCreditCards() throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
            try self.secureVault.storeSyncableCreditCard("2", cardNumber: "5555555555554444", in: database)
            try self.secureVault.storeSyncableCreditCard("3", cardNumber: "378282246310005", in: database)
            try self.secureVault.storeSyncableCreditCard("4", cardNumber: "6011111111111117", in: database)
        }

        var syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertTrue(syncableCreditCards.allSatisfy { $0.metadata.lastModified == nil })

        try provider.prepareForFirstSync()

        XCTAssertNil(provider.lastSyncTimestamp)

        syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 4)
        XCTAssertTrue(syncableCreditCards.allSatisfy { $0.metadata.lastModified != nil })
    }

    func testThatFetchChangedObjectsReturnsAllObjectsWithNonNilModifiedAt() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCreditCard("2", cardNumber: "5555555555554444", in: database)
            try self.secureVault.storeSyncableCreditCard("3", cardNumber: "378282246310005", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCreditCard("4", cardNumber: "6011111111111117", in: database)
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableCreditCardsAdapter.init)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set(["1", "3"])
        )
    }

    func testThatFetchChangedObjectsFiltersOutInvalidCreditCards() async throws {
        let longValue = String(repeating: "x", count: 10000)

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", title: longValue, cardNumber: "4111111111111111", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCreditCard("2", cardNumber: "5555555555554444", in: database)
            try self.secureVault.storeSyncableCreditCard("3", cardNumber: "378282246310005", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCreditCard("4", cardNumber: "6011111111111117", in: database)
            try self.secureVault.storeSyncableCreditCard("5", cardholderName: longValue, cardNumber: "4532015112830366", lastModified: Date(), in: database)
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableCreditCardsAdapter.init)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set(["3"])
        )
    }

    func testWhenCreditCardsAreSoftDeletedThenFetchChangedObjectsContainsDeletedSyncable() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
            try self.secureVault.storeSyncableCreditCard("2", cardNumber: "5555555555554444", in: database)
            try self.secureVault.storeSyncableCreditCard("3", cardNumber: "378282246310005", in: database)
            try self.secureVault.storeSyncableCreditCard("4", cardNumber: "6011111111111117", in: database)
        }

        try secureVault.deleteCreditCardFor(cardId: 2)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableCreditCardsAdapter.init)

        XCTAssertEqual(changedObjects.count, 1)

        let syncable = try XCTUnwrap(changedObjects.first)

        XCTAssertTrue(syncable.isDeleted)
        XCTAssertEqual(syncable.uuid, "2")
    }

    func testThatSentItemsAreProperlyCleanedUp() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("10", cardNumber: "4111111111111111", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCreditCard("20", cardNumber: "5555555555554444", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCreditCard("30", cardNumber: "378282246310005", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCreditCard("40", cardNumber: "6011111111111117", lastModified: Date(), in: database)
        }

        try secureVault.deleteCreditCardFor(cardId: 2)

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 3)
        XCTAssertTrue(syncableCreditCards.allSatisfy { $0.metadata.lastModified == nil })
    }

    func testThatItemsThatFailedValidationRetainTheirTimestamps() async throws {
        let longValue = String(repeating: "x", count: 10000)
        let timestamp = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("10", title: longValue, cardNumber: "4111111111111111", lastModified: timestamp, in: database)
            try self.secureVault.storeSyncableCreditCard("20", cardNumber: "5555555555554444", lastModified: timestamp, in: database)
            try self.secureVault.storeSyncableCreditCard("30", title: longValue, cardNumber: "378282246310005", lastModified: timestamp, in: database)
            try self.secureVault.storeSyncableCreditCard("40", cardNumber: "6011111111111117", lastModified: timestamp, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 4)
        XCTAssertNotNil(syncableCreditCards.first(where: { $0.metadata.uuid == "10" })?.metadata.lastModified)
        XCTAssertNil(syncableCreditCards.first(where: { $0.metadata.uuid == "20" })?.metadata.lastModified)
        XCTAssertNotNil(syncableCreditCards.first(where: { $0.metadata.uuid == "30" })?.metadata.lastModified)
        XCTAssertNil(syncableCreditCards.first(where: { $0.metadata.uuid == "40" })?.metadata.lastModified)
    }

    func testThatDeduplicationReturnsOnlyOneOfDuplicateCreditCards() async throws {
        try secureVault.inDatabaseTransaction { database in

            try self.secureVault.storeSyncableCreditCard("1", title: "Card A", cardholderName: "User", cardNumber: "4111111111111111", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCreditCard("2", title: "Card A", cardholderName: "User", cardNumber: "4111111111111111", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCreditCard("3", title: "Card B", cardholderName: "Other", cardNumber: "5555555555554444", lastModified: Date(), in: database)
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableCreditCardsAdapter.init)

        XCTAssertEqual(changedObjects.count, 3)
    }

    func testThatInitialSyncIntoEmptyDatabaseClearsModifiedAtFromAllReceivedObjects() async throws {
        let received: [Syncable] = [
            .creditCard(uuid: "1", cardNumber: "4111111111111111"),
            .creditCard(uuid: "2", cardNumber: "5555555555554444")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 2)
        XCTAssertTrue(syncableCreditCards.allSatisfy { $0.metadata.lastModified == nil })
    }

    func testThatInitialSyncClearsModifiedAtFromDeduplicatedCreditCard() async throws {
        try secureVault.inDatabaseTransaction { database in

            try self.secureVault.storeSyncableCreditCard("1", title: "Card", cardholderName: "User", cardNumber: "4111111111111111", cardSecurityCode: "2", expirationMonth: 2, expirationYear: 2, lastModified: Date(), in: database)
        }

        let received: [Syncable] = [

            .creditCard("Card", uuid: "2", cardholderName: "User", cardNumber: "4111111111111111", cardSecurityCode: "2", expirationMonth: "2", expirationYear: "2")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "2")
        XCTAssertNil(syncableCreditCards.first?.metadata.lastModified)
    }

    func testThatInitialSyncClearsModifiedAtFromDeduplicatedCreditCardWithAllFieldsNil() async throws {

        try secureVault.inDatabaseTransaction { database in
            let creditCard = SecureVaultModels.CreditCard(
                title: nil,
                cardNumber: "4111111111111111",
                cardholderName: nil,
                cardSecurityCode: nil,
                expirationMonth: nil,
                expirationYear: nil
            )
            let syncableCreditCard = SecureVaultModels.SyncableCreditCard(
                uuid: "1",
                creditCard: creditCard,
                lastModified: nil
            )
            try self.secureVault.storeSyncableCreditCard(syncableCreditCard, in: database, encryptedUsing: Data())
        }

        let received: [Syncable] = [
            .creditCard(uuid: "2", cardNumber: "4111111111111111", nullifyOtherFields: true)
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        let creditCard = try XCTUnwrap(syncableCreditCards.first)
        XCTAssertNil(creditCard.metadata.lastModified)
    }

    func testWhenDatabaseIsLockedDuringInitialSyncThenSyncResponseHandlingIsRetried() async throws {
        let received: [Syncable] = [
            .creditCard(uuid: "1", cardNumber: "4111111111111111"),
            .creditCard(uuid: "2", cardNumber: "5555555555554444")
        ]

        var numberOfAttempts = 0
        var didThrowError = false

        provider.willSaveContextAfterApplyingSyncResponse = {
            numberOfAttempts += 1
            if !didThrowError {
                didThrowError = true
                throw DatabaseError(resultCode: .SQLITE_LOCKED)
            }
        }

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        XCTAssertEqual(numberOfAttempts, 2)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 2)
        XCTAssertTrue(syncableCreditCards.allSatisfy { $0.metadata.lastModified == nil })
    }

    // MARK: - Regular Sync

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedThenObjectIsNotDeleted() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
        }

        try secureVault.deleteCreditCardFor(cardId: 1)

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [.creditCard(uuid: "1", cardholderName: "Updated", cardNumber: "4111111111111111")]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: 1).withMillisecondPrecision, serverTimestamp: "1234", crypter: crypter)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "1")
        XCTAssertNil(syncableCreditCards.first?.metadata.lastModified)
    }

    func testWhenObjectWasSentAndThenDeletedLocallyAndAnUpdateIsReceivedThenTheObjectIsDeleted() async throws {
        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        try secureVault.deleteCreditCardFor(cardId: 1)

        let received: [Syncable] = [.creditCard(uuid: "1", cardholderName: "Updated", cardNumber: "4111111111111111")]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        let deletedCard = try XCTUnwrap(syncableCreditCards.first)
        XCTAssertNotNil(deletedCard.metadata.lastModified)
        XCTAssertNil(deletedCard.metadata.objectId)
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteChangesAreDropped() async throws {
        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", title: "Original", cardNumber: "4111111111111111", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [.creditCard("Remote Update", uuid: "1", cardNumber: "4111111111111111")]

        var creditCard = try XCTUnwrap(try secureVault.creditCardFor(id: 1))
        creditCard.title = "Local Update"
        try secureVault.storeCreditCard(creditCard)

        let updateTimestamp = try fetchAllSyncableCreditCards().first?.metadata.lastModified

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.first?.title, "Local Update")

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        let updatedCreditCard = try XCTUnwrap(syncableCreditCards.first)
        XCTAssertEqual(updatedCreditCard.metadata.lastModified, updateTimestamp)
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteDeletionIsApplied() async throws {
        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", title: "Original", cardNumber: "4111111111111111", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [.creditCard(uuid: "1", isDeleted: true)]

        var creditCard = try XCTUnwrap(try secureVault.creditCardFor(id: 1))
        creditCard.title = "Local Update"
        try secureVault.storeCreditCard(creditCard)

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 0)
    }

    func testWhenDatabaseIsLockedDuringRegularSyncThenSyncResponseHandlingIsRetried() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", lastModified: Date(), in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [
            .creditCard(uuid: "1", cardNumber: "4111111111111111")
        ]

        var numberOfAttempts = 0
        var didThrowError = false

        provider.willSaveContextAfterApplyingSyncResponse = {
            numberOfAttempts += 1
            if !didThrowError {
                didThrowError = true
                throw DatabaseError(resultCode: .SQLITE_LOCKED)
            }
        }

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        XCTAssertEqual(numberOfAttempts, 2)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertNil(syncableCreditCards.first?.metadata.lastModified)
    }
}

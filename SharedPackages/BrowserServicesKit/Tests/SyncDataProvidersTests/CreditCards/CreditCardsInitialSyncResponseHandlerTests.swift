//
//  CreditCardsInitialSyncResponseHandlerTests.swift
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

final class CreditCardsInitialSyncResponseHandlerTests: CreditCardsProviderTestsBase {

    func testThatNewCreditCardIsAppended() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
        }

        let received: [Syncable] = [
            .creditCard(uuid: "2", cardNumber: "5555555555554444")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 2)
        XCTAssertEqual(syncableCreditCards.map(\.metadata.uuid), ["1", "2"])
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testWhenDeletedCreditCardIsReceivedThenItIsDeletedLocally() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
            try self.secureVault.storeSyncableCreditCard("2", cardNumber: "5555555555554444", in: database)
        }

        let received: [Syncable] = [
            .creditCard(uuid: "1", isDeleted: true)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards.map(\.metadata.uuid), ["2"])
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatDeletesForNonExistentCreditCardsAreIgnored() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
        }

        let received: [Syncable] = [
            .creditCard(uuid: "2", isDeleted: true)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards.map(\.metadata.uuid), ["1"])
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatCreditCardsAreDeduplicated() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", title: "Card A", cardholderName: "User A", cardNumber: "4111111111111111", cardSecurityCode: "2", expirationMonth: 2, expirationYear: 2, in: database)
            try self.secureVault.storeSyncableCreditCard("3", title: "Card B", cardholderName: "User B", cardNumber: "378282246310005", cardSecurityCode: "4", expirationMonth: 4, expirationYear: 4, in: database)
        }

        let received: [Syncable] = [
            .creditCard("Card A", uuid: "2", cardholderName: "User A", cardNumber: "4111111111111111", cardSecurityCode: "2", expirationMonth: "2", expirationYear: "2"),
            .creditCard("Card B", uuid: "4", cardholderName: "User B", cardNumber: "378282246310005", cardSecurityCode: "4", expirationMonth: "4", expirationYear: "4")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 2)
        XCTAssertEqual(syncableCreditCards.map(\.metadata.uuid).sorted(), ["2", "4"])
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatExistingCreditCardIsUpdatedWhenMatchingUUID() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", title: "Original", cardholderName: "Original User", cardNumber: "4111111111111111", expirationMonth: 1, expirationYear: 2025, in: database)
        }

        let received: [Syncable] = [
            .creditCard("Updated", uuid: "1", cardholderName: "Updated User", cardNumber: "4111111111111111", expirationMonth: "12", expirationYear: "2026")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "1")

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards.first?.title, "Updated")
        XCTAssertEqual(creditCards.first?.cardholderName, "Updated User")
        XCTAssertEqual(creditCards.first?.expirationMonth, 12)
        XCTAssertEqual(creditCards.first?.expirationYear, 2026)
    }

    func testThatWhenCreditCardsAreDeduplicatedThenRemoteTitleIsApplied() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", title: "local-title1", cardholderName: "1", cardNumber: "4111111111111111", cardSecurityCode: "1", expirationMonth: 1, expirationYear: 1, in: database)
            try self.secureVault.storeSyncableCreditCard("3", title: "local-title2", cardholderName: "3", cardNumber: "5555555555554444", cardSecurityCode: "3", expirationMonth: 3, expirationYear: 3, in: database)
        }

        let received: [Syncable] = [
            .creditCard("remote-title1", uuid: "2", cardholderName: "1", cardNumber: "4111111111111111", cardSecurityCode: "1", expirationMonth: "1", expirationYear: "1"),
            .creditCard("remote-title2", uuid: "4", cardholderName: "3", cardNumber: "5555555555554444", cardSecurityCode: "3", expirationMonth: "3", expirationYear: "3")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 2)
        XCTAssertEqual(syncableCreditCards.map(\.metadata.uuid).sorted(), ["2", "4"])

        let creditCards = try secureVault.creditCards()
        let sortedCreditCards = creditCards.sorted { $0.cardNumber < $1.cardNumber }
        XCTAssertEqual(sortedCreditCards[0].title, "remote-title1")
        XCTAssertEqual(sortedCreditCards[1].title, "remote-title2")
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatCreditCardsWithNilFieldsAreDeduplicated() async throws {
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

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1, "Expected 1 card after deduplication, got \(syncableCreditCards.count)")
        XCTAssertEqual(syncableCreditCards.map(\.metadata.uuid), ["2"], "Expected UUID [2], got \(syncableCreditCards.map(\.metadata.uuid))")
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil }, "lastModified should be nil but got: \(syncableCreditCards.map(\.metadata.lastModified))")
    }

    func testWhenPayloadContainsDuplicatedRecordsThenAllRecordsAreStored() async throws {
        let received: [Syncable] = [
            .creditCard(uuid: "1", cardNumber: "4111111111111111", nullifyOtherFields: true),
            .creditCard(uuid: "2", cardNumber: "4111111111111111", nullifyOtherFields: true)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 2)
        XCTAssertEqual(syncableCreditCards.map(\.metadata.uuid).sorted(), ["1", "2"])
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatDeduplicationReplacesCardWithOlderExpirationDate() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("local-uuid",
                                                         title: "Old Expiry",
                                                         cardholderName: "Mr John Doe",
                                                         cardNumber: "4111111111111111",
                                                         cardSecurityCode: "987",
                                                         expirationMonth: 1,
                                                         expirationYear: 2025,
                                                         in: database)
        }

        let received: [Syncable] = [
            .creditCard("New Expiry",
                        uuid: "remote-uuid",
                        cardholderName: "John Doe",
                        cardNumber: "4111111111111111",
                        cardSecurityCode: "123",
                        expirationMonth: "12",
                        expirationYear: "2026")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1, "Should have only one card after deduplication")
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "remote-uuid", "Should have the remote UUID")

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards.first?.title, "New Expiry")
        XCTAssertEqual(creditCards.first?.cardholderName, "John Doe")
        XCTAssertEqual(creditCards.first?.cardSecurityCode, "123")
        XCTAssertEqual(creditCards.first?.expirationMonth, 12)
        XCTAssertEqual(creditCards.first?.expirationYear, 2026)
    }

    func testThatDeduplicationIgnoresCardWithNewerExpirationDate() async throws {
        try reinitializeVaultUsingBitFlipCryptoProvider()

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("local-uuid",
                                                         title: "New Expiry",
                                                         cardholderName: "John Doe",
                                                         cardNumber: "4111111111111111",
                                                         cardSecurityCode: "123",
                                                         expirationMonth: 12,
                                                         expirationYear: 2026,
                                                         in: database)
        }

        let received: [Syncable] = [
            .creditCard("Old Expiry",
                        uuid: "remote-uuid",
                        cardholderName: "Mr John Doe",
                        cardNumber: "4111111111111111",
                        cardSecurityCode: "111",
                        expirationMonth: "1",
                        expirationYear: "2025")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1, "Should keep only the newer card")
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "remote-uuid", "Should accept incoming UUID but keep local data with newer expiry")

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards.first?.title, "New Expiry")
        XCTAssertEqual(creditCards.first?.cardholderName, "John Doe")
        XCTAssertEqual(creditCards.first?.cardSecurityCode, "123")
        XCTAssertEqual(creditCards.first?.expirationMonth, 12)
        XCTAssertEqual(creditCards.first?.expirationYear, 2026)
        XCTAssertEqual(creditCards.first?.cardNumber, "4111111111111111")
    }

    func testThatDeduplicatedLocalCardRemainsDecryptable() async throws {
        try reinitializeVaultUsingBitFlipCryptoProvider()

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("local-uuid",
                                                         title: "Local Card",
                                                         cardholderName: "Jane Doe",
                                                         cardNumber: "4111111111111111",
                                                         cardSecurityCode: "123",
                                                         expirationMonth: 12,
                                                         expirationYear: 2030,
                                                         in: database)
        }

        let received: [Syncable] = [
            .creditCard("Remote Older",
                        uuid: "remote-uuid",
                        cardholderName: "Jane Doe",
                        cardNumber: "4111111111111111",
                        cardSecurityCode: "321",
                        expirationMonth: "1",
                        expirationYear: "2025")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1, "Should deduplicate into a single card")
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "remote-uuid", "Incoming UUID should replace local UUID")
        XCTAssertNotNil(syncableCreditCards.first?.metadata.lastModified, "Dedup branch should mark the record as modified for upload")

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.count, 1)
        let card = creditCards[0]
        XCTAssertEqual(card.title, "Local Card")
        XCTAssertEqual(card.cardholderName, "Jane Doe")
        XCTAssertEqual(card.expirationMonth, 12)
        XCTAssertEqual(card.expirationYear, 2030)

        XCTAssertEqual(card.cardNumber, "4111111111111111")
    }

    func testThatDeduplicationReplacesCardWithSameExpirationDate() async throws {
        try reinitializeVaultUsingBitFlipCryptoProvider()

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("local-uuid",
                                                         title: "Local Card",
                                                         cardholderName: "Mr John Doe",
                                                         cardNumber: "4111111111111111",
                                                         cardSecurityCode: "123",
                                                         expirationMonth: 12,
                                                         expirationYear: 2026,
                                                         in: database)
        }

        let received: [Syncable] = [
            .creditCard("Remote Card",
                        uuid: "remote-uuid",
                        cardholderName: "John Doe",
                        cardNumber: "4111111111111111",
                        cardSecurityCode: "123",
                        expirationMonth: "12",
                        expirationYear: "2026")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1, "Should have only one card after deduplication")
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "remote-uuid", "Should accept incoming card when expiry dates are the same")

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards.first?.title, "Remote Card")
        XCTAssertEqual(creditCards.first?.cardholderName, "John Doe")
        XCTAssertEqual(creditCards.first?.cardSecurityCode, "123")
        XCTAssertEqual(creditCards.first?.expirationMonth, 12)
        XCTAssertEqual(creditCards.first?.expirationYear, 2026)
        XCTAssertEqual(creditCards.first?.cardNumber, "4111111111111111")
    }

    func testThatCardsWithMismatchedExpiryPresenceAreNotDeduplicated() async throws {
        try reinitializeVaultUsingBitFlipCryptoProvider()

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("local-uuid",
                                                         title: "Card With Expiry",
                                                         cardholderName: "John Doe",
                                                         cardNumber: "4111111111111111",
                                                         cardSecurityCode: "123",
                                                         expirationMonth: 12,
                                                         expirationYear: 2026,
                                                         in: database)
        }

        let received: [Syncable] = [
            .creditCard("Card Without Expiry",
                        uuid: "remote-uuid",
                        cardholderName: "Jane Smith",
                        cardNumber: "4111111111111111",
                        cardSecurityCode: "456",
                        expirationMonth: nil,
                        expirationYear: nil)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1, "Should deduplicate when one has expiry and the other doesn't (local with expiry wins)")
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "remote-uuid", "Should use incoming UUID but keep local data")

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards[0].title, "Card With Expiry", "Should keep local card data")
        XCTAssertEqual(creditCards[0].expirationMonth, 12)
        XCTAssertEqual(creditCards[0].expirationYear, 2026)
        XCTAssertEqual(creditCards[0].cardNumber, "4111111111111111")
    }

    func testThatCardsWithMismatchedExpiryPresenceAreNotDeduplicatedReverseCase() async throws {
        try secureVault.inDatabaseTransaction { database in
            let creditCard = SecureVaultModels.CreditCard(
                title: "Card Without Expiry",
                cardNumber: "4111111111111111",
                cardholderName: "John Doe",
                cardSecurityCode: "123",
                expirationMonth: nil,
                expirationYear: nil
            )
            let syncableCreditCard = SecureVaultModels.SyncableCreditCard(
                uuid: "local-uuid",
                creditCard: creditCard,
                lastModified: nil
            )
            try self.secureVault.storeSyncableCreditCard(syncableCreditCard, in: database, encryptedUsing: Data())
        }

        let received: [Syncable] = [
            .creditCard("Card With Expiry",
                        uuid: "remote-uuid",
                        cardholderName: "Jane Smith",
                        cardNumber: "4111111111111111",
                        cardSecurityCode: "456",
                        expirationMonth: "12",
                        expirationYear: "2026")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1, "Should deduplicate when one has expiry and the other doesn't (incoming with expiry wins)")
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "remote-uuid", "Should use incoming UUID")

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards[0].title, "Card With Expiry")
        XCTAssertEqual(creditCards[0].expirationMonth, 12)
        XCTAssertEqual(creditCards[0].expirationYear, 2026)
    }

    func testThatCardsWithoutExpiryAreDeduplicated() async throws {
        try reinitializeVaultUsingBitFlipCryptoProvider()

        try secureVault.inDatabaseTransaction { database in
            let creditCard = SecureVaultModels.CreditCard(
                title: "Local Card",
                cardNumber: "4111111111111111",
                cardholderName: "John Doe",
                cardSecurityCode: "123",
                expirationMonth: nil,
                expirationYear: nil
            )
            let syncableCreditCard = SecureVaultModels.SyncableCreditCard(
                uuid: "local-uuid",
                creditCard: creditCard,
                lastModified: nil
            )
            try self.secureVault.storeSyncableCreditCard(syncableCreditCard, in: database, encryptedUsing: Data())
        }

        let received: [Syncable] = [
            .creditCard("Remote Card",
                        uuid: "remote-uuid",
                        cardholderName: "John Doe",
                        cardNumber: "4111111111111111",
                        cardSecurityCode: "123",
                        expirationMonth: nil,
                        expirationYear: nil)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1, "Should deduplicate when both cards have no expiry and all fields match")
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "remote-uuid", "Should replace local with incoming card")

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards.first?.title, "Remote Card")
        XCTAssertEqual(creditCards.first?.cardholderName, "John Doe")
        XCTAssertEqual(creditCards.first?.cardSecurityCode, "123")
        XCTAssertNil(creditCards.first?.expirationMonth)
        XCTAssertNil(creditCards.first?.expirationYear)
        XCTAssertEqual(creditCards.first?.cardNumber, "4111111111111111")
    }

    func testThatCardsWithoutExpiryAreNotDeduplicatedWhenFieldsDiffer() async throws {
        try reinitializeVaultUsingBitFlipCryptoProvider()

        try secureVault.inDatabaseTransaction { database in
            let creditCard = SecureVaultModels.CreditCard(
                title: "Local Card",
                cardNumber: "4111111111111111",
                cardholderName: "John Doe",
                cardSecurityCode: "123",
                expirationMonth: nil,
                expirationYear: nil
            )
            let syncableCreditCard = SecureVaultModels.SyncableCreditCard(
                uuid: "local-uuid",
                creditCard: creditCard,
                lastModified: nil
            )
            try self.secureVault.storeSyncableCreditCard(syncableCreditCard, in: database, encryptedUsing: Data())
        }

        let received: [Syncable] = [
            .creditCard("Remote Card",
                        uuid: "remote-uuid",
                        cardholderName: "Jane Smith",
                        cardNumber: "4111111111111111",
                        cardSecurityCode: "456",
                        expirationMonth: nil,
                        expirationYear: nil)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1, "Should deduplicate when both have no expiry (incoming wins)")
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "remote-uuid", "Should use incoming UUID and data")

        let creditCards = try secureVault.creditCards()
        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards[0].title, "Remote Card")
        XCTAssertEqual(creditCards[0].cardholderName, "Jane Smith")
        XCTAssertEqual(creditCards[0].cardSecurityCode, "456")
        XCTAssertEqual(creditCards[0].cardNumber, "4111111111111111")
    }

    func testThatMultipleIncomingCardsWithSameNumberAreNotDeduplicatedAgainstEachOther() async throws {
       try secureVault.inDatabaseTransaction { database in
           try self.secureVault.storeSyncableCreditCard("local-uuid",
                                                        title: "Local Card",
                                                        cardNumber: "4111111111111111",
                                                        expirationMonth: 1,
                                                        expirationYear: 2025,
                                                        in: database)
       }

       let received: [Syncable] = [
           .creditCard("Incoming Card 1",
                      uuid: "incoming-1",
                      cardNumber: "4111111111111111",
                      expirationMonth: "12",
                      expirationYear: "2026"),
           .creditCard("Incoming Card 2",
                      uuid: "incoming-2",
                      cardNumber: "4111111111111111",
                      expirationMonth: "12",
                      expirationYear: "2027")
       ]

       try await handleInitialSyncResponse(received: received)

       let syncableCreditCards = try fetchAllSyncableCreditCards()
       XCTAssertEqual(syncableCreditCards.count, 2, "Should keep both incoming cards even though they have same card number")
       XCTAssertTrue(syncableCreditCards.contains { $0.metadata.uuid == "incoming-1" })
       XCTAssertTrue(syncableCreditCards.contains { $0.metadata.uuid == "incoming-2" })

       let creditCards = try secureVault.creditCards().sorted { ($0.expirationYear ?? 0) < ($1.expirationYear ?? 0) }
       XCTAssertEqual(creditCards.count, 2)
       XCTAssertEqual(creditCards[0].title, "Incoming Card 1")
       XCTAssertEqual(creditCards[0].expirationYear, 2026)
       XCTAssertEqual(creditCards[1].title, "Incoming Card 2")
       XCTAssertEqual(creditCards[1].expirationYear, 2027)
   }

   func testThatIncomingCardDeduplicatesOnlyFirstLocalCardWithSameNumber() async throws {
       try secureVault.inDatabaseTransaction { database in
           try self.secureVault.storeSyncableCreditCard("local-1",
                                                        title: "Local Card 1",
                                                        cardNumber: "4111111111111111",
                                                        expirationMonth: 1,
                                                        expirationYear: 2025,
                                                        in: database)
           try self.secureVault.storeSyncableCreditCard("local-2",
                                                        title: "Local Card 2",
                                                        cardNumber: "4111111111111111",
                                                        expirationMonth: 2,
                                                        expirationYear: 2025,
                                                        in: database)
       }

       let received: [Syncable] = [
           .creditCard("Incoming Card",
                      uuid: "incoming",
                      cardNumber: "4111111111111111",
                      expirationMonth: "12",
                      expirationYear: "2026")
       ]

       try await handleInitialSyncResponse(received: received)

       let syncableCreditCards = try fetchAllSyncableCreditCards()
       XCTAssertEqual(syncableCreditCards.count, 2, "Should deduplicate only the first local match, leaving the second local card orphaned")
       XCTAssertTrue(syncableCreditCards.contains { $0.metadata.uuid == "incoming" }, "Should have the incoming card")
       XCTAssertTrue(syncableCreditCards.contains { $0.metadata.uuid == "local-1" } || syncableCreditCards.contains { $0.metadata.uuid == "local-2" }, "Should have one of the local cards remaining")

       let creditCards = try secureVault.creditCards()
       XCTAssertEqual(creditCards.count, 2, "Should have 2 cards total after deduplication")
   }
}

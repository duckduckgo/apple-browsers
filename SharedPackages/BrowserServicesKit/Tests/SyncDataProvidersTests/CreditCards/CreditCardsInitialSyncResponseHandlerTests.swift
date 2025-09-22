//
//
//
//
//
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

    func testThatDeduplicationComparesCardSecurityCode() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("existing",
                                                         title: "Test Card",
                                                         cardholderName: "John Doe",
                                                         cardNumber: "4111111111111111",
                                                         cardSecurityCode: "123",
                                                         expirationMonth: 12,
                                                         expirationYear: 2025,
                                                         in: database)
        }

        let received: [Syncable] = [
            .creditCard("Test Card",
                       uuid: "new",
                       cardholderName: "John Doe",
                       cardNumber: "4111111111111111",
                       cardSecurityCode: "456",
                       expirationMonth: "12",
                       expirationYear: "2025")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 2)
        XCTAssertTrue(syncableCreditCards.contains { $0.metadata.uuid == "existing" })
        XCTAssertTrue(syncableCreditCards.contains { $0.metadata.uuid == "new" })
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

    func testThatDeduplicationMatchesWhenCardSecurityCodeIsIdentical() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("existing",
                                                         title: "Test Card",
                                                         cardholderName: "John Doe",
                                                         cardNumber: "4111111111111111",
                                                         cardSecurityCode: "123",
                                                         expirationMonth: 12,
                                                         expirationYear: 2025,
                                                         in: database)
        }

        let received: [Syncable] = [
            .creditCard("Test Card",
                       uuid: "new",
                       cardholderName: "John Doe",
                       cardNumber: "4111111111111111",
                       cardSecurityCode: "123",
                       expirationMonth: "12",
                       expirationYear: "2025")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards.first?.metadata.uuid, "new")
    }
}

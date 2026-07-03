//
//  CreditCardsRegularSyncResponseHandlerTests.swift
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

final class CreditCardsRegularSyncResponseHandlerTests: CreditCardsProviderTestsBase {

    func testThatNewCreditCardIsAppended() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
        }

        let received: [Syncable] = [
            .creditCard(uuid: "2", cardNumber: "5555555555554444")
        ]

        try await handleSyncResponse(received: received)

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

        try await handleSyncResponse(received: received)

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

        try await handleSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards.map(\.metadata.uuid), ["1"])
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatSinglePayloadCanDeleteCreateAndUpdateCreditCards() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
            try self.secureVault.storeSyncableCreditCard("3", cardNumber: "378282246310005", in: database)
        }

        let received: [Syncable] = [
            .creditCard(uuid: "1", isDeleted: true),
            .creditCard(uuid: "2", cardNumber: "5555555555554444"),
            .creditCard(uuid: "3", cardholderName: "Updated Name", cardNumber: "378282246310005")
        ]

        try await handleSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 2)
        XCTAssertEqual(Set(syncableCreditCards.map(\.metadata.uuid)), Set(["2", "3"]))

        let card3 = syncableCreditCards.first(where: { $0.metadata.uuid == "3" })
        XCTAssertEqual(card3?.creditCard?.cardholderName, "Updated Name")
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatDecryptionFailureDoesntAffectCreditCardsOrCrash() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
        }

        let received: [Syncable] = [
            .creditCard(uuid: "2", cardNumber: "5555555555554444")
        ]

        crypter.throwsException(exceptionString: "ddgSyncDecrypt failed: invalid ciphertext length: X")

        try await handleSyncResponse(received: received)

        let syncableCreditCards = try fetchAllSyncableCreditCards()
        XCTAssertEqual(syncableCreditCards.count, 1)
        XCTAssertEqual(syncableCreditCards.map(\.metadata.uuid), ["1"])
        XCTAssertTrue(syncableCreditCards.map(\.metadata.lastModified).allSatisfy { $0 == nil })
        crypter.throwsException(exceptionString: nil)
    }

    func testWhenCardSuffixIsStaleThenSyncRefreshesItOnlyOnce() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
        }
        try setStaleStoredCardSuffix("0000", forUUID: "1")

        try await handleSyncResponse(received: [])
        XCTAssertEqual(try storedCardSuffix(forUUID: "1"), "1111")

        try setStaleStoredCardSuffix("2222", forUUID: "1")
        try await handleSyncResponse(received: [])
        XCTAssertEqual(try storedCardSuffix(forUUID: "1"), "2222")
    }

    func testWhenRefreshGateWriteFailsThenSyncSucceedsAndRefreshIsRetried() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
        }
        try setStaleStoredCardSuffix("0000", forUUID: "1")
        keyValueStore.shouldThrowOnSet = true

        try await handleSyncResponse(received: [])
        XCTAssertEqual(try storedCardSuffix(forUUID: "1"), "1111")
        XCTAssertTrue(keyValueStore.underlyingDict.isEmpty)

        keyValueStore.shouldThrowOnSet = false
        try await handleSyncResponse(received: [])
        XCTAssertEqual(try storedCardSuffix(forUUID: "1"), "1111")
        XCTAssertEqual(keyValueStore.underlyingDict.count, 1)
    }

    func testWhenOneCardDecryptFailsDuringStaleSuffixRefreshThenOtherCardsStillRefresh() async throws {
        try reinitializeVaultUsingBitFlipCryptoProvider()
        let decryptionFailureMarker = Data([0xAA, 0xBB, 0xCC, 0xDD])
        TestBitFlipCryptoProvider.decryptionFailureMarker = decryptionFailureMarker
        defer { TestBitFlipCryptoProvider.decryptionFailureMarker = nil }

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
            try self.secureVault.storeSyncableCreditCard("2", cardNumber: "5555555555554444", in: database)
        }
        try setStaleStoredCardSuffix("0000", forUUID: "1")
        try setStaleStoredCardSuffix("0000", forUUID: "2")
        try setStoredEncryptedCardNumberData(decryptionFailureMarker, forUUID: "1")

        try await handleSyncResponse(received: [])

        XCTAssertEqual(try storedCardSuffix(forUUID: "1"), "0000")
        XCTAssertEqual(try storedCardSuffix(forUUID: "2"), "4444")
        XCTAssertEqual(keyValueStore.underlyingDict.count, 1)
    }

    func testWhenIncomingSyncUpdatesCardNumberThenSuffixUpdatesWithoutBackfill() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCreditCard("1", cardNumber: "4111111111111111", in: database)
        }

        // Complete the one-time refresh upfront so this assertion validates the forward update path.
        try await handleSyncResponse(received: [])

        let received: [Syncable] = [
            .creditCard(uuid: "1", cardNumber: "5555555555554444")
        ]
        try await handleSyncResponse(received: received)

        XCTAssertEqual(try storedCardSuffix(forUUID: "1"), "4444")
    }

    private func storedCardSuffix(forUUID uuid: String) throws -> String? {
        try fetchAllSyncableCreditCards()
            .first(where: { $0.metadata.uuid == uuid })?
            .creditCard?.cardSuffix
    }

    private func setStaleStoredCardSuffix(_ suffix: String, forUUID uuid: String) throws {
        try secureVault.inDatabaseTransaction { database in
            guard let syncableCreditCard = try SecureVaultModels.SyncableCreditCard.query
                .filter(SecureVaultModels.SyncableCreditCardsRecord.Columns.uuid == uuid)
                .fetchOne(database),
                var creditCard = syncableCreditCard.creditCard else {
                XCTFail("Expected syncable credit card to exist for uuid \(uuid)")
                return
            }

            creditCard.cardSuffix = suffix
            try creditCard.update(database)
        }
    }

    private func setStoredEncryptedCardNumberData(_ cardNumberData: Data, forUUID uuid: String) throws {
        try secureVault.inDatabaseTransaction { database in
            guard let syncableCreditCard = try SecureVaultModels.SyncableCreditCard.query
                .filter(SecureVaultModels.SyncableCreditCardsRecord.Columns.uuid == uuid)
                .fetchOne(database),
                var creditCard = syncableCreditCard.creditCard else {
                XCTFail("Expected syncable credit card to exist for uuid \(uuid)")
                return
            }

            creditCard.cardNumberData = cardNumberData
            try creditCard.update(database)
        }
    }
}

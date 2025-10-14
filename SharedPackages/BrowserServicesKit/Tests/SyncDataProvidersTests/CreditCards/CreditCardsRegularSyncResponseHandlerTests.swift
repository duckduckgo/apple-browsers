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
}

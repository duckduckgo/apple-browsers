//
//  IdentitiesInitialSyncResponseHandlerTests.swift
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

final class IdentitiesInitialSyncResponseHandlerTests: IdentitiesProviderTestsBase {

    func testThatNewIdentityIsAppended() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", firstName: "John", lastName: "Doe", in: database)
        }

        let received: [Syncable] = [
            .identity(uuid: "2", firstName: "Jane", lastName: "Smith")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 2)
        XCTAssertEqual(syncableIdentities.map(\.metadata.uuid), ["1", "2"])
        XCTAssertTrue(syncableIdentities.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testWhenDeletedIdentityIsReceivedThenItIsDeletedLocally() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", firstName: "John", in: database)
            try self.secureVault.storeSyncableIdentity("2", firstName: "Jane", in: database)
        }

        let received: [Syncable] = [
            .identity(uuid: "1", isDeleted: true)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities.map(\.metadata.uuid), ["2"])
        XCTAssertTrue(syncableIdentities.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatDeletesForNonExistentIdentitiesAreIgnored() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", firstName: "John", in: database)
        }

        let received: [Syncable] = [
            .identity(uuid: "2", isDeleted: true)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities.map(\.metadata.uuid), ["1"])
        XCTAssertTrue(syncableIdentities.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatIdentitiesAreDeduplicated() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", title: "Home", firstName: "John", lastName: "Doe", addressStreet: "123 Main", addressCity: "Ducktown", emailAddress: "john@example.com", nullifyOtherFields: true, in: database)
            try self.secureVault.storeSyncableIdentity("3", title: "Work", firstName: "Alice", lastName: "Smith", addressStreet: "456 Elm", addressCity: "Mallard", emailAddress: "alice@example.com", nullifyOtherFields: true, in: database)
        }

        let received: [Syncable] = [
            .identity("Remote Home", uuid: "2", firstName: "John", lastName: "Doe", emailAddress: "john@example.com", addressStreet: "123 Main", addressCity: "Ducktown", nullifyOtherFields: true),
            .identity("Remote Work", uuid: "4", firstName: "Alice", lastName: "Smith", emailAddress: "alice@example.com", addressStreet: "456 Elm", addressCity: "Mallard", nullifyOtherFields: true)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 2)
        XCTAssertEqual(syncableIdentities.map(\.metadata.uuid), ["2", "4"])
        XCTAssertTrue(syncableIdentities.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatWhenIdentitiesAreDeduplicatedThenRemoteTitleIsApplied() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", title: "local-title1", firstName: "John", lastName: "Doe", nullifyOtherFields: true, in: database)
            try self.secureVault.storeSyncableIdentity("3", title: "local-title2", firstName: "Alice", lastName: "Smith", nullifyOtherFields: true, in: database)
        }

        let received: [Syncable] = [
            .identity("remote-title1", uuid: "2", firstName: "John", lastName: "Doe", nullifyOtherFields: true),
            .identity("remote-title2", uuid: "4", firstName: "Alice", lastName: "Smith", nullifyOtherFields: true)
        ]

        try await handleInitialSyncResponse(received: received)

        let identities = try secureVault.identities().sorted { ($0.title, $0.firstName ?? "") < ($1.title, $1.firstName ?? "") }
        XCTAssertEqual(identities.map(\.title), ["remote-title1", "remote-title2"])
    }

    func testThatExistingIdentityIsUpdatedWhenMatchingUUID() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", title: "Original", firstName: "John", lastName: "Doe", emailAddress: "john@example.com", in: database)
        }

        let received: [Syncable] = [
            .identity("Updated", uuid: "1", firstName: "Updated", lastName: "User", emailAddress: "updated@example.com")
        ]

        try await handleInitialSyncResponse(received: received)

        let identities = try secureVault.identities()
        XCTAssertEqual(identities.count, 1)
        XCTAssertEqual(identities.first?.title, "Updated")
        XCTAssertEqual(identities.first?.firstName, "Updated")
        XCTAssertEqual(identities.first?.emailAddress, "updated@example.com")
    }

    func testThatIdentitiesWithNilFieldsAreDeduplicated() async throws {
        try secureVault.inDatabaseTransaction { database in
            let identity = SecureVaultModels.Identity(id: nil, title: "", created: Date(), lastUpdated: Date())
            let syncableIdentity = SecureVaultModels.SyncableIdentity(uuid: "1", identity: identity, lastModified: nil)
            try self.secureVault.storeSyncableIdentity(syncableIdentity, in: database)
        }

        let received: [Syncable] = [
            .identity(uuid: "2", nullifyOtherFields: true)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities.map(\.metadata.uuid), ["2"])
        XCTAssertTrue(syncableIdentities.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testWhenPayloadContainsDuplicatedRecordsThenAllRecordsAreStored() async throws {
        let received: [Syncable] = [
            .identity(uuid: "1", nullifyOtherFields: true),
            .identity(uuid: "2", nullifyOtherFields: true)
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 2)
        XCTAssertEqual(syncableIdentities.map(\.metadata.uuid), ["1", "2"])
        XCTAssertTrue(syncableIdentities.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }
}

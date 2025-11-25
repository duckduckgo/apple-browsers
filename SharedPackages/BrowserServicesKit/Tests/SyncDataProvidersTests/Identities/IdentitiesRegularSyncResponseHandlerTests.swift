//
//  IdentitiesRegularSyncResponseHandlerTests.swift
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

final class IdentitiesRegularSyncResponseHandlerTests: IdentitiesProviderTestsBase {

    func testThatNewIdentityIsAppended() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", firstName: "John", in: database)
        }

        let received: [Syncable] = [
            .identity(uuid: "2", firstName: "Jane")
        ]

        try await handleSyncResponse(received: received)

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

        try await handleSyncResponse(received: received)

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

        try await handleSyncResponse(received: received)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities.map(\.metadata.uuid), ["1"])
        XCTAssertTrue(syncableIdentities.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatSinglePayloadCanDeleteCreateAndUpdateIdentities() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", firstName: "John", in: database)
            try self.secureVault.storeSyncableIdentity("3", firstName: "Alice", in: database)
        }

        let received: [Syncable] = [
            .identity(uuid: "1", isDeleted: true),
            .identity(uuid: "2", firstName: "Jane"),
            .identity(uuid: "3", firstName: "Updated", lastName: "User")
        ]

        try await handleSyncResponse(received: received)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 2)
        XCTAssertEqual(syncableIdentities.map(\.metadata.uuid), ["2", "3"])
        XCTAssertEqual(syncableIdentities.map { $0.identity?.firstName }, ["Jane", "Updated"])
        XCTAssertTrue(syncableIdentities.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatDecryptionFailureDoesntAffectIdentitiesOrCrash() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", firstName: "John", in: database)
        }

        let received: [Syncable] = [
            .identity(uuid: "2", firstName: "Jane")
        ]

        crypter.throwsException(exceptionString: "ddgSyncDecrypt failed: invalid ciphertext length: X")

        try await handleSyncResponse(received: received)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities.map(\.metadata.uuid), ["1"])
        XCTAssertTrue(syncableIdentities.map(\.metadata.lastModified).allSatisfy { $0 == nil })
        crypter.throwsException(exceptionString: nil)
    }
}

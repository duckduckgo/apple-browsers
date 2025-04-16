//
//  CredentialsRegularSyncResponseHandlerTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

final class CredentialsRegularSyncResponseHandlerTests: CredentialsProviderTestsBase {

    func testThatNewCredentialIsAppended() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "2")
        ]

        try await handleSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 2)
        XCTAssertEqual(syncableCredentials.map(\.account?.id), ["1", "2"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testWhenDeletedCredentialIsReceivedThenItIsDeletedLocally() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
            try self.secureVault.storeSyncableCredentials("2", in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "1", isDeleted: true)
        ]

        try await handleSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials.map(\.metadata.uuid), ["2"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatDeletesForNonExistentCredentialsAreIgnored() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "2", isDeleted: true)
        ]

        try await handleSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials.map(\.metadata.uuid), ["1"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatSinglePayloadCanDeleteCreateAndUpdateCredentials() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
            try self.secureVault.storeSyncableCredentials("3", in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "1", isDeleted: true),
            .credentials(id: "2"),
            .credentials(id: "3", username: "4")
        ]

        try await handleSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 2)
        XCTAssertEqual(syncableCredentials.map(\.metadata.uuid), ["2", "3"])
        XCTAssertEqual(syncableCredentials.map(\.account?.username), ["2", "4"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatDecryptionFailureDoesntAffectCredentialsOrCrash() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "2")
        ]

        crypter.throwsException(exceptionString: "ddgSyncDecrypt failed: invalid ciphertext length: X")

        try await handleSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials.map(\.account?.id), ["1"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
        crypter.throwsException(exceptionString: nil)
    }
}

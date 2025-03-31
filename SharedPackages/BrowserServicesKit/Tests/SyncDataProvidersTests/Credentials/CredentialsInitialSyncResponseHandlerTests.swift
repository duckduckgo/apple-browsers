//
//  CredentialsInitialSyncResponseHandlerTests.swift
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

final class CredentialsInitialSyncResponseHandlerTests: CredentialsProviderTestsBase {

    func testThatNewCredentialIsAppended() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "2")
        ]

        try await handleInitialSyncResponse(received: received)

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

        try await handleInitialSyncResponse(received: received)

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

        try await handleInitialSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials.map(\.metadata.uuid), ["1"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatCredentialsAreDeduplicated() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
            try self.secureVault.storeSyncableCredentials("3", in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "2", domain: "1", username: "1", password: "1", notes: "1"),
            .credentials(id: "4", domain: "3", username: "3", password: "3", notes: "3")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 2)
        XCTAssertEqual(syncableCredentials.map(\.metadata.uuid), ["2", "4"])
        XCTAssertEqual(syncableCredentials.map(\.account?.username), ["1", "3"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatWhenCredentialsAreDeduplicatedThenRemoteTitleIsApplied() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", title: "local-title2", in: database)
            try self.secureVault.storeSyncableCredentials("3", title: "local-title4", in: database)
        }

        let received: [Syncable] = [
            .credentials("remote-title2", id: "2", domain: "1", username: "1", password: "1", notes: "1"),
            .credentials("remote-title4", id: "4", domain: "3", username: "3", password: "3", notes: "3")
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 2)
        XCTAssertEqual(syncableCredentials.map(\.metadata.uuid), ["2", "4"])
        XCTAssertEqual(syncableCredentials.map(\.account?.username), ["1", "3"])
        XCTAssertEqual(syncableCredentials.map(\.account?.title), ["remote-title2", "remote-title4"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testThatCredentialsWithNilFieldsAreDeduplicated() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", nullifyOtherFields: true, in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "2", nullifyOtherFields: true),
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials.map(\.metadata.uuid), ["2"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }

    func testWhenPayloadContainsDuplicatedRecordsThenAllRecordsAreStored() async throws {

        let received: [Syncable] = [
            .credentials(id: "1", nullifyOtherFields: true),
            .credentials(id: "2", nullifyOtherFields: true),
        ]

        try await handleInitialSyncResponse(received: received)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 2)
        XCTAssertEqual(syncableCredentials.map(\.metadata.uuid), ["1", "2"])
        XCTAssertTrue(syncableCredentials.map(\.metadata.lastModified).allSatisfy { $0 == nil })
    }
}

//
//  SecureVaultSyncableCredentialsTests.swift
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

import GRDB
import XCTest
@testable import BrowserServicesKit

class SecureVaultSyncableCredentialsTests: XCTestCase {

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

    func testWhenCredentialsAreInsertedThenSyncableCredentialsArePopulated() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        let accountId = try provider.storeWebsiteCredentials(credentials)

        let syncableCredentials = try provider.modifiedSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials[0].metadata.objectId, accountId)
        XCTAssertNotNil(syncableCredentials[0].metadata.lastModified)
    }

    func testWhenSyncableCredentialsAreInsertedThenObjectIdIsPopulated() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        let metadata = SecureVaultModels.SyncableCredentials(uuid: UUID().uuidString, credentials: credentials, lastModified: nil)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCredentials(metadata, in: database)
        }

        let syncableCredentials = try provider.db.read { database in
            try SecureVaultModels.SyncableCredentials.query.fetchAll(database)
        }

        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials[0].metadata.objectId, 1)
        XCTAssertNil(syncableCredentials[0].metadata.lastModified)
    }

    func testWhenSyncableCredentialsAreInsertedThenNilLastModifiedIsHonored() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        let metadata = SecureVaultModels.SyncableCredentials(uuid: UUID().uuidString, credentials: credentials, lastModified: nil)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCredentials(metadata, in: database)
        }

        let syncableCredentials = try provider.db.read { database in
            try SecureVaultModels.SyncableCredentials.query.fetchAll(database)
        }

        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertNil(syncableCredentials[0].metadata.lastModified)
    }

    func testWhenSyncableCredentialsAreInsertedThenNonNilLastModifiedIsHonored() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        let timestamp = Date().withMillisecondPrecision
        let syncableCredentials = SecureVaultModels.SyncableCredentials(uuid: UUID().uuidString, credentials: credentials, lastModified: timestamp)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCredentials(syncableCredentials, in: database)
        }

        let allSyncableCredentials = try provider.db.read { database in
            try SecureVaultModels.SyncableCredentials.query.fetchAll(database)
        }

        XCTAssertEqual(allSyncableCredentials.count, 1)
        XCTAssertEqual(allSyncableCredentials[0].metadata.lastModified!.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWhenSyncableCredentialsAreUpdatedThenNonNilLastModifiedIsHonored() throws {
        let account = SecureVaultModels.WebsiteAccount(id: "2", username: "brindy", domain: "example.com", created: Date(), lastUpdated: Date())
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        let timestamp = Date().withMillisecondPrecision
        var syncableCredentials = SecureVaultModels.SyncableCredentials(uuid: UUID().uuidString, credentials: credentials, lastModified: timestamp)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCredentials(syncableCredentials, in: database)
        }

        syncableCredentials = try provider.db.read { database in
            try XCTUnwrap(try self.provider.syncableCredentialsForAccountId(2, in: database))
        }
        syncableCredentials.credentials?.account.username = "brindy2"

        try provider.inTransaction { database in
            try self.provider.storeSyncableCredentials(syncableCredentials, in: database)
        }

        let metadataObjects = try provider.db.read { database in
            try SecureVaultModels.SyncableCredentials.query.fetchAll(database)
        }

        XCTAssertEqual(metadataObjects.count, 1)
        XCTAssertEqual(metadataObjects[0].metadata.lastModified!.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWhenCredentialsAreUpdatedThenSyncTimestampIsUpdated() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        var credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        let accountId = try provider.storeWebsiteCredentials(credentials)

        var metadata = try XCTUnwrap(try provider.db.read { try SecureVaultModels.SyncableCredentialsRecord.fetchOne($0) })
        metadata.lastModified = nil
        try provider.db.write { try metadata.update($0) }

        credentials.account = try XCTUnwrap(try provider.db.read { try SecureVaultModels.WebsiteAccount.fetchOne($0) })
        credentials.account.username = "brindy2"
        try provider.storeWebsiteCredentials(credentials)

        let syncableCredentials = try provider.modifiedSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials[0].metadata.objectId, accountId)
        XCTAssertNotNil(syncableCredentials[0].metadata.lastModified)
    }

    func testWhenSyncableCredentialsAreDeletedThenAccountAndCredentialsAreDeleted() throws {
        let account = SecureVaultModels.WebsiteAccount(id: "2", username: "brindy", domain: "example.com", created: Date(), lastUpdated: Date())
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        var syncableCredentials = SecureVaultModels.SyncableCredentials(uuid: UUID().uuidString, credentials: credentials, lastModified: nil)

        try provider.inTransaction { database in
            try self.provider.storeSyncableCredentials(syncableCredentials, in: database)
        }

        syncableCredentials = try provider.db.read { database in
            try XCTUnwrap(try self.provider.syncableCredentialsForAccountId(2, in: database))
        }

        try provider.inTransaction { database in
            try self.provider.deleteSyncableCredentials(syncableCredentials, in: database)
        }

        let allSyncableCredentials = try provider.db.read { database in
            try SecureVaultModels.SyncableCredentials.query.fetchAll(database)
        }

        let accounts = try provider.db.read { database in
            try SecureVaultModels.WebsiteAccount.fetchAll(database)
        }

        XCTAssertTrue(allSyncableCredentials.isEmpty)
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertNil(try provider.websiteCredentialsForAccountId(2))
    }

    func testWhenPasswordIsUpdatedThenSyncableCredentialsTimestampIsUpdated() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        var credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        credentials = try storeAndFetchCredentials(credentials)
        let createdTimestamp = try provider.modifiedSyncableCredentials().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        credentials.password = "password2".data(using: .utf8)
        credentials = try storeAndFetchCredentials(credentials)

        let syncableCredentials = try provider.modifiedSyncableCredentials()
        XCTAssertGreaterThan(syncableCredentials[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenUsernameIsUpdatedThenSyncableCredentialsTimestampIsUpdated() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        var credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        credentials = try storeAndFetchCredentials(credentials)
        let createdTimestamp = try provider.modifiedSyncableCredentials().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        credentials.account.username = "brindy2"
        credentials = try storeAndFetchCredentials(credentials)

        let syncableCredentials = try provider.modifiedSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials[0].metadata.objectId, credentials.account.id.flatMap(Int64.init))
        XCTAssertGreaterThan(syncableCredentials[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenDomainIsUpdatedThenSyncableCredentialsTimestampIsUpdated() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        var credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        credentials = try storeAndFetchCredentials(credentials)
        let createdTimestamp = try provider.modifiedSyncableCredentials().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        credentials.account.domain = "example2.com"
        credentials = try storeAndFetchCredentials(credentials)

        let syncableCredentials = try provider.modifiedSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials[0].metadata.objectId, credentials.account.id.flatMap(Int64.init))
        XCTAssertGreaterThan(syncableCredentials[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenTitleIsUpdatedThenSyncableCredentialsTimestampIsUpdated() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        var credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        credentials = try storeAndFetchCredentials(credentials)
        let createdTimestamp = try provider.modifiedSyncableCredentials().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        credentials.account.title = "brindy's account"
        credentials = try storeAndFetchCredentials(credentials)

        let syncableCredentials = try provider.modifiedSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials[0].metadata.objectId, credentials.account.id.flatMap(Int64.init))
        XCTAssertGreaterThan(syncableCredentials[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenNotesIsUpdatedThenSyncableCredentialsTimestampIsUpdated() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        var credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        credentials = try storeAndFetchCredentials(credentials)
        let createdTimestamp = try provider.modifiedSyncableCredentials().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        credentials.account.notes = "here's my example.com login information"
        credentials = try storeAndFetchCredentials(credentials)

        let syncableCredentials = try provider.modifiedSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials[0].metadata.objectId, credentials.account.id.flatMap(Int64.init))
        XCTAssertGreaterThan(syncableCredentials[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenCredentialsAreDeletedThenSyncableCredentialsIsPersisted() throws {
        let account = SecureVaultModels.WebsiteAccount(username: "brindy", domain: "example.com")
        var credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
        credentials = try storeAndFetchCredentials(credentials)
        let metadata = try provider.modifiedSyncableCredentials().first!
        let accountId = try XCTUnwrap(metadata.metadata.objectId)
        Thread.sleep(forTimeInterval: 0.001)

        try provider.deleteWebsiteCredentialsForAccountId(accountId)

        let syncableCredentials = try provider.modifiedSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertEqual(syncableCredentials[0].metadata.objectId, nil)
        XCTAssertGreaterThan(syncableCredentials[0].metadata.lastModified!, metadata.metadata.lastModified!)
    }

    // MARK: - Private

    private func storeAndFetchCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> SecureVaultModels.WebsiteCredentials {
        let accountId = try provider.storeWebsiteCredentials(credentials)
        return try XCTUnwrap(try provider.websiteCredentialsForAccountId(accountId))
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

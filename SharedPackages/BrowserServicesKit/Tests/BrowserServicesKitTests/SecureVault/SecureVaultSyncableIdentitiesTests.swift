//
//  SecureVaultSyncableIdentitiesTests.swift
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

import GRDB
import XCTest
@testable import BrowserServicesKit

final class SecureVaultSyncableIdentitiesTests: XCTestCase {

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

    func testWhenIdentitiesAreInsertedThenSyncableIdentitiesArePopulated() throws {
        let identity = makeIdentity(firstName: "John", lastName: "Doe", emailAddress: "john@example.com")
        let identityId = try provider.storeIdentity(identity)

        let syncableIdentities = try provider.modifiedSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities[0].metadata.objectId, identityId)
        XCTAssertNotNil(syncableIdentities[0].metadata.lastModified)
    }

    func testWhenSyncableIdentitiesAreInsertedThenObjectIdIsPopulated() throws {
        let identity = makeIdentity(firstName: "Jane", lastName: "Smith", emailAddress: "jane@example.com")
        let metadata = SecureVaultModels.SyncableIdentity(uuid: UUID().uuidString, identity: identity, lastModified: nil)

        try provider.inTransaction { database in
            try self.provider.storeSyncableIdentity(metadata, in: database)
        }

        let syncableIdentities = try provider.db.read { database in
            try SecureVaultModels.SyncableIdentity.query.fetchAll(database)
        }

        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities[0].metadata.objectId, 1)
        XCTAssertNil(syncableIdentities[0].metadata.lastModified)
    }

    func testWhenSyncableIdentitiesAreInsertedThenNilLastModifiedIsHonored() throws {
        let identity = makeIdentity(firstName: "John", lastName: "Roe")
        let metadata = SecureVaultModels.SyncableIdentity(uuid: UUID().uuidString, identity: identity, lastModified: nil)

        try provider.inTransaction { database in
            try self.provider.storeSyncableIdentity(metadata, in: database)
        }

        let syncableIdentities = try provider.db.read { database in
            try SecureVaultModels.SyncableIdentity.query.fetchAll(database)
        }

        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertNil(syncableIdentities[0].metadata.lastModified)
    }

    func testWhenSyncableIdentitiesAreInsertedThenNonNilLastModifiedIsHonored() throws {
        let identity = makeIdentity(firstName: "Janet", lastName: "Doe")
        let timestamp = Date().withMillisecondPrecision
        let metadata = SecureVaultModels.SyncableIdentity(uuid: UUID().uuidString, identity: identity, lastModified: timestamp)

        try provider.inTransaction { database in
            try self.provider.storeSyncableIdentity(metadata, in: database)
        }

        let syncableIdentities = try provider.db.read { database in
            try SecureVaultModels.SyncableIdentity.query.fetchAll(database)
        }

        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities[0].metadata.lastModified!.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWhenSyncableIdentitiesAreUpdatedThenNonNilLastModifiedIsHonored() throws {
        let identity = makeIdentity(identityId: 2, firstName: "Alex", lastName: "Roe")
        let timestamp = Date().withMillisecondPrecision
        var metadata = SecureVaultModels.SyncableIdentity(uuid: UUID().uuidString, identity: identity, lastModified: timestamp)

        try provider.inTransaction { database in
            try self.provider.storeSyncableIdentity(metadata, in: database)
        }

        metadata = try provider.db.read { database in
            try XCTUnwrap(
                try SecureVaultModels.SyncableIdentity.query
                    .filter(SecureVaultModels.SyncableIdentitiesRecord.Columns.objectId == 2)
                    .fetchOne(database)
            )
        }
        metadata.identity?.firstName = "Alexander"

        try provider.inTransaction { database in
            try self.provider.storeSyncableIdentity(metadata, in: database)
        }

        let syncableIdentities = try provider.db.read { database in
            try SecureVaultModels.SyncableIdentity.query.fetchAll(database)
        }

        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities[0].metadata.lastModified!.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWhenIdentitiesAreUpdatedThenSyncTimestampIsUpdated() throws {
        var identity = makeIdentity(firstName: "Chris", lastName: "Jones")
        let identityId = try provider.storeIdentity(identity)

        var metadata = try XCTUnwrap(try provider.db.read { try SecureVaultModels.SyncableIdentitiesRecord.fetchOne($0) })
        metadata.lastModified = nil
        try provider.db.write { try metadata.update($0) }

        identity = try XCTUnwrap(try provider.identityForIdentityId(identityId))
        identity.firstName = "Christina"
        _ = try provider.storeIdentity(identity)

        let syncableIdentities = try provider.modifiedSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities[0].metadata.objectId, identityId)
        XCTAssertNotNil(syncableIdentities[0].metadata.lastModified)
    }

    func testWhenSyncableIdentitiesAreDeletedThenIdentityIsDeleted() throws {
        let identity = makeIdentity(identityId: 2, firstName: "Taylor", lastName: "Miles")
        var metadata = SecureVaultModels.SyncableIdentity(uuid: UUID().uuidString, identity: identity, lastModified: nil)

        try provider.inTransaction { database in
            try self.provider.storeSyncableIdentity(metadata, in: database)
        }

        metadata = try provider.db.read { database in
            try XCTUnwrap(
                try SecureVaultModels.SyncableIdentity.query
                    .filter(SecureVaultModels.SyncableIdentitiesRecord.Columns.objectId == 2)
                    .fetchOne(database)
            )
        }

        try provider.inTransaction { database in
            try self.provider.deleteSyncableIdentity(metadata, in: database)
        }

        let syncableIdentities = try provider.db.read { database in
            try SecureVaultModels.SyncableIdentity.query.fetchAll(database)
        }
        let identities = try provider.db.read { database in
            try SecureVaultModels.Identity.fetchAll(database)
        }

        XCTAssertTrue(syncableIdentities.isEmpty)
        XCTAssertTrue(identities.isEmpty)
        XCTAssertNil(try provider.identityForIdentityId(2))
    }

    func testWhenFirstNameIsUpdatedThenSyncableIdentitiesTimestampIsUpdated() throws {
        var identity = try storeAndFetchIdentity(makeIdentity(firstName: "Jordan", lastName: "Smith"))
        let createdTimestamp = try provider.modifiedSyncableIdentities().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        identity.firstName = "Jordana"
        identity = try storeAndFetchIdentity(identity)

        let syncableIdentities = try provider.modifiedSyncableIdentities()
        XCTAssertGreaterThan(syncableIdentities[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenTitleIsUpdatedThenSyncableIdentitiesTimestampIsUpdated() throws {
        var identity = try storeAndFetchIdentity(makeIdentity(title: "Home", firstName: "Jamie", lastName: "Stone"))
        let createdTimestamp = try provider.modifiedSyncableIdentities().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        identity.title = "Work"
        identity = try storeAndFetchIdentity(identity)

        let syncableIdentities = try provider.modifiedSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities[0].metadata.objectId, identity.id)
        XCTAssertGreaterThan(syncableIdentities[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenAddressIsUpdatedThenSyncableIdentitiesTimestampIsUpdated() throws {
        var identity = try storeAndFetchIdentity(makeIdentity(firstName: "Avery", lastName: "Green", addressStreet: "123 Main"))
        let createdTimestamp = try provider.modifiedSyncableIdentities().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        identity.addressStreet = "456 Oak Ave"
        identity = try storeAndFetchIdentity(identity)

        let syncableIdentities = try provider.modifiedSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities[0].metadata.objectId, identity.id)
        XCTAssertGreaterThan(syncableIdentities[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenEmailIsUpdatedThenSyncableIdentitiesTimestampIsUpdated() throws {
        var identity = try storeAndFetchIdentity(makeIdentity(firstName: "Morgan", lastName: "Black", emailAddress: "morgan@old.com"))
        let createdTimestamp = try provider.modifiedSyncableIdentities().first!.metadata.lastModified!
        Thread.sleep(forTimeInterval: 0.001)

        identity.emailAddress = "morgan@new.com"
        identity = try storeAndFetchIdentity(identity)

        let syncableIdentities = try provider.modifiedSyncableIdentities()
        XCTAssertGreaterThan(syncableIdentities[0].metadata.lastModified!, createdTimestamp)
    }

    func testWhenIdentityIsDeletedThenSyncableIdentityIsPersisted() throws {
        let identity = try storeAndFetchIdentity(makeIdentity(firstName: "Sam", lastName: "Parker"))
        let initialMetadata = try provider.modifiedSyncableIdentities().first!
        Thread.sleep(forTimeInterval: 0.001)

        try provider.deleteIdentityForIdentityId(try XCTUnwrap(identity.id))

        let syncableIdentities = try provider.modifiedSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertNil(syncableIdentities[0].metadata.objectId)
        XCTAssertGreaterThan(syncableIdentities[0].metadata.lastModified!, initialMetadata.metadata.lastModified!)
    }

    // MARK: - Helpers

    private func makeIdentity(identityId: Int64? = nil,
                              title: String? = nil,
                              firstName: String? = nil,
                              middleName: String? = nil,
                              lastName: String? = nil,
                              birthdayDay: Int? = nil,
                              birthdayMonth: Int? = nil,
                              birthdayYear: Int? = nil,
                              addressStreet: String? = nil,
                              addressStreet2: String? = nil,
                              addressCity: String? = nil,
                              addressProvince: String? = nil,
                              addressPostalCode: String? = nil,
                              addressCountryCode: String? = nil,
                              homePhone: String? = nil,
                              emailAddress: String? = nil) -> SecureVaultModels.Identity {
        let now = Date()
        return SecureVaultModels.Identity(
            id: identityId,
            title: title ?? "",
            created: now,
            lastUpdated: now,
            firstName: firstName,
            middleName: middleName,
            lastName: lastName,
            birthdayDay: birthdayDay,
            birthdayMonth: birthdayMonth,
            birthdayYear: birthdayYear,
            addressStreet: addressStreet,
            addressStreet2: addressStreet2,
            addressCity: addressCity,
            addressProvince: addressProvince,
            addressPostalCode: addressPostalCode,
            addressCountryCode: addressCountryCode,
            homePhone: homePhone,
            mobilePhone: nil,
            emailAddress: emailAddress
        )
    }

    @discardableResult
    private func storeAndFetchIdentity(_ identity: SecureVaultModels.Identity) throws -> SecureVaultModels.Identity {
        let identityId = try provider.storeIdentity(identity)
        return try XCTUnwrap(try provider.identityForIdentityId(identityId))
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

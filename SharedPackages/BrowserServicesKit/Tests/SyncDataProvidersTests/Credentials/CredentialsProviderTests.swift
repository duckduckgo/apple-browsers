//
//  CredentialsProviderTests.swift
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

final class CredentialsProviderTests: CredentialsProviderTestsBase {

    func testThatLastSyncTimestampIsNilByDefault() {
        XCTAssertNil(provider.lastSyncTimestamp)
        XCTAssertNil(provider.lastSyncLocalTimestamp)
    }

    func testThatLastSyncTimestampIsPersisted() throws {
        try provider.registerFeature(withState: .readyToSync)
        let date = Date()
        provider.updateSyncTimestamps(server: "12345", local: date)
        XCTAssertEqual(provider.lastSyncTimestamp, "12345")
        XCTAssertEqual(provider.lastSyncLocalTimestamp, date)
    }

    func testThatPrepareForFirstSyncClearsLastSyncTimestampAndSetsModifiedAtForAllCredentials() throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
            try self.secureVault.storeSyncableCredentials("2", in: database)
            try self.secureVault.storeSyncableCredentials("3", in: database)
            try self.secureVault.storeSyncableCredentials("4", in: database)
        }

        var syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertTrue(syncableCredentials.allSatisfy { $0.metadata.lastModified == nil })

        try provider.prepareForFirstSync()

        XCTAssertNil(provider.lastSyncTimestamp)

        syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 4)
        XCTAssertTrue(syncableCredentials.allSatisfy { $0.metadata.lastModified != nil })
    }

    func testThatFetchChangedObjectsReturnsAllObjectsWithNonNilModifiedAt() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("2", in: database)
            try self.secureVault.storeSyncableCredentials("3", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("4", in: database)
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableCredentialsAdapter.init)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set(["1", "3"])
        )
    }

    func testThatFetchChangedObjectsFiltersOutInvalidCredentials() async throws {
        let longValue = String(repeating: "x", count: 10000)

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", title: longValue, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("2", in: database)
            try self.secureVault.storeSyncableCredentials("3", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("4", in: database)
            try self.secureVault.storeSyncableCredentials("5", domain: longValue, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("6", username: longValue, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("7", password: longValue, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("8", notes: longValue, lastModified: Date(), in: database)
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableCredentialsAdapter.init)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set(["3"])
        )
    }

    func testWhenCredentialsAreSoftDeletedThenFetchChangedObjectsContainsDeletedSyncable() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
            try self.secureVault.storeSyncableCredentials("2", in: database)
            try self.secureVault.storeSyncableCredentials("3", in: database)
            try self.secureVault.storeSyncableCredentials("4", in: database)
        }

        try secureVault.deleteWebsiteCredentialsFor(accountId: 2)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableCredentialsAdapter.init)

        XCTAssertEqual(changedObjects.count, 1)

        let syncable = try XCTUnwrap(changedObjects.first)

        XCTAssertTrue(syncable.isDeleted)
        XCTAssertEqual(syncable.uuid, "2")
    }

    func testThatSentItemsAreProperlyCleanedUp() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("10", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("20", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("30", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableCredentials("40", lastModified: Date(), in: database)
        }

        try secureVault.deleteWebsiteCredentialsFor(accountId: 2)

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 3)
        XCTAssertTrue(syncableCredentials.allSatisfy { $0.metadata.lastModified == nil })
    }

    func testThatItemsThatFailedValidationRetainTheirTimestamps() async throws {
        let longValue = String(repeating: "x", count: 10000)
        let timestamp = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("10", title: longValue, lastModified: timestamp, in: database)
            try self.secureVault.storeSyncableCredentials("20", lastModified: timestamp, in: database)
            try self.secureVault.storeSyncableCredentials("30", title: longValue, lastModified: timestamp, in: database)
            try self.secureVault.storeSyncableCredentials("40", lastModified: timestamp, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 4)
        XCTAssertNotNil(syncableCredentials.first(where: { $0.metadata.uuid == "10" })?.metadata.lastModified)
        XCTAssertNil(syncableCredentials.first(where: { $0.metadata.uuid == "20" })?.metadata.lastModified)
        XCTAssertNotNil(syncableCredentials.first(where: { $0.metadata.uuid == "30" })?.metadata.lastModified)
        XCTAssertNil(syncableCredentials.first(where: { $0.metadata.uuid == "40" })?.metadata.lastModified)
    }

    // MARK: - Initial Sync

    func testThatInitialSyncIntoEmptyDatabaseClearsModifiedAtFromAllReceivedObjects() async throws {

        let received: [Syncable] = [
            .credentials(id: "1"),
            .credentials(id: "2"),
            .credentials(id: "3"),
            .credentials(id: "4"),
            .credentials(id: "5")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertEqual(syncableCredentials.count, 5)
        XCTAssertTrue(syncableCredentials.allSatisfy { $0.metadata.lastModified == nil })
    }

    func testThatInitialSyncClearsModifiedAtFromDeduplicatedCredential() async throws {

        let date = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", lastModified: date, in: database)
        }

        let received: [Syncable] = [
            .credentials("1", id: "2", domain: "1", username: "1", password: "1", notes: "1")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: date.addingTimeInterval(1), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let credential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertNil(credential.metadata.lastModified)
    }

    func testThatInitialSyncClearsModifiedAtFromDeduplicatedCredentialWithAllFieldsNil() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", nullifyOtherFields: true, lastModified: Date().withMillisecondPrecision, in: database)
        }

        let received: [Syncable] = [
            .credentials(id: "2", nullifyOtherFields: true)
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let credential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertNil(credential.metadata.lastModified)
    }

    func testWhenDatabaseIsLockedDuringInitialSyncThenSyncResponseHandlingIsRetried() async throws {

        let localDatabaseProvider = try DefaultAutofillDatabaseProvider(file: databaseLocation, key: simpleL1Key)
        let localSecureVaultFactory = AutofillVaultFactory.testFactory(databaseProvider: localDatabaseProvider)
        let localSecureVault = try localSecureVaultFactory.makeVault(reporter: nil)
        _ = try localSecureVault.authWith(password: "abcd".data(using: .utf8)!)

        let received: [Syncable] = [
            .credentials(id: "1")
        ]

        var numberOfAttempts = 0
        var didThrowError = false

        provider.willSaveContextAfterApplyingSyncResponse = {
            numberOfAttempts += 1
            if !didThrowError {
                didThrowError = true
                throw DatabaseError(resultCode: .SQLITE_LOCKED)
            }
        }

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        XCTAssertEqual(numberOfAttempts, 2)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let credential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertEqual(credential.account?.title, "1")
        XCTAssertNil(credential.metadata.lastModified)
    }

    // MARK: - Regular Sync

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedThenObjectIsNotDeleted() async throws {

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", in: database)
        }

        try secureVault.deleteWebsiteCredentialsFor(accountId: 1)

        let received: [Syncable] = [
            .credentials(id: "1", username: "2")
        ]

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: 1).withMillisecondPrecision, serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let updatedCredential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertEqual(syncableCredentials.count, 1)
        XCTAssertNil(updatedCredential.metadata.lastModified)
        XCTAssertEqual(updatedCredential.account?.username, "2")
    }

    func testWhenObjectWasSentAndThenDeletedLocallyAndAnUpdateIsReceivedThenTheObjectIsDeleted() async throws {

        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        try secureVault.deleteWebsiteCredentialsFor(accountId: 1)

        let received: [Syncable] = [
            .credentials(id: "1", username: "2")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let deletedCredential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertNotNil(deletedCredential.metadata.lastModified)
        XCTAssertNil(deletedCredential.metadata.objectId)
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteChangesAreDropped() async throws {

        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [
            .credentials(id: "1", username: "2")
        ]

        var credentials = try XCTUnwrap(try secureVault.websiteCredentialsFor(accountId: 1))
        credentials.password = "updated".data(using: .utf8)
        try secureVault.storeWebsiteCredentials(credentials)
        var updateTimestamp: Date?
        try secureVault.inDatabaseTransaction({ database in
            updateTimestamp = try self.secureVault.syncableCredentialsForAccountId(1, in: database)?.metadata.lastModified
        })

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let updatedCredential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertEqual(updatedCredential.metadata.lastModified, updateTimestamp)
        XCTAssertEqual(updatedCredential.account?.username, "1")
        XCTAssertEqual(updatedCredential.credentialsRecord?.password, credentials.password)
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteDeletionIsApplied() async throws {

        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [
            .credentials(id: "1", username: "2", isDeleted: true)
        ]

        var credentials = try XCTUnwrap(try secureVault.websiteCredentialsFor(accountId: 1))
        credentials.password = "updated".data(using: .utf8)
        try secureVault.storeWebsiteCredentials(credentials)
        try secureVault.inDatabaseTransaction({ database in
            _ = try self.secureVault.syncableCredentialsForAccountId(1, in: database)
        })

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let syncableCredentials = try fetchAllSyncableCredentials()
        XCTAssertTrue(syncableCredentials.isEmpty)
    }

    func testWhenDatabaseIsLockedDuringRegularSyncThenSyncResponseHandlingIsRetried() async throws {

        let localDatabaseProvider = try DefaultAutofillDatabaseProvider(file: databaseLocation, key: simpleL1Key)
        let localSecureVaultFactory = AutofillVaultFactory.testFactory(databaseProvider: localDatabaseProvider)
        let localSecureVault = try localSecureVaultFactory.makeVault(reporter: nil)
        _ = try localSecureVault.authWith(password: "abcd".data(using: .utf8)!)

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableCredentials("1", lastModified: Date(), in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [
            .credentials(id: "1")
        ]

        var numberOfAttempts = 0
        var didThrowError = false

        provider.willSaveContextAfterApplyingSyncResponse = {
            numberOfAttempts += 1
            if !didThrowError {
                didThrowError = true
                throw DatabaseError(resultCode: .SQLITE_LOCKED)
            }
        }

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        XCTAssertEqual(numberOfAttempts, 2)

        let syncableCredentials = try fetchAllSyncableCredentials()
        let credential = try XCTUnwrap(syncableCredentials.first)
        XCTAssertEqual(credential.account?.title, "1")
        XCTAssertNil(credential.metadata.lastModified)
    }
}

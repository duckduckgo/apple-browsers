//
//  IdentitiesProviderTests.swift
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

final class IdentitiesProviderTests: IdentitiesProviderTestsBase {

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

    func testThatPrepareForFirstSyncClearsLastSyncTimestampAndSetsModifiedAtForAllIdentities() throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", in: database)
            try self.secureVault.storeSyncableIdentity("2", in: database)
            try self.secureVault.storeSyncableIdentity("3", in: database)
            try self.secureVault.storeSyncableIdentity("4", in: database)
        }

        var syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertTrue(syncableIdentities.allSatisfy { $0.metadata.lastModified == nil })

        try provider.prepareForFirstSync()

        XCTAssertNil(provider.lastSyncTimestamp)

        syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 4)
        XCTAssertTrue(syncableIdentities.allSatisfy { $0.metadata.lastModified != nil })
    }

    func testThatFetchChangedObjectsReturnsAllObjectsWithNonNilModifiedAt() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("2", in: database)
            try self.secureVault.storeSyncableIdentity("3", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("4", in: database)
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableIdentitiesAdapter.init)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set(["1", "3"])
        )
    }

    func testThatFetchChangedObjectsFiltersOutInvalidIdentities() async throws {
        let longValue = String(repeating: "x", count: 10_000)

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", title: longValue, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("2", in: database)
            try self.secureVault.storeSyncableIdentity("3", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("4", in: database)
            try self.secureVault.storeSyncableIdentity("5", firstName: longValue, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("6", lastName: longValue, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("7", addressStreet: longValue, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("8", emailAddress: longValue, lastModified: Date(), in: database)
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableIdentitiesAdapter.init)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set(["3"])
        )
    }

    func testWhenIdentitiesAreSoftDeletedThenFetchChangedObjectsContainsDeletedSyncable() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", in: database)
            try self.secureVault.storeSyncableIdentity("2", in: database)
            try self.secureVault.storeSyncableIdentity("3", in: database)
            try self.secureVault.storeSyncableIdentity("4", in: database)
        }

        try secureVault.deleteIdentityFor(identityId: 2)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableIdentitiesAdapter.init)

        XCTAssertEqual(changedObjects.count, 1)

        let syncable = try XCTUnwrap(changedObjects.first)

        XCTAssertTrue(syncable.isDeleted)
        XCTAssertEqual(syncable.uuid, "2")
    }

    func testThatSentItemsAreProperlyCleanedUp() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("10", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("20", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("30", lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("40", lastModified: Date(), in: database)
        }

        try secureVault.deleteIdentityFor(identityId: 2)

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 3)
        XCTAssertTrue(syncableIdentities.allSatisfy { $0.metadata.lastModified == nil })
    }

    func testThatItemsThatFailedValidationRetainTheirTimestamps() async throws {
        let longValue = String(repeating: "x", count: 10_000)
        let timestamp = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("10", title: longValue, lastModified: timestamp, in: database)
            try self.secureVault.storeSyncableIdentity("20", lastModified: timestamp, in: database)
            try self.secureVault.storeSyncableIdentity("30", addressStreet: longValue, lastModified: timestamp, in: database)
            try self.secureVault.storeSyncableIdentity("40", lastModified: timestamp, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 4)
        XCTAssertNotNil(syncableIdentities.first(where: { $0.metadata.uuid == "10" })?.metadata.lastModified)
        XCTAssertNil(syncableIdentities.first(where: { $0.metadata.uuid == "20" })?.metadata.lastModified)
        XCTAssertNotNil(syncableIdentities.first(where: { $0.metadata.uuid == "30" })?.metadata.lastModified)
        XCTAssertNil(syncableIdentities.first(where: { $0.metadata.uuid == "40" })?.metadata.lastModified)
    }

    func testThatDeduplicationReturnsOnlyOneOfDuplicateIdentities() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", title: "Profile A", firstName: "User", lastName: "One", nullifyOtherFields: true, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("2", title: "Profile A", firstName: "User", lastName: "One", nullifyOtherFields: true, lastModified: Date(), in: database)
            try self.secureVault.storeSyncableIdentity("3", title: "Profile B", firstName: "Other", lastName: "User", nullifyOtherFields: true, lastModified: Date(), in: database)
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableIdentitiesAdapter.init)

        XCTAssertEqual(changedObjects.count, 3)
    }

    func testThatInitialSyncIntoEmptyDatabaseClearsModifiedAtFromAllReceivedObjects() async throws {
        let received: [Syncable] = [
            .identity(uuid: "1", firstName: "One"),
            .identity(uuid: "2", firstName: "Two")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 2)
        XCTAssertTrue(syncableIdentities.allSatisfy { $0.metadata.lastModified == nil })
    }

    func testThatInitialSyncClearsModifiedAtFromDeduplicatedIdentity() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("local", title: "Profile", firstName: "John", lastName: "Doe", addressStreet: "123 Street", nullifyOtherFields: true, lastModified: Date(), in: database)
        }

        let received: [Syncable] = [
            .identity("Profile", uuid: "remote", firstName: "John", lastName: "Doe", addressStreet: "123 Street", nullifyOtherFields: true)
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities.first?.metadata.uuid, "remote")
        XCTAssertNil(syncableIdentities.first?.metadata.lastModified)
    }

    func testThatInitialSyncClearsModifiedAtFromDeduplicatedIdentityWithAllFieldsNil() async throws {
        try secureVault.inDatabaseTransaction { database in
            let identity = SecureVaultModels.Identity(
                id: nil,
                title: "",
                created: Date(),
                lastUpdated: Date(),
                firstName: nil,
                middleName: nil,
                lastName: nil,
                birthdayDay: nil,
                birthdayMonth: nil,
                birthdayYear: nil,
                addressStreet: nil,
                addressStreet2: nil,
                addressCity: nil,
                addressProvince: nil,
                addressPostalCode: nil,
                addressCountryCode: nil,
                homePhone: nil,
                mobilePhone: nil,
                emailAddress: nil
            )
            let syncableIdentity = SecureVaultModels.SyncableIdentity(
                uuid: "1",
                identity: identity,
                lastModified: nil
            )
            try self.secureVault.storeSyncableIdentity(syncableIdentity, in: database)
        }

        let received: [Syncable] = [
            .identity(uuid: "2", nullifyOtherFields: true)
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableIdentities = try fetchAllSyncableIdentities()
        let identity = try XCTUnwrap(syncableIdentities.first)
        XCTAssertNil(identity.metadata.lastModified)
    }

    func testWhenDatabaseIsLockedDuringInitialSyncThenSyncResponseHandlingIsRetried() async throws {
        let received: [Syncable] = [
            .identity(uuid: "1", firstName: "One"),
            .identity(uuid: "2", firstName: "Two")
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

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 2)
        XCTAssertTrue(syncableIdentities.allSatisfy { $0.metadata.lastModified == nil })
    }

    // MARK: - Regular Sync

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedThenObjectIsNotDeleted() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", in: database)
        }

        try secureVault.deleteIdentityFor(identityId: 1)

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [
            .identity("Updated", uuid: "1", firstName: "Updated", lastName: "Person")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertEqual(syncableIdentities.first?.metadata.uuid, "1")
        XCTAssertNil(syncableIdentities.first?.metadata.lastModified)
    }

    func testWhenObjectWasSentAndThenDeletedLocallyAndAnUpdateIsReceivedThenTheObjectIsDeleted() async throws {
        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", firstName: "John", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        try secureVault.deleteIdentityFor(identityId: 1)

        let received: [Syncable] = [
            .identity("Updated", uuid: "1", firstName: "Updated", lastName: "Person")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let syncableIdentities = try fetchAllSyncableIdentities()
        let deletedIdentity = try XCTUnwrap(syncableIdentities.first)
        XCTAssertNotNil(deletedIdentity.metadata.lastModified)
        XCTAssertNil(deletedIdentity.metadata.objectId)
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteChangesAreDropped() async throws {
        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", title: "Original", firstName: "John", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [
            .identity("Remote Update", uuid: "1", firstName: "Remote", lastName: "Person")
        ]

        var identity = try XCTUnwrap(try secureVault.identityFor(id: 1))
        identity.title = "Local Update"
        identity.firstName = "Local"
        _ = try secureVault.storeIdentity(identity)

        let updateTimestamp = try fetchAllSyncableIdentities().first?.metadata.lastModified

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let identities = try secureVault.identities()
        let storedIdentity = try XCTUnwrap(identities.first)
        XCTAssertEqual(storedIdentity.title, "Local Update")
        XCTAssertEqual(storedIdentity.firstName, "Local")

        let syncableIdentities = try fetchAllSyncableIdentities()
        let updatedIdentity = try XCTUnwrap(syncableIdentities.first)
        XCTAssertEqual(updatedIdentity.metadata.lastModified, updateTimestamp)
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteDeletionIsApplied() async throws {
        let modifiedAt = Date().withMillisecondPrecision

        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", title: "Original", firstName: "John", lastModified: modifiedAt, in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [
            .identity(uuid: "1", isDeleted: true)
        ]

        var identity = try XCTUnwrap(try secureVault.identityFor(id: 1))
        identity.title = "Local Update"
        identity.firstName = "Local"
        _ = try secureVault.storeIdentity(identity)

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 0)
    }

    func testWhenDatabaseIsLockedDuringRegularSyncThenSyncResponseHandlingIsRetried() async throws {
        try secureVault.inDatabaseTransaction { database in
            try self.secureVault.storeSyncableIdentity("1", lastModified: Date(), in: database)
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let received: [Syncable] = [
            .identity(uuid: "1", firstName: "Updated")
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

        let syncableIdentities = try fetchAllSyncableIdentities()
        XCTAssertEqual(syncableIdentities.count, 1)
        XCTAssertNil(syncableIdentities.first?.metadata.lastModified)
    }
}

//
//  SettingsProviderTests.swift
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

final class SettingsProviderTests: SettingsProviderTestsBase {

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

    func testThatPrepareForFirstSyncClearsLastSyncTimestampAndSetsModifiedAtForAllSettings() throws {

        try emailManager.signIn(username: "dax", token: "secret-token")

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.allSatisfy { $0.lastModified == nil })

        try provider.prepareForFirstSync()

        XCTAssertNil(provider.lastSyncTimestamp)

        settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 2)
        XCTAssertTrue(settingsMetadata.allSatisfy { $0.lastModified != nil })
    }

    func testThatFetchChangedObjectsReturnsEmailSettingsWithNonNilModifiedAt() async throws {

        let otherEmailManager = EmailManager(storage: MockEmailManagerStorage())
        try otherEmailManager.signIn(username: "dax", token: "secret-token")

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableSettingAdapter.init)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set([SettingsProvider.Setting.emailProtectionGeneration.key])
        )
    }

    func testThatFetchChangedObjectsReturnsTestSettingWithNonNilModifiedAt() async throws {

        testSettingSyncHandler.syncedValue = "1"

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableSettingAdapter.init)

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set([SettingsProvider.Setting.testSetting.key])
        )
    }

    func testThatFetchChangedObjectsReturnsEmptyArrayWhenNothingHasChanged() async throws {
        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableSettingAdapter.init)
        XCTAssertTrue(changedObjects.isEmpty)
    }

    func testWhenEmailProtectionIsDisabledThenFetchChangedObjectsContainsDeletedSyncable() async throws {

        let otherEmailManager = EmailManager(storage: MockEmailManagerStorage())
        try otherEmailManager.signOut()

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableSettingAdapter.init)

        XCTAssertEqual(changedObjects.count, 1)

        let syncable = try XCTUnwrap(changedObjects.first)

        XCTAssertTrue(syncable.isDeleted)
        XCTAssertEqual(syncable.uuid, SettingsProvider.Setting.emailProtectionGeneration.key)
    }

    func testWhenTestSettingIsClearedThenFetchChangedObjectsContainsDeletedSyncable() async throws {

        testSettingSyncHandler.syncedValue = "1"
        testSettingSyncHandler.syncedValue = nil

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter).map(SyncableSettingAdapter.init)

        XCTAssertEqual(changedObjects.count, 1)

        let syncable = try XCTUnwrap(changedObjects.first)

        XCTAssertTrue(syncable.isDeleted)
        XCTAssertEqual(syncable.uuid, SettingsProvider.Setting.testSetting.key)
    }

    func testThatSigninInToEmailProtectionStateUpdatesSyncMetadataTimestamp() async throws {

        try provider.prepareForFirstSync()

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let initialSettingsMetadata = fetchAllSettingsMetadata(in: context)
        let initialEmailMetadata = try XCTUnwrap(initialSettingsMetadata.first(where: { $0.key == SettingsProvider.Setting.emailProtectionGeneration.key }))
        let initialTimestamp = initialEmailMetadata.lastModified
        XCTAssertEqual(initialSettingsMetadata.count, 2)
        XCTAssertNotNil(initialTimestamp)

        try await Task.sleep(nanoseconds: 1000)

        let otherEmailManager = EmailManager(storage: MockEmailManagerStorage())
        try otherEmailManager.signIn(username: "dax", token: "secret-token")

        context.refreshAllObjects()

        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first(where: { $0.key == SettingsProvider.Setting.emailProtectionGeneration.key }))
        let timestamp = emailMetadata.lastModified
        XCTAssertEqual(settingsMetadata.count, 2)
        XCTAssertNotNil(timestamp)

        XCTAssertTrue(timestamp! > initialTimestamp!)
    }

    func testThatSigningOutOfEmailProtectionStateUpdatesSyncMetadataTimestamp() async throws {

        try emailManager.signIn(username: "dax", token: "secret-token")

        try provider.prepareForFirstSync()

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let initialSettingsMetadata = fetchAllSettingsMetadata(in: context)
        let initialEmailMetadata = try XCTUnwrap(initialSettingsMetadata.first(where: { $0.key == SettingsProvider.Setting.emailProtectionGeneration.key }))
        let initialTimestamp = initialEmailMetadata.lastModified
        XCTAssertEqual(initialSettingsMetadata.count, 2)
        XCTAssertNotNil(initialTimestamp)

        try await Task.sleep(nanoseconds: 1000)

        let otherEmailManager = EmailManager(storage: MockEmailManagerStorage())
        try otherEmailManager.signOut()

        context.refreshAllObjects()

        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first(where: { $0.key == SettingsProvider.Setting.emailProtectionGeneration.key }))
        let timestamp = emailMetadata.lastModified
        XCTAssertEqual(settingsMetadata.count, 2)
        XCTAssertNotNil(timestamp)

        XCTAssertTrue(timestamp! > initialTimestamp!)
    }

    func testThatUpdatingSettingValueUpdatesSyncMetadataTimestamp() async throws {

        try provider.prepareForFirstSync()

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let initialSettingsMetadata = fetchAllSettingsMetadata(in: context)
        let initialTestSettingMetadata = try XCTUnwrap(initialSettingsMetadata.first(where: { $0.key == SettingsProvider.Setting.testSetting.key }))
        let initialTimestamp = initialTestSettingMetadata.lastModified
        XCTAssertEqual(initialSettingsMetadata.count, 2)
        XCTAssertNotNil(initialTimestamp)

        try await Task.sleep(nanoseconds: 1000)

        testSettingSyncHandler.syncedValue = "1"

        context.refreshAllObjects()

        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let testSettingMetadata = try XCTUnwrap(settingsMetadata.first(where: { $0.key == SettingsProvider.Setting.testSetting.key }))
        let timestamp = testSettingMetadata.lastModified
        XCTAssertEqual(settingsMetadata.count, 2)
        XCTAssertNotNil(timestamp)

        XCTAssertTrue(timestamp! > initialTimestamp!)
    }

    func testThatSentItemsAreProperlyCleanedUp() async throws {

        let otherEmailManager = EmailManager(storage: MockEmailManagerStorage())
        try otherEmailManager.signIn(username: "dax", token: "secret-token")

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertNil(emailMetadata.lastModified)
    }

    // MARK: - Initial Sync

    func testThatInitialSyncClearsLastModifiedForAllReceivedObjects() async throws {

        try provider.prepareForFirstSync()

        let received: [Syncable] = [
            .emailProtection(username: "abcd", token: "secret-token")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first(where: { $0.key == SettingsProvider.Setting.emailProtectionGeneration.key }))
        XCTAssertNil(emailMetadata.lastModified)
    }

    func testThatInitialSyncClearsLastModifiedForDeduplicatedEmailProtectionSetting() async throws {

        let date = Date()

        let emailManager = EmailManager(storage: MockEmailManagerStorage())
        try emailManager.signIn(username: "dax", token: "secret-token")

        let received: [Syncable] = [
            .emailProtection(username: "dax", token: try emailManager.getToken()!)
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: date.addingTimeInterval(1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(emailMetadata.lastModified)
    }

    func testThatInitialSyncClearsLastModifiedForDeduplicatedSetting() async throws {

        let date = Date()

        testSettingSyncHandler.syncedValue = "1"

        let received: [Syncable] = [
            .testSetting("1")
        ]

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: date.addingTimeInterval(1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let testSettingMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(testSettingMetadata.lastModified)
    }

    func testWhenThereIsMergeConflictDuringInitialSyncThenSyncResponseHandlingIsRetried() async throws {
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(username: "dax-local", token: "secret-token-local")

        let received: [Syncable] = [
            .emailProtection(username: "dax", token: "secret-token")
        ]

        var willSaveCallCount = 0

        var emailProtectionModificationDate: Date?
        provider.willSaveContextAfterApplyingSyncResponse = {
            willSaveCallCount += 1
            if emailProtectionModificationDate != nil {
                return
            }
            try emailManager.signOut()
            context.performAndWait {
                emailProtectionModificationDate = SyncableSettingsMetadataUtils
                    .fetchSettingsMetadata(with: SettingsProvider.Setting.emailProtectionGeneration.key, in: context)?
                    .lastModified
            }
        }
        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        XCTAssertEqual(willSaveCallCount, 2)

        context.refreshAllObjects()
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertFalse(settingsMetadata.isEmpty)
        XCTAssertNil(emailManagerStorage.mockUsername)
        XCTAssertNil(emailManagerStorage.mockToken)
    }

    // MARK: - Regular Sync

    func testWhenEmailProtectionDeleteIsSentAndUpdateIsReceivedThenEmailProtectionIsNotDeleted() async throws {
        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(username: "dax", token: "secret-token")
        try emailManager.signOut()

        let received: [Syncable] = [
            .emailProtection(username: "dax", token: "secret-token2")
        ]

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(emailMetadata.lastModified)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token2")
    }

    func testWhenSettingDeleteIsSentAndUpdateIsReceivedThenSettingIsNotDeleted() async throws {
        testSettingSyncHandler.syncedValue = "local"
        testSettingSyncHandler.syncedValue = nil

        let received: [Syncable] = [
            .testSetting("remote")
        ]

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let testSettingMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(testSettingMetadata.lastModified)
        XCTAssertEqual(testSettingSyncHandler.syncedValue, "remote")
    }

    func testWhenEmailProtectionWasSentAndThenDisabledLocallyAndAnUpdateIsReceivedThenEmailProtectionIsDisabled() async throws {

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(username: "dax", token: "secret-token")

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        try emailManager.signOut()

        let received: [Syncable] = [
            .emailProtection(username: "dax2", token: "secret-token2")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.emailProtectionGeneration.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertNil(emailManagerStorage.mockUsername)
        XCTAssertNil(emailManagerStorage.mockToken)
    }

    func testWhenSettingWasSentAndThenDeletedLocallyAndAnUpdateIsReceivedThenSettingIsDeleted() async throws {

        testSettingSyncHandler.syncedValue = "local"

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        testSettingSyncHandler.syncedValue = nil

        let received: [Syncable] = [
            .testSetting("remote")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.testSetting.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertNil(testSettingSyncHandler.syncedValue)
    }

    func testWhenEmailProtectionWasEnabledLocallyAfterStartingSyncThenRemoteChangesAreDropped() async throws {

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(username: "dax", token: "secret-token")

        let received: [Syncable] = [
            .emailProtection(username: "dax2", token: "secret-token2")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.emailProtectionGeneration.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token")
    }

    func testWhenSettingWasUpdatedLocallyAfterStartingSyncThenRemoteChangesAreDropped() async throws {

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        testSettingSyncHandler.syncedValue = "local"

        let received: [Syncable] = [
            .testSetting("remote")
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.testSetting.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertEqual(testSettingSyncHandler.syncedValue, "local")
    }

    func testWhenEmailProtectionWasEnabledLocallyAfterStartingSyncThenRemoteDisableIsDropped() async throws {

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(username: "dax", token: "secret-token")

        let received: [Syncable] = [
            .emailProtectionDeleted()
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.emailProtectionGeneration.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token")
    }

    func testWhenSettingWasUpdatedLocallyAfterStartingSyncThenRemoteDeleteIsDropped() async throws {

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        testSettingSyncHandler.syncedValue = "local"

        let received: [Syncable] = [
            .testSettingDeleted()
        ]

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().advanced(by: -1), serverTimestamp: "1234", crypter: crypter)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.testSetting.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertEqual(testSettingSyncHandler.syncedValue, "local")
    }

    func testWhenThereIsMergeConflictDuringRegularSyncThenSyncResponseHandlingIsRetried() async throws {
        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(username: "dax", token: "secret-token-local")

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let received: [Syncable] = [
            .emailProtection(username: "dax", token: "secret-token")
        ]

        var willSaveCallCount = 0

        var emailProtectionModificationDate: Date?
        provider.willSaveContextAfterApplyingSyncResponse = {
            willSaveCallCount += 1
            if emailProtectionModificationDate != nil {
                return
            }
            try emailManager.signOut()
            context.performAndWait {
                emailProtectionModificationDate = SyncableSettingsMetadataUtils
                    .fetchSettingsMetadata(with: SettingsProvider.Setting.emailProtectionGeneration.key, in: context)?
                    .lastModified
            }
        }
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        XCTAssertEqual(willSaveCallCount, 2)

        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertEqual(settingsMetadata.count, 1)
        XCTAssertEqual(settingsMetadata.first?.key, SettingsProvider.Setting.emailProtectionGeneration.key)
        XCTAssertNotNil(settingsMetadata.first?.lastModified)
        XCTAssertNil(emailManagerStorage.mockUsername)
        XCTAssertNil(emailManagerStorage.mockToken)
    }
}

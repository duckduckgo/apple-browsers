//
//  SettingsInitialSyncResponseHandlerTests.swift
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

final class SettingsInitialSyncResponseHandlerTests: SettingsProviderTestsBase {

    func testThatEmailProtectionEnabledStateIsAppliedLocally() async throws {
        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signOut()

        let received: [Syncable] = [
            .emailProtection(username: "dax", token: "secret-token")
        ]

        try await handleInitialSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(emailMetadata.lastModified)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token")
    }

    func testThatEmailProtectionDisabledStateIsIgnoredWhenLocallyIsDisabled() async throws {
        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signOut()

        let received: [Syncable] = [
            .emailProtectionDeleted()
        ]

        try await handleInitialSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(emailMetadata.lastModified)
        XCTAssertNil(emailManagerStorage.mockUsername)
        XCTAssertNil(emailManagerStorage.mockToken)
    }

    func testWhenEmailProtectionIsEnabledLocallyAndRemotelyThenRemoteStateIsApplied() async throws {
        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(username: "dax-local", token: "secret-token-local")

        let received: [Syncable] = [
            .emailProtection(username: "dax-remote", token: "secret-token-remote")
        ]

        try await handleInitialSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(emailMetadata.lastModified)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax-remote")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token-remote")
    }

    func testThatEmailProtectionStateIsDeduplicated() async throws {
        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(username: "dax", token: "secret-token")

        let received: [Syncable] = [
            .emailProtection(username: "dax", token: "secret-token")
        ]

        try await handleInitialSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(emailMetadata.lastModified)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token")
    }

    func testThatSettingStateIsAppliedLocally() async throws {
        testSettingSyncHandler.syncedValue = nil

        let received: [Syncable] = [
            .testSetting("remote")
        ]

        try await handleInitialSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let testSettingMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(testSettingMetadata.lastModified)
        XCTAssertEqual(testSettingSyncHandler.syncedValue, "remote")
    }

    func testThatDeletedSettingIsIgnoredWhenLocallyIsNil() async throws {
        testSettingSyncHandler.syncedValue = nil

        let received: [Syncable] = [
            .testSettingDeleted()
        ]

        try await handleInitialSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let testSettingMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(testSettingMetadata.lastModified)
        XCTAssertNil(testSettingSyncHandler.syncedValue)
    }

    func testWhenSettingIsNotNilLocallyAndRemotelyThenRemoteStateIsApplied() async throws {
        testSettingSyncHandler.syncedValue = "local"

        let received: [Syncable] = [
            .testSetting("remote")
        ]

        try await handleInitialSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let testSettingMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(testSettingMetadata.lastModified)
        XCTAssertEqual(testSettingSyncHandler.syncedValue, "remote")
    }

    func testThatSettingValueIsDeduplicated() async throws {
        testSettingSyncHandler.syncedValue = "local"

        let received: [Syncable] = [
            .testSetting("local")
        ]

        try await handleInitialSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let testSettingMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(testSettingMetadata.lastModified)
        XCTAssertEqual(testSettingSyncHandler.syncedValue, "local")
    }
}

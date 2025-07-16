//
//  SettingsRegularSyncResponseHandlerTests.swift
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

final class SettingsRegularSyncResponseHandlerTests: SettingsProviderTestsBase {

    func testThatEmailProtectionEnabledStateIsApplied() async throws {
        let received: [Syncable] = [
            .emailProtection(username: "dax", token: "secret-token")
        ]

        try await handleSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token")
    }

    func testThatEmailProtectionDisabledStateIsApplied() async throws {
        let emailManager = EmailManager(storage: emailManagerStorage)
        try emailManager.signIn(username: "dax", token: "secret-token")

        let received: [Syncable] = [
            .emailProtectionDeleted()
        ]

        try await handleSyncResponse(received: received)

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

        try await handleSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let emailMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(emailMetadata.lastModified)
        XCTAssertEqual(emailManagerStorage.mockUsername, "dax-remote")
        XCTAssertEqual(emailManagerStorage.mockToken, "secret-token-remote")
    }

    func testThatSettingStateIsApplied() async throws {

        let received: [Syncable] = [
            .testSetting("remote")
        ]

        let exp = XCTestExpectation(description: "should process response")

        let cancellable = testSettingSyncHandler.$syncedValue.sink { value in
            guard let value else { return }
            XCTAssertEqual(value, "remote")
            exp.fulfill()
        }

        try await handleSyncResponse(received: received)
        await fulfillment(of: [exp], timeout: 1.0)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
    }

    func testThatSettingDeletedStateIsApplied() async throws {
        testSettingSyncHandler.syncedValue = "local"

        let received: [Syncable] = [
            .testSettingDeleted()
        ]

        try await handleSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let testSettingMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(testSettingMetadata.lastModified)
        XCTAssertNil(testSettingSyncHandler.syncedValue)
    }

    func testWhenSettingIsSetLocallyAndRemotelyThenRemoteStateIsApplied() async throws {
        testSettingSyncHandler.syncedValue = "local"

        let received: [Syncable] = [
            .testSetting("remote")
        ]

        try await handleSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        let testSettingMetadata = try XCTUnwrap(settingsMetadata.first)
        XCTAssertNil(testSettingMetadata.lastModified)
        XCTAssertEqual(testSettingSyncHandler.syncedValue, "remote")
    }

    func testThatDecryptionFailureDoesntAffectSettingsOrCrash() async throws {
        let received: [Syncable] = [
            .emailProtection(username: "dax", token: "secret-token")
        ]

        crypter.throwsException(exceptionString: "ddgSyncDecrypt failed: invalid ciphertext length: X")

        try await handleSyncResponse(received: received)

        let context = metadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let settingsMetadata = fetchAllSettingsMetadata(in: context)
        XCTAssertTrue(settingsMetadata.isEmpty)
        XCTAssertEqual(emailManagerStorage.mockUsername, nil)
        XCTAssertEqual(emailManagerStorage.mockToken, nil)
        crypter.throwsException(exceptionString: nil)
    }
}

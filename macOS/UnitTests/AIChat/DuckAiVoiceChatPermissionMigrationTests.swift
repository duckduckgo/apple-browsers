//
//  DuckAiVoiceChatPermissionMigrationTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AIChat
import DuckAiDataStore
import PixelKit
import PixelKitTestingUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DuckAiVoiceChatPermissionMigrationTests: XCTestCase {

    private static let testURL = URL(string: "https://duck.ai/")!
    private var testHost: String { Self.testURL.host! }

    private var permissionManager: PermissionManagerMock!
    private var storageHandler: SpyDuckAiNativeStorageHandler!
    private var pixelFiring: PixelKitMock!
    private var sut: DuckAiVoiceChatPermissionMigration!

    override func setUp() {
        super.setUp()
        permissionManager = PermissionManagerMock()
        storageHandler = SpyDuckAiNativeStorageHandler()
        pixelFiring = PixelKitMock()
        sut = DuckAiVoiceChatPermissionMigration(
            permissionManager: permissionManager,
            storageHandler: storageHandler,
            aiChatURL: Self.testURL,
            pixelFiring: pixelFiring
        )
    }

    override func tearDown() {
        sut = nil
        pixelFiring = nil
        storageHandler = nil
        permissionManager = nil
        super.tearDown()
    }

    // MARK: - .allow (no migration needed)

    func testWhenStoredDecisionIsAllow_thenNothingChanges() {
        permissionManager.savedPermissions[testHost] = [.microphone: .allow]

        sut.tryToMigrateVoiceChatPermission()

        XCTAssertTrue(permissionManager.setPermissionCalls.isEmpty)
        XCTAssertEqual(storageHandler.deleteEntryCalls.count, 0)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - .ask (no entry persisted — fresh install)

    func testWhenNothingPersisted_thenSetsToAllowAndDoesNotFirePixel() {
        // No prior entry → permission(forDomain:permissionType:) returns .ask by default,
        // but hasPermissionPersisted is false. We still pin to .allow so the user gets the
        // seamless flow, but we don't fire the migration pixel — there was nothing to
        // migrate, this is a fresh install.

        sut.tryToMigrateVoiceChatPermission()

        XCTAssertEqual(permissionManager.setPermissionCalls.count, 1)
        let call = permissionManager.setPermissionCalls[0]
        XCTAssertEqual(call.decision, .allow)
        XCTAssertEqual(call.domain, testHost)
        XCTAssertEqual(call.permissionType, .microphone)

        XCTAssertEqual(storageHandler.deleteEntryCalls.count, 0)

        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty,
                      "Pixel must not fire for fresh installs — no decision was migrated")
    }

    func testWhenStoredDecisionIsAsk_thenSetsToAllowAndFiresFromAsk() {
        permissionManager.savedPermissions[testHost] = [.microphone: .ask]

        sut.tryToMigrateVoiceChatPermission()

        XCTAssertEqual(permissionManager.setPermissionCalls.last?.decision, .allow)
        XCTAssertEqual(storageHandler.deleteEntryCalls.count, 0,
                       "Voice-mode consent should NOT be cleared when migrating from .ask")

        XCTAssertEqual(pixelFiring.actualFireCalls, [
            ExpectedFireCall(
                pixel: AIChatPixel.aiChatVoiceChatPermissionAutoGranted(from: .ask),
                frequency: .dailyAndCount
            )
        ])
    }

    // MARK: - .deny

    func testWhenStoredDecisionIsDeny_thenClearsConsentSetsToAllowAndFiresFromDeny() {
        permissionManager.savedPermissions[testHost] = [.microphone: .deny]

        sut.tryToMigrateVoiceChatPermission()

        XCTAssertEqual(permissionManager.setPermissionCalls.last?.decision, .allow)

        XCTAssertEqual(storageHandler.deleteEntryCalls, ["hasVoiceModeConsent"])

        XCTAssertEqual(pixelFiring.actualFireCalls, [
            ExpectedFireCall(
                pixel: AIChatPixel.aiChatVoiceChatPermissionAutoGranted(from: .deny),
                frequency: .dailyAndCount
            )
        ])
    }

    // MARK: - Storage handler nil

    func testWhenStoredDecisionIsDenyAndStorageHandlerIsNil_thenStillSetsToAllowAndFires() {
        sut = DuckAiVoiceChatPermissionMigration(
            permissionManager: permissionManager,
            storageHandler: nil,
            aiChatURL: Self.testURL,
            pixelFiring: pixelFiring
        )
        permissionManager.savedPermissions[testHost] = [.microphone: .deny]

        sut.tryToMigrateVoiceChatPermission()

        XCTAssertEqual(permissionManager.setPermissionCalls.last?.decision, .allow)
        XCTAssertEqual(pixelFiring.actualFireCalls, [
            ExpectedFireCall(
                pixel: AIChatPixel.aiChatVoiceChatPermissionAutoGranted(from: .deny),
                frequency: .dailyAndCount
            )
        ])
    }

    // MARK: - Scoping

    func testOnlyMicrophonePermissionIsAffected() {
        permissionManager.savedPermissions[testHost] = [
            .microphone: .ask,
            .camera: .deny,
            .geolocation: .deny
        ]

        sut.tryToMigrateVoiceChatPermission()

        // We should only see a single setPermission call, for .microphone
        XCTAssertEqual(permissionManager.setPermissionCalls.count, 1)
        XCTAssertEqual(permissionManager.setPermissionCalls[0].permissionType, .microphone)

        // Other permission types remain untouched
        XCTAssertEqual(permissionManager.permission(forDomain: testHost, permissionType: .camera), .deny)
        XCTAssertEqual(permissionManager.permission(forDomain: testHost, permissionType: .geolocation), .deny)
    }
}

// MARK: - Helpers

private final class SpyDuckAiNativeStorageHandler: DuckAiNativeStorageHandling {

    private(set) var deleteEntryCalls: [String] = []

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] { [:] }

    func deleteEntry(key: String) throws {
        deleteEntryCalls.append(key)
    }

    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}

    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getChat(chatId: String) throws -> DuckAiChatRecord? { nil }
    func getAllChats() throws -> [DuckAiChatRecord] { [] }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}

    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteFiles(chatId: String) throws {}
    func deleteAllFiles() throws {}

    func isMigrationDone() throws -> Bool { false }
    func isMigrationDone(key: String) throws -> Bool { false }
    func markMigrationDone(key: String) throws {}
}

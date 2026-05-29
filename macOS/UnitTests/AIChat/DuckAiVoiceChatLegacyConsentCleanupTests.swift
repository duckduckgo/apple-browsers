//
//  DuckAiVoiceChatLegacyConsentCleanupTests.swift
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
import BrowserServicesKit
import DuckAiDataStore
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DuckAiVoiceChatLegacyConsentCleanupTests: XCTestCase {

    private let voiceModeConsentKey = "hasVoiceModeConsent"
    private let cleanupDoneKey = "com.duckduckgo.duckAiVoiceChat.legacyConsentCleanupDone"

    private var permissionManager: PermissionManagerMock!
    private var storageHandler: SpyStorageHandler!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    private var duckAiHost: String {
        guard let host = URL.duckAi.host else {
            fatalError("URL.duckAi has no host — test setup expected duck.ai URL to be resolvable")
        }
        return host
    }

    override func setUp() {
        super.setUp()
        permissionManager = PermissionManagerMock()
        storageHandler = SpyStorageHandler()
        defaultsSuiteName = "test.legacyConsentCleanup.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        storageHandler = nil
        permissionManager = nil
        super.tearDown()
    }

    private func makeSUT() -> DuckAiVoiceChatLegacyConsentCleanup {
        DuckAiVoiceChatLegacyConsentCleanup(
            permissionManager: permissionManager,
            storageHandler: storageHandler,
            aiChatURL: .duckAi,
            userDefaults: defaults
        )
    }

    // MARK: - Positive case

    func testWhenPersistedDecisionIsDenyThenClearsFeConsentAndMarksDone() {
        permissionManager.savedPermissions[duckAiHost] = [.microphone: .deny]

        makeSUT().runIfNeeded()

        XCTAssertEqual(storageHandler.deletedKeys, [voiceModeConsentKey])
        XCTAssertTrue(defaults.bool(forKey: cleanupDoneKey))
    }

    // MARK: - No-op cases (mark done but don't touch FE storage)

    func testWhenPersistedDecisionIsAskThenDoesNotClearFeConsentButMarksDone() {
        permissionManager.savedPermissions[duckAiHost] = [.microphone: .ask]

        makeSUT().runIfNeeded()

        XCTAssertTrue(storageHandler.deletedKeys.isEmpty,
                      ".ask is a user choice we shouldn't reinterpret; FE consent stays")
        XCTAssertTrue(defaults.bool(forKey: cleanupDoneKey))
    }

    func testWhenPersistedDecisionIsAllowThenDoesNotClearFeConsentButMarksDone() {
        permissionManager.savedPermissions[duckAiHost] = [.microphone: .allow]

        makeSUT().runIfNeeded()

        XCTAssertTrue(storageHandler.deletedKeys.isEmpty)
        XCTAssertTrue(defaults.bool(forKey: cleanupDoneKey))
    }

    func testWhenNothingPersistedThenDoesNotClearFeConsentButMarksDone() {
        // Fresh install: no mic entry for duck.ai at all.
        makeSUT().runIfNeeded()

        XCTAssertTrue(storageHandler.deletedKeys.isEmpty)
        XCTAssertTrue(defaults.bool(forKey: cleanupDoneKey))
    }

    // MARK: - Idempotence

    func testWhenAlreadyMarkedDoneThenRunIfNeededIsANoOpEvenIfDenyPersisted() {
        defaults.set(true, forKey: cleanupDoneKey)
        permissionManager.savedPermissions[duckAiHost] = [.microphone: .deny]

        makeSUT().runIfNeeded()

        XCTAssertTrue(storageHandler.deletedKeys.isEmpty,
                      "Once cleanup has run, we never touch FE consent again — protects against re-prompting users who later re-granted")
    }

    func testWhenRunTwiceThenSecondCallIsANoOp() {
        permissionManager.savedPermissions[duckAiHost] = [.microphone: .deny]

        let sut = makeSUT()
        sut.runIfNeeded()
        sut.runIfNeeded()

        XCTAssertEqual(storageHandler.deletedKeys, [voiceModeConsentKey],
                       "Second run must observe the marker and skip the delete call")
    }

    // MARK: - Robustness

    func testWhenStorageHandlerIsNilThenStillMarksDoneAndDoesNotCrash() {
        permissionManager.savedPermissions[duckAiHost] = [.microphone: .deny]

        DuckAiVoiceChatLegacyConsentCleanup(
            permissionManager: permissionManager,
            storageHandler: nil,
            aiChatURL: .duckAi,
            userDefaults: defaults
        ).runIfNeeded()

        XCTAssertTrue(defaults.bool(forKey: cleanupDoneKey))
    }

    func testWhenAiChatUrlHasNoHostThenSkipsAndDoesNotMarkDone() {
        // A URL with no host means we can't identify the duck.ai mic entry. Leave the marker
        // unset so a future launch with a proper URL still gets a chance to run.
        permissionManager.savedPermissions[duckAiHost] = [.microphone: .deny]

        DuckAiVoiceChatLegacyConsentCleanup(
            permissionManager: permissionManager,
            storageHandler: storageHandler,
            aiChatURL: URL(string: "data:,empty")!,
            userDefaults: defaults
        ).runIfNeeded()

        XCTAssertTrue(storageHandler.deletedKeys.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: cleanupDoneKey))
    }
}

// MARK: - Mock

private final class SpyStorageHandler: DuckAiNativeStorageHandling {

    private(set) var deletedKeys: [String] = []

    func deleteEntry(key: String) throws { deletedKeys.append(key) }

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] { [:] }
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

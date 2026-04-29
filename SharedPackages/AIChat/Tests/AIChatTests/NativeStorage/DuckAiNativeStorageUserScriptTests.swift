//
//  DuckAiNativeStorageUserScriptTests.swift
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

import XCTest
import UserScript
import WebKit
import DuckAiDataStore
import BrowserServicesKitTestsUtils
@testable import AIChat

final class DuckAiNativeStorageUserScriptTests: XCTestCase {

    private var sut: DuckAiNativeStorageUserScript!
    private var mockHandler: MockDuckAiNativeStorageHandler!
    private var mockPixelFiring: MockDuckAiNativeStoragePixelFiring!

    override func setUp() {
        super.setUp()
        mockHandler = MockDuckAiNativeStorageHandler()
        mockPixelFiring = MockDuckAiNativeStoragePixelFiring()
        sut = DuckAiNativeStorageUserScript(
            handler: mockHandler,
            originRules: [.exact(hostname: "duck.ai")],
            pixelFiring: mockPixelFiring
        )
    }

    func testFeatureNameIsDuckAiNativeStorage() {
        XCTAssertEqual(sut.featureName, "duckAiNativeStorage")
    }

    func testWhenAllMessageNamesThenHandlerReturnsNonNil() {
        for message in DuckAiNativeStorageUserScriptMessages.allCases {
            let handler = sut.handler(forMethodNamed: message.rawValue)
            XCTAssertNotNil(handler, "Handler for \(message.rawValue) should not be nil")
        }
    }

    func testWhenUnknownMethodThenHandlerReturnsNil() {
        let handler = sut.handler(forMethodNamed: "unknownMethod")
        XCTAssertNil(handler)
    }

    // MARK: - markMigrationDone pixel firing

    func testWhenMarkMigrationDoneWithValidKeyThenFiresStartedAndDonePixels() async throws {
        let handler = try XCTUnwrap(sut.handler(forMethodNamed: "markMigrationDone"))
        _ = try await handler(["key": "chats"], WKScriptMessage.mock())
        XCTAssertTrue(mockPixelFiring.firedEvents.contains { if case .migrationStarted = $0 { return true }; return false })
        XCTAssertTrue(mockPixelFiring.firedEvents.contains { if case .migrationDone(let k) = $0, k == "chats" { return true }; return false })
    }

    func testWhenMarkMigrationDoneWithMissingKeyThenFiresStartedAndBlankKeyPixels() async throws {
        let handler = try XCTUnwrap(sut.handler(forMethodNamed: "markMigrationDone"))
        _ = try await handler([String: Any](), WKScriptMessage.mock())
        XCTAssertTrue(mockPixelFiring.firedEvents.contains { if case .migrationStarted = $0 { return true }; return false })
        XCTAssertTrue(mockPixelFiring.firedEvents.contains { if case .migrationDoneBlankKey = $0 { return true }; return false })
        XCTAssertFalse(mockPixelFiring.firedEvents.contains { if case .migrationDone = $0 { return true }; return false })
    }

    func testWhenIsMigrationDoneReturnsTrueThenFiresAlreadyDonePixel() async throws {
        mockHandler.stubbedIsMigrationDone = true
        let handler = try XCTUnwrap(sut.handler(forMethodNamed: "isMigrationDone"))
        _ = try await handler(["key": "chats"], WKScriptMessage.mock())
        XCTAssertTrue(mockPixelFiring.firedEvents.contains { if case .migrationAlreadyDone = $0 { return true }; return false })
    }

    func testWhenIsMigrationDoneReturnsFalseThenDoesNotFireAlreadyDonePixel() async throws {
        mockHandler.stubbedIsMigrationDone = false
        let handler = try XCTUnwrap(sut.handler(forMethodNamed: "isMigrationDone"))
        _ = try await handler(["key": "chats"], WKScriptMessage.mock())
        XCTAssertFalse(mockPixelFiring.firedEvents.contains { if case .migrationAlreadyDone = $0 { return true }; return false })
    }

    func testWhenInFireModeAndHandlerUnavailableThenStorageOperationsDoNotFallBackToDisk() async throws {
        sut.fireModeStorageProvider = { .unavailable }

        let putHandler = try XCTUnwrap(sut.handler(forMethodNamed: "putEntry"))
        _ = try await putHandler(["key": "setting_kae", "value": "disk"], WKScriptMessage.mock())

        XCTAssertEqual(mockHandler.putEntryCalls, 0)
    }
}

// MARK: - Test helpers

final class MockDuckAiNativeStoragePixelFiring: DuckAiNativeStoragePixelFiring {
    var firedEvents: [DuckAiNativeStorageEvent] = []

    func fire(_ event: DuckAiNativeStorageEvent) { firedEvents.append(event) }
}

// MARK: - Mock

final class MockDuckAiNativeStorageHandler: DuckAiNativeStorageHandling {
    var stubbedIsMigrationDone = false
    var stubbedGetAllEntries: [String: Any] = [:]
    var stubbedGetAllEntriesError: Error?
    var putEntryCalls = 0

    func putEntry(key: String, value: Any) throws { putEntryCalls += 1 }
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] {
        if let stubbedGetAllEntriesError { throw stubbedGetAllEntriesError }
        return stubbedGetAllEntries
    }
    func deleteEntry(key: String) throws {}
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
    func isMigrationDone() throws -> Bool { stubbedIsMigrationDone }
    func isMigrationDone(key: String) throws -> Bool { stubbedIsMigrationDone }
    func markMigrationDone(key: String) throws {}
}

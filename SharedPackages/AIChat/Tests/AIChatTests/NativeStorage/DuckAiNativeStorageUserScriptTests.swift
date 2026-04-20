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
import DuckAiDataStore
@testable import AIChat

final class DuckAiNativeStorageUserScriptTests: XCTestCase {

    var sut: DuckAiNativeStorageUserScript!

    override func setUp() {
        super.setUp()
        let mockHandler = MockDuckAiNativeStorageHandler()
        sut = DuckAiNativeStorageUserScript(
            handler: mockHandler,
            originRules: [.exact(hostname: "duck.ai")]
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
}

// MARK: - Mock

private final class MockDuckAiNativeStorageHandler: DuckAiNativeStorageHandling {
    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] { [:] }
    func deleteEntry(key: String) throws {}
    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}
    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getAllChats() throws -> [DuckAiChatRecord] { [] }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone() throws -> Bool { false }
    func isMigrationDone(key: String) throws -> Bool { false }
    func markMigrationDone(key: String) throws {}
}

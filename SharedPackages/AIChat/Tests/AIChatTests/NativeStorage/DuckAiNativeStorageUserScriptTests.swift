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

    // MARK: - Values returned to the web

    func testWhenStoredChatHasPartIndexZeroAndOneThenGetChatReturnsNumbersNotBooleans() async throws {
        mockHandler.stubbedChats = [DuckAiChatRecord(chatId: "canonical-chat", data: Data(Self.canonicalChatJSON.utf8))]

        let response = try await response(of: "getChat", params: ["chatId": "canonical-chat"])

        let chat = try XCTUnwrap(response["chat"] as? [String: Any])
        let messages = try XCTUnwrap(chat["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        let partIndexes = parts.prefix(2).map { $0["partIndex"] }
        XCTAssertEqual(partIndexes.map { $0 as? NSNumber }, [0, 1])
        XCTAssertFalse(partIndexes.contains { isBoolean($0) })
    }

    func testWhenGetChatReturnsCanonicalChatThenEveryValueKeepsItsStoredTypeAndValue() async throws {
        mockHandler.stubbedChats = [DuckAiChatRecord(chatId: "canonical-chat", data: Data(Self.canonicalChatJSON.utf8))]

        let response = try await response(of: "getChat", params: ["chatId": "canonical-chat"])

        assertSameJSON(response["chat"], try parsed(Self.canonicalChatJSON))
    }

    func testWhenGetAllChatsReturnsLegacyAndCanonicalChatsThenEveryValueKeepsItsStoredTypeAndValue() async throws {
        mockHandler.stubbedChats = [
            DuckAiChatRecord(chatId: "legacy-chat", data: Data(Self.legacyChatJSON.utf8)),
            DuckAiChatRecord(chatId: "canonical-chat", data: Data(Self.canonicalChatJSON.utf8))
        ]

        let response = try await response(of: "getAllChats")

        let chats = try XCTUnwrap(response["chats"] as? [Any])
        assertSameJSON(chats, [try parsed(Self.legacyChatJSON), try parsed(Self.canonicalChatJSON)])
    }

    func testWhenGetAllEntriesReturnsStoredValuesThenEveryValueKeepsItsStoredTypeAndValue() async throws {
        let entriesJSON = """
            {"isRecentChatsOn":true,"duckaiHasAgreedToTerms":"true","windowIndex":0,"percentage":1,"ratio":0.5,
             "negative":-1,"int64Max":9223372036854775807,"uint64Max":18446744073709551615,"missing":null,
             "nested":{"enabled":false,"index":1,"values":[0,1,true,false,2]}}
            """
        mockHandler.stubbedGetAllEntries = try parsed(entriesJSON)

        let response = try await response(of: "getAllEntries")

        assertSameJSON(response["entries"], try parsed(entriesJSON))
    }

    func testWhenGetFileReturnsStoredPayloadThenEveryValueKeepsItsStoredTypeAndValue() async throws {
        let fileJSON = #"{"data":"aGVsbG8=","mimeType":"image/jpeg","fileName":"image-1.jpeg","width":1,"height":0,"moderated":false}"#
        mockHandler.stubbedFiles = [DuckAiFileContent(uuid: "file-1", chatId: "canonical-chat", data: Data(fileJSON.utf8))]

        let response = try await response(of: "getFile", params: ["uuid": "file-1"])

        assertSameJSON(response, try parsed(fileJSON))
    }

    // MARK: - Fixtures and helpers

    private static let canonicalChatJSON = """
        {"version":"1.2","chatId":"canonical-chat","title":"Duck pictures","model":"gpt-5-mini","pinned":false,
         "lastEdit":"2026-01-01T10:00:05.000Z","reasoningMode":"fast","conversationLimitPercentage":0,
         "fileRefs":["00000000-0000-4000-8000-000000000001"],
         "messages":[
          {"id":"m1","role":"user","createdAt":"2026-01-01T10:00:00.000Z",
           "content":[{"type":"text","text":"Draw a duck"}],
           "meta":{"recovery":{"messageId":"r1","generationTimestamp":1767261600000}}},
          {"id":"m2","role":"assistant","createdAt":"2026-01-01T10:00:01.000Z",
           "content":[
            {"type":"reasoning-progress","id":"rs1","partIndex":0,"text":"Planning","complete":true},
            {"type":"reasoning-progress","id":"rs1","partIndex":1,"text":"Drawing","complete":false},
            {"type":"reasoning","id":"rs1","encryptedText":"opaque","redacted":false},
            {"type":"ui-component","id":"ui1","name":"generate-image","toolCallId":"call_1",
             "data":{"status":"success","width":1024,"height":1024,"generationDurationMs":1},
             "ref":{"id":"00000000-0000-4000-8000-000000000001","handlerId":"native","handlerVersion":1}},
            {"type":"tool-call","toolCallId":"call_1","toolName":"GenerateImage","toolArguments":"{}"},
            {"type":"tool-result","toolCallId":"call_1","result":"ok","data":null},
            {"type":"text","text":"Here is your duck."}],
           "meta":{"status":"active","model":"gpt-5-mini","reasoningDurationMs":0,"origin":"text"}}]}
        """

    private static let legacyChatJSON = """
        {"chatId":"legacy-chat","title":"Duck facts","model":"gpt-5-mini","pinned":true,"lastEdit":"2026-09-01T10:00:01.000Z",
         "messages":[
          {"role":"user","content":"Tell me about ducks","createdAt":"2026-09-01T10:00:00.000Z"},
          {"role":"assistant","content":"","createdAt":"2026-09-01T10:00:01.000Z","status":"active","reasoningDurationMs":1,
           "parts":[
            {"type":"reasoning","state":"progress","id":"rs1","partIndex":0,"text":"Thinking","complete":true},
            {"type":"tool-invocation","state":"call","toolCallId":"call_1","toolName":"WebSearch","toolArguments":"{}"},
            {"type":"text","text":"Ducks are waterfowl."}]}]}
        """

    private func response(of method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        let handler = try XCTUnwrap(sut.handler(forMethodNamed: method))
        let result = try await handler(params, WKScriptMessage.mock())
        let encodable = try XCTUnwrap(result)
        let data = try JSONEncoder().encode(encodable)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func parsed(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func isBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// `NSNumber` equality treats `false` and `0` as equal, so booleans are compared separately.
    private func assertSameJSON(_ returned: Any?, _ stored: Any?, path: String = "$", file: StaticString = #filePath, line: UInt = #line) {
        switch (returned, stored) {
        case let (returned as [String: Any], stored as [String: Any]):
            XCTAssertEqual(Set(returned.keys), Set(stored.keys), "keys at \(path)", file: file, line: line)
            for (key, value) in stored {
                assertSameJSON(returned[key], value, path: "\(path).\(key)", file: file, line: line)
            }
        case let (returned as [Any], stored as [Any]):
            XCTAssertEqual(returned.count, stored.count, "count at \(path)", file: file, line: line)
            for (index, (returnedElement, storedElement)) in zip(returned, stored).enumerated() {
                assertSameJSON(returnedElement, storedElement, path: "\(path)[\(index)]", file: file, line: line)
            }
        case let (returned as NSNumber, stored as NSNumber):
            XCTAssertEqual(isBoolean(returned), isBoolean(stored), "boolean vs number at \(path)", file: file, line: line)
            XCTAssertEqual(returned, stored, "value at \(path)", file: file, line: line)
        case let (returned as String, stored as String):
            XCTAssertEqual(returned, stored, "value at \(path)", file: file, line: line)
        case (is NSNull, is NSNull):
            break
        default:
            XCTFail("\(path): returned \(String(describing: returned)), stored \(String(describing: stored))", file: file, line: line)
        }
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
    var stubbedChats: [DuckAiChatRecord] = []
    var stubbedFiles: [DuckAiFileContent] = []
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
    func getChat(chatId: String) throws -> DuckAiChatRecord? { stubbedChats.first { $0.chatId == chatId } }
    func getAllChats() throws -> [DuckAiChatRecord] { stubbedChats }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { stubbedFiles.first { $0.uuid == uuid } }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteFiles(chatId: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone() throws -> Bool { stubbedIsMigrationDone }
    func isMigrationDone(key: String) throws -> Bool { stubbedIsMigrationDone }
    func markMigrationDone(key: String) throws {}
}

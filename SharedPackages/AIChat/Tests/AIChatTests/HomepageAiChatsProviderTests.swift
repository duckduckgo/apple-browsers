//
//  HomepageAiChatsProviderTests.swift
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

import DuckAiDataStore
import XCTest
@testable import AIChat

@MainActor
final class HomepageAiChatsProviderTests: XCTestCase {

    private var storageHandler: HomepageChatsStorageHandler!
    private var featureFlags: MockAIChatFeatureFlagProvider!

    override func setUp() {
        super.setUp()
        storageHandler = HomepageChatsStorageHandler()
        storageHandler.isMigrationDoneResult = true
        featureFlags = MockAIChatFeatureFlagProvider()
        featureFlags.isHomepageChatSuggestionsEnabledResult = true
        featureFlags.isNativeDataAccessEnabledResult = true
    }

    override func tearDown() {
        storageHandler = nil
        featureFlags = nil
        super.tearDown()
    }

    private func makeSUT() -> HomepageAiChatsProvider {
        HomepageAiChatsProvider(storageHandler: storageHandler, featureFlagProvider: featureFlags)
    }

    // MARK: - Support gate

    func testWhenFeatureOnAndNativeStorageReadyThenSupported() {
        XCTAssertTrue(makeSUT().isSupported)
    }

    func testWhenHomepageFlagOffThenNotSupportedAndNoChats() async {
        featureFlags.isHomepageChatSuggestionsEnabledResult = false
        storageHandler.chatsToReturn = [makeChatRecord(chatId: "a", title: "A", lastEdit: Date(), pinned: false)]
        let sut = makeSUT()

        XCTAssertFalse(sut.isSupported)
        let response = await sut.chats(for: HomepageAiChatsRequest())
        XCTAssertEqual(response, .empty)
        XCTAssertEqual(storageHandler.getAllChatsCalls, 0)
    }

    func testWhenNativeDataAccessOffThenNotSupported() {
        featureFlags.isNativeDataAccessEnabledResult = false
        XCTAssertFalse(makeSUT().isSupported)
    }

    func testWhenMigrationNotDoneThenNotSupported() {
        storageHandler.isMigrationDoneResult = false
        XCTAssertFalse(makeSUT().isSupported)
    }

    func testWhenStorageSetupFailedThenNotSupported() {
        storageHandler.setupSucceededResult = false
        XCTAssertFalse(makeSUT().isSupported)
    }

    func testWhenNoStorageHandlerThenNotSupported() {
        let sut = HomepageAiChatsProvider(storageHandler: nil, featureFlagProvider: featureFlags)
        XCTAssertFalse(sut.isSupported)
    }

    // MARK: - Chats

    func testChatsArePinnedFirstThenRecentWithoutMessageContent() async throws {
        let now = Date()
        storageHandler.chatsToReturn = [
            makeChatRecord(chatId: "recent-old", title: "Older", lastEdit: now.addingTimeInterval(-7200), pinned: false),
            makeChatRecord(chatId: "pinned", title: "Pinned", lastEdit: now.addingTimeInterval(-30 * 24 * 3600), pinned: true),
            makeChatRecord(chatId: "recent-new", title: "Newer", lastEdit: now.addingTimeInterval(-60), pinned: false, model: "voice-mode"),
        ]

        let response = await makeSUT().chats(for: HomepageAiChatsRequest())

        XCTAssertEqual(response.chats.map(\.chatId), ["pinned", "recent-new", "recent-old"])
        XCTAssertEqual(response.chats.map(\.pinned), [true, false, false])
        XCTAssertEqual(response.chats[1].model, "voice-mode")
        XCTAssertNotNil(response.chats[1].lastEdit)

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(response), encoding: .utf8))
        XCTAssertFalse(json.contains("Hello"), "The homepage must not receive message content")
        XCTAssertFalse(json.contains("firstUserMessageContent"))
    }

    func testMaxChatsLimitsRecentChatsAndIsClamped() async {
        let now = Date()
        storageHandler.chatsToReturn = (0..<30).map {
            makeChatRecord(chatId: "c\($0)", title: "Chat \($0)", lastEdit: now.addingTimeInterval(-Double($0) * 60), pinned: false)
        }
        let sut = makeSUT()

        let two = await sut.chats(for: HomepageAiChatsRequest(maxChats: 2))
        XCTAssertEqual(two.chats.map(\.chatId), ["c0", "c1"])

        let tooMany = await sut.chats(for: HomepageAiChatsRequest(maxChats: 1000))
        XCTAssertEqual(tooMany.chats.count, HomepageAiChatsProvider.maxChatsLimit)

        let defaulted = await sut.chats(for: HomepageAiChatsRequest())
        XCTAssertEqual(defaulted.chats.count, HomepageAiChatsProvider.defaultMaxChats)
    }

    func testQueryFiltersByTitle() async {
        storageHandler.chatsToReturn = [
            makeChatRecord(chatId: "a", title: "Sourdough recipe", lastEdit: Date(), pinned: false),
            makeChatRecord(chatId: "b", title: "Trip ideas", lastEdit: Date(), pinned: false),
        ]

        let response = await makeSUT().chats(for: HomepageAiChatsRequest(query: "  recipe "))

        XCTAssertEqual(response.chats.map(\.chatId), ["a"])
    }

    func testWhenStorageThrowsThenNoChats() async {
        storageHandler.errorToThrow = NSError(domain: "test", code: 1)

        let response = await makeSUT().chats(for: HomepageAiChatsRequest())

        XCTAssertEqual(response, .empty)
    }

    // MARK: - Origin

    func testOnlyNonDuckAiHostsAreHomepageMessages() {
        XCTAssertTrue(HomepageAiChatsProvider.isHomepageMessage(host: "duckduckgo.com"))
        XCTAssertTrue(HomepageAiChatsProvider.isHomepageMessage(host: "someone.duckduckgo.com"))
        XCTAssertFalse(HomepageAiChatsProvider.isHomepageMessage(host: "duck.ai"))
        XCTAssertFalse(HomepageAiChatsProvider.isHomepageMessage(host: "Duck.AI"))
        XCTAssertFalse(HomepageAiChatsProvider.isHomepageMessage(host: "staging.duck.ai"))
    }

    // MARK: - Wire format

    func testRequestDecodesFromHomepageParams() throws {
        let request = try JSONDecoder().decode(HomepageAiChatsRequest.self, from: Data(#"{"maxChats":5}"#.utf8))
        XCTAssertEqual(request, HomepageAiChatsRequest(query: nil, maxChats: 5))
    }

    func testMessageNameMatchesTheHomepageContract() {
        XCTAssertEqual(AIChatUserScriptMessages.getAIChats.rawValue, "getAIChats")
    }

    // MARK: - Helpers

    private func makeChatRecord(chatId: String, title: String, lastEdit: Date, pinned: Bool, model: String = "gpt-4o-mini") -> DuckAiChatRecord {
        let chatJSON: [String: Any] = [
            "chatId": chatId,
            "title": title,
            "model": model,
            "lastEdit": AIChatSuggestion.formatISO8601Date(lastEdit) ?? "",
            "pinned": pinned,
            "messages": [
                ["role": "user", "content": "Hello"]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: chatJSON) else {
            XCTFail("Failed to serialize chat JSON for chatId: \(chatId)")
            return DuckAiChatRecord(chatId: chatId, data: Data())
        }
        return DuckAiChatRecord(chatId: chatId, data: data)
    }
}

// MARK: - Mock

private final class HomepageChatsStorageHandler: DuckAiNativeStorageHandling {
    var chatsToReturn: [DuckAiChatRecord] = []
    var errorToThrow: Error?
    var isMigrationDoneResult = false
    var setupSucceededResult: Bool? = true
    private(set) var getAllChatsCalls = 0

    var setupSucceeded: Bool? { setupSucceededResult }

    func getAllChats() throws -> [DuckAiChatRecord] {
        getAllChatsCalls += 1
        if let error = errorToThrow { throw error }
        return chatsToReturn
    }

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] { [:] }
    func deleteEntry(key: String) throws {}
    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}
    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getChat(chatId: String) throws -> DuckAiChatRecord? { nil }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteFiles(chatId: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone() throws -> Bool { isMigrationDoneResult }
    func isMigrationDone(key: String) throws -> Bool { isMigrationDoneResult }
    func markMigrationDone(key: String) throws {}
}

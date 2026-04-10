//
//  LocalSuggestionsReaderTests.swift
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
final class LocalSuggestionsReaderTests: XCTestCase {

    private var mockHandler: CapturingStorageHandler!
    private var sut: LocalSuggestionsReader!

    override func setUp() {
        super.setUp()
        mockHandler = CapturingStorageHandler()
        sut = LocalSuggestionsReader(storageHandler: mockHandler)
    }

    override func tearDown() {
        sut = nil
        mockHandler = nil
        super.tearDown()
    }

    // MARK: - Pinned Chat Date Filtering

    func testWhenNoQueryAndPinnedChatIsOlderThanOneWeekThenPinnedChatIsIncluded() async {
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        mockHandler.chatsToReturn = [
            makeChatRecord(chatId: "pinned-old", title: "Old Pinned", lastEdit: twoWeeksAgo, pinned: true)
        ]

        let result = await sut.fetchSuggestions(query: nil, maxChats: 10)

        guard case .success(let suggestions) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(suggestions.pinned.count, 1)
        XCTAssertEqual(suggestions.pinned.first?.chatId, "pinned-old")
    }

    func testWhenNoQueryAndUnpinnedChatIsOlderThanOneWeekThenUnpinnedChatIsExcluded() async {
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        mockHandler.chatsToReturn = [
            makeChatRecord(chatId: "recent-old", title: "Old Recent", lastEdit: twoWeeksAgo, pinned: false)
        ]

        let result = await sut.fetchSuggestions(query: nil, maxChats: 10)

        guard case .success(let suggestions) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertTrue(suggestions.recent.isEmpty)
    }

    func testWhenNoQueryAndUnpinnedChatIsWithinOneWeekThenUnpinnedChatIsIncluded() async {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        mockHandler.chatsToReturn = [
            makeChatRecord(chatId: "recent-new", title: "New Recent", lastEdit: oneHourAgo, pinned: false)
        ]

        let result = await sut.fetchSuggestions(query: nil, maxChats: 10)

        guard case .success(let suggestions) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(suggestions.recent.count, 1)
        XCTAssertEqual(suggestions.recent.first?.chatId, "recent-new")
    }

    func testWhenNoQueryThenMixOfPinnedAndRecentAreSplitCorrectly() async {
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        let oneHourAgo = Date().addingTimeInterval(-3600)
        mockHandler.chatsToReturn = [
            makeChatRecord(chatId: "pinned-old", title: "Old Pinned", lastEdit: twoWeeksAgo, pinned: true),
            makeChatRecord(chatId: "pinned-new", title: "New Pinned", lastEdit: oneHourAgo, pinned: true),
            makeChatRecord(chatId: "recent-old", title: "Old Recent", lastEdit: twoWeeksAgo, pinned: false),
            makeChatRecord(chatId: "recent-new", title: "New Recent", lastEdit: oneHourAgo, pinned: false),
        ]

        let result = await sut.fetchSuggestions(query: nil, maxChats: 10)

        guard case .success(let suggestions) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(suggestions.pinned.count, 2, "Both pinned chats should be included regardless of age")
        XCTAssertEqual(suggestions.recent.count, 1, "Only the recent unpinned chat within one week should be included")
        XCTAssertEqual(suggestions.recent.first?.chatId, "recent-new")
    }

    // MARK: - Query Filtering

    func testWhenQueryMatchesTitleThenPinnedAndRecentAreReturnedRegardlessOfAge() async {
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        mockHandler.chatsToReturn = [
            makeChatRecord(chatId: "pinned-old", title: "Swift tips", lastEdit: twoWeeksAgo, pinned: true),
            makeChatRecord(chatId: "recent-old", title: "Swift concurrency", lastEdit: twoWeeksAgo, pinned: false),
        ]

        let result = await sut.fetchSuggestions(query: "Swift", maxChats: 10)

        guard case .success(let suggestions) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(suggestions.pinned.count, 1)
        XCTAssertEqual(suggestions.recent.count, 1)
    }

    func testWhenQueryDoesNotMatchThenNoResultsReturned() async {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        mockHandler.chatsToReturn = [
            makeChatRecord(chatId: "chat-1", title: "Swift tips", lastEdit: oneHourAgo, pinned: false)
        ]

        let result = await sut.fetchSuggestions(query: "Python", maxChats: 10)

        guard case .success(let suggestions) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertTrue(suggestions.pinned.isEmpty)
        XCTAssertTrue(suggestions.recent.isEmpty)
    }

    // MARK: - maxChats

    func testWhenRecentChatsExceedMaxChatsThenResultIsTruncated() async {
        let now = Date()
        mockHandler.chatsToReturn = (1...5).map { i in
            makeChatRecord(chatId: "chat-\(i)", title: "Chat \(i)", lastEdit: now.addingTimeInterval(Double(-i * 60)), pinned: false)
        }

        let result = await sut.fetchSuggestions(query: nil, maxChats: 3)

        guard case .success(let suggestions) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(suggestions.recent.count, 3)
    }

    func testWhenPinnedChatsExceedMaxChatsThenPinnedAreNotTruncated() async {
        let now = Date()
        mockHandler.chatsToReturn = (1...5).map { i in
            makeChatRecord(chatId: "pinned-\(i)", title: "Pinned \(i)", lastEdit: now.addingTimeInterval(Double(-i * 60)), pinned: true)
        }

        let result = await sut.fetchSuggestions(query: nil, maxChats: 2)

        guard case .success(let suggestions) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(suggestions.pinned.count, 5, "maxChats should not limit pinned chats")
        XCTAssertTrue(suggestions.recent.isEmpty)
    }

    // MARK: - Sorting

    func testWhenNoQueryThenRecentChatsAreSortedByMostRecentFirst() async {
        let now = Date()
        mockHandler.chatsToReturn = [
            makeChatRecord(chatId: "oldest", title: "Oldest", lastEdit: now.addingTimeInterval(-3600), pinned: false),
            makeChatRecord(chatId: "newest", title: "Newest", lastEdit: now, pinned: false),
            makeChatRecord(chatId: "middle", title: "Middle", lastEdit: now.addingTimeInterval(-1800), pinned: false),
        ]

        let result = await sut.fetchSuggestions(query: nil, maxChats: 10)

        guard case .success(let suggestions) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(suggestions.recent.map(\.chatId), ["newest", "middle", "oldest"])
    }

    // MARK: - Error Handling

    func testWhenStorageHandlerThrowsThenFailureIsReturned() async {
        mockHandler.errorToThrow = NSError(domain: "test", code: 1)

        let result = await sut.fetchSuggestions(query: nil, maxChats: 10)

        guard case .failure = result else {
            return XCTFail("Expected failure")
        }
    }

    // MARK: - Helpers

    private func makeChatRecord(chatId: String, title: String, lastEdit: Date, pinned: Bool) -> DuckAiChatRecord {
        let iso8601 = AIChatSuggestion.formatISO8601Date(lastEdit) ?? ""
        let chatJSON: [String: Any] = [
            "chatId": chatId,
            "title": title,
            "model": "gpt-4o-mini",
            "lastEdit": iso8601,
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

private final class CapturingStorageHandler: DuckAiNativeStorageHandling {
    var chatsToReturn: [DuckAiChatRecord] = []
    var errorToThrow: Error?

    func getAllChats() throws -> [DuckAiChatRecord] {
        if let error = errorToThrow { throw error }
        return chatsToReturn
    }

    func putSetting(key: String, value: Any) throws {}
    func getSetting(key: String) throws -> Any? { nil }
    func getAllSettings() throws -> [String: Any] { [:] }
    func deleteSetting(key: String) throws {}
    func deleteAllSettings() throws {}
    func replaceAllSettings(_ settings: [String: Any]) throws {}
    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone() throws -> Bool { false }
    func markMigrationDone() throws {}
}

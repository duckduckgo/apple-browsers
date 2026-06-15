//
//  AIChatMenuTests.swift
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
import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AIChatMenuTests: XCTestCase {

    private var suggestionsReader: MockAIChatSuggestionsReader!
    private var actions: AIChatMenu.Actions!

    // Recorded action calls
    private var openNewChatCalled = false
    private var openNewVoiceChatCalled = false
    private var openNewImageChatCalled = false
    private var openedChat: AIChatSuggestion?
    private var deleteAllChatsCalled = false

    override func setUp() {
        super.setUp()
        suggestionsReader = MockAIChatSuggestionsReader()
        actions = AIChatMenu.Actions(
            openNewChat: { [weak self] in self?.openNewChatCalled = true },
            openNewVoiceChat: { [weak self] in self?.openNewVoiceChatCalled = true },
            openNewImageChat: { [weak self] in self?.openNewImageChatCalled = true },
            openChat: { [weak self] suggestion in self?.openedChat = suggestion },
            deleteAllChats: { [weak self] in self?.deleteAllChatsCalled = true }
        )
    }

    override func tearDown() {
        suggestionsReader = nil
        actions = nil
        super.tearDown()
    }

    // MARK: - Menu structure

    func testMenuTitleIsDuckAI() {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        XCTAssertEqual(menu.title, "Duck.ai")
    }

    func testStaticItemsArePresent() {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains(UserText.aiChatMenuOpenDuckAI))
        XCTAssertTrue(titles.contains(UserText.aiChatMenuNewChat))
        XCTAssertTrue(titles.contains(UserText.aiChatMenuNewVoiceChat))
        XCTAssertTrue(titles.contains(UserText.aiChatMenuNewImageChat))
        XCTAssertTrue(titles.contains(UserText.aiChatMenuRecentChats))
        XCTAssertTrue(titles.contains(UserText.aiChatMenuDeleteAllChats))
    }

    func testOpenDuckAIItemHasOptionCommandNShortcut() {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        let item = menu.items.first { $0.title == UserText.aiChatMenuOpenDuckAI }
        XCTAssertEqual(item?.keyEquivalent, "n")
        XCTAssertEqual(item?.keyEquivalentModifierMask, [.option, .command])
    }

    func testMoreOptionsOpenDuckAIItemHasNoShortcut() {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions, origin: .moreOptionsMenu)
        let item = menu.items.first { $0.title == UserText.aiChatMenuOpenDuckAI }
        XCTAssertEqual(item?.keyEquivalent, "")
    }

    // MARK: - Dynamic chat items

    func testUpdateInsertsChatsAfterRecentChatsLabel() async {
        let chat1 = makeChat(chatId: "1", title: "First", timestamp: Date(timeIntervalSince1970: 200))
        let chat2 = makeChat(chatId: "2", title: "Second", timestamp: Date(timeIntervalSince1970: 100))
        suggestionsReader.recentChats = [chat1, chat2]

        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        let labelIndex = menu.items.firstIndex { $0.title == UserText.aiChatMenuRecentChats }!
        XCTAssertEqual(menu.items[labelIndex + 1].title, "First")
        XCTAssertEqual(menu.items[labelIndex + 2].title, "Second")
    }

    func testUpdateClearsPreviousChatItemsBeforeInserting() async {
        suggestionsReader.recentChats = [makeChat(chatId: "1", title: "Old")]
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)

        suggestionsReader.fetchExpectation = XCTestExpectation(description: "first fetch")
        menu.update()
        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        suggestionsReader.recentChats = [makeChat(chatId: "2", title: "New")]
        suggestionsReader.fetchExpectation = XCTestExpectation(description: "second fetch")
        menu.update()
        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        let chatTitles = menu.items.map(\.title).filter { $0 == "Old" || $0 == "New" }
        XCTAssertEqual(chatTitles, ["New"])
    }

    func testUpdateShowsAllChats() async {
        suggestionsReader.recentChats = (1...20).map { makeChat(chatId: "\($0)", title: "Chat \($0)") }
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        let labelIndex = menu.items.firstIndex { $0.title == UserText.aiChatMenuRecentChats }!
        let nextSeparatorIndex = menu.items[(labelIndex + 1)...].firstIndex { $0.isSeparatorItem }!
        XCTAssertEqual(nextSeparatorIndex - labelIndex - 1, 20)
    }

    func testUpdateSortsChatsByTimestampDescending() async {
        let older = makeChat(chatId: "1", title: "Older", timestamp: Date(timeIntervalSince1970: 100))
        let newer = makeChat(chatId: "2", title: "Newer", timestamp: Date(timeIntervalSince1970: 200))
        suggestionsReader.recentChats = [older, newer]

        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        let labelIndex = menu.items.firstIndex { $0.title == UserText.aiChatMenuRecentChats }!
        XCTAssertEqual(menu.items[labelIndex + 1].title, "Newer")
        XCTAssertEqual(menu.items[labelIndex + 2].title, "Older")
    }

    func testUpdatePassesIntMaxToFetchSuggestions() async {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        XCTAssertEqual(suggestionsReader.receivedMaxChats, .max)
    }

    func testUpdateWithMaxChatItems_fetchesMaxPlusOne() async {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions, maxChatItems: 8)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        XCTAssertEqual(suggestionsReader.receivedMaxChats, 9)
    }

    // MARK: - View All Chats

    func testViewAllChatsNotShown_whenChatsDoNotExceedLimit() async {
        suggestionsReader.recentChats = (1...8).map { makeChat(chatId: "\($0)", title: "Chat \($0)") }
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions, maxChatItems: 8)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        XCTAssertFalse(menu.items.contains { $0.title == UserText.aiChatMenuViewAllChats })
    }

    func testViewAllChatsShown_whenChatsExceedLimit() async {
        suggestionsReader.recentChats = (1...9).map { makeChat(chatId: "\($0)", title: "Chat \($0)") }
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions, maxChatItems: 8)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        XCTAssertTrue(menu.items.contains { $0.title == UserText.aiChatMenuViewAllChats })
    }

    func testViewAllChatsNotShown_whenNoMaxChatItems() async {
        suggestionsReader.recentChats = (1...20).map { makeChat(chatId: "\($0)", title: "Chat \($0)") }
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        XCTAssertFalse(menu.items.contains { $0.title == UserText.aiChatMenuViewAllChats })
    }

    func testViewAllChats_appearsAfterChatsAndBeforeDeleteAll() async {
        suggestionsReader.recentChats = (1...9).map { makeChat(chatId: "\($0)", title: "Chat \($0)") }
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions, maxChatItems: 8)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        let viewAllIndex = menu.items.firstIndex { $0.title == UserText.aiChatMenuViewAllChats }!
        let deleteAllIndex = menu.items.firstIndex { $0.title == UserText.aiChatMenuDeleteAllChats }!
        XCTAssertLessThan(viewAllIndex, deleteAllIndex)
        XCTAssertTrue(menu.items[viewAllIndex + 1].isSeparatorItem)
        XCTAssertEqual(menu.items[viewAllIndex + 2].title, UserText.aiChatMenuDeleteAllChats)
    }

    func testViewAllChatsOnlyShowsMaxChatItems() async {
        suggestionsReader.recentChats = (1...9).map { makeChat(chatId: "\($0)", title: "Chat \($0)") }
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions, maxChatItems: 8)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        let labelIndex = menu.items.firstIndex { $0.title == UserText.aiChatMenuRecentChats }!
        let viewAllIndex = menu.items.firstIndex { $0.title == UserText.aiChatMenuViewAllChats }!
        // separator before "View All Chats..." is at viewAllIndex - 1
        let chatCount = viewAllIndex - 1 - labelIndex - 1
        XCTAssertEqual(chatCount, 8)
    }

    func testViewAllChatsTapped_callsOpenNewChat() async {
        suggestionsReader.recentChats = (1...9).map { makeChat(chatId: "\($0)", title: "Chat \($0)") }
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions, maxChatItems: 8)
        menu.update()

        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        let item = menu.items.first { $0.title == UserText.aiChatMenuViewAllChats }!
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertTrue(openNewChatCalled)
    }

    // MARK: - Action handlers

    func testOpenDuckAITappedCallsAction() {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        let item = menu.items.first { $0.title == UserText.aiChatMenuOpenDuckAI }!
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertTrue(openNewChatCalled)
    }

    func testNewChatTappedCallsAction() {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        let item = menu.items.first { $0.title == UserText.aiChatMenuNewChat }!
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertTrue(openNewChatCalled)
    }

    func testNewVoiceChatTappedCallsAction() {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        let item = menu.items.first { $0.title == UserText.aiChatMenuNewVoiceChat }!
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertTrue(openNewVoiceChatCalled)
    }

    func testNewImageChatTappedCallsAction() {
        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        let item = menu.items.first { $0.title == UserText.aiChatMenuNewImageChat }!
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertTrue(openNewImageChatCalled)
    }

    func testChatItemTappedCallsOpenChatWithCorrectSuggestion() async {
        let chat = makeChat(chatId: "abc", title: "My Chat")
        suggestionsReader.recentChats = [chat]

        let menu = AIChatMenu(suggestionsReader: suggestionsReader, actions: actions)
        menu.update()
        await fulfillment(of: [suggestionsReader.fetchExpectation], timeout: 1)

        let item = menu.items.first { $0.title == "My Chat" }!
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertEqual(openedChat?.chatId, "abc")
    }

    // MARK: - Delete all chats sync handoff

    func testDeleteAllChats_recordsLocalClearForSyncOnSuccess() async {
        let historyCleaner = StubAIChatHistoryCleaner(result: .success(()))
        let syncCleaner = StubAIChatSyncCleaning()
        let defaultActions = AIChatMenu.Actions.makeDefault(
            remoteSettings: AIChatRemoteSettings(),
            tabOpener: MockAIChatTabOpener(),
            historyCleaner: historyCleaner,
            windowControllersManager: WindowControllersManagerMock(),
            aiChatSyncCleaner: { syncCleaner }
        )

        await defaultActions.deleteAllChats()

        XCTAssertEqual(syncCleaner.recordLocalClearDates.count, 1)
        XCTAssertNotNil(syncCleaner.recordLocalClearDates.first ?? nil)
    }

    func testDeleteAllChats_doesNotRecordLocalClearOnFailure() async {
        let historyCleaner = StubAIChatHistoryCleaner(result: .failure(NSError(domain: "test", code: 0)))
        let syncCleaner = StubAIChatSyncCleaning()
        let defaultActions = AIChatMenu.Actions.makeDefault(
            remoteSettings: AIChatRemoteSettings(),
            tabOpener: MockAIChatTabOpener(),
            historyCleaner: historyCleaner,
            windowControllersManager: WindowControllersManagerMock(),
            aiChatSyncCleaner: { syncCleaner }
        )

        await defaultActions.deleteAllChats()

        XCTAssertTrue(syncCleaner.recordLocalClearDates.isEmpty)
    }

    func testDeleteAllChats_succeedsWhenSyncCleanerIsNil() async {
        let historyCleaner = StubAIChatHistoryCleaner(result: .success(()))
        let defaultActions = AIChatMenu.Actions.makeDefault(
            remoteSettings: AIChatRemoteSettings(),
            tabOpener: MockAIChatTabOpener(),
            historyCleaner: historyCleaner,
            windowControllersManager: WindowControllersManagerMock(),
            aiChatSyncCleaner: { nil }
        )

        await defaultActions.deleteAllChats()

        XCTAssertTrue(historyCleaner.cleanAIChatHistoryCalled)
    }

    func testDeleteAllChats_resolvesSyncCleanerLazilyAtCallTime() async {
        let historyCleaner = StubAIChatHistoryCleaner(result: .success(()))
        var syncCleaner: StubAIChatSyncCleaning?
        let defaultActions = AIChatMenu.Actions.makeDefault(
            remoteSettings: AIChatRemoteSettings(),
            tabOpener: MockAIChatTabOpener(),
            historyCleaner: historyCleaner,
            windowControllersManager: WindowControllersManagerMock(),
            aiChatSyncCleaner: { syncCleaner }
        )

        // Sync cleaner becomes available after the actions are constructed,
        // mirroring AppDelegate setting `aiChatSyncCleaner` after MainMenu init.
        syncCleaner = StubAIChatSyncCleaning()

        await defaultActions.deleteAllChats()

        XCTAssertEqual(syncCleaner?.recordLocalClearDates.count, 1)
    }

    // MARK: - Private helpers

    private func makeChat(chatId: String, title: String, timestamp: Date = .distantPast) -> AIChatSuggestion {
        AIChatSuggestion(id: chatId, title: title, isPinned: false, chatId: chatId, timestamp: timestamp)
    }
}

// MARK: - Mocks

private final class StubAIChatHistoryCleaner: AIChatHistoryCleaning {
    private let result: Result<Void, Error>
    private(set) var cleanAIChatHistoryCalled = false

    @Published
    var shouldDisplayCleanAIChatHistoryOption: Bool = false

    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> {
        $shouldDisplayCleanAIChatHistoryOption.eraseToAnyPublisher()
    }

    init(result: Result<Void, Error>) {
        self.result = result
    }

    @MainActor
    func cleanAIChatHistory() async -> Result<Void, Error> {
        cleanAIChatHistoryCalled = true
        return result
    }
}

private final class StubAIChatSyncCleaning: AIChatSyncCleaning {
    private(set) var recordLocalClearDates: [Date?] = []

    func recordAutoClearBackgroundTimestamp(date: Date?) async {}

    func recordLocalClear(date: Date?) async {
        recordLocalClearDates.append(date)
    }

    func recordLocalClearFromAutoClearBackgroundTimestampIfPresent() async {}

    func recordChatDeletion(chatID: String) async {}

    func deleteIfNeeded() async {}

    func scheduleSync() {}
}

private final class MockAIChatSuggestionsReader: AIChatSuggestionsReading {
    var maxHistoryCount: Int = 10
    var pinnedChats: [AIChatSuggestion] = []
    var recentChats: [AIChatSuggestion] = []
    var receivedQuery: String?
    var receivedMaxChats: Int?
    var fetchExpectation = XCTestExpectation(description: "fetchSuggestions called")

    func fetchSuggestions(query: String?, maxChats: Int) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
        receivedQuery = query
        receivedMaxChats = maxChats
        fetchExpectation.fulfill()
        return (pinned: pinnedChats, recent: recentChats)
    }

    func tearDown() {}
}

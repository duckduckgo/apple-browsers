//
//  NewTabPageOmnibarAiChatsProviderTests.swift
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
import AIChat
import Combine
import PrivacyConfig
import FeatureFlags
@testable import DuckDuckGo_Privacy_Browser
@testable import NewTabPage

@MainActor
final class NewTabPageOmnibarAiChatsProviderTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var suggestionsReader: MockAIChatSuggestionsReader!
    private var configProvider: MockAiChatsConfigProvider!
    private var provider: NewTabPageOmnibarAiChatsProvider!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        suggestionsReader = MockAIChatSuggestionsReader()
        configProvider = MockAiChatsConfigProvider()
        provider = NewTabPageOmnibarAiChatsProvider(
            featureFlagger: featureFlagger,
            configProvider: configProvider,
            suggestionsReader: suggestionsReader
        )
    }

    override func tearDown() {
        provider = nil
        configProvider = nil
        suggestionsReader = nil
        featureFlagger = nil
        super.tearDown()
    }

    // MARK: - Feature flag

    @MainActor
    func testWhenFeatureFlagOff_thenReturnsEmpty() async {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": false]

        let result = await provider.aiChats(query: nil)

        XCTAssertTrue(result.chats.isEmpty)
    }

    @MainActor
    func testWhenFeatureFlagOn_thenReturnChats() async {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true]
        suggestionsReader.pinnedChats = [.make(chatId: "1", title: "Pinned")]
        suggestionsReader.recentChats = [.make(chatId: "2", title: "Recent")]

        let result = await provider.aiChats(query: nil)

        XCTAssertFalse(result.chats.isEmpty)
    }

    // MARK: - Query normalisation

    @MainActor
    func testWhenQueryIsWhitespaceOnly_thenPassesNilToReader() async {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true]

        _ = await provider.aiChats(query: "   ")

        XCTAssertNil(suggestionsReader.receivedQuery)
    }

    @MainActor
    func testWhenQueryIsNil_thenPassesNilToReader() async {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true]

        _ = await provider.aiChats(query: nil)

        XCTAssertNil(suggestionsReader.receivedQuery)
    }

    @MainActor
    func testWhenQueryHasContent_thenPassesTrimmedQueryToReader() async {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true]

        _ = await provider.aiChats(query: "  swift  ")

        XCTAssertEqual(suggestionsReader.receivedQuery, "swift")
    }

    // MARK: - Ordering

    @MainActor
    func testPinnedChatsAppearBeforeRecentChats() async {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true]
        suggestionsReader.pinnedChats = [.make(chatId: "pinned", title: "Pinned", isPinned: true)]
        suggestionsReader.recentChats = [.make(chatId: "recent", title: "Recent", isPinned: false)]

        let result = await provider.aiChats(query: nil)

        XCTAssertEqual(result.chats.first?.chatId, "pinned")
        XCTAssertEqual(result.chats.last?.chatId, "recent")
    }

    @MainActor
    func testRecentChatsAreSortedByTimestampDescending() async {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true]
        let older = AIChatSuggestion.make(chatId: "older", title: "Older", timestamp: Date().addingTimeInterval(-3600))
        let newer = AIChatSuggestion.make(chatId: "newer", title: "Newer", timestamp: Date().addingTimeInterval(-60))
        suggestionsReader.recentChats = [older, newer]

        let result = await provider.aiChats(query: nil)

        XCTAssertEqual(result.chats.first?.chatId, "newer")
        XCTAssertEqual(result.chats.last?.chatId, "older")
    }

    // MARK: - Mapping

    @MainActor
    func testLastEditIsFormattedAsISO8601() async throws {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true]
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        suggestionsReader.recentChats = [.make(chatId: "1", title: "Chat", timestamp: date)]

        let result = await provider.aiChats(query: nil)

        XCTAssertNotNil(result.chats.first?.lastEdit)
        // Verify it round-trips through ISO8601 back to the original date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = try XCTUnwrap(formatter.date(from: result.chats.first!.lastEdit!))
        XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    @MainActor
    func testWhenTimestampIsNil_thenLastEditIsNil() async {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true]
        suggestionsReader.recentChats = [.make(chatId: "1", title: "Chat", timestamp: nil)]

        let result = await provider.aiChats(query: nil)

        XCTAssertNil(result.chats.first?.lastEdit)
    }

    @MainActor
    func testPinnedFlagIsMappedCorrectly() async {
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true]
        suggestionsReader.pinnedChats = [.make(chatId: "p", title: "Pinned", isPinned: true)]
        suggestionsReader.recentChats = [.make(chatId: "r", title: "Recent", isPinned: false)]

        let result = await provider.aiChats(query: nil)

        XCTAssertEqual(result.chats.first(where: { $0.chatId == "p" })?.pinned, true)
        XCTAssertEqual(result.chats.first(where: { $0.chatId == "r" })?.pinned, false)
    }
}

// MARK: - Mocks

@MainActor
private final class MockAIChatSuggestionsReader: AIChatSuggestionsReading {

    var maxHistoryCount: Int = 5
    var pinnedChats: [AIChatSuggestion] = []
    var recentChats: [AIChatSuggestion] = []
    var receivedQuery: String?

    func fetchSuggestions(query: String?) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
        receivedQuery = query
        return (pinned: pinnedChats, recent: recentChats)
    }

    func tearDown() {}
}

private final class MockAiChatsConfigProvider: NewTabPageOmnibarConfigProviding {

    @MainActor var mode: NewTabPageDataModel.OmnibarMode = .ai
    private let modeSubject = PassthroughSubject<NewTabPageDataModel.OmnibarMode, Never>()
    var modePublisher: AnyPublisher<NewTabPageDataModel.OmnibarMode, Never> { modeSubject.eraseToAnyPublisher() }

    var isAIChatShortcutEnabled: Bool = true
    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }

    var isAIChatSettingVisible: Bool = true
    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }

    var showCustomizePopover: Bool = false
    var isAIChatRecentChatsEnabled: Bool = true
}

private extension AIChatSuggestion {

    static func make(
        chatId: String,
        title: String,
        isPinned: Bool = false,
        timestamp: Date? = nil
    ) -> AIChatSuggestion {
        AIChatSuggestion(id: chatId, title: title, isPinned: isPinned, chatId: chatId, timestamp: timestamp)
    }
}

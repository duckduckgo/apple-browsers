//
//  NewTabPageOmnibarClientTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import NewTabPage

final class NewTabPageOmnibarClientTests: XCTestCase {

    private var suggestionsProvider: MockNewTabPageOmnibarSuggestionsProvider!
    private var aiChatsProvider: MockNewTabPageOmnibarAiChatsProvider!
    private var configProvider: MockNewTabPageOmnibarConfigProvider!
    private var actionHandler: NewTabPageOmnibarActionsHandling!
    private var client: NewTabPageOmnibarClient!
    private var userScript: NewTabPageUserScript!
    private var messageHelper: MessageHelper<NewTabPageOmnibarClient.MessageName>!

    override func setUp() async throws {
        try await super.setUp()

        suggestionsProvider = MockNewTabPageOmnibarSuggestionsProvider()
        aiChatsProvider = MockNewTabPageOmnibarAiChatsProvider()
        configProvider = MockNewTabPageOmnibarConfigProvider()
        actionHandler = MockNewTabPageOmnibarActionsHandler()
        client = NewTabPageOmnibarClient(configProvider: configProvider,
                                         suggestionsProvider: suggestionsProvider,
                                         aiChatsProvider: aiChatsProvider,
                                         actionHandler: actionHandler)

        userScript = NewTabPageUserScript()
        messageHelper = .init(userScript: userScript)

        client.registerMessageHandlers(for: userScript)
    }

    // MARK: - getConfig

    @MainActor
    func testGetConfigReturnsConfigFromTheProvider() async throws {
        configProvider.mode = .search
        configProvider.isAIChatShortcutEnabled = true
        configProvider.isAIChatSettingVisible = false
        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.mode, configProvider.mode)
        XCTAssertEqual(config.enableAi, configProvider.isAIChatShortcutEnabled)
        XCTAssertEqual(config.showAiSetting, configProvider.isAIChatSettingVisible)
    }

    // MARK: - setConfig

    @MainActor
    func testSetConfigUpdatesModeAndSettings() async throws {
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: false, showAiSetting: true, showCustomizePopover: true, enableRecentAiChats: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)
        XCTAssertEqual(configProvider.mode, .ai)
        XCTAssertEqual(configProvider.isAIChatShortcutEnabled, false)
        XCTAssertEqual(configProvider.isAIChatSettingVisible, true)
    }

    // MARK: - getSuggestions

    func testGetSuggestionsReturnsSuggestionsFromProvider() async throws {
        suggestionsProvider.suggestionsHandler = { term in
            XCTAssertEqual(term, "test")
            return NewTabPageDataModel.Suggestions(
                topHits: [.website(url: "https://example.com")],
                duckduckgoSuggestions: [],
                localSuggestions: []
            )
        }

        let request = NewTabPageDataModel.OmnibarGetSuggestionsRequest(term: "test")
        let response: NewTabPageDataModel.SuggestionsData = try await messageHelper.handleMessage(
            named: .getSuggestions,
            parameters: request
        )

        let expected = NewTabPageDataModel.SuggestionsData(
            suggestions: NewTabPageDataModel.Suggestions(
                topHits: [.website(url: "https://example.com")],
                duckduckgoSuggestions: [],
                localSuggestions: []
            )
        )
        XCTAssertEqual(response, expected)
    }

    // MARK: - submitSearch

    func testSubmitSearchIsForwardedToHandler() async throws {
        let expectation = expectation(description: "submitSearchCalled")
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitSearchHandler = { term, target in
            XCTAssertEqual(term, "searchTerm")
            XCTAssertEqual(target, .sameTab)
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.SubmitSearchAction(target: .sameTab, term: "searchTerm")
        try await messageHelper.handleMessageExpectingNilResponse(named: .submitSearch, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: - openSuggestion

    func testOpenSuggestionIsForwardedToHandler() async throws {
        let expectation = expectation(description: "openSuggestionCalled")
        let suggestion = NewTabPageDataModel.Suggestion.website(url: "https://suggestion.com")
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.openSuggestionHandler = { s, target in
            XCTAssertEqual(s, suggestion)
            XCTAssertEqual(target, .newTab)
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.OpenSuggestionAction(suggestion: suggestion, target: .newTab)
        try await messageHelper.handleMessageExpectingNilResponse(named: .openSuggestion, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: - getAiChats

    func testGetAiChatsReturnsChatsFromProvider() async throws {
        let expectedChats = NewTabPageDataModel.AiChatsData(chats: [
            NewTabPageDataModel.AiChat(chatId: "1", title: "Chat 1"),
            NewTabPageDataModel.AiChat(chatId: "2", title: "Chat 2")
        ])
        aiChatsProvider.aiChatsHandler = { _ in expectedChats }

        let request = NewTabPageDataModel.OmnibarGetAiChatsRequest(query: "test")
        let response: NewTabPageDataModel.AiChatsData = try await messageHelper.handleMessage(named: .getAiChats, parameters: request)

        XCTAssertEqual(response, expectedChats)
    }

    func testGetAiChatsPassesQueryToProvider() async throws {
        var receivedQuery: String?
        aiChatsProvider.aiChatsHandler = { query in
            receivedQuery = query
            return .empty
        }

        let request = NewTabPageDataModel.OmnibarGetAiChatsRequest(query: "swift concurrency")
        try await messageHelper.handleMessageIgnoringResponse(named: .getAiChats, parameters: request)

        XCTAssertEqual(receivedQuery, "swift concurrency")
    }

    func testGetAiChatsWithNilQueryCallsProviderWithNil() async throws {
        var receivedQuery: String? = "not nil"
        aiChatsProvider.aiChatsHandler = { query in
            receivedQuery = query
            return .empty
        }

        let request = NewTabPageDataModel.OmnibarGetAiChatsRequest(query: nil)
        try await messageHelper.handleMessageIgnoringResponse(named: .getAiChats, parameters: request)

        XCTAssertNil(receivedQuery)
    }

    // MARK: - openAiChat

    func testOpenAiChatIsForwardedToHandler() async throws {
        let expectation = expectation(description: "openAiChatCalled")
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.openAiChatHandler = { chatId, isPinned, trigger, target in
            XCTAssertEqual(chatId, "abc-123")
            XCTAssertEqual(isPinned, true)
            XCTAssertEqual(trigger, .keyboard)
            XCTAssertEqual(target, .newTab)
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.OpenAiChatAction(chatId: "abc-123", target: .newTab, trigger: .keyboard, isPinned: true)
        try await messageHelper.handleMessageExpectingNilResponse(named: .openAiChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOpenAiChatWithMissingTriggerDefaultsToMouse() async throws {
        let expectation = expectation(description: "openAiChatCalled")
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.openAiChatHandler = { _, _, trigger, _ in
            XCTAssertEqual(trigger, .mouse)
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.OpenAiChatAction(chatId: "abc-123", target: .sameTab, trigger: nil, isPinned: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .openAiChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: - submitChat

    func testSubmitChatIsForwardedToHandler() async throws {
        let expectation = expectation(description: "submitChatCalled")
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { chat, target in
            XCTAssertEqual(chat, "Hello Chat")
            XCTAssertEqual(target, .newWindow)
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hello Chat", target: .newWindow)
        try await messageHelper.handleMessageExpectingNilResponse(named: .submitChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)
    }
}

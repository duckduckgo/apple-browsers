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

import AIChat
import XCTest
@testable import NewTabPage

final class NewTabPageOmnibarClientTests: XCTestCase {

    private var suggestionsProvider: MockNewTabPageOmnibarSuggestionsProvider!
    private var aiChatsProvider: MockNewTabPageOmnibarAiChatsProvider!
    private var configProvider: MockNewTabPageOmnibarConfigProvider!
    private var modelsProvider: StubNewTabPageOmnibarModelsProvider!
    private var actionHandler: NewTabPageOmnibarActionsHandling!
    private var client: NewTabPageOmnibarClient!
    private var userScript: NewTabPageUserScript!
    private var messageHelper: MessageHelper<NewTabPageOmnibarClient.MessageName>!

    override func setUp() async throws {
        try await super.setUp()

        suggestionsProvider = MockNewTabPageOmnibarSuggestionsProvider()
        aiChatsProvider = MockNewTabPageOmnibarAiChatsProvider()
        configProvider = MockNewTabPageOmnibarConfigProvider()
        modelsProvider = StubNewTabPageOmnibarModelsProvider()
        actionHandler = MockNewTabPageOmnibarActionsHandler()
        client = NewTabPageOmnibarClient(configProvider: configProvider,
                                         suggestionsProvider: suggestionsProvider,
                                         aiChatsProvider: aiChatsProvider,
                                         modelsProvider: modelsProvider,
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
        configProvider.isWebSearchEnabled = true
        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.mode, configProvider.mode)
        XCTAssertEqual(config.enableAi, configProvider.isAIChatShortcutEnabled)
        XCTAssertEqual(config.showAiSetting, configProvider.isAIChatSettingVisible)
        XCTAssertEqual(config.enableWebSearch, configProvider.isWebSearchEnabled)
    }

    // MARK: - setConfig

    @MainActor
    func testSetConfigUpdatesModeAndSettings() async throws {
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: false, showAiSetting: true, showCustomizePopover: true, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, selectedModelId: nil, aiModelSections: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)
        XCTAssertEqual(configProvider.mode, .ai)
        XCTAssertEqual(configProvider.isAIChatShortcutEnabled, false)
        XCTAssertEqual(configProvider.isAIChatSettingVisible, true)
    }

    @MainActor
    func testWhenSetConfigWithSelectedModelIdThenModelIdIsPersisted() async throws {
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, selectedModelId: "gpt-4o-mini", aiModelSections: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)
        XCTAssertEqual(configProvider.selectedModelId, "gpt-4o-mini")
    }

    @MainActor
    func testWhenSetConfigWithSelectedModelIdThenShortNameIsCachedFromModelsProvider() async throws {
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "gpt-4o-mini", name: "GPT-4o mini", shortName: "G4m", isEnabled: true, supportsImageUpload: false, supportedTools: []),
                NewTabPageDataModel.AIModelItem(id: "maverick", name: "Maverick", shortName: "Maverick", isEnabled: true, supportsImageUpload: false, supportedTools: [])
            ])
        ]
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, selectedModelId: "maverick", aiModelSections: nil)

        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)

        XCTAssertEqual(configProvider.selectedModelId, "maverick")
        XCTAssertEqual(configProvider.selectedModelShortName, "Maverick")
    }

    @MainActor
    func testWhenSetConfigWithUnknownModelIdThenShortNameIsCleared() async throws {
        configProvider.selectedModelShortName = "StaleName"
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "gpt-4o-mini", name: "GPT-4o mini", shortName: "G4m", isEnabled: true, supportsImageUpload: false, supportedTools: [])
            ])
        ]
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, selectedModelId: "brand-new-model", aiModelSections: nil)

        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)

        XCTAssertEqual(configProvider.selectedModelId, "brand-new-model")
        XCTAssertNil(configProvider.selectedModelShortName)
    }

    @MainActor
    func testWhenSetConfigWithUnchangedModelIdAndEmptyLookupThenCachedShortNameIsPreserved() async throws {
        // Given — id already stored with a cached short name, and models haven't been fetched yet
        configProvider.selectedModelId = "gpt-4o-mini"
        configProvider.selectedModelShortName = "G4m"
        modelsProvider.lastFetchedSections = nil

        // When — web echoes back the same id (typical on launch)
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, selectedModelId: "gpt-4o-mini", aiModelSections: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)

        // Then — cached short name is preserved (not wiped by a failed lookup)
        XCTAssertEqual(configProvider.selectedModelId, "gpt-4o-mini")
        XCTAssertEqual(configProvider.selectedModelShortName, "G4m")
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
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { chat, target, modelId, images, mode, toolChoice in
            XCTAssertEqual(chat, "Hello Chat")
            XCTAssertEqual(target, .newWindow)
            XCTAssertEqual(modelId, "gpt-4o-mini")
            XCTAssertEqual(images?.count, 1)
            XCTAssertEqual(toolChoice, ["WebSearch"])
            XCTAssertEqual(mode, AIChatNativePrompt.imageGenerationMode)
            expectation.fulfill()
        }

        let image = NewTabPageDataModel.SubmitChatImage(data: "base64data", format: "png")
        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hello Chat", target: .newWindow, modelId: "gpt-4o-mini", images: [image], mode: AIChatNativePrompt.imageGenerationMode, toolChoice: ["WebSearch"])
        try await messageHelper.handleMessageExpectingNilResponse(named: .submitChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)
    }

}

private final class StubNewTabPageOmnibarModelsProvider: NewTabPageOmnibarModelsProviding {
    var lastFetchedSections: [NewTabPageDataModel.AIModelSection]?

    func fetchAIModelSections() async -> [NewTabPageDataModel.AIModelSection] {
        lastFetchedSections ?? []
    }
}

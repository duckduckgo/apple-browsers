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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: false, showAiSetting: true, showCustomizePopover: true, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, selectedModelId: nil, aiModelSections: nil, selectedReasoningEffort: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)
        XCTAssertEqual(configProvider.mode, .ai)
        XCTAssertEqual(configProvider.isAIChatShortcutEnabled, false)
        XCTAssertEqual(configProvider.isAIChatSettingVisible, true)
    }

    @MainActor
    func testWhenSetConfigWithSelectedModelIdThenModelIdIsPersisted() async throws {
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, selectedModelId: "gpt-4o-mini", aiModelSections: nil, selectedReasoningEffort: nil)
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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, selectedModelId: "maverick", aiModelSections: nil, selectedReasoningEffort: nil)

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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, selectedModelId: "brand-new-model", aiModelSections: nil, selectedReasoningEffort: nil)

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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, selectedModelId: "gpt-4o-mini", aiModelSections: nil, selectedReasoningEffort: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)

        // Then — cached short name is preserved (not wiped by a failed lookup)
        XCTAssertEqual(configProvider.selectedModelId, "gpt-4o-mini")
        XCTAssertEqual(configProvider.selectedModelShortName, "G4m")
    }

    // MARK: - reasoning effort (getConfig / notifyConfigUpdated)

    @MainActor
    func testWhenReasoningEffortDisabledThenSupportedReasoningEffortStrippedInGetConfig() async throws {
        configProvider.isReasoningEffortEnabled = false
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "reasoning-model", name: "Reasoning", shortName: "R",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedReasoningEffort: ["none", "low", "medium"])
            ])
        ]

        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.aiModelSections?.flatMap(\.items).first?.supportedReasoningEffort, [])
    }

    @MainActor
    func testWhenReasoningEffortDisabledThenSupportedToolsPreservedInGetConfig() async throws {
        configProvider.isReasoningEffortEnabled = false
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "reasoning-model", name: "Reasoning", shortName: "R",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedTools: ["WebSearch"],
                                                 supportedReasoningEffort: ["none", "low", "medium"])
            ])
        ]

        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.aiModelSections?.flatMap(\.items).first?.supportedTools, ["WebSearch"])
    }

    @MainActor
    func testWhenReasoningEffortEnabledThenSupportedReasoningEffortPreservedInGetConfig() async throws {
        configProvider.isReasoningEffortEnabled = true
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "reasoning-model", name: "Reasoning", shortName: "R",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedReasoningEffort: ["none", "low", "medium"])
            ])
        ]

        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.aiModelSections?.flatMap(\.items).first?.supportedReasoningEffort, ["none", "low", "medium"])
    }

    @MainActor
    func testWhenReasoningEffortEnabledThenSelectedReasoningEffortIsIncludedInGetConfig() async throws {
        configProvider.isReasoningEffortEnabled = true
        configProvider.selectedReasoningEffort = "medium"

        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.selectedReasoningEffort, "medium")
    }

    // MARK: - reasoning effort (setConfig)

    @MainActor
    func testWhenSetConfigWithValidReasoningEffortThenItIsPersisted() async throws {
        configProvider.isReasoningEffortEnabled = true
        configProvider.selectedModelId = "reasoning-model"
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "reasoning-model", name: "Reasoning", shortName: "R",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedReasoningEffort: ["none", "low", "medium"])
            ])
        ]
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, selectedModelId: "reasoning-model", aiModelSections: nil, selectedReasoningEffort: "low")

        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)

        XCTAssertEqual(configProvider.selectedReasoningEffort, "low")
    }

    @MainActor
    func testWhenSetConfigWithUnsupportedReasoningEffortThenItIsIgnored() async throws {
        configProvider.isReasoningEffortEnabled = true
        configProvider.selectedReasoningEffort = "low"
        configProvider.selectedModelId = "limited-model"
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "limited-model", name: "Limited", shortName: "L",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedReasoningEffort: ["low"])
            ])
        ]
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, selectedModelId: "limited-model", aiModelSections: nil, selectedReasoningEffort: "medium")

        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)

        XCTAssertEqual(configProvider.selectedReasoningEffort, "low")
    }

    @MainActor
    func testWhenSetConfigAndReasoningEffortDisabledThenValueIsIgnored() async throws {
        configProvider.isReasoningEffortEnabled = false
        configProvider.selectedModelId = "reasoning-model"
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "reasoning-model", name: "Reasoning", shortName: "R",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedReasoningEffort: ["low"])
            ])
        ]
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, selectedModelId: "reasoning-model", aiModelSections: nil, selectedReasoningEffort: "low")

        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)

        XCTAssertNil(configProvider.selectedReasoningEffort)
    }

    // MARK: - reasoning effort (submitChat)

    @MainActor
    func testWhenSubmitChatWithSupportedReasoningEffortThenItIsForwarded() async throws {
        configProvider.isReasoningEffortEnabled = true
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "reasoning-model", name: "Reasoning", shortName: "R",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedReasoningEffort: ["low", "medium"])
            ])
        ]
        let expectation = expectation(description: "submitChatCalled")
        var forwardedEffort: String?
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { _, _, _, _, _, _, reasoningEffort in
            forwardedEffort = reasoningEffort
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hi", target: .sameTab, modelId: "reasoning-model", images: nil, mode: nil, toolChoice: nil, reasoningEffort: "medium")
        try await messageHelper.handleMessageExpectingNilResponse(named: .submitChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(forwardedEffort, "medium")
    }

    @MainActor
    func testWhenSubmitChatWithUnsupportedReasoningEffortThenItIsDropped() async throws {
        configProvider.isReasoningEffortEnabled = true
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "limited-model", name: "Limited", shortName: "L",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedReasoningEffort: ["low"])
            ])
        ]
        let expectation = expectation(description: "submitChatCalled")
        var forwardedEffort: String?
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { _, _, _, _, _, _, reasoningEffort in
            forwardedEffort = reasoningEffort
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hi", target: .sameTab, modelId: "limited-model", images: nil, mode: nil, toolChoice: nil, reasoningEffort: "medium")
        try await messageHelper.handleMessageExpectingNilResponse(named: .submitChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertNil(forwardedEffort)
    }

    @MainActor
    func testWhenSubmitChatAndReasoningEffortDisabledThenItIsDropped() async throws {
        configProvider.isReasoningEffortEnabled = false
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "reasoning-model", name: "Reasoning", shortName: "R",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedReasoningEffort: ["low"])
            ])
        ]
        let expectation = expectation(description: "submitChatCalled")
        var forwardedEffort: String?
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { _, _, _, _, _, _, reasoningEffort in
            forwardedEffort = reasoningEffort
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hi", target: .sameTab, modelId: "reasoning-model", images: nil, mode: nil, toolChoice: nil, reasoningEffort: "low")
        try await messageHelper.handleMessageExpectingNilResponse(named: .submitChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertNil(forwardedEffort)
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

    func testGetAiChatsRoundTripsModelField() async throws {
        let expectedChats = NewTabPageDataModel.AiChatsData(chats: [
            NewTabPageDataModel.AiChat(chatId: "v", title: "Voice", model: AIChatNativePrompt.voiceMode),
            NewTabPageDataModel.AiChat(chatId: "i", title: "Image", model: AIChatNativePrompt.imageGenerationMode),
            NewTabPageDataModel.AiChat(chatId: "t", title: "Text", model: nil)
        ])
        aiChatsProvider.aiChatsHandler = { _ in expectedChats }

        let request = NewTabPageDataModel.OmnibarGetAiChatsRequest(query: nil)
        let response: NewTabPageDataModel.AiChatsData = try await messageHelper.handleMessage(named: .getAiChats, parameters: request)

        XCTAssertEqual(response, expectedChats)
        XCTAssertEqual(response.chats[0].model, "voice-mode")
        XCTAssertEqual(response.chats[1].model, "image-generation")
        XCTAssertNil(response.chats[2].model)
    }

    func testGetAiChatsOmitsModelKeyWhenNil() async throws {
        let chat = NewTabPageDataModel.AiChat(chatId: "1", title: "Chat 1")
        let encoded = try JSONEncoder().encode(chat)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertFalse(json.keys.contains("model"), "Expected `model` key to be absent when nil; got: \(json.keys.sorted())")
    }

    func testGetAiChatsEncodesModelKeyWhenPresent() async throws {
        let chat = NewTabPageDataModel.AiChat(chatId: "1", title: "Chat 1", model: AIChatNativePrompt.voiceMode)
        let encoded = try JSONEncoder().encode(chat)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "voice-mode")
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
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { chat, target, modelId, images, mode, toolChoice, reasoningEffort in
            XCTAssertEqual(chat, "Hello Chat")
            XCTAssertEqual(target, .newWindow)
            XCTAssertEqual(modelId, "gpt-4o-mini")
            XCTAssertEqual(images?.count, 1)
            XCTAssertEqual(toolChoice, ["WebSearch"])
            XCTAssertEqual(mode, AIChatNativePrompt.imageGenerationMode)
            XCTAssertNil(reasoningEffort)
            expectation.fulfill()
        }

        let image = NewTabPageDataModel.SubmitChatImage(data: "base64data", format: "png")
        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hello Chat", target: .newWindow, modelId: "gpt-4o-mini", images: [image], mode: AIChatNativePrompt.imageGenerationMode, toolChoice: ["WebSearch"], reasoningEffort: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .submitChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: - voice chat access

    @MainActor
    func testWhenVoiceChatAccessEnabledThenGetConfigIncludesEnableVoiceChatAccessTrue() async throws {
        configProvider.isVoiceChatAccessEnabled = true

        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.enableVoiceChatAccess, true)
    }

    @MainActor
    func testWhenVoiceChatAccessDisabledThenGetConfigIncludesEnableVoiceChatAccessFalse() async throws {
        configProvider.isVoiceChatAccessEnabled = false

        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.enableVoiceChatAccess, false)
    }

}

private final class StubNewTabPageOmnibarModelsProvider: NewTabPageOmnibarModelsProviding {
    var lastFetchedSections: [NewTabPageDataModel.AIModelSection]?

    func fetchAIModelSections() async -> [NewTabPageDataModel.AIModelSection] {
        lastFetchedSections ?? []
    }
}

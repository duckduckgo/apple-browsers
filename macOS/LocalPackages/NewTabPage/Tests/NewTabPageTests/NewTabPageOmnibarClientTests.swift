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
import WebKit
import XCTest
@testable import NewTabPage

@MainActor
final class NewTabPageOmnibarClientTests: XCTestCase {

    private var suggestionsProvider: MockNewTabPageOmnibarSuggestionsProvider!
    private var aiChatsProvider: MockNewTabPageOmnibarAiChatsProvider!
    private var configProvider: MockNewTabPageOmnibarConfigProvider!
    private var modelsProvider: StubNewTabPageOmnibarModelsProvider!
    private var actionHandler: NewTabPageOmnibarActionsHandling!
    private var tabsProvider: StubNewTabPageOmnibarTabsProvider!
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
        tabsProvider = StubNewTabPageOmnibarTabsProvider()
        client = NewTabPageOmnibarClient(configProvider: configProvider,
                                         suggestionsProvider: suggestionsProvider,
                                         aiChatsProvider: aiChatsProvider,
                                         modelsProvider: modelsProvider,
                                         actionHandler: actionHandler,
                                         tabsProvider: tabsProvider)

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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: false, showAiSetting: true, showCustomizePopover: true, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, enableAskAiSuggestion: nil, selectedModelId: nil, aiModelSections: nil, selectedReasoningEffort: nil, enableAttachTabs: nil, attachmentLimits: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: newConfig)
        XCTAssertEqual(configProvider.mode, .ai)
        XCTAssertEqual(configProvider.isAIChatShortcutEnabled, false)
        XCTAssertEqual(configProvider.isAIChatSettingVisible, true)
    }

    @MainActor
    func testWhenSetConfigWithSelectedModelIdThenModelIdIsPersisted() async throws {
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, enableAskAiSuggestion: nil, selectedModelId: "gpt-4o-mini", aiModelSections: nil, selectedReasoningEffort: nil, enableAttachTabs: nil, attachmentLimits: nil)
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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, enableAskAiSuggestion: nil, selectedModelId: "maverick", aiModelSections: nil, selectedReasoningEffort: nil, enableAttachTabs: nil, attachmentLimits: nil)

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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, enableAskAiSuggestion: nil, selectedModelId: "brand-new-model", aiModelSections: nil, selectedReasoningEffort: nil, enableAttachTabs: nil, attachmentLimits: nil)

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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, enableAskAiSuggestion: nil, selectedModelId: "gpt-4o-mini", aiModelSections: nil, selectedReasoningEffort: nil, enableAttachTabs: nil, attachmentLimits: nil)
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
    func testWhenReasoningEffortDisabledThenSupportedFileTypesPreservedInGetConfig() async throws {
        // Stripping reasoning effort must not also drop supportedFileTypes, or PDF attachment
        // would be hidden for capable models whenever reasoning effort is off.
        configProvider.isReasoningEffortEnabled = false
        modelsProvider.lastFetchedSections = [
            NewTabPageDataModel.AIModelSection(header: nil, items: [
                NewTabPageDataModel.AIModelItem(id: "model", name: "Model", shortName: "M",
                                                 isEnabled: true, supportsImageUpload: false,
                                                 supportedReasoningEffort: ["none", "low"],
                                                 supportedFileTypes: ["application/pdf"])
            ])
        ]

        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.aiModelSections?.flatMap(\.items).first?.supportedFileTypes, ["application/pdf"])
        XCTAssertEqual(config.aiModelSections?.flatMap(\.items).first?.supportedReasoningEffort, [])
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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, enableAskAiSuggestion: nil, selectedModelId: "reasoning-model", aiModelSections: nil, selectedReasoningEffort: "low", enableAttachTabs: nil, attachmentLimits: nil)

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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, enableAskAiSuggestion: nil, selectedModelId: "limited-model", aiModelSections: nil, selectedReasoningEffort: "medium", enableAttachTabs: nil, attachmentLimits: nil)

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
        let newConfig = NewTabPageDataModel.OmnibarConfig(mode: .ai, enableAi: true, showAiSetting: nil, showCustomizePopover: nil, enableRecentAiChats: nil, showViewAllAiChats: nil, enableAiChatTools: nil, enableImageGeneration: nil, enableWebSearch: nil, enableVoiceChatAccess: nil, enableAskAiSuggestion: nil, selectedModelId: "reasoning-model", aiModelSections: nil, selectedReasoningEffort: "low", enableAttachTabs: nil, attachmentLimits: nil)

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
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { _, _, _, _, _, _, reasoningEffort, _, _ in
            forwardedEffort = reasoningEffort
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hi", target: .sameTab, modelId: "reasoning-model", images: nil, mode: nil, toolChoice: nil, reasoningEffort: "medium", pageContext: nil, files: nil)
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
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { _, _, _, _, _, _, reasoningEffort, _, _ in
            forwardedEffort = reasoningEffort
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hi", target: .sameTab, modelId: "limited-model", images: nil, mode: nil, toolChoice: nil, reasoningEffort: "medium", pageContext: nil, files: nil)
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
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { _, _, _, _, _, _, reasoningEffort, _, _ in
            forwardedEffort = reasoningEffort
            expectation.fulfill()
        }

        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hi", target: .sameTab, modelId: "reasoning-model", images: nil, mode: nil, toolChoice: nil, reasoningEffort: "low", pageContext: nil, files: nil)
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
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { chat, target, modelId, images, mode, toolChoice, reasoningEffort, _, _ in
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
        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hello Chat", target: .newWindow, modelId: "gpt-4o-mini", images: [image], mode: AIChatNativePrompt.imageGenerationMode, toolChoice: ["WebSearch"], reasoningEffort: nil, pageContext: nil, files: nil)
        try await messageHelper.handleMessageExpectingNilResponse(named: .submitChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: - attach tabs (config)

    @MainActor
    func testWhenAttachTabsEnabledThenGetConfigIncludesEnableAttachTabsTrue() async throws {
        configProvider.isAttachTabsEnabled = true

        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.enableAttachTabs, true)
    }

    @MainActor
    func testWhenAttachTabsDisabledThenGetConfigIncludesEnableAttachTabsFalse() async throws {
        configProvider.isAttachTabsEnabled = false

        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)

        XCTAssertEqual(config.enableAttachTabs, false)
    }

    // MARK: - getOpenTabs / getTabContent

    @MainActor
    func testGetOpenTabsReturnsTabsFromProvider() async throws {
        tabsProvider.openTabsResult = [
            NewTabPageDataModel.OmnibarTabMetadata(tabId: "tab-1", title: "Apple", url: "https://apple.com", favicon: NewTabPageDataModel.OmnibarTabFavicon(src: "data:image/png;base64,AAAA", maxAvailableSize: 32)),
            NewTabPageDataModel.OmnibarTabMetadata(tabId: "tab-2", title: "DDG", url: "https://duckduckgo.com", favicon: nil)
        ]

        let response: NewTabPageDataModel.OmnibarGetOpenTabsResponse = try await messageHelper.handleMessage(named: .getOpenTabs)

        XCTAssertEqual(response.tabs.map(\.tabId), ["tab-1", "tab-2"])
        XCTAssertEqual(response.tabs.first?.favicon?.src, "data:image/png;base64,AAAA")
    }

    @MainActor
    func testGetTabContentForwardsTabIdAndReturnsPageContext() async throws {
        tabsProvider.tabContentResult = NewTabPageDataModel.OmnibarPageContext(
            tabId: "tab-1", title: "Apple", url: "https://apple.com", favicon: nil,
            content: "## Hello", truncated: false, fullContentLength: 8
        )

        let request = NewTabPageDataModel.OmnibarGetTabContentRequest(tabId: "tab-1")
        let response: NewTabPageDataModel.OmnibarGetTabContentResponse = try await messageHelper.handleMessage(named: .getTabContent, parameters: request)

        XCTAssertEqual(tabsProvider.requestedTabId, "tab-1")
        XCTAssertEqual(response.pageContext?.tabId, "tab-1")
        XCTAssertEqual(response.pageContext?.content, "## Hello")
    }

    @MainActor
    func testGetTabContentReturnsNullWhenProviderReturnsNil() async throws {
        tabsProvider.tabContentResult = nil

        let request = NewTabPageDataModel.OmnibarGetTabContentRequest(tabId: "missing")
        let response: NewTabPageDataModel.OmnibarGetTabContentResponse = try await messageHelper.handleMessage(named: .getTabContent, parameters: request)

        XCTAssertNil(response.pageContext)
    }

    // MARK: - submitChat (attachments)

    @MainActor
    func testSubmitChatForwardsPageContextsAndFiles() async throws {
        let expectation = expectation(description: "submitChatCalled")
        var forwardedContexts: [NewTabPageDataModel.OmnibarPageContext]?
        var forwardedFiles: [NewTabPageDataModel.OmnibarPromptFile]?
        (actionHandler as? MockNewTabPageOmnibarActionsHandler)?.submitChatHandler = { _, _, _, _, _, _, _, pageContexts, files in
            forwardedContexts = pageContexts
            forwardedFiles = files
            expectation.fulfill()
        }

        let context = NewTabPageDataModel.OmnibarPageContext(tabId: "tab-1", title: "Apple", url: "https://apple.com", favicon: nil, content: "...", truncated: false, fullContentLength: 3)
        let file = NewTabPageDataModel.OmnibarPromptFile(data: "base64", fileName: "doc.pdf", mimeType: "application/pdf")
        let action = NewTabPageDataModel.SubmitChatAction(chat: "Hi", target: .sameTab, modelId: nil, images: nil, mode: nil, toolChoice: nil, reasoningEffort: nil, pageContext: [context], files: [file])
        try await messageHelper.handleMessageExpectingNilResponse(named: .submitChat, parameters: action)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(forwardedContexts?.count, 1)
        XCTAssertEqual(forwardedContexts?.first?.tabId, "tab-1")
        XCTAssertEqual(forwardedFiles?.first?.fileName, "doc.pdf")
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

@MainActor
private final class StubNewTabPageOmnibarModelsProvider: NewTabPageOmnibarModelsProviding {
    var lastFetchedSections: [NewTabPageDataModel.AIModelSection]?

    func fetchAIModelSections() async -> [NewTabPageDataModel.AIModelSection] {
        lastFetchedSections ?? []
    }
}

private final class StubNewTabPageOmnibarTabsProvider: NewTabPageOmnibarTabsProviding {
    var openTabsResult: [NewTabPageDataModel.OmnibarTabMetadata] = []
    var tabContentResult: NewTabPageDataModel.OmnibarPageContext?
    var requestedTabId: String?

    @MainActor
    func openTabs(requestingWebView: WKWebView?) async -> [NewTabPageDataModel.OmnibarTabMetadata] {
        openTabsResult
    }

    @MainActor
    func tabContent(tabId: String, requestingWebView: WKWebView?) async -> NewTabPageDataModel.OmnibarPageContext? {
        requestedTabId = tabId
        return tabContentResult
    }
}

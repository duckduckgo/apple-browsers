//
//  UnifiedToggleInputCoordinatorNewChatHintsTests.swift
//  DuckDuckGo
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
import Foundation
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Full-tab input: new chat hints")
final class UnifiedToggleInputCoordinatorNewChatHintsTests {

    private enum IPhone: DevicePlatformProviding { static let isIphone = true }

    private static let everyModel = AIChatRemoteModel(id: "all", name: "All", provider: "openai", entityHasAccess: true,
                                                      supportsImageUpload: true, supportedFileTypes: ["application/pdf"],
                                                      supportedTools: [AIChatRAGTool.imageGeneration.rawValue], accessTier: ["free"])
    private static let textOnlyModel = AIChatRemoteModel(id: "text", name: "Text", provider: "openai", entityHasAccess: true,
                                                         supportsImageUpload: false, supportedTools: [], accessTier: ["free"])

    private let script = makeTestUserScript()
    private let pixels = PixelKitMock()
    private let capStore = NewChatHintsCapStore(keyValueStore: MockThrowingKeyValueStore())
    private var hintsSubscription: AnyCancellable?

    private static let defaultAttachmentLimits: AIChatAttachmentLimits = {
        let tier = AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 5, maxFileSizeMB: 10, maxTotalFileSizeBytes: 50_000_000, maxPagesPerFile: 100),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 10, maxInputCharsWithAttachments: 10_000))
        return AIChatAttachmentLimits(free: tier, plus: tier, pro: tier)
    }()

    private func makeSUT(isFlagOn: Bool = true,
                         featureFlagger: MockFeatureFlagger? = nil,
                         isReturningUser: Bool = true,
                         models: [AIChatRemoteModel] = [everyModel],
                         attachmentLimits: AIChatAttachmentLimits? = defaultAttachmentLimits,
                         usageLimitsStore: DuckAiUsageLimitsStore? = nil) throws -> UnifiedToggleInputCoordinator {
        let storage = DuckAiNativeMemoryStorageHandler()
        if isReturningUser {
            try storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.originConversions.rawValue, value: #"["duckai_prompt"]"#)
        }
        let terms = DuckAiTermsOfServiceStore(keyValueStore: UserDefaults(suiteName: "NewChatHintsCoordinatorTests-\(UUID().uuidString)")!)
        terms.recordAcceptedOnWeb()
        let flagger = featureFlagger ?? MockFeatureFlagger(enabledFeatureFlags: isFlagOn ? [.newChatHints] : [])
        return UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            duckAiNativeStorageHandler: storage,
            modelsService: StubHintModelsService(models: models, attachmentLimits: attachmentLimits),
            preferences: HintsTestPreferences(),
            toggleModeStorage: HintsTestToggleModeStorage(),
            stateStore: HintsTestStateStore(),
            usageLimitsStore: usageLimitsStore,
            featureFlagger: flagger,
            termsOfServiceStore: terms,
            devicePlatform: IPhone.self,
            newChatHintsUsage: NewChatHintsUsage(capStore: capStore, pixelFiring: pixels,
                                                 isFeatureEnabled: { flagger.isFeatureOn(.newChatHints) })
        )
    }

    /// A blank Duck.ai chat on screen, ready for a prompt, with the models loaded and the page reporting no promo.
    private func openBlankChat(_ sut: UnifiedToggleInputCoordinator) async throws {
        sut.activateForTab("tab-A")
        sut.bindToTab(script, hasExistingChat: false)
        sut.showCollapsed()
        sut.aiChatStatus = .ready
        sut.isAIChatPromoVisible = false
        sut.fetchModels()
        try await waitForModels(sut)
    }

    /// The models load asynchronously; the hints settle once they have.
    private func waitForModels(_ sut: UnifiedToggleInputCoordinator) async throws {
        for _ in 0..<100 where sut.selectedModelSupportsImageUpload == false && sut.newChatHints.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private var tabOrder: [NewChatHint] { NewChatHint.displayOrder }

    private func fired(_ name: String) -> [[String: String]?] {
        pixels.actualFireCalls.filter { $0.pixel.name == name }.map(\.pixel.parameters)
    }

    private func submitPrompt(_ sut: UnifiedToggleInputCoordinator) {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "prompt", mode: .aiChat, trigger: .sendButton)
    }

    /// What the main view controller does when tab A's page leaves Duck.ai for a website.
    private func navigateToWebsite(_ sut: UnifiedToggleInputCoordinator) {
        sut.activateForTab("tab-A")
        sut.tabLeftDuckAI("tab-A")
        sut.deactivateToOmnibar()
        sut.hide()
        sut.unbind()
    }

    /// What the main view controller does when switching to tab B, a website, then back to tab A's blank chat.
    private func switchToWebsiteTabAndBack(_ sut: UnifiedToggleInputCoordinator) {
        sut.deactivateToOmnibar(animateDismiss: false)
        sut.hide()
        sut.unbind()
        sut.activateForTab("tab-B")
        sut.tabLeftDuckAI("tab-B")
        sut.deactivateToOmnibar(animateDismiss: false)
        sut.activateForTab("tab-A")
        sut.bindToTab(script, hasExistingChat: false)
        sut.showCollapsed()
        sut.aiChatStatus = .ready
        sut.isAIChatPromoVisible = false
    }

    @available(iOS 16, macOS 13, *)
    @Test("A returning user's blank chat shows every hint in the tab's order, counted once on screen", .timeLimit(.minutes(1)))
    func showsHints() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        #expect(sut.newChatHints == tabOrder)
        #expect(pixels.actualFireCalls.filter { $0.pixel.name == "aichat_new_chat_hints_shown" }.isEmpty)
        sut.newChatHintsDidAppear(sut.newChatHints)
        sut.newChatHintsDidAppear(sut.newChatHints)
        #expect(pixels.actualFireCalls.filter { $0.pixel.name == "aichat_new_chat_hints_shown" }.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Typing hides the hints and clearing brings them back in the same order", .timeLimit(.minutes(1)))
    func typingHides() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        sut.setText("Hello")
        #expect(sut.newChatHints.isEmpty)
        sut.setText("")
        #expect(sut.newChatHints == tabOrder)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Selecting a tool hides the hints, clearing it brings them back", .timeLimit(.minutes(1)))
    func toolHides() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        sut.selectTool(.imageGeneration)
        #expect(sut.newChatHints.isEmpty)
        sut.clearSelectedTool()
        #expect(sut.newChatHints == tabOrder)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A promo hides the hints until the page says it's gone", .timeLimit(.minutes(1)))
    func promoHides() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        sut.isAIChatPromoVisible = true
        #expect(sut.newChatHints.isEmpty)
        sut.isAIChatPromoVisible = false
        #expect(sut.newChatHints == tabOrder)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Hints only offer what an accessible model can do", .timeLimit(.minutes(1)))
    func capabilityFilter() async throws {
        let sut = try makeSUT(models: [Self.textOnlyModel])
        try await openBlankChat(sut)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sut.newChatHints.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A first-time user sees no hints", .timeLimit(.minutes(1)))
    func firstTimeUser() async throws {
        let sut = try makeSUT(isReturningUser: false)
        try await openBlankChat(sut)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sut.newChatHints.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("No hints once the cap is reached", .timeLimit(.minutes(1)))
    func capReached() async throws {
        for _ in 0..<NewChatHintsCapStore.hideAfterIgnoredChats { _ = capStore.recordIgnoredChat() }
        let sut = try makeSUT()
        try await openBlankChat(sut)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sut.newChatHints.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off nothing shows, but the new chat still counts", .timeLimit(.minutes(1)))
    func flagOff() async throws {
        let sut = try makeSUT(isFlagOn: false)
        try await openBlankChat(sut)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sut.newChatHints.isEmpty)
        let shown = pixels.actualFireCalls.filter { $0.pixel.name == "aichat_new_chat_shown" }
        #expect(shown.count == 1)
        #expect(shown.first?.pixel.parameters == ["newchathints_enabled": "false"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A history chat shows no hints and isn't counted", .timeLimit(.minutes(1)))
    func historyChat() async throws {
        let sut = try makeSUT()
        sut.activateForTab("tab-A")
        sut.bindToTab(script, hasExistingChat: true)
        sut.showCollapsed()
        sut.aiChatStatus = .ready
        sut.isAIChatPromoVisible = false
        sut.fetchModels()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sut.newChatHints.isEmpty)
        #expect(pixels.actualFireCalls.filter { $0.pixel.name == "aichat_new_chat_shown" }.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Leaving a blank chat for a website ends it: the next blank chat in that tab counts again and reports fresh",
          .timeLimit(.minutes(1)))
    func websiteEndsNewChat() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        sut.newChatHintsDidAppear(sut.newChatHints)

        navigateToWebsite(sut)
        try await openBlankChat(sut)
        submitPrompt(sut)

        #expect(fired("aichat_new_chat_shown").count == 2)
        #expect(fired("aichat_new_chat_first_prompt_sent").map { $0?["hints_shown"] } == ["false"])
        #expect(capStore.ignoredChats == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Switching to a website tab and back to the blank chat counts it once", .timeLimit(.minutes(1)))
    func tabSwitchKeepsNewChat() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        sut.newChatHintsDidAppear(sut.newChatHints)

        switchToWebsiteTabAndBack(sut)
        #expect(sut.newChatHints == tabOrder)
        sut.newChatHintsDidAppear(sut.newChatHints)
        submitPrompt(sut)

        #expect(fired("aichat_new_chat_shown").count == 1)
        #expect(fired("aichat_new_chat_hints_shown").count == 1)
        #expect(fired("aichat_new_chat_first_prompt_sent").map { $0?["hints_shown"] } == ["true"])
        #expect(capStore.ignoredChats == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Switching to a chat tab and back counts the blank chat once and keeps its hints", .timeLimit(.minutes(1)))
    func chatTabSwitchKeepsNewChat() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        sut.newChatHintsDidAppear(sut.newChatHints)
        let chatTab = makeTestUserScript()

        // The main view controller activates each incoming tab before it binds that tab's page.
        sut.activateForTab("tab-B")
        #expect(sut.newChatHints.isEmpty)
        sut.bindToTab(chatTab, hasExistingChat: true)
        sut.showCollapsed()
        sut.aiChatStatus = .ready

        sut.activateForTab("tab-A")
        #expect(sut.newChatHints.isEmpty)
        sut.bindToTab(script, hasExistingChat: false)
        sut.showCollapsed()
        sut.aiChatStatus = .ready
        sut.isAIChatPromoVisible = false
        #expect(sut.newChatHints == tabOrder)
        sut.newChatHintsDidAppear(sut.newChatHints)
        submitPrompt(sut)

        #expect(fired("aichat_new_chat_shown").count == 1)
        #expect(fired("aichat_new_chat_hints_shown").count == 1)
        #expect(fired("aichat_new_chat_first_prompt_sent").map { $0?["hints_shown"] } == ["true"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag off while hints show clears the row and ignores a tap", .timeLimit(.minutes(1)))
    func flagTurnsOff() async throws {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.newChatHints])
        let sut = try makeSUT(featureFlagger: flagger)
        try await openBlankChat(sut)
        #expect(sut.newChatHints == tabOrder)

        flagger.enabledFeatureFlags = []
        // A tap that lands before the flag update reaches the row.
        sut.performNewChatHint(.imageGeneration)
        #expect(sut.selectedTool == nil)
        #expect(fired("aichat_new_chat_hint_tapped").isEmpty)

        flagger.triggerUpdate()
        try await waitUntil { sut.newChatHints.isEmpty }
        #expect(sut.newChatHints.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag on while a blank chat is open shows the row", .timeLimit(.minutes(1)))
    func flagTurnsOn() async throws {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let sut = try makeSUT(featureFlagger: flagger)
        try await openBlankChat(sut)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sut.newChatHints.isEmpty)

        flagger.enabledFeatureFlags = [.newChatHints]
        flagger.triggerUpdate()
        try await waitUntil { !sut.newChatHints.isEmpty }
        #expect(sut.newChatHints == tabOrder)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Photo and file hints need attachment limits, as their pickers do", .timeLimit(.minutes(1)))
    func attachmentHintsNeedLimits() async throws {
        let sut = try makeSUT(attachmentLimits: nil)
        try await openBlankChat(sut)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sut.newChatHints == [.imageGeneration])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new chat started in place counts as a new chat, and the hints still on screen count as shown in it",
          .timeLimit(.minutes(1)))
    func newChatInPlaceCountsAgain() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        sut.newChatHintsDidAppear(sut.newChatHints)

        sut.startNewChat()
        #expect(sut.newChatHints == tabOrder)
        submitPrompt(sut)

        #expect(fired("aichat_new_chat_shown").count == 2)
        #expect(fired("aichat_new_chat_hints_shown").count == 2)
        #expect(fired("aichat_new_chat_first_prompt_sent").map { $0?["hints_shown"] } == ["true"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A spoken first prompt reports the first prompt once, without the draft's tool", .timeLimit(.minutes(1)))
    func voiceFirstPrompt() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        sut.newChatHintsDidAppear(sut.newChatHints)
        // Voice sends neither the selected tool nor attachments.
        sut.selectTool(.imageGeneration)

        sut.submitVoicePrompt("prompt")
        submitPrompt(sut)

        #expect(fired("aichat_new_chat_first_prompt_sent") == [[
            "newchathints_enabled": "true", "hints_shown": "true", "hint_tapped": "none",
            "has_image_attachment": "false", "has_file_attachment": "false", "selected_tool": "none",
        ]])
        #expect(capStore.ignoredChats == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A first prompt sent from outside the input, like an Ask Duck.ai suggestion, reports once", .timeLimit(.minutes(1)))
    func externalFirstPrompt() async throws {
        let sut = try makeSUT()
        try await openBlankChat(sut)
        sut.newChatHintsDidAppear(sut.newChatHints)

        _ = sut.prepareExternalPromptSubmission()
        _ = sut.prepareExternalPromptSubmission()

        #expect(fired("aichat_new_chat_first_prompt_sent") == [[
            "newchathints_enabled": "true", "hints_shown": "true", "hint_tapped": "none",
            "has_image_attachment": "false", "has_file_attachment": "false", "selected_tool": "none",
        ]])
        #expect(capStore.ignoredChats == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the usage limit reached the hints hide and a tap does nothing, but the new chat still counts",
          .timeLimit(.minutes(1)))
    func usageLimitHidesHints() async throws {
        let limits = DuckAiNativeMemoryStorageHandler()
        try limits.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue, value: Self.weeklyLimitReached)
        let sut = try makeSUT(usageLimitsStore: DuckAiUsageLimitsStore(
            storageHandler: limits,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.utiDuckAIWarnings]),
            dismissalStore: InMemoryDuckAiUsageWarningDismissalStore()))
        try await openBlankChat(sut)
        try await Task.sleep(nanoseconds: 300_000_000)
        try #require(sut.viewController.isInputBlockedByUsageLimit)

        #expect(sut.newChatHints.isEmpty)
        sut.performNewChatHint(.imageGeneration)
        #expect(sut.selectedTool == nil)
        #expect(fired("aichat_new_chat_hint_tapped").isEmpty)
        #expect(fired("aichat_new_chat_shown").count == 1)
    }

    private static let weeklyLimitReached: String = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetsAt = formatter.string(from: Date().addingTimeInterval(172_800))
        return """
        {"notice":{"id":"weeklyReached","window":"weekly","percentUsed":100,"resetsAt":"\(resetsAt)","reached":true}}
        """
    }()

    /// Flag updates arrive on the main queue, after the call that sends them.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<50 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private struct StubHintModelsService: AIChatModelsProviding {
    let models: [AIChatRemoteModel]
    let attachmentLimits: AIChatAttachmentLimits?
    func fetchModels() async throws -> AIChatModelsResponse { AIChatModelsResponse(models: models, attachmentLimits: attachmentLimits) }
}

@MainActor
private final class HintsTestStateStore: UnifiedInputStateStoring {
    private var states: [TabUID: TabInputState] = [:]
    let lastUsed = LastUsedInputDefaults(toggleMode: .aiChat, selectedModelID: nil, selectedReasoningMode: nil, selectedTool: nil)

    func state(for uid: TabUID) -> TabInputState { states[uid] ?? TabInputState(toggleMode: .aiChat) }
    func update(_ state: TabInputState, for uid: TabUID) { states[uid] = state }
    func recordUserChoice(_ state: TabInputState, for uid: TabUID, isNewChatContext: Bool) { states[uid] = state }
    func commitToggleMode(_ mode: TextEntryMode) {}
    func remove(for uid: TabUID) { states.removeValue(forKey: uid) }
}

private final class HintsTestPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class HintsTestToggleModeStorage: ToggleModeStoring {
    private var storedMode: TextEntryMode?
    func save(_ mode: TextEntryMode) { storedMode = mode }
    func restore() -> TextEntryMode? { storedMode }
}

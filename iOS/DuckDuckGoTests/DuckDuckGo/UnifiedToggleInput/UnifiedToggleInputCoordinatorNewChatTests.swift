//
//  UnifiedToggleInputCoordinatorNewChatTests.swift
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
import AIChatTestingUtilities
import Combine
import Foundation
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Full-tab input: guaranteed new chat")
final class UnifiedToggleInputCoordinatorNewChatTests {

    private enum IPhone: DevicePlatformProviding { static let isIphone = true }
    private enum IPad: DevicePlatformProviding { static let isIphone = false }

    private func makeSUT(host: UnifiedToggleInputHost = .omnibar,
                         devicePlatform: DevicePlatformProviding.Type = IPhone.self,
                         isFlagOn: Bool = true) -> UnifiedToggleInputCoordinator {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: isFlagOn ? [.newChatHints] : [])
        return UnifiedToggleInputCoordinator(
            host: host,
            isToggleEnabled: true,
            preferences: NewChatTestPreferences(),
            toggleModeStorage: NewChatTestToggleModeStorage(),
            stateStore: NewChatTestStateStore(),
            featureFlagger: featureFlagger,
            newChatHintsFeature: NewChatHintsFeature(featureFlagger: featureFlagger, devicePlatform: devicePlatform)
        )
    }

    /// The input holds its tab's script weakly, as the tab owns it.
    private let script = makeTestUserScript()

    private func openBlankChat(_ sut: UnifiedToggleInputCoordinator, hasExistingChat: Bool = false) {
        sut.activateForTab("tab-A")
        sut.bindToTab(script, hasExistingChat: hasExistingChat)
        sut.showCollapsed()
        sut.aiChatStatus = .ready
    }

    @available(iOS 16, macOS 13, *)
    @Test("A blank chat in the selected Duck.ai tab is a guaranteed new chat", .timeLimit(.minutes(1)))
    func blankChat() {
        let sut = makeSUT()
        openBlankChat(sut)
        #expect(sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Not before the page is ready for a prompt", .timeLimit(.minutes(1)))
    func beforeInputReady() {
        let sut = makeSUT()
        openBlankChat(sut)
        sut.aiChatStatus = .unknown
        #expect(!sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Not while the page hides its input", .timeLimit(.minutes(1)))
    func inputHidden() {
        let sut = makeSUT()
        openBlankChat(sut)
        sut.aiChatInputBoxVisibility = .hidden
        #expect(!sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Not on a chat from history", .timeLimit(.minutes(1)))
    func existingChat() {
        let sut = makeSUT()
        openBlankChat(sut, hasExistingChat: true)
        #expect(!sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Never on iPad", .timeLimit(.minutes(1)))
    func iPad() {
        let sut = makeSUT(devicePlatform: IPad.self)
        openBlankChat(sut)
        #expect(!sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Never in the contextual sheet", .timeLimit(.minutes(1)))
    func contextualSheet() {
        let sut = makeSUT(host: .contextualChat)
        openBlankChat(sut)
        #expect(!sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Detected with the flag off too, so new chats are counted either way", .timeLimit(.minutes(1)))
    func flagOff() {
        let sut = makeSUT(isFlagOn: false)
        openBlankChat(sut)
        #expect(sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Not once the tab is no longer bound", .timeLimit(.minutes(1)))
    func unbound() {
        let sut = makeSUT()
        openBlankChat(sut)
        sut.unbind()
        #expect(!sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Back on a blank chat from another tab, it is a new chat again", .timeLimit(.minutes(1)))
    func switchBack() async {
        let sut = makeSUT()
        let blankChat = PageScript()
        let otherTab = PageScript()
        sut.activateForTab("tab-A")
        sut.bindToTab(blankChat.script)
        sut.showCollapsed()
        await blankChat.reportResponseState("ready")
        #expect(sut.isGuaranteedNewChat)

        sut.activateForTab("tab-B")
        sut.bindToTab(otherTab.script)
        #expect(!sut.isGuaranteedNewChat)

        sut.activateForTab("tab-A")
        sut.bindToTab(blankChat.script)
        #expect(sut.isGuaranteedNewChat)

        sut.unbind()
        sut.bindToTab(blankChat.script)
        #expect(sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Not while a tab waits for voice to start", .timeLimit(.minutes(1)))
    func voiceRequested() {
        let sut = makeSUT()
        openBlankChat(sut)
        sut.holdNewChatForVoice()
        #expect(!sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Not during voice, nor right after it closes, but once the hold passes", .timeLimit(.minutes(1)))
    func voiceSession() async throws {
        let sut = makeSUT()
        sut.newChatVoiceHoldAfterClose = 0.05
        openBlankChat(sut)
        sut.isVoiceSessionActive = true
        #expect(!sut.isGuaranteedNewChat)

        sut.isVoiceSessionActive = false
        #expect(!sut.isGuaranteedNewChat)

        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new chat button ends a voice hold", .timeLimit(.minutes(1)))
    func newChatEndsVoiceHold() {
        let sut = makeSUT()
        openBlankChat(sut)
        sut.holdNewChatForVoice()
        sut.startNewChat()
        #expect(sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new chat button ends a voice hold while voice is still open", .timeLimit(.minutes(1)))
    func newChatEndsVoiceHoldWhileVoiceIsOpen() {
        let sut = makeSUT()
        openBlankChat(sut)
        sut.holdNewChatForVoice()
        sut.isVoiceSessionActive = true
        sut.startNewChat()
        #expect(sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A reloaded page is not ready until it reports again, and the input reports no made-up state", .timeLimit(.minutes(1)))
    func reloadWaitsForTheNewDocument() async {
        let sut = makeSUT()
        let page = PageScript()
        sut.activateForTab("tab-A")
        sut.bindToTab(page.script)
        sut.showCollapsed()
        await page.reportResponseState("ready")
        #expect(sut.isGuaranteedNewChat)
        var reported: [AIChatStatusValue] = []
        let reporting = sut.aiChatStatusPublisher.dropFirst().sink { reported.append($0) }

        page.commitNewDocument(in: sut, tab: "tab-A")
        #expect(!sut.isGuaranteedNewChat)
        #expect(reported.isEmpty)

        await page.reportResponseState("ready")
        #expect(sut.isGuaranteedNewChat)
        reporting.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("Not for an incoming tab until its own page is bound", .timeLimit(.minutes(1)))
    func incomingTabBeforeItsPageIsBound() async {
        let sut = makeSUT()
        let blankChat = PageScript()
        sut.activateForTab("tab-A")
        sut.bindToTab(blankChat.script)
        sut.showCollapsed()
        await blankChat.reportResponseState("ready")
        #expect(sut.isGuaranteedNewChat)

        // The main view controller activates the incoming tab before it binds that tab's page.
        sut.activateForTab("tab-B")
        #expect(!sut.isGuaranteedNewChat)

        sut.activateForTab("tab-A")
        sut.bindToTab(blankChat.script)
        #expect(sut.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("While a tab switch binds the incoming page, the state never pairs it with the outgoing chat", .timeLimit(.minutes(1)))
    func bindPublishesOnlyTheIncomingChat() async {
        let sut = makeSUT()
        let blankChat = PageScript()
        let historyChat = PageScript()
        sut.activateForTab("tab-B")
        sut.bindToTab(historyChat.script, hasExistingChat: true)
        sut.showCollapsed()
        await historyChat.reportResponseState("ready")
        sut.activateForTab("tab-A")
        sut.bindToTab(blankChat.script)
        await blankChat.reportResponseState("ready")
        #expect(sut.isGuaranteedNewChat)
        var published: [NewChatState] = []
        let publishing = sut.$newChatState.dropFirst().sink { published.append($0) }

        sut.activateForTab("tab-B")
        sut.bindToTab(historyChat.script, hasExistingChat: true)
        #expect(!published.contains { $0.isGuaranteedNewChat })

        published = []
        sut.activateForTab("tab-A")
        sut.bindToTab(blankChat.script)
        #expect(!published.contains { $0.isTabSelected && $0.hasChat })
        #expect(sut.isGuaranteedNewChat)
        publishing.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("The promo is clear only once the page says so", .timeLimit(.minutes(1)))
    func promoClear() {
        let sut = makeSUT()
        openBlankChat(sut)
        #expect(!sut.isAIChatPromoClear)

        sut.isAIChatPromoVisible = true
        #expect(!sut.isAIChatPromoClear)

        sut.isAIChatPromoVisible = false
        #expect(sut.isAIChatPromoClear)
    }
}

/// A tab's script with the real handler, so it remembers what the page reported.
@MainActor
private final class PageScript {
    let handler: AIChatUserScriptHandler
    let script: AIChatUserScript

    init() {
        let featureFlagger = MockFeatureFlagger()
        handler = AIChatUserScriptHandler(experimentalAIChatManager: ExperimentalAIChatManager(featureFlagger: featureFlagger),
                                          syncHandler: MockAIChatSyncHandling(),
                                          bonusHandler: MockAIChatBonusHandling(),
                                          featureFlagger: featureFlagger)
        script = AIChatUserScript(handler: handler, debugSettings: MockAIChatDebugSettingsForTests())
    }

    func reportResponseState(_ status: String) async {
        _ = await handler.getResponseState(params: ["status": status], message: MockUserScriptMessage(name: "test", body: [:]))
    }

    /// What the tab does when its web view commits a new document on this page, such as a reload.
    func commitNewDocument(in input: UnifiedToggleInputCoordinator, tab: TabUID) {
        script.isAIChatPromoVisible = nil
        script.aiChatStatusOnPage = nil
        input.handleNavigationCommit(tabUID: tab, didChangeChat: false)
    }
}

@MainActor
private final class NewChatTestStateStore: UnifiedInputStateStoring {
    private var states: [TabUID: TabInputState] = [:]
    let lastUsed = LastUsedInputDefaults(toggleMode: .aiChat, selectedModelID: nil, selectedReasoningMode: nil, selectedTool: nil)

    func state(for uid: TabUID) -> TabInputState { states[uid] ?? TabInputState(toggleMode: .aiChat) }
    func update(_ state: TabInputState, for uid: TabUID) { states[uid] = state }
    func recordUserChoice(_ state: TabInputState, for uid: TabUID, isNewChatContext: Bool) { states[uid] = state }
    func commitToggleMode(_ mode: TextEntryMode) {}
    func remove(for uid: TabUID) { states.removeValue(forKey: uid) }
}

private final class NewChatTestPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class NewChatTestToggleModeStorage: ToggleModeStoring {
    private var storedMode: TextEntryMode?
    func save(_ mode: TextEntryMode) { storedMode = mode }
    func restore() -> TextEntryMode? { storedMode }
}

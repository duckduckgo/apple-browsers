//
//  NewChatHintsUsageTests.swift
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
import Foundation
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("New chat hints: cap and pixels")
final class NewChatHintsUsageTests {

    private let store = MockThrowingKeyValueStore()
    private let pixels = PixelKitMock()
    private var isFeatureEnabled = true
    private lazy var capStore = NewChatHintsCapStore(keyValueStore: store)
    private lazy var sut = NewChatHintsUsage(capStore: capStore, pixelFiring: pixels, isFeatureEnabled: { [unowned self] in isFeatureEnabled })

    private static let hints: [NewChatHint] = [.photo, .imageGeneration, .documents]

    private var firedNames: [String] { pixels.actualFireCalls.map(\.pixel.name) }

    private func fired(_ name: String) -> [ExpectedFireCall] {
        pixels.actualFireCalls.filter { $0.pixel.name == name }
    }

    /// A new chat where the hints showed and the user typed their own prompt, which turned it into a chat.
    private func ignoreHints(tab: TabUID = "tab", isFireTab: Bool = false) {
        sut.newChatShown(tab: tab, isFireTab: isFireTab)
        sut.hintsShown(Self.hints, tab: tab)
        sut.promptSubmitted(tab: tab, isNewChat: true, prompt: .init())
        sut.leftNewChat(tab: tab)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new chat counts once until the tab leaves it", .timeLimit(.minutes(1)))
    func newChatShownOnce() {
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.newChatShown(tab: "tab", isFireTab: false)
        #expect(fired("aichat_new_chat_shown").count == 1)
        #expect(fired("aichat_new_chat_shown").first?.pixel.parameters == ["newchathints_enabled": "true"])
        sut.leftNewChat(tab: "tab")
        sut.newChatShown(tab: "tab", isFireTab: false)
        #expect(fired("aichat_new_chat_shown").count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new chat counts with the flag off, and says so", .timeLimit(.minutes(1)))
    func newChatShownWithFlagOff() {
        isFeatureEnabled = false
        sut.newChatShown(tab: "tab", isFireTab: false)
        #expect(fired("aichat_new_chat_shown").first?.pixel.parameters == ["newchathints_enabled": "false"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Hints shown fires once per new chat with each hint's 1-based slot", .timeLimit(.minutes(1)))
    func hintsShownOnce() {
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.hintsShown([.photo, .documents], tab: "tab")
        sut.hintsShown([.photo, .documents], tab: "tab")
        let calls = fired("aichat_new_chat_hints_shown")
        #expect(calls.count == 1)
        #expect(calls.first?.pixel.parameters == ["photo_position": "1", "documents_position": "2", "image_generation_position": "0"])
        #expect(calls.first?.frequency == .dailyAndCount)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A tap reports the hint and its 1-based slot", .timeLimit(.minutes(1)))
    func hintTapped() {
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.hintTapped(.imageGeneration, position: 2, tab: "tab")
        #expect(fired("aichat_new_chat_hint_tapped").first?.pixel.parameters == ["hint": "image_generation", "position": "2"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("The first prompt reports what the new chat saw and sent", .timeLimit(.minutes(1)))
    func firstPromptParameters() {
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.hintsShown(Self.hints, tab: "tab")
        sut.hintTapped(.photo, position: 1, tab: "tab")
        sut.promptSubmitted(tab: "tab", isNewChat: true,
                            prompt: .init(hasImageAttachment: true, hasFileAttachment: false, selectedTool: .webSearch))
        #expect(fired("aichat_new_chat_first_prompt_sent").first?.pixel.parameters == [
            "newchathints_enabled": "true",
            "hints_shown": "true",
            "hint_tapped": "photo",
            "has_image_attachment": "true",
            "has_file_attachment": "false",
            "selected_tool": "web_search",
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only the first prompt of a counted new chat reports", .timeLimit(.minutes(1)))
    func onlyFirstPrompt() {
        sut.promptSubmitted(tab: "tab", isNewChat: true, prompt: .init())
        ignoreHints()
        sut.promptSubmitted(tab: "tab", isNewChat: true, prompt: .init())
        #expect(fired("aichat_new_chat_first_prompt_sent").count == 1)
        #expect(fired("aichat_new_chat_first_prompt_sent").first?.pixel.parameters?["hint_tapped"] == "none")
    }

    @available(iOS 16, macOS 13, *)
    @Test("The chat still looking new right after its prompt doesn't count as another one", .timeLimit(.minutes(1)))
    func blankMomentAfterSubmit() {
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.hintsShown(Self.hints, tab: "tab")
        sut.promptSubmitted(tab: "tab", isNewChat: true, prompt: .init())
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.hintsShown(Self.hints, tab: "tab")
        sut.promptSubmitted(tab: "tab", isNewChat: true, prompt: .init())
        #expect(fired("aichat_new_chat_shown").count == 1)
        #expect(fired("aichat_new_chat_first_prompt_sent").count == 1)
        #expect(capStore.ignoredChats == 1)
        sut.leftNewChat(tab: "tab")
        sut.newChatShown(tab: "tab", isFireTab: false)
        #expect(fired("aichat_new_chat_shown").count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt outside a new chat drops the chat without reporting", .timeLimit(.minutes(1)))
    func promptOutsideNewChat() {
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.hintsShown(Self.hints, tab: "tab")
        sut.promptSubmitted(tab: "tab", isNewChat: false, prompt: .init())
        #expect(fired("aichat_new_chat_first_prompt_sent").isEmpty)
        #expect(capStore.ignoredChats == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt after the hints showed adds one ignored chat", .timeLimit(.minutes(1)))
    func displayedCounts() {
        ignoreHints()
        #expect(capStore.ignoredChats == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Opening a new chat and leaving it doesn't count", .timeLimit(.minutes(1)))
    func openingDoesNotCount() {
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.hintsShown(Self.hints, tab: "tab")
        sut.leftNewChat(tab: "tab")
        #expect(capStore.ignoredChats == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt in a chat where hints never showed doesn't count", .timeLimit(.minutes(1)))
    func notShownDoesNotCount() {
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.promptSubmitted(tab: "tab", isNewChat: true, prompt: .init())
        #expect(capStore.ignoredChats == 0)
        #expect(fired("aichat_new_chat_first_prompt_sent").first?.pixel.parameters?["hints_shown"] == "false")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A tap resets the count", .timeLimit(.minutes(1)))
    func tapResets() {
        ignoreHints()
        ignoreHints()
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.hintsShown(Self.hints, tab: "tab")
        sut.hintTapped(.documents, position: 3, tab: "tab")
        sut.promptSubmitted(tab: "tab", isNewChat: true, prompt: .init())
        #expect(capStore.ignoredChats == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A promo covering the hints means the prompt didn't ignore them", .timeLimit(.minutes(1)))
    func promoClearsDisplayed() {
        sut.newChatShown(tab: "tab", isFireTab: false)
        sut.hintsShown(Self.hints, tab: "tab")
        sut.promoShown(tab: "tab")
        sut.promptSubmitted(tab: "tab", isNewChat: true, prompt: .init())
        #expect(capStore.ignoredChats == 0)
        #expect(fired("aichat_new_chat_first_prompt_sent").first?.pixel.parameters?["hints_shown"] == "true")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fire tabs show hints and report pixels but never move the count", .timeLimit(.minutes(1)))
    func fireTabsDoNotCount() {
        ignoreHints()
        ignoreHints(tab: "fire", isFireTab: true)
        #expect(capStore.ignoredChats == 1)
        sut.newChatShown(tab: "fire", isFireTab: true)
        sut.hintsShown(Self.hints, tab: "fire")
        sut.hintTapped(.photo, position: 1, tab: "fire")
        sut.promptSubmitted(tab: "fire", isNewChat: true, prompt: .init())
        #expect(capStore.ignoredChats == 1)
        #expect(fired("aichat_new_chat_first_prompt_sent").count == 3)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The cap is reached at 5 ignored chats and its pixel fires exactly then", .timeLimit(.minutes(1)))
    func capReachedAtFive() {
        for _ in 1...4 { ignoreHints() }
        #expect(!sut.isCapReached)
        #expect(fired("aichat_new_chat_hints_cap_reached_u").isEmpty)
        ignoreHints()
        #expect(sut.isCapReached)
        #expect(fired("aichat_new_chat_hints_cap_reached_u").count == 1)
        #expect(fired("aichat_new_chat_hints_cap_reached_u").first?.frequency == .uniqueByName)
        // A later ignored chat (say the limit was raised) doesn't report it again.
        ignoreHints()
        #expect(fired("aichat_new_chat_hints_cap_reached_u").count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The dev reset brings the hints back", .timeLimit(.minutes(1)))
    func resetClearsCap() {
        for _ in 1...5 { ignoreHints() }
        capStore.reset()
        #expect(!sut.isCapReached)
        #expect(capStore.ignoredChats == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Tabs are followed separately", .timeLimit(.minutes(1)))
    func tabsAreSeparate() {
        sut.newChatShown(tab: "A", isFireTab: false)
        sut.hintsShown(Self.hints, tab: "A")
        sut.newChatShown(tab: "B", isFireTab: false)
        sut.hintTapped(.photo, position: 1, tab: "A")
        sut.promptSubmitted(tab: "B", isNewChat: true, prompt: .init())
        #expect(fired("aichat_new_chat_first_prompt_sent").first?.pixel.parameters?["hint_tapped"] == "none")
        #expect(fired("aichat_new_chat_shown").count == 2)
    }
}

@Suite("New chat hints: order and capability")
struct NewChatHintOrderTests {

    @available(iOS 16, macOS 13, *)
    @Test("Hints show best first: image generation, photos, then files", .timeLimit(.minutes(1)))
    func fixedBestFirstOrder() {
        #expect(NewChatHint.displayOrder == [.imageGeneration, .photo, .documents])
        #expect(Set(NewChatHint.displayOrder) == Set(NewChatHint.allCases))
    }

    private static func model(_ id: String, access: Bool = true, images: Bool = false, files: Bool = false,
                              imageGeneration: Bool = false) -> AIChatModel {
        AIChatModel(id: id, name: id, provider: .unknown, supportsImageUpload: images,
                    supportedFileTypes: files ? ["application/pdf"] : [],
                    supportedTools: imageGeneration ? [.imageGeneration] : [],
                    entityHasAccess: access)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A hint uses the selected model when it can", .timeLimit(.minutes(1)))
    func selectedModelPreferred() {
        let models = [Self.model("a", images: true), Self.model("b", images: true)]
        #expect(NewChatHint.capableModel(for: .photo, in: models, selectedModelID: "b")?.id == "b")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A hint falls back to the first accessible model that can", .timeLimit(.minutes(1)))
    func fallsBackToCapableModel() {
        let models = [Self.model("plain"), Self.model("locked", access: false, files: true), Self.model("docs", files: true)]
        #expect(NewChatHint.capableModel(for: .documents, in: models, selectedModelID: "plain")?.id == "docs")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A hint no accessible model supports is hidden", .timeLimit(.minutes(1)))
    func noCapableModel() {
        let models = [Self.model("plain"), Self.model("locked", access: false, imageGeneration: true)]
        #expect(NewChatHint.capableModel(for: .imageGeneration, in: models, selectedModelID: "plain") == nil)
        #expect(NewChatHint.capableModel(for: .photo, in: [], selectedModelID: nil) == nil)
    }
}

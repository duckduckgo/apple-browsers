//
//  AIChatSelectionActionPageContextTests.swift
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
import AppKit
import Combine
import Navigation
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// Selection-based Duck.ai actions (summarize, translate) must tell the page context extension to
/// skip auto-attaching the whole page — the selection is the context. The extension's own decision
/// is covered by `ContextCollectionEnabledTests`.
@MainActor
final class AIChatSelectionActionPageContextTests: XCTestCase {

    private var config: DummyAIChatConfig!
    private var coordinator: SelectionActionAIChatCoordinatorMock!
    private var pageContext: PageContextMock!

    override func setUp() {
        super.setUp()
        config = DummyAIChatConfig()
        config.shouldDisplaySummarizationMenuItem = true
        config.shouldDisplayTranslationMenuItem = true
        coordinator = SelectionActionAIChatCoordinatorMock()
        pageContext = PageContextMock()
    }

    func testSummarizeSuppressesAutoPageContext() {
        makeSummarizer().summarize(.init(text: "selected", websiteURL: URL(string: "https://example.com"), websiteTitle: "Example", source: .contextMenu))

        XCTAssertEqual(pageContext.suppressCallCount, 1)
        XCTAssertEqual(coordinator.revealChatWithPromptCallCount, 1)
    }

    func testTranslateSuppressesAutoPageContext() {
        makeTranslator().translate(.init(text: "selected", websiteURL: URL(string: "https://example.com"), websiteTitle: "Example", websiteTLD: "example.com", sourceLanguage: "en"))

        XCTAssertEqual(pageContext.suppressCallCount, 1)
        XCTAssertEqual(coordinator.revealChatWithPromptCallCount, 1)
    }

    /// The gating decision belongs to the extension, so the actions delegate unconditionally —
    /// including when the sidebar is already up.
    func testSummarizeStillDelegatesWhenChatAlreadyPresented() {
        coordinator.isChatPresented = true
        makeSummarizer().summarize(.init(text: "selected", websiteURL: nil, websiteTitle: nil, source: .keyboardShortcut))

        XCTAssertEqual(pageContext.suppressCallCount, 1)
    }

    func testSummarizeDoesNothingWhenMenuItemDisabled() {
        config.shouldDisplaySummarizationMenuItem = false
        makeSummarizer().summarize(.init(text: "selected", websiteURL: nil, websiteTitle: nil, source: .contextMenu))

        XCTAssertEqual(pageContext.suppressCallCount, 0)
        XCTAssertEqual(coordinator.revealChatWithPromptCallCount, 0)
    }

    // MARK: - Factories

    private func makeSummarizer() -> AIChatSummarizer {
        AIChatSummarizer(aiChatMenuConfig: config,
                         aiChatCoordinator: coordinator,
                         aiChatTabOpener: SelectionActionAIChatTabOpenerMock(),
                         pixelFiring: nil,
                         currentPageContextProvider: { [pageContext] in pageContext },
                         aiChatConversationSourceHandler: AIChatConversationSourceHandler())
    }

    private func makeTranslator() -> AIChatTranslator {
        AIChatTranslator(aiChatMenuConfig: config,
                         aiChatCoordinator: coordinator,
                         aiChatTabOpener: SelectionActionAIChatTabOpenerMock(),
                         pixelFiring: nil,
                         currentPageContextProvider: { [pageContext] in pageContext },
                         aiChatConversationSourceHandler: AIChatConversationSourceHandler())
    }

}

// MARK: - Mocks

@MainActor
private final class PageContextMock: PageContextProtocol {
    var appendSelectionContextCallCount = 0
    var suppressCallCount = 0
    var requestPageContextAttachmentCallCount = 0

    func appendSelectionContext(_ selection: AIChatSelectionContextData) {
        appendSelectionContextCallCount += 1
    }

    func suppressAutoPageContextForSelectionAction() {
        suppressCallCount += 1
    }

    func requestPageContextAttachment() {
        requestPageContextAttachmentCallCount += 1
    }
}

private final class SelectionActionAIChatCoordinatorMock: AIChatCoordinating {
    var isChatPresented = false
    var revealChatWithPromptCallCount = 0
    var revealChatCallCount = 0

    func toggleSidebar() {}
    func collapseSidebar(withAnimation: Bool) {}
    func isSidebarOpen(for tabID: TabIdentifier) -> Bool { isChatPresented }
    func isSidebarOpenForCurrentTab() -> Bool { isChatPresented }
    func isChatPresentedForCurrentTab() -> Bool { isChatPresented }
    func sidebarHiddenAt(for tabID: TabIdentifier) -> Date? { nil }
    func sidebarHiddenAtForCurrentTab() -> Date? { nil }
    var sidebarPresenceDidChangePublisher: AnyPublisher<AIChatPresenceChange, Never> { Empty().eraseToAnyPublisher() }
    func isChatFloating(for tabID: TabIdentifier) -> Bool { false }
    var chatFloatingStateDidChangePublisher: AnyPublisher<TabIdentifier, Never> { Empty().eraseToAnyPublisher() }
    func focusFloatingWindow(for tabID: TabIdentifier) {}
    func closeFloatingWindow(for tabID: TabIdentifier) {}
    func closeChat(for tabID: TabIdentifier, withAnimation: Bool) {}
    func revealChat(for prompt: AIChatNativePrompt) { revealChatWithPromptCallCount += 1 }
    func revealChat() { revealChatCallCount += 1 }
}

private struct SelectionActionAIChatTabOpenerMock: AIChatTabOpening {
    func openAIChatTab(with trigger: AIChatOpenTrigger, behavior: LinkOpenBehavior) {}
    func openNewAIChat(in linkOpenBehavior: LinkOpenBehavior) {}
    func openVoiceSession(inSourceCollection sourceCollection: TabCollectionViewModel?, behavior: LinkOpenBehavior) {}
    func openAIChatTab(withQuery query: String, inNewTabOf windowController: MainWindowController) {}
    func openAIChatTab(withQuery query: String, inNewWindowAt droppingPoint: NSPoint) {}
}

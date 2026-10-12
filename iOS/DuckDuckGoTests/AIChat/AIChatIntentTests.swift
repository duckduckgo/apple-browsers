//
//  AIChatIntentTests.swift
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

import XCTest
import AIChat
import UIKit
@testable import Core
@testable import DuckDuckGo

@available(iOS 17.0, *)
@MainActor
final class AIChatIntentTests: XCTestCase {

    func testWhenQuestionIsUnsetThenIntentUsesOriginalDeepLink() {
        XCTAssertEqual(AIChatIntent().deepLinkURL, AppDeepLinkSchemes.openAIChat.url)
    }

    func testWhenQuestionContainsReservedCharactersThenDeepLinkPreservesQuestion() {
        let prompt = "Why is 2 + 2 = 4? & # / % \n你好"
        let intent = AIChatIntent()
        intent.prompt = prompt

        XCTAssertEqual(intent.deepLinkURL.getParameter(named: "prompt"), prompt)
        XCTAssertEqual(AppDeepLinkSchemes.fromURL(intent.deepLinkURL), .openAIChat)
        XCTAssertNil(intent.deepLinkURL.fragment)
    }

    func testWhenShortcutHasQuestionThenChatAutoSendsAfterDismissal() {
        let intent = AIChatIntent()
        intent.prompt = "Explain 2 + 2 & 你好"
        let presenter = MockAIChatShortcutPresenter()

        AIChatDeepLinkHandler().handleDeepLink(intent.deepLinkURL, on: presenter)

        XCTAssertEqual(presenter.textChatOpenCount, 0)
        presenter.dismissCompletion?()
        XCTAssertEqual(presenter.textChatOpenCount, 1)
        XCTAssertEqual(presenter.query, intent.prompt)
        XCTAssertTrue(presenter.autoSend)
        XCTAssertTrue(presenter.fromDeepLink)
        XCTAssertEqual(presenter.source, .deepLinkOther)
    }

    func testWhenDeepLinkHasNoQuestionThenChatOpensWithoutAutoSend() {
        assertBlankChat(url: AppDeepLinkSchemes.openAIChat.url)
    }

    func testWhenDeepLinkHasEmptyQuestionThenChatOpensWithoutAutoSend() {
        assertBlankChat(url: AppDeepLinkSchemes.openAIChat.url.appendingParameter(name: "prompt", value: ""))
    }

    func testWhenDeepLinkHasWhitespaceQuestionThenChatOpensWithoutAutoSend() {
        assertBlankChat(url: AppDeepLinkSchemes.openAIChat.url.appendingParameter(name: "prompt", value: " \n\t "))
    }

    func testWhenDeepLinkHasQuestionThenWhitespaceIsTrimmedAndSourceIsPreserved() {
        let url = AppDeepLinkSchemes.openAIChat.url
            .appendingParameter(name: "prompt", value: " \nHello\t ")
            .appendingParameter(name: "source", value: "siri")
        let presenter = MockAIChatShortcutPresenter()

        AIChatDeepLinkHandler().handleDeepLink(url, on: presenter)
        presenter.dismissCompletion?()

        XCTAssertEqual(presenter.query, "Hello")
        XCTAssertTrue(presenter.autoSend)
        XCTAssertEqual(presenter.source, .siri)
    }

    func testWhenVoiceDeepLinkHasQuestionThenOnlyVoiceChatOpens() {
        let url = AppDeepLinkSchemes.openAIVoiceChat.url.appendingParameter(name: "prompt", value: "Hello")
        let presenter = MockAIChatShortcutPresenter()

        AIChatDeepLinkHandler().handleDeepLink(url, on: presenter, voiceMode: true)
        presenter.dismissCompletion?()

        XCTAssertEqual(presenter.voiceChatOpenCount, 1)
        XCTAssertEqual(presenter.textChatOpenCount, 0)
    }

    private func assertBlankChat(url: URL, file: StaticString = #filePath, line: UInt = #line) {
        let presenter = MockAIChatShortcutPresenter()

        AIChatDeepLinkHandler().handleDeepLink(url, on: presenter)
        presenter.dismissCompletion?()

        XCTAssertEqual(presenter.textChatOpenCount, 1, file: file, line: line)
        XCTAssertNil(presenter.query, file: file, line: line)
        XCTAssertFalse(presenter.autoSend, file: file, line: line)
        XCTAssertTrue(presenter.fromDeepLink, file: file, line: line)
    }
}

private final class MockAIChatShortcutPresenter: UIViewController, AIChatDeepLinkPresenting {
    var dismissCompletion: (() -> Void)?
    var textChatOpenCount = 0
    var voiceChatOpenCount = 0
    var query: String?
    var autoSend = false
    var fromDeepLink = false
    var source: AIChatEntryPointSource?

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissCompletion = completion
    }

    func openAIVoiceChatFromDeepLink(source: AIChatEntryPointSource) {
        voiceChatOpenCount += 1
        self.source = source
    }

    func openAIChat(source: AIChatEntryPointSource,
                    _ query: String?,
                    autoSend: Bool,
                    payload: Any?,
                    flowType: AIChatOnboardingFlowType,
                    tools: [AIChatRAGTool]?,
                    modelId: String?,
                    reasoningEffort: AIChatReasoningEffort?,
                    images: [AIChatNativePrompt.NativePromptImage]?,
                    files: [AIChatNativePrompt.NativePromptFile]?,
                    reportsNewTab: Bool?,
                    forcesNewTab: Bool,
                    fromDeepLink: Bool) {
        textChatOpenCount += 1
        self.query = query
        self.autoSend = autoSend
        self.fromDeepLink = fromDeepLink
        self.source = source
    }
}

//
//  AIChatUserScriptOpenChatTests.swift
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
import JavaScriptCore
import UserScript
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatUserScriptOpenChatTests: XCTestCase {
    private let webView = OpenChatRecordingWebView()
    private let broker = UserScriptMessageBroker(context: "aiChat", requiresRunInPageContentWorld: true)

    func testWhenOpeningAChatThenThePageGetsItsIdInTheOpenChatPush() async throws {
        let script = makeScript()

        let outcome = await open("chat-1", in: script, reply: ["chatId": "chat-1", "status": "opened"])

        XCTAssertEqual(webView.openChatPushes.map { $0["chatId"] as? String }, ["chat-1"])
        XCTAssertEqual(outcome, .opened)
    }

    func testWhenThePageReportsNotFoundThenTheOutcomeIsNotFound() async throws {
        let outcome = await open("chat-1", in: makeScript(), reply: ["chatId": "chat-1", "status": "notFound"])

        XCTAssertEqual(outcome, .notFound)
    }

    func testWhenThePageReportsAnUnknownStatusThenTheOutcomeIsFailed() async throws {
        let outcome = await open("chat-1", in: makeScript(), reply: ["chatId": "chat-1", "status": "somethingNew"])

        XCTAssertEqual(outcome, .failed)
    }

    func testWhenTheReplyIsForAnotherChatThenItIsIgnoredAndTheOpenTimesOut() async throws {
        let script = makeScript()
        script.openChatReplyTimeout = 0

        let outcome = await open("chat-1", in: script, reply: ["chatId": "chat-2", "status": "opened"])

        XCTAssertNil(outcome)
    }

    func testWhenThePageNeverRepliesThenTheOpenTimesOut() async {
        let script = makeScript()
        script.openChatReplyTimeout = 0

        let outcome = await script.openChat(chatId: "chat-1")

        XCTAssertNil(outcome)
    }

    func testWhenASecondChatIsOpenedBeforeTheReplyThenTheFirstOpenEndsWithoutAnOutcome() async throws {
        let script = makeScript()
        let firstPushed = expectation(description: "First open pushed")
        webView.onOpenChatPush = { _ in firstPushed.fulfill() }
        let first = Task { await script.openChat(chatId: "chat-1") }
        await fulfillment(of: [firstPushed], timeout: 1)
        webView.onOpenChatPush = nil

        let second = await open("chat-2", in: script, reply: ["chatId": "chat-2", "status": "opened"])

        let firstOutcome = await first.value
        XCTAssertNil(firstOutcome)
        XCTAssertEqual(second, .opened)
    }

    func testWhenThereIsNoWebViewThenNothingIsPushedAndThereIsNoOutcome() async {
        let script = makeScript()
        script.webView = nil

        let outcome = await script.openChat(chatId: "chat-1")

        XCTAssertNil(outcome)
        XCTAssertTrue(webView.openChatPushes.isEmpty)
    }

    // MARK: - Helpers

    private func makeScript() -> AIChatUserScript {
        let script = AIChatUserScript(handler: MockAIChatUserScriptHandling(), debugSettings: MockAIChatDebugSettingsForTests())
        script.webView = webView
        script.broker = broker
        return script
    }

    /// Opens `chatId` and answers the push with `reply` once the page receives it.
    private func open(_ chatId: String, in script: AIChatUserScript, reply: [String: Any]) async -> AIChatOpenChatOutcome? {
        webView.onOpenChatPush = { _ in
            Task { @MainActor in
                guard let handler = script.handler(forMethodNamed: AIChatUserScriptMessages.openChatActionHandled.rawValue) else {
                    return XCTFail("No handler for openChatActionHandled")
                }
                _ = try? await handler(reply, WKScriptMessage())
            }
        }
        return await script.openChat(chatId: chatId)
    }
}

private final class OpenChatRecordingWebView: WKWebView {
    private(set) var openChatPushes: [[String: Any]] = []
    var onOpenChatPush: (([String: Any]) -> Void)?
    private let javaScriptContext = JSContext()!

    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        javaScriptContext.evaluateScript("""
            var capturedOpenChat = null;
            var navigator = { duckduckgo: { messageHandlers: {
                submitOpenChatAction: function(event) { capturedOpenChat = event.params; }
            } } };
            """)
        javaScriptContext.evaluateScript(javaScriptString)
        if let error = javaScriptContext.exception {
            XCTFail("Bridge JavaScript failed: \(error)")
        }
        if let params = javaScriptContext.objectForKeyedSubscript("capturedOpenChat")?.toDictionary() as? [String: Any] {
            openChatPushes.append(params)
            onOpenChatPush?(params)
        }
        completionHandler?(nil, nil)
    }
}

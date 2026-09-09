//
//  AIChatUserScriptMultiTabTests.swift
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
import FeatureFlags_iOS
import JavaScriptCore
import UserScript
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatUserScriptMultiTabTests: XCTestCase {
    private let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatContextualAttachMoreTabs])
    private let webView = PromptRecordingWebView()
    private let broker = UserScriptMessageBroker(context: "aiChat", requiresRunInPageContentWorld: true)
    private var requestProvider: (() -> MultiTabAttachmentRequest?)?

    func testNoRequestKeepsSingleCurrentPagePayload() async throws {
        let script = makeScript()
        let page = context()
        script.attachedPageContextProvider = { page }

        let prompt = await dispatch(script)

        XCTAssertEqual(prompt, .queryPrompt("hello", autoSubmit: true, pageContext: .single(page)))
    }

    func testEmptyContextsWithoutCurrentPageOmitsPageContext() async throws {
        let script = makeScript()
        var consumed = false
        requestProvider = { MultiTabAttachmentRequest(contexts: { [] }, didConsume: { consumed = true }) }

        let prompt = await dispatch(script)
        let json = try XCTUnwrap(webView.payloads.last)

        XCTAssertNil(prompt?.pageContext)
        XCTAssertNil(json["pageContext"])
        XCTAssertTrue(consumed)
    }

    func testEmptyContextsKeepsSingleCurrentPageObject() async throws {
        let script = makeScript()
        let page = context()
        script.attachedPageContextProvider = { page }
        requestProvider = { MultiTabAttachmentRequest(contexts: { [] }, didConsume: {}) }

        let prompt = await dispatch(script)
        let json = try XCTUnwrap(webView.payloads.last)

        XCTAssertEqual(prompt?.pageContext, .single(page))
        XCTAssertNotNil(json["pageContext"] as? [String: Any])
    }

    func testOneAdditionalTabUsesArrayAndPreservesIdentity() async throws {
        let script = makeScript()
        let tab = context(tabId: "tab-one")
        requestProvider = { MultiTabAttachmentRequest(contexts: { [tab] }, didConsume: {}) }

        let prompt = await dispatch(script)
        let json = try XCTUnwrap(webView.payloads.last)
        let entries = try XCTUnwrap(json["pageContext"] as? [[String: Any]])

        XCTAssertEqual(prompt?.pageContext, .multiple([tab]))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?["tabId"] as? String, "tab-one")
    }

    func testMultipleTabsKeepProviderOrderAndSameAddressTabsRemainDistinct() async {
        let script = makeScript()
        let tabs = [context(tabId: "second"), context(tabId: "first")]
        requestProvider = { MultiTabAttachmentRequest(contexts: { tabs }, didConsume: {}) }

        let prompt = await dispatch(script)

        XCTAssertEqual(prompt?.pageContext, .multiple(tabs))
    }

    func testCurrentPageGoesFirstWithoutTabIdentity() async throws {
        let script = makeScript()
        let page = context(tabId: "current")
        let tab = context(tabId: "other")
        script.attachedPageContextProvider = { page }
        requestProvider = { MultiTabAttachmentRequest(contexts: { [tab] }, didConsume: {}) }

        let prompt = await dispatch(script)
        let json = try XCTUnwrap(webView.payloads.last)
        let entries = try XCTUnwrap(json["pageContext"] as? [[String: Any]])

        XCTAssertEqual(prompt?.pageContext, .multiple([page.withTabId(nil), tab]))
        XCTAssertNil(entries.first?["tabId"])
        XCTAssertEqual(entries.last?["tabId"] as? String, "other")
    }

    func testCurrentPageFromRequestIsPreservedWithoutSeparateProvider() async {
        let script = makeScript()
        let contexts = [context(tabId: "other"), context()]
        requestProvider = { MultiTabAttachmentRequest(contexts: { contexts }, didConsume: {}) }

        let prompt = await dispatch(script)

        XCTAssertEqual(prompt?.pageContext, .multiple(contexts))
    }

    func testSeparateCurrentPageTakesPrecedenceOverDuplicateRequestEntry() async {
        let script = makeScript()
        let page = context(content: "current")
        let tab = context(tabId: "other")
        script.attachedPageContextProvider = { page }
        requestProvider = {
            MultiTabAttachmentRequest(contexts: { [self.context(content: "duplicate"), tab] }, didConsume: {})
        }

        let prompt = await dispatch(script)

        XCTAssertEqual(prompt?.pageContext, .multiple([page, tab]))
    }

    func testDisabledFeatureDoesNotInvokeAdditionalContextProvider() async {
        featureFlagger.enabledFeatureFlags = []
        let script = makeScript()
        let page = context()
        script.attachedPageContextProvider = { page }
        requestProvider = {
            XCTFail("Disabled feature must not invoke the request provider")
            return nil
        }
        var submitted = false
        script.onPromptSubmitted = { submitted = true }
        let delivered = expectation(description: "Legacy prompt dispatched")
        webView.onPrompt = { _ in delivered.fulfill() }

        script.submitPrompt("hello", images: nil, modelId: nil)

        XCTAssertTrue(submitted, "Legacy submission remains synchronous")
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(webView.prompts.last?.pageContext, .single(page))
        XCTAssertEqual(featureFlagger.updatesPublisherSubscriptionCount, 0)
    }

    func testDisablingFeatureWhileWaitingDiscardsOnlyAdditionalContexts() async {
        let script = makeScript()
        let page = context()
        let gate = ContextGate(started: expectation(description: "Provider started"))
        var consumed = false
        script.attachedPageContextProvider = { page }
        requestProvider = { MultiTabAttachmentRequest(contexts: { await gate.wait() }, didConsume: { consumed = true }) }
        let delivered = expectation(description: "Prompt dispatched")
        webView.onPrompt = { _ in delivered.fulfill() }

        script.submitPrompt("hello", images: nil, modelId: nil)
        await fulfillment(of: [gate.started], timeout: 1)
        featureFlagger.enabledFeatureFlags = []
        gate.resume([context(tabId: "other")])
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(webView.prompts.last?.pageContext, .single(page))
        XCTAssertFalse(consumed)
    }

    func testDisablingFeatureBeforeWaitingDoesNotInvokeContextProvider() async {
        let script = makeScript()
        let page = context()
        script.attachedPageContextProvider = { page }
        requestProvider = {
            MultiTabAttachmentRequest(contexts: {
                XCTFail("Disabled feature must not invoke the context provider")
                return []
            }, didConsume: { XCTFail("Disabled contexts must not be consumed") })
        }
        let delivered = expectation(description: "Prompt dispatched without additional contexts")
        webView.onPrompt = { _ in delivered.fulfill() }

        script.submitPrompt("hello", images: nil, modelId: nil)
        featureFlagger.enabledFeatureFlags = []
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(webView.prompts.last?.pageContext, .single(page))
    }

    func testRichPromptCapturesSelectionsAndCurrentPageBeforeWaiting() async {
        let script = makeScript()
        let gate = ContextGate(started: expectation(description: "Provider started"))
        let page = context(content: "original")
        let tab = context(tabId: "other")
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "original selection", url: nil)
        var selectedPage = page
        var selections = [selection]
        var consumedSelections: [String] = []
        var consumed = false
        var submitted = false
        script.attachedPageContextProvider = { selectedPage }
        script.attachedSelectionsProvider = { selections }
        script.onAttachedSelectionsConsumed = { consumedSelections = $0 }
        script.onPromptSubmitted = { submitted = true }
        requestProvider = { MultiTabAttachmentRequest(contexts: { await gate.wait() }, didConsume: { consumed = true }) }
        let images = [AIChatNativePrompt.NativePromptImage(data: "image", format: "png")]
        let files = [AIChatNativePrompt.NativePromptFile(data: "file", fileName: "file.txt", mimeType: "text/plain")]
        let delivered = expectation(description: "Rich prompt dispatched")
        webView.onPrompt = { _ in delivered.fulfill() }

        script.submitPrompt("hello", images: images, files: files, modelId: "model", tools: [.webSearch], reasoningEffort: .high)
        await fulfillment(of: [gate.started], timeout: 1)
        XCTAssertFalse(consumed)
        XCTAssertFalse(submitted)
        XCTAssertTrue(consumedSelections.isEmpty)
        selectedPage = context(content: "new")
        selections = []
        gate.resume([tab])
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(webView.prompts.last, .queryPrompt(
            "hello", autoSubmit: true, toolChoice: [AIChatRAGTool.webSearch.rawValue], images: images, files: files,
            modelId: "model", pageContext: .multiple([page, tab]), selections: [selection], reasoningEffort: .high))
        XCTAssertEqual(consumedSelections, [selection.id])
        XCTAssertTrue(consumed)
        XCTAssertTrue(submitted)
    }

    func testPlainPromptUsesExplicitPageContextAndSuppliedTabs() async {
        let script = makeScript()
        let page = context()
        let tab = context(tabId: "other")
        requestProvider = { MultiTabAttachmentRequest(contexts: { [tab] }, didConsume: {}) }
        let delivered = expectation(description: "Plain prompt dispatched")
        webView.onPrompt = { _ in delivered.fulfill() }

        script.submitPrompt("hello", pageContext: page, modelId: "model", reasoningEffort: .low)
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(webView.prompts.last, .queryPrompt(
            "hello", autoSubmit: true, modelId: "model", pageContext: .multiple([page, tab]), reasoningEffort: .low))
    }

    func testSecondPromptWaitsForFirstEvenWithoutAdditionalContexts() async {
        let script = makeScript()
        let gate = ContextGate(started: expectation(description: "First provider started"))
        var requestCount = 0
        requestProvider = {
            requestCount += 1
            return requestCount == 1 ? MultiTabAttachmentRequest(contexts: { await gate.wait() }, didConsume: {}) : nil
        }
        let delivered = expectation(description: "Both prompts dispatched")
        delivered.expectedFulfillmentCount = 2
        webView.onPrompt = { _ in delivered.fulfill() }

        script.submitPrompt("first", images: nil, modelId: nil)
        await fulfillment(of: [gate.started], timeout: 1)
        script.submitPrompt("second", images: nil, modelId: nil)
        XCTAssertTrue(webView.prompts.isEmpty)
        gate.resume([])
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(webView.prompts, [.queryPrompt("first", autoSubmit: true), .queryPrompt("second", autoSubmit: true)])
    }

    func testExplicitCancellationDropsLateResult() async {
        await assertLateResultIsDropped { $0.cancelPendingTabContextSubmission() }
    }

    func testNewChatDropsLateResult() async {
        await assertLateResultIsDropped { $0.submitStartChatAction() }
    }

    func testFrontendNewChatDropsLateResult() async {
        await assertLateResultIsDropped { _ = $0.handler(forMethodNamed: AIChatUserScriptMessages.newChatStarted.rawValue) }
    }

    func testNewChatDiscardsQueuedPromptsAndDoesNotWaitForOldProvider() async {
        let script = makeScript()
        let gate = ContextGate(started: expectation(description: "First provider started"))
        var requestCount = 0
        requestProvider = {
            requestCount += 1
            if requestCount == 1 {
                return MultiTabAttachmentRequest(contexts: { await gate.wait() }, didConsume: { XCTFail("Old request consumed") })
            }
            return MultiTabAttachmentRequest(contexts: {
                XCTFail("Cancelled queued request must not invoke its context provider")
                return []
            }, didConsume: { XCTFail("Queued request consumed") })
        }
        script.submitPrompt("old", images: nil, modelId: nil)
        await fulfillment(of: [gate.started], timeout: 1)
        script.submitPrompt("queued", images: nil, modelId: nil)

        script.submitStartChatAction()
        requestProvider = nil
        let newPrompt = await dispatch(script)
        XCTAssertEqual(newPrompt, .queryPrompt("hello", autoSubmit: true))

        let unexpected = expectation(description: "Old queue remains cancelled")
        unexpected.isInverted = true
        webView.onPrompt = { _ in unexpected.fulfill() }
        gate.resume([context(tabId: "old-tab")])
        await fulfillment(of: [unexpected], timeout: 0.1)
        XCTAssertEqual(webView.prompts.count, 1)
    }

    func testPendingProviderDoesNotKeepUserScriptAlive() async {
        var script: AIChatUserScript? = makeScript()
        weak var weakScript = script
        let gate = ContextGate(started: expectation(description: "Provider started"))
        let unexpected = expectation(description: "Released script does not dispatch")
        unexpected.isInverted = true
        webView.onPrompt = { _ in unexpected.fulfill() }
        requestProvider = {
            MultiTabAttachmentRequest(contexts: { await gate.wait() }, didConsume: { unexpected.fulfill() })
        }
        script?.submitPrompt("old", images: nil, modelId: nil)
        await fulfillment(of: [gate.started], timeout: 1)

        script = nil
        XCTAssertNil(weakScript)
        gate.resume([context(tabId: "other")])
        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    func testReplacingWebViewDropsLateResult() async {
        let replacement = PromptRecordingWebView()
        await assertLateResultIsDropped { $0.webView = replacement }
        XCTAssertTrue(replacement.prompts.isEmpty)
    }

    func testLosingBridgeDoesNotConsumeRequest() async {
        await assertLateResultIsDropped { $0.broker = nil }
    }

    func testUnavailableBridgeDoesNotConsumeSuppliedContexts() async {
        let script = makeScript()
        script.broker = nil
        let provided = expectation(description: "Contexts supplied")
        let unexpected = expectation(description: "Dropped push does not consume")
        unexpected.isInverted = true
        script.onPromptSubmitted = { unexpected.fulfill() }
        let tab = context(tabId: "other")
        requestProvider = {
            MultiTabAttachmentRequest(contexts: {
                provided.fulfill()
                return [tab]
            }, didConsume: { unexpected.fulfill() })
        }

        script.submitPrompt("hello", images: nil, modelId: nil)
        await fulfillment(of: [provided], timeout: 1)
        await fulfillment(of: [unexpected], timeout: 0.1)

        XCTAssertTrue(webView.prompts.isEmpty)
    }

    func testStopDropsLateResult() async {
        let input = MultiTabInputBox()
        await assertLateResultIsDropped { script in
            script.inputBoxHandler = input
            input.didPressStopGeneratingButton.send()
        }
    }

    func testFireDropsLateResult() async {
        let input = MultiTabInputBox()
        await assertLateResultIsDropped { script in
            script.inputBoxHandler = input
            input.didPressFireButton.send()
        }
    }

    private func makeScript() -> AIChatUserScript {
        let script = makeTestUserScript()
        let feature = AIChatContextualAttachMoreTabsFeature(
            featureFlagger: featureFlagger, aiChatSettings: MockAIChatSettingsProvider())
        script.attachedTabContextsProvider = { [weak self] in
            feature.makeRequest { self?.requestProvider?() }
        }
        script.webView = webView
        script.broker = broker
        return script
    }

    private func context(tabId: String? = nil, content: String = "content") -> AIChatPageContextData {
        AIChatPageContextData(title: "Page", favicon: [], url: "https://example.com/page", content: content,
                              truncated: false, fullContentLength: content.count, tabId: tabId)
    }

    private func dispatch(_ script: AIChatUserScript) async -> AIChatNativePrompt? {
        let delivered = expectation(description: "Prompt dispatched")
        webView.onPrompt = { _ in delivered.fulfill() }
        script.submitPrompt("hello", images: nil, modelId: nil)
        await fulfillment(of: [delivered], timeout: 1)
        return webView.prompts.last
    }

    private func assertLateResultIsDropped(_ invalidate: (AIChatUserScript) -> Void) async {
        let script = makeScript()
        let gate = ContextGate(started: expectation(description: "Provider started"))
        let unexpected = expectation(description: "Cancelled request neither dispatches nor consumes")
        unexpected.isInverted = true
        webView.onPrompt = { _ in unexpected.fulfill() }
        script.onPromptSubmitted = { unexpected.fulfill() }
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "selected", url: nil)
        script.attachedSelectionsProvider = { [selection] }
        script.onAttachedSelectionsConsumed = { _ in unexpected.fulfill() }
        requestProvider = {
            MultiTabAttachmentRequest(contexts: { await gate.wait() }, didConsume: { unexpected.fulfill() })
        }
        script.submitPrompt("cancelled", images: nil, modelId: nil)
        await fulfillment(of: [gate.started], timeout: 1)

        invalidate(script)
        gate.resume([context(tabId: "other")])
        await fulfillment(of: [unexpected], timeout: 0.1)

        XCTAssertTrue(webView.prompts.isEmpty)
    }
}

@MainActor
private final class ContextGate {
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<[AIChatPageContextData], Never>?

    init(started: XCTestExpectation) {
        self.started = started
    }

    func wait() async -> [AIChatPageContextData] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    // Intentionally ignores cancellation to exercise late provider results.
    func resume(_ contexts: [AIChatPageContextData]) {
        continuation?.resume(returning: contexts)
        continuation = nil
    }
}

@MainActor
private final class PromptRecordingWebView: WKWebView {
    var prompts: [AIChatNativePrompt] = []
    var payloads: [[String: Any]] = []
    var onPrompt: ((AIChatNativePrompt) -> Void)?
    private let javaScriptContext = JSContext()!

    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        javaScriptContext.evaluateScript("""
            var capturedPrompt = null;
            var navigator = { duckduckgo: { messageHandlers: {
                submitAIChatNativePrompt: function(event) { capturedPrompt = event.params; }
            } } };
            """)
        javaScriptContext.evaluateScript(javaScriptString)
        if let error = javaScriptContext.exception {
            XCTFail("Bridge JavaScript failed: \(error)")
        }
        if let object = javaScriptContext.objectForKeyedSubscript("capturedPrompt")?.toDictionary() as? [String: Any] {
            do {
                let data = try JSONSerialization.data(withJSONObject: object)
                let prompt = try JSONDecoder().decode(AIChatNativePrompt.self, from: data)
                payloads.append(object)
                prompts.append(prompt)
                onPrompt?(prompt)
            } catch {
                XCTFail("Invalid native prompt: \(error)")
            }
        }
        completionHandler?(nil, nil)
    }
}

private final class MultiTabInputBox: AIChatInputBoxHandling {
    let didPressFireButton = PassthroughSubject<Void, Never>()
    let didPressNewChatButton = PassthroughSubject<Void, Never>()
    let didSubmitPrompt = PassthroughSubject<String, Never>()
    let didSubmitQuery = PassthroughSubject<String, Never>()
    let didPressStopGeneratingButton = PassthroughSubject<Void, Never>()
    let didPressCustomizeResponsesButton = PassthroughSubject<Void, Never>()
    var persistedModelId: String?
    var persistedReasoningEffort: AIChatReasoningEffort?
    var isSubmitBlockedByRecoveryCard = false
    @Published var aiChatStatus: AIChatStatusValue = .unknown
    var aiChatStatusPublisher: Published<AIChatStatusValue>.Publisher { $aiChatStatus }
    @Published var aiChatInputBoxVisibility: AIChatInputBoxVisibility = .unknown
    var aiChatInputBoxVisibilityPublisher: Published<AIChatInputBoxVisibility>.Publisher { $aiChatInputBoxVisibility }
    @Published var attachmentUsage: AIChatAttachmentUsage?
    var attachmentUsagePublisher: Published<AIChatAttachmentUsage?>.Publisher { $attachmentUsage }
}

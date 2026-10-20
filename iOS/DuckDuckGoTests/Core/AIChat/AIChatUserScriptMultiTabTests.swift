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
import AIChatTestingUtilities
import BrowserServicesKitTestsUtils
import Combine
import FeatureFlags_iOS
import JavaScriptCore
@_spi(Testing) import PixelKit
import UserScript
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatUserScriptMultiTabTests: XCTestCase {
    private let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatContextualAttachMoreTabs])
    private weak var releasedScript: AIChatUserScript?
    private let initialPromptSession = AIChatInitialPromptSession()
    private let webView = PromptRecordingWebView()
    private let broker = UserScriptMessageBroker(context: "aiChat", requiresRunInPageContentWorld: true)
    private let pixelKitMock = PixelKitMock()
    private var requestedTabCount = 1
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

        script.submitPrompt("hello", attachments: .none, modelId: nil)

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

        script.submitPrompt("hello", attachments: .none, modelId: nil)
        await fulfillment(of: [gate.started], timeout: 1)
        featureFlagger.enabledFeatureFlags = []
        gate.resume([context(tabId: "other")])
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(webView.prompts.last?.pageContext, .single(page))
        XCTAssertFalse(consumed)
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
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

        script.submitPrompt("hello", attachments: .none, modelId: nil)
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

        script.submitPrompt("hello", attachments: AIChatPromptAttachments(images: images, files: files), modelId: "model", tools: [.webSearch], reasoningEffort: .high)
        await fulfillment(of: [gate.started], timeout: 1)
        XCTAssertFalse(consumed)
        XCTAssertFalse(submitted)
        XCTAssertTrue(consumedSelections.isEmpty)
        selectedPage = context(content: "new")
        selections = []
        gate.resume([tab])
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(webView.prompts.last, .queryPrompt(
            "hello", autoSubmit: true, toolChoice: [AIChatRAGTool.webSearch.rawValue], attachments: AIChatPromptAttachments(images: images, files: files),
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

        script.submitPrompt("first", attachments: .none, modelId: nil)
        await fulfillment(of: [gate.started], timeout: 1)
        script.submitPrompt("second", attachments: .none, modelId: nil)
        XCTAssertTrue(webView.prompts.isEmpty)
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
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
        await assertLateResultIsDropped(waitForCancellation: true) { script in
            _ = script.handler(forMethodNamed: AIChatUserScriptMessages.newChatStarted.rawValue)
        }
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
        script.submitPrompt("old", attachments: .none, modelId: nil)
        await fulfillment(of: [gate.started], timeout: 1)
        script.submitPrompt("queued", attachments: .none, modelId: nil)

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
        script?.submitPrompt("old", attachments: .none, modelId: nil)
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

        script.submitPrompt("hello", attachments: .none, modelId: nil)
        await fulfillment(of: [provided], timeout: 1)
        await fulfillment(of: [unexpected], timeout: 0.1)

        XCTAssertTrue(webView.prompts.isEmpty)
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
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

    func testInitialPromptSurvivesRepeatedUserScriptReplacementBeforeFrontendRequest() async throws {
        let prompt = AIChatNativePrompt.queryPrompt("captured", autoSubmit: true, modelId: "model")
        let attached = context(tabId: "submitted")
        var collectionCount = 0
        var consumptionCount = 0
        var releaseCount = 0
        var submissions: [MultiTabAttachmentRequest.SubmissionResult] = []
        let request = MultiTabAttachmentRequest(contexts: {
            collectionCount += 1
            return [attached, self.context(tabId: "closed")]
        }, didConsume: { consumptionCount += 1 }, cancel: { releaseCount += 1 },
                                              validate: { $0.filter { $0.tabId == "submitted" } },
                                              didDispatch: { submissions.append($0) })
        let prepared = expectation(description: "Contexts prepared before opening chat")
        var preparedDelivery: AIChatInitialPromptDelivery?
        let preparation = AIChatInitialPromptPreparation(prompt: prompt, request: request) {
            preparedDelivery = $0
            prepared.fulfill()
        }
        defer { preparation.cancel() }
        await fulfillment(of: [prepared], timeout: 1)
        let delivery = try XCTUnwrap(preparedDelivery)
        XCTAssertEqual(collectionCount, 1)
        XCTAssertEqual(consumptionCount, 1)
        XCTAssertEqual(releaseCount, 1)
        XCTAssertTrue(submissions.isEmpty)

        let original = makeScript()
        initialPromptSession.install(delivery)
        original.cleanUpForReplacement()

        let intermediate = makeScript()
        intermediate.cleanUpForReplacement()

        let replacement = makeScript()
        defer { replacement.cancelPendingTabContextSubmission() }
        let handler = try XCTUnwrap(replacement.handler(forMethodNamed: "getAIChatNativePrompt"))
        let result = try await handler([:], .mock()) as? AIChatNativePrompt
        let duplicate = try await handler([:], .mock())

        XCTAssertEqual(result, .queryPrompt("captured", autoSubmit: true, modelId: "model", pageContext: .multiple([attached])))
        XCTAssertNil(duplicate)
        XCTAssertEqual(collectionCount, 1)
        XCTAssertEqual(consumptionCount, 1)
        XCTAssertEqual(releaseCount, 1)
        XCTAssertEqual(submissions.count, 1)
        XCTAssertEqual(submissions.first?.totalTabCount, 1)
        XCTAssertEqual(submissions.first?.deliveredAttachmentCount, 1)
        XCTAssertTrue(webView.prompts.isEmpty)
    }

    func testPreparedCurrentOmnibarTabCountsAsDeliveredAttachmentWithoutTabID() async throws {
        let currentTab = context()
        var submissions: [MultiTabAttachmentRequest.SubmissionResult] = []
        let prepared = expectation(description: "Current tab context prepared")
        var preparedDelivery: AIChatInitialPromptDelivery?
        let request = MultiTabAttachmentRequest(contexts: { [currentTab] }, didConsume: {},
                                                didDispatch: { submissions.append($0) })
        let preparation = AIChatInitialPromptPreparation(prompt: .queryPrompt("hello", autoSubmit: true), request: request) {
            preparedDelivery = $0
            prepared.fulfill()
        }
        defer { preparation.cancel() }
        await fulfillment(of: [prepared], timeout: 1)
        let delivery = try XCTUnwrap(preparedDelivery)
        defer { delivery.cancel() }
        XCTAssertTrue(submissions.isEmpty)

        XCTAssertEqual(delivery.consume()?.pageContext, .multiple([currentTab]))
        XCTAssertEqual(submissions.count, 1)
        XCTAssertEqual(submissions.first?.totalTabCount, 1)
        XCTAssertEqual(submissions.first?.deliveredAttachmentCount, 1)
    }

    func testReplacementAfterFrontendRequestDoesNotDeliverInitialPromptTwice() async throws {
        let prompt = AIChatNativePrompt.queryPrompt("captured", autoSubmit: true, pageContext: .multiple([context(tabId: "submitted")]))
        var consumptionCount = 0
        let delivery = AIChatInitialPromptDelivery(prompt: prompt) { consumptionCount += 1 }
        let script = makeScript()
        initialPromptSession.install(delivery)
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "getAIChatNativePrompt"))
        let result = try await handler([:], .mock()) as? AIChatNativePrompt

        script.cleanUpForReplacement()
        let replacement = makeScript()
        let replacementHandler = try XCTUnwrap(replacement.handler(forMethodNamed: "getAIChatNativePrompt"))
        let duplicate = try await replacementHandler([:], .mock())

        XCTAssertEqual(result, prompt)
        XCTAssertNil(duplicate)
        XCTAssertEqual(consumptionCount, 1)
        XCTAssertTrue(webView.prompts.isEmpty)
    }

    func testStopBeforeFrontendRequestCancelsPreparedInitialPrompt() async throws {
        let script = makeScript()
        let input = MultiTabInputBox()
        script.inputBoxHandler = input
        let delivery = AIChatInitialPromptDelivery(prompt: .queryPrompt("captured", autoSubmit: true)) {
            XCTFail("Stopped prompt must not be consumed")
        }
        initialPromptSession.install(delivery)
        let cancelled = expectation(description: "Stop cancels prepared delivery")
        let waiter = Task {
            let result = await delivery.waitUntilConsumed()
            XCTAssertEqual(result, .cancelled)
            cancelled.fulfill()
        }
        defer { waiter.cancel() }

        input.didPressStopGeneratingButton.send()
        await fulfillment(of: [cancelled], timeout: 1)
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "getAIChatNativePrompt"))
        let result = try await handler([:], .mock())

        XCTAssertNil(result)
        XCTAssertNil(delivery.consume())
        XCTAssertTrue(webView.prompts.isEmpty)
    }

    func testCancellingInitialPromptPreparationReleasesRequestAndDropsLateContexts() async {
        let gate = ContextGate(started: expectation(description: "Initial context collection started"))
        let unexpected = expectation(description: "Cancelled preparation does not consume late contexts")
        unexpected.isInverted = true
        var consumptionCount = 0
        var releaseCount = 0
        var completionCount = 0
        let completed = expectation(description: "Preparation cancelled")
        let preparation = AIChatInitialPromptPreparation(prompt: .queryPrompt("captured", autoSubmit: true), request: .init(
            contexts: { await gate.wait() }, didConsume: { consumptionCount += 1; unexpected.fulfill() },
            cancel: { releaseCount += 1 }, didDispatch: { _ in unexpected.fulfill() })) { delivery in
                completionCount += 1
                XCTAssertNil(delivery)
                completed.fulfill()
            }
        defer { preparation.cancel() }
        await fulfillment(of: [gate.started], timeout: 1)

        preparation.cancel()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(releaseCount, 1)
        gate.resume([context(tabId: "submitted")])
        await fulfillment(of: [unexpected], timeout: 0.1)

        XCTAssertEqual(consumptionCount, 0)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(releaseCount, 1)
    }

    func testSubsequentPromptWaitsUntilPreparedInitialPromptIsConsumed() async throws {
        let script = makeScript()
        var initialWasConsumed = false
        let first = AIChatNativePrompt.queryPrompt("first", autoSubmit: true, pageContext: .multiple([context(tabId: "submitted")]))
        let delivery = AIChatInitialPromptDelivery(prompt: first) { initialWasConsumed = true }
        initialPromptSession.install(delivery)
        defer { script.cancelPendingTabContextSubmission() }
        let unexpected = expectation(description: "Subsequent prompt does not push before initial pull")
        unexpected.isInverted = true
        webView.onPrompt = { _ in unexpected.fulfill() }
        let collected = expectation(description: "Subsequent prompt collects contexts after initial pull")

        script.submitPrompt("second", attachments: .none, modelId: nil, tools: nil, tabAttachmentRequest: .init(contexts: {
            XCTAssertTrue(initialWasConsumed)
            collected.fulfill()
            return []
        }, didConsume: {}))
        await fulfillment(of: [unexpected], timeout: 0.1)
        XCTAssertFalse(initialWasConsumed)
        XCTAssertTrue(webView.prompts.isEmpty)
        let pushed = expectation(description: "Subsequent prompt pushed")
        webView.onPrompt = { _ in pushed.fulfill() }
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "getAIChatNativePrompt"))

        let result = try await handler([:], .mock()) as? AIChatNativePrompt
        await fulfillment(of: [collected, pushed], timeout: 1)

        XCTAssertEqual(result, first)
        XCTAssertTrue(initialWasConsumed)
        XCTAssertEqual(webView.prompts, [.queryPrompt("second", autoSubmit: true)])
    }

    func testInitialPromptTimeoutDiscardsLatePullAndDispatchesQueuedPrompts() async throws {
        let script = makeScript()
        let delivery = AIChatInitialPromptDelivery(prompt: .queryPrompt("first", autoSubmit: true), consumptionTimeout: 0.05) {
            XCTFail("Timed-out initial prompt must not be consumed")
        }
        initialPromptSession.install(delivery)
        defer { script.cancelPendingTabContextSubmission() }
        let pushed = expectation(description: "Queued prompts dispatched after initial pull times out")
        pushed.expectedFulfillmentCount = 2
        webView.onPrompt = { _ in pushed.fulfill() }

        script.submitPrompt("second", attachments: .none, modelId: nil, tools: nil, tabAttachmentRequest: nil)
        script.submitPrompt("third", attachments: .none, modelId: nil, tools: nil,
                            tabAttachmentRequest: .init(contexts: { [] }, didConsume: {}))

        await fulfillment(of: [pushed], timeout: 1)
        XCTAssertEqual(webView.prompts, [
            .queryPrompt("second", autoSubmit: true),
            .queryPrompt("third", autoSubmit: true)
        ])
        let result = await delivery.waitUntilConsumed()
        XCTAssertEqual(result, .timedOut)
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "getAIChatNativePrompt"))
        let latePull = try await handler([:], .mock())
        XCTAssertNil(latePull)
    }

    func testOrdinaryContextSubmissionStillCancelsAfterInitialPromptDetachment() async {
        let script = makeScript()
        let gate = ContextGate(started: expectation(description: "Ordinary context collection started"))
        let released = expectation(description: "Ordinary submission releases preparations")
        released.assertForOverFulfill = false
        let unexpected = expectation(description: "Cancelled ordinary submission does not dispatch or consume")
        unexpected.isInverted = true
        webView.onPrompt = { _ in unexpected.fulfill() }
        script.submitPrompt("captured", attachments: .none, modelId: nil, tools: nil,
                            tabAttachmentRequest: .init(contexts: { await gate.wait() }, didConsume: { unexpected.fulfill() },
                                                        cancel: { released.fulfill() }))
        await fulfillment(of: [gate.started], timeout: 1)

        script.cleanUpForReplacement()
        await fulfillment(of: [released], timeout: 1)
        gate.resume([context(tabId: "submitted")])
        await fulfillment(of: [unexpected], timeout: 0.1)

        XCTAssertTrue(webView.prompts.isEmpty)
    }

    func testExplicitRequestDoesNotReadLaterDraftProvider() async {
        let script = makeScript()
        let attached = context(tabId: "submitted")
        requestProvider = { XCTFail("Submitted request must not read a later draft"); return nil }
        let delivered = expectation(description: "Captured prompt dispatched")
        webView.onPrompt = { _ in delivered.fulfill() }
        script.submitPrompt("captured", attachments: .none, modelId: nil, tools: nil,
                            tabAttachmentRequest: .init(contexts: { [attached] }, didConsume: {}))
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(webView.prompts.last?.pageContext, .multiple([attached]))
    }

    func testCurrentOmnibarTabCountsAsDeliveredAttachmentWithoutTabID() async {
        let script = makeScript()
        let currentTab = context().withTabId(nil)
        let reporter = UTIPixelReporter(firing: UTIPixelFiring(pixelKit: { [pixelKitMock] in pixelKitMock }), context: {
            UTIPixelContext(surface: .addressBar, isDuckAISurfaceForAttribution: false,
                            inputMode: .aiChat, isToggleVisible: false, pageType: .website, duckAIEntrySource: nil)
        })
        let delivered = expectation(description: "Current tab prompt dispatched")
        webView.onPrompt = { _ in delivered.fulfill() }

        script.submitPrompt("captured", attachments: .none, modelId: nil, tools: nil,
                            tabAttachmentRequest: .init(contexts: { [currentTab] }, didConsume: {},
                                                        didDispatch: reporter.makeTabSubmissionReporter(requestedTabCount: 1)))
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(webView.prompts.last?.pageContext, .multiple([currentTab]))
        XCTAssertEqual(pixelKitMock.actualFireCalls.map(\.pixel.name), ["aichat_unified_input_tabs_sent"])
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.parameters,
                       ["surface": "address_bar", "page_type": "website", "payload_tab_count": "one"])
    }

    func testDeliveryRevalidatesContextsAfterAwait() async {
        let script = makeScript()
        let attached = context(tabId: "submitted")
        let delivered = expectation(description: "Prompt dispatched without invalidated context")
        webView.onPrompt = { _ in delivered.fulfill() }
        script.submitPrompt("captured", attachments: .none, modelId: nil, tools: nil,
                            tabAttachmentRequest: .init(contexts: { [attached] }, didConsume: {}, validate: { _ in [] }))
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertNil(webView.prompts.last?.pageContext)
    }

    func testMissingBrokerReleasesRequestWithoutConsumingIt() async {
        let script = makeScript()
        script.broker = nil
        let released = expectation(description: "Unavailable dispatch releases request")
        script.submitPrompt("captured", attachments: .none, modelId: nil, tools: nil,
                            tabAttachmentRequest: .init(contexts: { [self.context(tabId: "other")] },
                                                        didConsume: { XCTFail("Missing broker must not consume") },
                                                        cancel: { released.fulfill() }))
        await fulfillment(of: [released], timeout: 1)
    }

    func testCancellationReleasesProviderWithoutWaitingForLateResult() async {
        let script = makeScript()
        let gate = ContextGate(started: expectation(description: "Provider started"))
        let released = expectation(description: "Provider cancelled")
        released.assertForOverFulfill = false
        script.submitPrompt("cancelled", attachments: .none, modelId: nil, tools: nil,
                            tabAttachmentRequest: .init(contexts: { await gate.wait() },
                                                        didConsume: { XCTFail("Cancelled request must not consume") },
                                                        cancel: { released.fulfill() }))
        await fulfillment(of: [gate.started], timeout: 1)
        script.cancelPendingTabContextSubmission()
        await fulfillment(of: [released], timeout: 1)
        gate.resume([])
        XCTAssertTrue(webView.prompts.isEmpty)
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
    }

    func testWhenPromptDispatchesThenMeasuresValidatedPayloadIncludingCurrentPage() async {
        requestedTabCount = 2
        let script = makeScript()
        script.attachedPageContextProvider = { self.context() }
        requestProvider = {
            MultiTabAttachmentRequest(contexts: { [self.context(tabId: "valid"), self.context(tabId: "closed")] },
                                      didConsume: {}, validate: { $0.filter { $0.tabId == "valid" } })
        }
        _ = await dispatch(script)
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 2)
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.parameters,
                       ["surface": "contextual_chat", "page_type": "contextual", "payload_tab_count": "some"])
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.parameters,
                       ["surface": "contextual_chat", "page_type": "contextual", "outcome": "partial"])
    }

    func testWhenNoAdditionalContextSurvivesThenMeasuresIncompleteSubmission() async {
        let script = makeScript()
        script.attachedPageContextProvider = { self.context() }
        requestProvider = { MultiTabAttachmentRequest(contexts: { [] }, didConsume: {}) }
        _ = await dispatch(script)
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.name, "aichat_unified_input_tabs_submission_incomplete")
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.parameters,
                       ["surface": "contextual_chat", "page_type": "contextual", "outcome": "all"])
    }

    func testWhenEveryContextIsMissingWithoutCurrentPageThenReportsAllMissing() async {
        let script = makeScript()
        requestProvider = { MultiTabAttachmentRequest(contexts: { [] }, didConsume: {}) }
        let prompt = await dispatch(script)
        XCTAssertNil(prompt?.pageContext)
        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.first?.pixel.parameters,
                       ["surface": "contextual_chat", "page_type": "contextual", "outcome": "all"])
    }

    func testWhenFeatureDisabledThenDoesNotMeasureTabsSent() async {
        featureFlagger.enabledFeatureFlags = []
        let script = makeScript()
        requestProvider = { MultiTabAttachmentRequest(contexts: { [self.context(tabId: "tab")] }, didConsume: {}) }
        _ = await dispatch(script)
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
    }

    func testDestroyingOriginalScriptPreservesSessionDelivery() async throws {
        var original: AIChatUserScript? = makeScript()
        releasedScript = original
        initialPromptSession.install(AIChatInitialPromptDelivery(prompt: .queryPrompt("survives", autoSubmit: true)) {})
        original = nil
        XCTAssertNil(releasedScript)

        let replacement = makeScript()
        let pull = try XCTUnwrap(replacement.handler(forMethodNamed: "getAIChatNativePrompt"))
        let actual = try await pull([:], .mock()) as? AIChatNativePrompt

        XCTAssertEqual(actual, .queryPrompt("survives", autoSubmit: true))
    }

    func testStaleScriptCannotCancelOrConsumeReplacementPrompt() async throws {
        let old = makeScript()
        let oldPull = try XCTUnwrap(old.handler(forMethodNamed: "getAIChatNativePrompt"))
        let replacement = makeScript()
        initialPromptSession.install(AIChatInitialPromptDelivery(prompt: .queryPrompt("replacement", autoSubmit: true)) {})

        old.cancelPendingTabContextSubmission()
        old.cleanUpForReplacement()
        let stale = try await oldPull([:], .mock())
        XCTAssertNil(stale)
        let pull = try XCTUnwrap(replacement.handler(forMethodNamed: "getAIChatNativePrompt"))
        let actual = try await pull([:], .mock()) as? AIChatNativePrompt
        XCTAssertEqual(actual, .queryPrompt("replacement", autoSubmit: true))
    }

    func testReplacementDropsQueuedFollowUpWithoutDiscardingInitialPrompt() async throws {
        let old = makeScript()
        initialPromptSession.install(AIChatInitialPromptDelivery(prompt: .queryPrompt("first", autoSubmit: true)) {})
        let unexpected = expectation(description: "Old queued message is dropped")
        unexpected.isInverted = true
        webView.onPrompt = { _ in unexpected.fulfill() }
        old.submitPrompt("cancelled follow-up", attachments: .none, modelId: nil)
        old.cleanUpForReplacement()

        let replacement = makeScript()
        let pull = try XCTUnwrap(replacement.handler(forMethodNamed: "getAIChatNativePrompt"))
        let actual = try await pull([:], .mock()) as? AIChatNativePrompt
        await fulfillment(of: [unexpected], timeout: 0.1)

        XCTAssertEqual(actual, .queryPrompt("first", autoSubmit: true))
        XCTAssertTrue(webView.prompts.isEmpty)
    }

    func testNavigationFailureCancelsQueuedFollowUpButPreservesInitialPromptForReplacement() async throws {
        let script = makeScript()
        let waitStarted = expectation(description: "Follow-up waits for initial prompt")
        let waitFinished = expectation(description: "Cancelled follow-up stops waiting")
        let unexpected = expectation(description: "Cancelled follow-up is not dispatched")
        unexpected.isInverted = true
        webView.onPrompt = { _ in unexpected.fulfill() }
        var consumptionCount = 0
        let initial = AIChatNativePrompt.queryPrompt("initial", autoSubmit: true)
        let delivery = AIChatInitialPromptDelivery(prompt: initial, waitUntilReady: { gate, timeout in
            let ready = await gate.waitUntilReady(timeout: timeout, onWaitStarted: { waitStarted.fulfill() })
            waitFinished.fulfill()
            return ready
        }, onConsumed: { consumptionCount += 1 })
        initialPromptSession.install(delivery)
        let navigation = DummyWKNavigation()
        initialPromptSession.didStartNavigation(navigation)
        script.submitPrompt("cancelled follow-up", attachments: .none, modelId: nil)
        await fulfillment(of: [waitStarted], timeout: 1)

        XCTAssertTrue(initialPromptSession.didFailNavigation(navigation))
        script.cancelQueuedTabContextSubmissions()
        await fulfillment(of: [waitFinished], timeout: 1)

        XCTAssertTrue(delivery.hasPendingPrompt)
        XCTAssertTrue(initialPromptSession.willRetryFailedNavigation())
        XCTAssertFalse(initialPromptSession.didStartNavigation(DummyWKNavigation()))
        script.cleanUpForReplacement()
        let replacement = makeScript()
        let pull = try XCTUnwrap(replacement.handler(forMethodNamed: "getAIChatNativePrompt"))
        let received = try await pull([:], .mock()) as? AIChatNativePrompt
        let duplicate = try await pull([:], .mock()) as? AIChatNativePrompt
        await fulfillment(of: [unexpected], timeout: 0.1)

        XCTAssertEqual(received, initial)
        XCTAssertNil(duplicate)
        XCTAssertEqual(consumptionCount, 1)
        XCTAssertTrue(webView.prompts.isEmpty)
    }

    func testReplacementStartsWaitingBeforeOldWaitingSubmissionFinishes() async throws {
        let old = makeScript()
        let oldWaitStarted = expectation(description: "Old script is waiting on delivery")
        let replacementWaitStarted = expectation(description: "Replacement script is waiting on the same delivery")
        let oldResultGate = InitialPromptWaitResultGate(started: expectation(description: "Old wait result is held"))
        let oldSubmissionFinished = expectation(description: "Old submission finishes after replacement starts waiting")
        var didFinishOldSubmission = false
        var waitsStarted = 0
        var consumptionCount = 0
        let initialPrompt = AIChatNativePrompt.queryPrompt("initial", autoSubmit: true)
        let delivery = AIChatInitialPromptDelivery(prompt: initialPrompt, waitUntilReady: { gate, timeout in
            waitsStarted += 1
            let isOldWait = waitsStarted == 1
            let ready = await gate.waitUntilReady(timeout: timeout, onWaitStarted: {
                if isOldWait {
                    oldWaitStarted.fulfill()
                } else {
                    XCTAssertFalse(didFinishOldSubmission)
                    replacementWaitStarted.fulfill()
                }
            })
            if isOldWait {
                await oldResultGate.wait()
            }
            return ready
        }, onConsumed: { consumptionCount += 1 })
        initialPromptSession.install(delivery)
        defer {
            old.cancelPendingTabContextSubmission()
            oldResultGate.open()
        }
        old.submitPrompt("old follow-up", attachments: .none, modelId: nil, tools: nil, tabAttachmentRequest: .init(contexts: {
            XCTFail("Cancelled old submission must not collect contexts")
            return []
        }, didConsume: { XCTFail("Cancelled old submission must not consume attachments") }, cancel: {
            guard !didFinishOldSubmission else { return }
            didFinishOldSubmission = true
            oldSubmissionFinished.fulfill()
        }))
        await fulfillment(of: [oldWaitStarted], timeout: 1)

        old.cleanUpForReplacement()
        let replacement = makeScript()
        defer { replacement.cancelPendingTabContextSubmission() }
        let unexpected = expectation(description: "Replacement does not dispatch before initial pull")
        unexpected.isInverted = true
        webView.onPrompt = { _ in unexpected.fulfill() }
        replacement.submitPrompt("replacement follow-up", attachments: .none, modelId: nil)
        await fulfillment(of: [replacementWaitStarted, oldResultGate.started], timeout: 1)
        XCTAssertFalse(didFinishOldSubmission)
        XCTAssertEqual(waitsStarted, 2)

        oldResultGate.open()
        await fulfillment(of: [oldSubmissionFinished], timeout: 1)
        await fulfillment(of: [unexpected], timeout: 0.1)
        XCTAssertTrue(delivery.hasPendingPrompt)
        XCTAssertTrue(initialPromptSession.isProtectedFromCacheEviction)
        XCTAssertEqual(consumptionCount, 0)

        let dispatched = expectation(description: "Only replacement follow-up dispatches after initial pull")
        webView.onPrompt = { _ in dispatched.fulfill() }
        let pull = try XCTUnwrap(replacement.handler(forMethodNamed: "getAIChatNativePrompt"))
        let actual = try await pull([:], .mock()) as? AIChatNativePrompt
        await fulfillment(of: [dispatched], timeout: 1)
        let duplicate = try await pull([:], .mock())

        XCTAssertEqual(actual, initialPrompt)
        XCTAssertNil(duplicate)
        XCTAssertEqual(consumptionCount, 1)
        XCTAssertEqual(webView.prompts, [.queryPrompt("replacement follow-up", autoSubmit: true)])
        XCTAssertFalse(initialPromptSession.isProtectedFromCacheEviction)
    }

    func testQueuedSendKeepsOriginalDeliveryWhileWaitingForPreviousSend() async throws {
        let script = makeScript()
        let gate = ContextGate(started: expectation(description: "Earlier send collecting context"))
        let pushed = expectation(description: "Earlier send dispatched")
        webView.onPrompt = { _ in pushed.fulfill() }
        script.submitPrompt("earlier", attachments: .none, modelId: nil, tools: nil,
                            tabAttachmentRequest: .init(contexts: { await gate.wait() }, didConsume: {}))
        await fulfillment(of: [gate.started], timeout: 1)
        initialPromptSession.install(AIChatInitialPromptDelivery(prompt: .queryPrompt("old initial", autoSubmit: true)) {})
        script.submitPrompt("must stay with old initial", attachments: .none, modelId: nil)
        initialPromptSession.install(AIChatInitialPromptDelivery(prompt: .queryPrompt("new initial", autoSubmit: true)) {})
        gate.resume([])
        await fulfillment(of: [pushed], timeout: 1)
        let pull = try XCTUnwrap(script.handler(forMethodNamed: "getAIChatNativePrompt"))
        let actual = try await pull([:], .mock()) as? AIChatNativePrompt
        let drained = expectation(description: "Queue drained")
        webView.onPrompt = { _ in drained.fulfill() }
        script.submitPrompt("last", attachments: .none, modelId: nil)
        await fulfillment(of: [drained], timeout: 1)

        XCTAssertEqual(actual, .queryPrompt("new initial", autoSubmit: true))
        XCTAssertEqual(webView.prompts, [.queryPrompt("earlier", autoSubmit: true), .queryPrompt("last", autoSubmit: true)])
    }

    func testIncomingConversationEndMessagesScheduleSessionPromptCancellation() async {
        for message in [AIChatUserScriptMessages.newChatStarted, .newImageGenerationChatStarted, .closeAIChat] {
            let script = makeScript()
            let delivery = AIChatInitialPromptDelivery(prompt: .queryPrompt("cancelled", autoSubmit: true)) {}
            initialPromptSession.install(delivery)
            var didReceiveMessage = false
            let delegate = ConversationMessageObserver { received in
                XCTAssertEqual(received, message)
                XCTAssertTrue(delivery.hasPendingPrompt)
                didReceiveMessage = true
            }
            script.delegate = delegate
            let receive = script.handler(forMethodNamed: message.rawValue)

            XCTAssertTrue(didReceiveMessage)
            XCTAssertTrue(delivery.hasPendingPrompt)
            if message == .newImageGenerationChatStarted {
                XCTAssertNotNil(receive)
            } else {
                XCTAssertNil(receive)
            }

            let result = await delivery.waitUntilConsumed()
            XCTAssertEqual(result, .cancelled)
            XCTAssertNil(delivery.consume())
            XCTAssertFalse(initialPromptSession.isProtectedFromCacheEviction)
        }
    }

    private func makeScript() -> AIChatUserScript {
        let handler = AIChatUserScriptHandler(
            experimentalAIChatManager: ExperimentalAIChatManager(featureFlagger: featureFlagger),
            syncHandler: MockAIChatSyncHandling(), bonusHandler: MockAIChatBonusHandling(), featureFlagger: featureFlagger)
        let script = AIChatUserScript(handler: handler, debugSettings: MockAIChatDebugSettingsForTests())
        script.connectInitialPromptSession(initialPromptSession)
        let feature = AIChatContextualAttachMoreTabsFeature(
            featureFlagger: featureFlagger, aiChatSettings: MockAIChatSettingsProvider())
        script.attachedTabContextsProvider = { [weak self] in
            guard let self else { return nil }
            let reporter = UTIPixelReporter(firing: UTIPixelFiring(pixelKit: { [pixelKitMock] in pixelKitMock }), context: {
                UTIPixelContext(surface: .contextualChat, isDuckAISurfaceForAttribution: false,
                                inputMode: .aiChat, isToggleVisible: false, pageType: .contextual, duckAIEntrySource: nil)
            })
            return MultiTabAttachmentContext(feature: feature).makeRequest {
                guard var request = self.requestProvider?() else { return nil }
                request.didDispatch = reporter.makeTabSubmissionReporter(requestedTabCount: self.requestedTabCount)
                return request
            }
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
        script.submitPrompt("hello", attachments: .none, modelId: nil)
        await fulfillment(of: [delivered], timeout: 1)
        return webView.prompts.last
    }

    private func assertLateResultIsDropped(
        waitForCancellation: Bool = false,
        _ invalidate: @MainActor (AIChatUserScript) async throws -> Void
    ) async rethrows {
        let script = makeScript()
        let gate = ContextGate(started: expectation(description: "Provider started"))
        defer {
            script.cancelPendingTabContextSubmission()
            gate.resume([])
        }
        let unexpected = expectation(description: "Cancelled request neither dispatches nor consumes")
        unexpected.isInverted = true
        let cancelled = waitForCancellation ? expectation(description: "Request cancelled before provider resumes") : nil
        cancelled?.assertForOverFulfill = false
        webView.onPrompt = { _ in unexpected.fulfill() }
        script.onPromptSubmitted = { unexpected.fulfill() }
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "selected", url: nil)
        script.attachedSelectionsProvider = { [selection] }
        script.onAttachedSelectionsConsumed = { _ in unexpected.fulfill() }
        requestProvider = {
            MultiTabAttachmentRequest(contexts: { await gate.wait() }, didConsume: { unexpected.fulfill() },
                                      cancel: { cancelled?.fulfill() })
        }
        script.submitPrompt("cancelled", attachments: .none, modelId: nil)
        await fulfillment(of: [gate.started], timeout: 1)

        try await invalidate(script)
        if let cancelled {
            await fulfillment(of: [cancelled], timeout: 1)
        }
        gate.resume([context(tabId: "other")])
        await fulfillment(of: [unexpected], timeout: 0.1)

        XCTAssertTrue(webView.prompts.isEmpty)
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
    }
}

@MainActor
private final class InitialPromptWaitResultGate {
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    init(started: XCTestExpectation) {
        self.started = started
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
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
    let didChangeInputFocus = PassthroughSubject<Bool, Never>()
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

private final class ConversationMessageObserver: AIChatUserScriptDelegate {
    private let receive: (AIChatUserScriptMessages) -> Void

    init(receive: @escaping (AIChatUserScriptMessages) -> Void) {
        self.receive = receive
    }

    func aiChatUserScript(_ userScript: AIChatUserScript, didReceiveMessage message: AIChatUserScriptMessages) {
        receive(message)
    }

    func aiChatUserScript(_ userScript: AIChatUserScript, didReceiveMetric metric: AIChatMetric) {}
}

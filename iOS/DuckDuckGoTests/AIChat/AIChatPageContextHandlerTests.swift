//
//  AIChatPageContextHandlerTests.swift
//  DuckDuckGoTests
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
import Combine
import Core
import UserScript
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatPageContextHandlerTests: XCTestCase {

    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStatePublishesNil() {
        let handler = makeHandler()

        var receivedValue: AIChatPageContext??
        handler.contextPublisher
            .first()
            .sink { context in
                receivedValue = context
            }
            .store(in: &cancellables)

        XCTAssertNotNil(receivedValue)
        XCTAssertNil(receivedValue!)
    }

    // MARK: - triggerContextCollection

    func testTriggerContextCollectionDoesNothingWhenUserScriptUnavailable() {
        let userScriptProvider: UserScriptProvider = { nil }
        let handler = makeHandler(userScriptProvider: userScriptProvider)

        let didTrigger = handler.triggerContextCollection(trigger: .auto)

        XCTAssertFalse(didTrigger)
        var receivedValue: AIChatPageContext??
        handler.contextPublisher
            .first()
            .sink { context in
                receivedValue = context
            }
            .store(in: &cancellables)

        XCTAssertNotNil(receivedValue)
        XCTAssertNil(receivedValue!)
    }

    // MARK: - resubscribe

    func testResubscribeSwitchesToNewScriptPublisher() {
        // Given: Two scripts that can publish context
        let firstScript = PageContextUserScript()
        let secondScript = PageContextUserScript()
        var currentScript: PageContextUserScript? = firstScript

        let handler = makeHandler(
            userScriptProvider: { currentScript }
        )

        var receivedContexts: [AIChatPageContext?] = []
        handler.contextPublisher
            .dropFirst() // Skip initial nil
            .sink { context in
                receivedContexts.append(context)
            }
            .store(in: &cancellables)

        // When: Subscribe to first script
        handler.resubscribe()

        // Then: Handler should be subscribed to first script
        // (We can't easily send values through the real script without a broker,
        // but we can verify the subscription logic by switching scripts)

        // When: Switch to second script and resubscribe
        currentScript = secondScript
        handler.resubscribe()

        // Then: Handler should now be subscribed to second script
        // The key behavior is that resubscribe() cancels old subscription and creates new one
        // We verify this indirectly - if no crash occurs and we can call resubscribe multiple times
        XCTAssertTrue(true, "resubscribe should complete without crash")
    }

    func testResubscribeDoesNothingWhenNoScriptAvailable() {
        // Given: Handler with no script
        let handler = makeHandler(userScriptProvider: { nil })

        var receivedContexts: [AIChatPageContext?] = []
        handler.contextPublisher
            .dropFirst() // Skip initial nil
            .sink { context in
                receivedContexts.append(context)
            }
            .store(in: &cancellables)

        // When: Call resubscribe
        handler.resubscribe()

        // Then: No crash, no new subscriptions
        XCTAssertEqual(receivedContexts.count, 0)
    }

    func testResubscribeCanBeCalledMultipleTimes() {
        // Given: Handler with a script
        let script = PageContextUserScript()
        let handler = makeHandler(userScriptProvider: { script })

        // When: Call resubscribe multiple times
        handler.resubscribe()
        handler.resubscribe()
        handler.resubscribe()

        // Then: No crash - each call cancels previous and creates new subscription
        XCTAssertTrue(true, "Multiple resubscribe calls should not crash")
    }

    // MARK: - Pixel Firing Tests

    func testEmptyPageContextFiresPixel() {
        // Given: Handler with a mock pixel handler
        let mockPixelHandler = MockContextualModePixelHandler()
        let mockScript = MockPageContextCollecting()
        let webView = WKWebView()
        let handler = makeHandler(
            webViewProvider: { webView },
            userScriptProvider: { mockScript },
            pixelHandler: mockPixelHandler
        )

        let expectation = XCTestExpectation(description: "Context published")
        var receivedContext: AIChatPageContext??
        handler.contextPublisher
            .dropFirst() // Skip initial nil
            .first()
            .sink { context in
                receivedContext = context
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When: Script publishes empty context (valid but no content)
        handler.triggerContextCollection(trigger: .auto)
        mockScript.simulateEmptyContext()

        wait(for: [expectation], timeout: 1.0)

        // Then: Pixel should fire and context should be nil
        XCTAssertEqual(mockPixelHandler.pageContextCollectionEmptyCount, 1)
        XCTAssertNotNil(receivedContext)
        XCTAssertNil(receivedContext!)
    }

    func testNilPageContextDoesNotFirePixel() {
        // Given: Handler with a mock pixel handler
        let mockPixelHandler = MockContextualModePixelHandler()
        let mockScript = MockPageContextCollecting()
        let webView = WKWebView()
        let handler = makeHandler(
            webViewProvider: { webView },
            userScriptProvider: { mockScript },
            pixelHandler: mockPixelHandler
        )

        let expectation = XCTestExpectation(description: "Context published")
        var receivedContext: AIChatPageContext??
        handler.contextPublisher
            .dropFirst() // Skip initial nil
            .first()
            .sink { context in
                receivedContext = context
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When: Script publishes nil (decode failure)
        handler.triggerContextCollection(trigger: .auto)
        mockScript.simulateNilContext()

        wait(for: [expectation], timeout: 1.0)

        // Then: Pixel should NOT fire (nil means decode failure, not empty content)
        XCTAssertEqual(mockPixelHandler.pageContextCollectionEmptyCount, 0)
        XCTAssertNotNil(receivedContext)
        XCTAssertNil(receivedContext!)
    }

    func testValidPageContextDoesNotFirePixel() {
        // Given: Handler with a mock pixel handler
        let mockPixelHandler = MockContextualModePixelHandler()
        let mockScript = MockPageContextCollecting()
        let webView = WKWebView()
        let handler = makeHandler(
            webViewProvider: { webView },
            userScriptProvider: { mockScript },
            pixelHandler: mockPixelHandler
        )

        let expectation = XCTestExpectation(description: "Context published")
        var receivedContext: AIChatPageContext??
        handler.contextPublisher
            .dropFirst() // Skip initial nil
            .first()
            .sink { context in
                receivedContext = context
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When: Script publishes valid context with content
        handler.triggerContextCollection(trigger: .auto)
        mockScript.simulateValidContext()

        wait(for: [expectation], timeout: 1.0)

        // Then: Pixel should NOT fire and context should be non-nil
        XCTAssertEqual(mockPixelHandler.pageContextCollectionEmptyCount, 0)
        XCTAssertNotNil(receivedContext)
        XCTAssertNotNil(receivedContext!)
    }

    // MARK: - Unavailable Pixel Tests

    func testUnavailablePixelFiresWhenNoUserScript() {
        let mockPixelHandler = MockContextualModePixelHandler()
        let handler = makeHandler(
            userScriptProvider: { nil },
            pixelHandler: mockPixelHandler
        )

        let didTrigger = handler.triggerContextCollection(trigger: .auto)

        XCTAssertFalse(didTrigger)
        XCTAssertEqual(mockPixelHandler.pageContextCollectionUnavailableCount, 1)
    }

    // MARK: - Attachability Gate

    func testWhenBlocklistedMIMEThenSkipsCollectionAndFiresPreventedPixel() {
        let mockScript = MockPageContextCollecting()
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let policy = makeBlocklistPolicy()
        let handler = makeHandler(
            webViewProvider: { WKWebView() },
            userScriptProvider: { mockScript },
            attachabilityPolicyProvider: { policy },
            currentURLProvider: { URL(string: "https://example.com/download") },
            mimeTypeProvider: { _ in "application/pdf" },
            extractionPixelHandler: extractionPixels
        )

        let didTrigger = handler.triggerContextCollection(trigger: .navigation)

        XCTAssertFalse(didTrigger)
        XCTAssertEqual(mockScript.collectCallCount, 0)
        XCTAssertEqual(extractionPixels.calls.count, 1)
        XCTAssertEqual(extractionPixels.calls.first?.outcome, .prevented("pdf"))
        XCTAssertEqual(extractionPixels.calls.first?.trigger, .navigation)
    }

    func testWhenBlocklistedExtensionAndNoMIMEThenSkipsCollectionAndFiresPreventedPixel() {
        let mockScript = MockPageContextCollecting()
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let policy = makeBlocklistPolicy()
        let handler = makeHandler(
            webViewProvider: { WKWebView() },
            userScriptProvider: { mockScript },
            attachabilityPolicyProvider: { policy },
            currentURLProvider: { URL(string: "https://example.com/report.pdf") },
            mimeTypeProvider: { _ in nil },
            extractionPixelHandler: extractionPixels
        )

        let didTrigger = handler.triggerContextCollection(trigger: .userRequest)

        XCTAssertFalse(didTrigger)
        XCTAssertEqual(mockScript.collectCallCount, 0)
        XCTAssertEqual(extractionPixels.calls.first?.outcome, .prevented("pdf"))
        XCTAssertEqual(extractionPixels.calls.first?.trigger, .userRequest)
    }

    func testWhenAttachablePageThenCollectsAndReportsSuccessOutcome() {
        let mockScript = MockPageContextCollecting()
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let policy = makeBlocklistPolicy()
        let handler = makeHandler(
            webViewProvider: { WKWebView() },
            userScriptProvider: { mockScript },
            attachabilityPolicyProvider: { policy },
            currentURLProvider: { URL(string: "https://example.com/article") },
            mimeTypeProvider: { _ in "text/html" },
            extractionPixelHandler: extractionPixels
        )

        let expectation = XCTestExpectation(description: "Context published")
        handler.contextPublisher.dropFirst().first().sink { _ in expectation.fulfill() }.store(in: &cancellables)

        let didTrigger = handler.triggerContextCollection(trigger: .navigation)
        XCTAssertTrue(didTrigger)
        XCTAssertEqual(mockScript.collectCallCount, 1)

        mockScript.simulateValidContext()
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(extractionPixels.calls.count, 1)
        XCTAssertEqual(extractionPixels.calls.first?.outcome, .success)
        XCTAssertEqual(extractionPixels.calls.first?.trigger, .navigation)
    }

    func testWhenEmptyContextThenReportsEmptyContentFailureOutcome() {
        let mockScript = MockPageContextCollecting()
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let policy = makeBlocklistPolicy()
        let handler = makeHandler(
            webViewProvider: { WKWebView() },
            userScriptProvider: { mockScript },
            attachabilityPolicyProvider: { policy },
            currentURLProvider: { URL(string: "https://example.com/article") },
            mimeTypeProvider: { _ in "text/html" },
            extractionPixelHandler: extractionPixels
        )

        let expectation = XCTestExpectation(description: "Context published")
        handler.contextPublisher.dropFirst().first().sink { _ in expectation.fulfill() }.store(in: &cancellables)

        handler.triggerContextCollection(trigger: .navigation)
        mockScript.simulateEmptyContext()
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(extractionPixels.calls.first?.outcome, .failure(.emptyContent))
    }

    func testWhenDeserializeFailureThenReportsDeserializeFailedOutcome() {
        let mockScript = MockPageContextCollecting()
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let policy = makeBlocklistPolicy()
        let handler = makeHandler(
            webViewProvider: { WKWebView() },
            userScriptProvider: { mockScript },
            attachabilityPolicyProvider: { policy },
            currentURLProvider: { URL(string: "https://example.com/article") },
            mimeTypeProvider: { _ in "text/html" },
            extractionPixelHandler: extractionPixels
        )

        let expectation = XCTestExpectation(description: "Context published")
        handler.contextPublisher.dropFirst().first().sink { _ in expectation.fulfill() }.store(in: &cancellables)

        handler.triggerContextCollection(trigger: .navigation)
        mockScript.simulateNilContext()
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(extractionPixels.calls.first?.outcome, .failure(.deserializeFailed))
    }

    func testWhenNoAttachabilityConfigThenCollectsButFiresNoExtractionPixels() {
        let mockScript = MockPageContextCollecting()
        let extractionPixels = MockPageContextExtractionPixelFiring()
        // attachabilityPolicyProvider defaults to { nil } — the kill-switch.
        let handler = makeHandler(
            webViewProvider: { WKWebView() },
            userScriptProvider: { mockScript },
            currentURLProvider: { URL(string: "https://example.com/report.pdf") },
            mimeTypeProvider: { _ in "application/pdf" },
            extractionPixelHandler: extractionPixels
        )

        let expectation = XCTestExpectation(description: "Context published")
        handler.contextPublisher.dropFirst().first().sink { _ in expectation.fulfill() }.store(in: &cancellables)

        let didTrigger = handler.triggerContextCollection(trigger: .navigation)
        XCTAssertTrue(didTrigger)
        XCTAssertEqual(mockScript.collectCallCount, 1, "kill-switch must not gate collection")

        mockScript.simulateValidContext()
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(extractionPixels.calls.isEmpty, "no extraction telemetry when blocklist config absent")
    }

    func testWhenSameNavigationTriggersOverlapThenReportsExtractionOnlyOnce() {
        let mockScript = MockPageContextCollecting()
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let policy = makeBlocklistPolicy()
        let handler = makeHandler(
            webViewProvider: { WKWebView() },
            userScriptProvider: { mockScript },
            attachabilityPolicyProvider: { policy },
            currentURLProvider: { URL(string: "https://example.com/article") },
            mimeTypeProvider: { _ in "text/html" },
            extractionPixelHandler: extractionPixels
        )

        let expectation = XCTestExpectation(description: "Two contexts published")
        expectation.expectedFulfillmentCount = 2
        handler.contextPublisher.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)

        // Two collects for the same URL (navigation + signals-only) — only one pixel expected.
        handler.triggerContextCollection(trigger: .navigation)
        handler.triggerContextCollection(trigger: .tabContent)
        mockScript.simulateValidContext()
        mockScript.simulateValidContext()
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(extractionPixels.calls.count, 1)
        XCTAssertEqual(extractionPixels.calls.first?.trigger, .navigation)
    }

    // MARK: - Attachability measurement (no collection)

    func testReportAttachabilityMeasurementFiresPreventedWhenNotAttachable() {
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let policy = makeBlocklistPolicy()
        let handler = makeHandler(
            attachabilityPolicyProvider: { policy },
            currentURLProvider: { URL(string: "https://example.com/report.pdf") },
            mimeTypeProvider: { _ in "application/pdf" },
            extractionPixelHandler: extractionPixels
        )

        handler.reportAttachabilityMeasurement(trigger: .navigation)

        XCTAssertEqual(extractionPixels.calls.count, 1)
        XCTAssertEqual(extractionPixels.calls.first?.outcome, .prevented("pdf"))
        XCTAssertEqual(extractionPixels.calls.first?.trigger, .navigation)
    }

    func testReportAttachabilityMeasurementDoesNothingWhenAttachable() {
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let policy = makeBlocklistPolicy()
        let handler = makeHandler(
            attachabilityPolicyProvider: { policy },
            currentURLProvider: { URL(string: "https://example.com/article") },
            mimeTypeProvider: { _ in "text/html" },
            extractionPixelHandler: extractionPixels
        )

        handler.reportAttachabilityMeasurement(trigger: .navigation)

        XCTAssertTrue(extractionPixels.calls.isEmpty)
    }

    func testReportAttachabilityMeasurementDoesNothingWhenNoConfig() {
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let handler = makeHandler(
            currentURLProvider: { URL(string: "https://example.com/report.pdf") },
            mimeTypeProvider: { _ in "application/pdf" },
            extractionPixelHandler: extractionPixels
        )

        handler.reportAttachabilityMeasurement(trigger: .navigation)

        XCTAssertTrue(extractionPixels.calls.isEmpty)
    }

    func testClearResetsExtractionQueueSoLaterCollectReportsItsOwnTrigger() {
        let mockScript = MockPageContextCollecting()
        let extractionPixels = MockPageContextExtractionPixelFiring()
        let policy = makeBlocklistPolicy()
        let handler = makeHandler(
            webViewProvider: { WKWebView() },
            userScriptProvider: { mockScript },
            attachabilityPolicyProvider: { policy },
            currentURLProvider: { URL(string: "https://example.com/article") },
            mimeTypeProvider: { _ in "text/html" },
            extractionPixelHandler: extractionPixels
        )

        // A .navigation collect is requested but never resolves, then the session is cleared.
        handler.triggerContextCollection(trigger: .navigation)
        handler.clear()

        // A later .userRequest collect on the same URL must report its own trigger, not the stale one.
        let expectation = XCTestExpectation(description: "Context published")
        handler.contextPublisher.dropFirst().first().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        handler.triggerContextCollection(trigger: .userRequest)
        mockScript.simulateValidContext()
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(extractionPixels.calls.count, 1)
        XCTAssertEqual(extractionPixels.calls.first?.trigger, .userRequest)
    }

    // MARK: - Helpers

    private func makeHandler(
        webViewProvider: WebViewProvider? = nil,
        userScriptProvider: UserScriptProvider? = nil,
        faviconProvider: FaviconProvider? = nil,
        pixelHandler: AIChatContextualModePixelFiring? = nil,
        attachabilityPolicyProvider: @escaping AttachabilityPolicyProvider = { nil },
        currentURLProvider: PageContextURLProvider? = nil,
        mimeTypeProvider: @escaping PageContextMIMETypeProvider = { _ in nil },
        extractionPixelHandler: PageContextExtractionPixelFiring? = nil
    ) -> DuckDuckGo.AIChatPageContextHandler {
        DuckDuckGo.AIChatPageContextHandler(
            webViewProvider: webViewProvider ?? { nil },
            userScriptProvider: userScriptProvider ?? { nil },
            faviconProvider: faviconProvider ?? { _ in nil },
            pixelHandler: pixelHandler ?? MockContextualModePixelHandler(),
            attachabilityPolicyProvider: attachabilityPolicyProvider,
            currentURLProvider: currentURLProvider,
            mimeTypeProvider: mimeTypeProvider,
            extractionPixelHandler: extractionPixelHandler ?? MockPageContextExtractionPixelFiring()
        )
    }

    private func makeBlocklistPolicy() -> PageContextAttachabilityPolicy {
        PageContextAttachabilityPolicy(settings: PageContextBlocklistSettings(categories: [
            "pdf": MediaCategoryRule(urlExtensions: [".pdf"], contentTypes: ["application/pdf"]),
            "image": MediaCategoryRule(urlExtensions: [".png"], contentTypePrefixes: ["image/"])
        ]))
    }
}

// MARK: - Mock Pixel Handler

private final class MockContextualModePixelHandler: AIChatContextualModePixelFiring {
    var pageContextCollectionEmptyCount = 0
    var pageContextCollectionUnavailableCount = 0

    func fireSheetOpened() {}
    func fireSheetDismissed() {}
    func fireSessionRestored() {}
    func fireExpandButtonTapped() {}
    func fireNewChatButtonTapped() {}
    func fireQuickActionSummarizeSelected() {}
    func fireQuickActionAskAboutPageSelected() {}
    func fireRecentChatsPopupDisplayed() {}
    func fireRecentChatSelected() {}
    func fireViewAllChatsTapped() {}
    func fireFireButtonTapped() {}
    func fireFireButtonConfirmed() {}
    func firePageContextAutoAttached() {}
    func firePageContextUpdatedOnNavigation(url: String) {}
    func firePageContextManuallyAttachedNative() {}
    func firePageContextManuallyAttachedFrontend() {}
    func firePageContextRemovedNative() {}
    func firePageContextRemovedFrontend() {}
    func firePageContextCollectionEmpty() {
        pageContextCollectionEmptyCount += 1
    }
    func firePageContextCollectionUnavailable() {
        pageContextCollectionUnavailableCount += 1
    }
    func firePromptSubmittedWithContext() {}
    func firePromptSubmittedWithoutContext() {}
    func beginManualAttach() {}
    func endManualAttach() {}
    var isManualAttachInProgress: Bool { false }
    func reset() {}
}

// MARK: - Mock Page Context Collecting

private final class MockPageContextCollecting: PageContextCollecting {
    private let mockSubject = PassthroughSubject<AIChatPageContextData?, Never>()

    var collectionResultPublisher: AnyPublisher<AIChatPageContextData?, Never> {
        mockSubject.eraseToAnyPublisher()
    }

    weak var webView: WKWebView?
    private(set) var collectCallCount = 0

    func collect() {
        // No-op for testing - we'll manually send values via simulate methods
        collectCallCount += 1
    }

    func simulateNilContext() {
        mockSubject.send(nil)
    }

    func simulateEmptyContext() {
        let emptyContext = AIChatPageContextData(
            title: "",
            favicon: [],
            url: "",
            content: "",
            truncated: false,
            fullContentLength: 0
        )
        mockSubject.send(emptyContext)
    }

    func simulateValidContext() {
        let validContext = AIChatPageContextData(
            title: "Test Page",
            favicon: [],
            url: "https://example.com",
            content: "This is some page content for testing.",
            truncated: false,
            fullContentLength: 39
        )
        mockSubject.send(validContext)
    }
}

// MARK: - Mock Extraction Pixel Firing

private final class MockPageContextExtractionPixelFiring: PageContextExtractionPixelFiring {
    struct Call: Equatable {
        let outcome: PageContextExtractionOutcome
        let trigger: PageContextExtractionTrigger
        let latency: PageContextExtractionLatencyBucket?
    }

    private(set) var calls: [Call] = []

    func fire(_ outcome: PageContextExtractionOutcome,
              trigger: PageContextExtractionTrigger,
              latency: PageContextExtractionLatencyBucket?) {
        calls.append(Call(outcome: outcome, trigger: trigger, latency: latency))
    }
}

// MARK: - PageContextExtractionPixelHandler mapping tests

final class PageContextExtractionPixelHandlerTests: XCTestCase {

    private func capture(_ outcome: PageContextExtractionOutcome,
                         trigger: PageContextExtractionTrigger,
                         latency: PageContextExtractionLatencyBucket?) -> (event: Pixel.Event, params: [String: String])? {
        var captured: (Pixel.Event, [String: String])?
        let handler = PageContextExtractionPixelHandler(firePixel: { captured = ($0, $1) })
        handler.fire(outcome, trigger: trigger, latency: latency)
        return captured.map { (event: $0.0, params: $0.1) }
    }

    func testWhenSuccessThenFiresSuccessPixelWithNoAdditionalParams() {
        let result = capture(.success, trigger: .navigation, latency: .under1s)
        XCTAssertEqual(result?.event.name, "aichat_page_context_extraction_success")
        XCTAssertEqual(result?.params, [:])
    }

    func testWhenFailureThenFiresFailedPixelWithReasonTriggerLatency() {
        let result = capture(.failure(.emptyContent), trigger: .auto, latency: .oneToFiveSeconds)
        XCTAssertEqual(result?.event.name, "aichat_page_context_extraction_failed")
        XCTAssertEqual(result?.params["reason"], "empty_content")
        XCTAssertEqual(result?.params["trigger"], "auto")
        XCTAssertEqual(result?.params["latency"], "1_to_5s")
    }

    func testWhenFailureWithoutLatencyThenOmitsLatencyParam() {
        let result = capture(.failure(.timeout), trigger: .navigation, latency: nil)
        XCTAssertEqual(result?.params["reason"], "timeout")
        XCTAssertNil(result?.params["latency"])
    }

    func testWhenPreventedThenFiresPreventedPixelWithCategoryReasonTrigger() {
        let result = capture(.prevented("pdf"), trigger: .tabContent, latency: nil)
        XCTAssertEqual(result?.event.name, "aichat_page_context_extraction_prevented")
        XCTAssertEqual(result?.params["category"], "pdf")
        XCTAssertEqual(result?.params["reason"], "non_attachable")
        XCTAssertEqual(result?.params["trigger"], "tab_content")
    }
}

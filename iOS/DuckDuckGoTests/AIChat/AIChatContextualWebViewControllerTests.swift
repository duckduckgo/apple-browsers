//
//  AIChatContextualWebViewControllerTests.swift
//  DuckDuckGo
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

import XCTest
import AIChat
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Combine
import UserScript
import WebKit
@testable import Core
@testable import DuckDuckGo

final class AIChatContextualWebViewControllerTests: XCTestCase {

    @MainActor
    func testQueuedFirstPromptKeepsItsRequestUntilFrontendIsReady() async {
        let sut = makeAttachmentSubmissionController()
        let script = makeTestUserScript()
        let collected = expectation(description: "Captured request collected")
        var collectionCount = 0
        script.attachedTabContextsProvider = { XCTFail("Queued prompt must not read a later draft"); return nil }
        sut.submitPrompt("first", images: nil, files: nil, modelId: nil, tools: nil, reasoningEffort: nil,
                         tabAttachmentRequest: .init(contexts: {
            collectionCount += 1
            collected.fulfill()
            return []
        }, didConsume: {}))
        sut.configureContentHandler(with: script)
        sut.webView(WKWebView(), didFinish: nil)
        XCTAssertEqual(collectionCount, 0)
        sut.markFrontendAsReady()
        await fulfillment(of: [collected], timeout: 1)
        XCTAssertEqual(collectionCount, 1)
        sut.cancelPendingTabAttachmentPrompt()
    }

    @MainActor
    func testCancelledQueuedPromptCannotCollectAfterReadiness() async {
        let sut = makeAttachmentSubmissionController()
        var cancelled = false
        sut.submitPrompt("first", images: nil, files: nil, modelId: nil, tools: nil, reasoningEffort: nil,
                         tabAttachmentRequest: .init(contexts: { XCTFail("Cancelled prompt must not collect"); return [] },
                                                     didConsume: {}, cancel: { cancelled = true }))
        sut.cancelPendingTabAttachmentPrompt()
        XCTAssertTrue(cancelled)
        let script = makeTestUserScript()
        script.attachedTabContextsProvider = { XCTFail("Cancelled prompt must not read draft"); return nil }
        sut.configureContentHandler(with: script)
        sut.webView(WKWebView(), didFinish: nil)
        sut.markFrontendAsReady()
        await Task.yield()
    }

    @MainActor
    func testQueuedRequestIsReleasedOnControllerTeardown() async {
        var sut: AIChatContextualWebViewController? = makeAttachmentSubmissionController()
        let released = expectation(description: "Queued request released")
        sut?.submitPrompt("first", images: nil, files: nil, modelId: nil, tools: nil, reasoningEffort: nil,
                          tabAttachmentRequest: .init(contexts: { XCTFail("Discarded request must not collect"); return [] },
                                                      didConsume: {}, cancel: { released.fulfill() }))
        sut = nil
        await fulfillment(of: [released], timeout: 1)
    }

    @MainActor
    private func makeAttachmentSubmissionController(utiHost: AIChatContextualUTIHost? = nil) -> AIChatContextualWebViewController {
        AIChatContextualWebViewController(aiChatSettings: MockAIChatSettingsProvider(aiChatURL: URL(string: "about:blank")!),
                                          privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                          contentBlockingAssetsPublisher: Empty().eraseToAnyPublisher(),
                                          featureDiscovery: MockFeatureDiscovery(), featureFlagger: MockFeatureFlagger(),
                                          unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: utiHost != nil),
                                          downloadHandler: StubDownloadHandler(), getPageContext: nil,
                                          pixelHandler: StubContextualModePixelHandler(),
                                          onboardingActivationRecorder: NullSubscriptionOnboardingActivationRecorder(),
                                          utiHostInstaller: { _ in utiHost })
    }

    @MainActor
    func testWhenTabContextIsPendingThenRichPromptDeliveryIsReportedOnlyAfterDispatch() async {
        for queued in [false, true] {
            await assertRichPromptDelivery(queued: queued, outcome: .dispatched)
        }
    }

    @MainActor
    func testWhenPendingTabContextSubmissionIsCancelledThenRichPromptDeliveryIsNotReported() async {
        for queued in [false, true] {
            await assertRichPromptDelivery(queued: queued, outcome: .cancelled)
        }
    }

    @MainActor
    func testWhenBridgeIsUnavailableThenRichPromptDeliveryIsNotReported() async {
        for queued in [false, true] {
            await assertRichPromptDelivery(queued: queued, outcome: .unavailableBridge)
        }
    }

    private enum SubmissionOutcome {
        case dispatched, cancelled, unavailableBridge
    }

    @MainActor
    private func assertRichPromptDelivery(queued: Bool, outcome: SubmissionOutcome,
                                          file: StaticString = #filePath, line: UInt = #line) async {
        let instrumentation = MockDuckAIWideEventInstrumentation()
        let host = AIChatContextualUTIHost(originatingURLPublisher: Empty<URL?, Never>().eraseToAnyPublisher(),
                                           initialAttachedContext: nil, hasActiveChat: { true },
                                           isAutoAttachEnabled: { false }, isFireTab: false,
                                           duckAIWideEventInstrumentation: instrumentation)
        let sut = makeAttachmentSubmissionController(utiHost: host)
        sut.loadViewIfNeeded()
        let script = makeTestUserScript()
        let broker = UserScriptMessageBroker(context: "test", requiresRunInPageContentWorld: true)
        script.with(broker: broker)
        sut.configureContentHandler(with: script)
        sut.webView(WKWebView(), didFinish: nil)
        if !queued {
            sut.markFrontendAsReady()
        }

        let collecting = expectation(description: "Collecting tab context")
        let finished = expectation(description: "Pending submission finished")
        if outcome == .cancelled {
            finished.isInverted = true
            instrumentation.onPromptDeliveryUpdated = { didSendBridgeMessage in
                if didSendBridgeMessage == true { finished.fulfill() }
            }
        }
        var continuation: CheckedContinuation<[AIChatPageContextData], Never>?
        var consumed = false
        let request = MultiTabAttachmentRequest(contexts: {
            await withCheckedContinuation {
                continuation = $0
                collecting.fulfill()
            }
        }, didConsume: { consumed = true }, cancel: {
            // Cancellation also releases the request before its suspended task finishes.
            if outcome != .cancelled { finished.fulfill() }
        })
        sut.submitPrompt("prompt", images: nil, files: nil, modelId: nil, tools: nil,
                         reasoningEffort: nil, tabAttachmentRequest: request)
        if queued {
            XCTAssertEqual(instrumentation.promptDeliveryUpdates.count, 1, file: file, line: line)
            XCTAssertEqual(instrumentation.promptDeliveryUpdates.first?.wasQueued, true, file: file, line: line)
            XCTAssertNil(instrumentation.promptDeliveryUpdates.first?.didSendBridgeMessage, file: file, line: line)
            sut.markFrontendAsReady()
        }
        await fulfillment(of: [collecting], timeout: 1)
        XCTAssertEqual(instrumentation.promptDeliveryUpdates.count, queued ? 1 : 0, file: file, line: line)

        switch outcome {
        case .dispatched: break
        case .cancelled: sut.cancelPendingTabAttachmentPrompt()
        case .unavailableBridge: script.broker = nil
        }
        continuation?.resume(returning: [])
        await fulfillment(of: [finished], timeout: outcome == .cancelled ? 0.1 : 1)

        let dispatched = outcome == .dispatched
        XCTAssertEqual(consumed, dispatched, file: file, line: line)
        XCTAssertEqual(instrumentation.promptDeliveryUpdates.count, (queued ? 1 : 0) + (dispatched ? 1 : 0), file: file, line: line)
        if dispatched {
            XCTAssertEqual(instrumentation.promptDeliveryUpdates.last?.didSendBridgeMessage, true, file: file, line: line)
            XCTAssertEqual(instrumentation.promptDeliveryUpdates.last?.wasQueued, queued ? nil : false, file: file, line: line)
        }
        withExtendedLifetime(broker) {}
    }

    // MARK: - Tests

    @MainActor
    func testWhenFrontendReadinessIsMarkedThenWaitingSucceeds() async {
        let readinessGate = AIChatFrontendReadinessGate()
        let resultTask = await makePendingReadinessTask(for: readinessGate)

        readinessGate.markReady()

        let result = await resultTask.value
        XCTAssertTrue(result)
    }

    @MainActor
    func testWhenFrontendIsAlreadyReadyThenWaitingSucceedsImmediately() async {
        let readinessGate = AIChatFrontendReadinessGate()
        readinessGate.markReady()

        let result = await readinessGate.waitUntilReady(timeout: 0)

        XCTAssertTrue(result)
    }

    @MainActor
    func testWhenFrontendReadinessIsResetThenPendingWaitFails() async {
        let readinessGate = AIChatFrontendReadinessGate()
        let resultTask = await makePendingReadinessTask(for: readinessGate)

        readinessGate.reset()

        let result = await resultTask.value
        XCTAssertFalse(result)
    }

    @MainActor
    func testWhenFrontendReadinessWaitIsCancelledThenReplacementCanSucceed() async {
        let readinessGate = AIChatFrontendReadinessGate()
        let cancelledTask = await makePendingReadinessTask(for: readinessGate)

        cancelledTask.cancel()
        let replacementTask = await makePendingReadinessTask(for: readinessGate)
        readinessGate.markReady()

        let cancelledResult = await cancelledTask.value
        let replacementResult = await replacementTask.value
        XCTAssertFalse(cancelledResult)
        XCTAssertTrue(replacementResult)
    }

    @MainActor
    func testWhenFrontendReadinessTimesOutThenWaitingFails() async {
        let readinessGate = AIChatFrontendReadinessGate()

        let result = await readinessGate.waitUntilReady(timeout: 0)

        XCTAssertFalse(result)
    }

    @MainActor
    private func makePendingReadinessTask(for readinessGate: AIChatFrontendReadinessGate) async -> Task<Bool, Never> {
        let readinessWaitStarted = expectation(description: "Frontend readiness wait started")
        let resultTask = Task { @MainActor in
            await readinessGate.waitUntilReady(timeout: 1) {
                readinessWaitStarted.fulfill()
            }
        }
        await fulfillment(of: [readinessWaitStarted], timeout: 1)
        return resultTask
    }

    @MainActor
    func testWebViewUsesCustomUserAgent() {
        let expectedURL = URL(string: "https://duck.ai/chat")!
        let stubUserAgent = StubUserAgentManager(stubbedUserAgent: "ddg_ios/7.100.0 (com.duckduckgo; iOS 17.0)")

        let sut = AIChatContextualWebViewController(
            aiChatSettings: MockAIChatSettingsProvider(aiChatURL: expectedURL),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: Empty().eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: MockFeatureFlagger(),
            downloadHandler: StubDownloadHandler(),
            getPageContext: nil,
            pixelHandler: StubContextualModePixelHandler(),
            userAgentManager: stubUserAgent,
            onboardingActivationRecorder: NullSubscriptionOnboardingActivationRecorder()
        )

        sut.loadViewIfNeeded()

        let webView = sut.view.firstSubview(ofType: WKWebView.self)
        XCTAssertNotNil(webView)
        XCTAssertEqual(webView?.customUserAgent, "ddg_ios/7.100.0 (com.duckduckgo; iOS 17.0)")
        XCTAssertEqual(stubUserAgent.capturedURL, expectedURL)
        XCTAssertEqual(stubUserAgent.capturedIsDesktop, false)
    }

    @MainActor
    func testWebViewUsesDefaultUserAgentManagerWhenNoneProvided() {
        let sut = AIChatContextualWebViewController(
            aiChatSettings: MockAIChatSettingsProvider(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: Empty().eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: MockFeatureFlagger(),
            downloadHandler: StubDownloadHandler(),
            getPageContext: nil,
            pixelHandler: StubContextualModePixelHandler(),
            onboardingActivationRecorder: NullSubscriptionOnboardingActivationRecorder()
        )

        sut.loadViewIfNeeded()

        let webView = sut.view.firstSubview(ofType: WKWebView.self)
        XCTAssertNotNil(webView)
        XCTAssertNotNil(webView?.customUserAgent)
        XCTAssertFalse(webView?.customUserAgent?.isEmpty ?? true)
    }

    @MainActor
    func testChatURLForLoadingWhenNativeInputUnavailableRemovesStaleNativeInputParameter() {
        let sut = AIChatContextualWebViewController(
            aiChatSettings: MockAIChatSettingsProvider(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: Empty().eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: MockFeatureFlagger(),
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: false),
            downloadHandler: StubDownloadHandler(),
            getPageContext: nil,
            pixelHandler: StubContextualModePixelHandler(),
            onboardingActivationRecorder: NullSubscriptionOnboardingActivationRecorder()
        )
        let restoreURL = URL(string: "https://duck.ai/chat?native-input=true")!

        let url = sut.chatURLForLoading(restoreURL)

        XCTAssertEqual(url.absoluteString, "https://duck.ai/chat")
    }

    @MainActor
    func testChatURLForLoadingDoesNotRewriteNonDuckAIURL() {
        let sut = AIChatContextualWebViewController(
            aiChatSettings: MockAIChatSettingsProvider(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: Empty().eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: MockFeatureFlagger(),
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true),
            downloadHandler: StubDownloadHandler(),
            getPageContext: nil,
            pixelHandler: StubContextualModePixelHandler(),
            onboardingActivationRecorder: NullSubscriptionOnboardingActivationRecorder()
        )
        let url = URL(string: "https://example.com/path")!

        let result = sut.chatURLForLoading(url)

        XCTAssertEqual(result, url)
    }
}

// MARK: - Helpers

private extension UIView {
    func firstSubview<T: UIView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }
            if let match = subview.firstSubview(ofType: type) {
                return match
            }
        }
        return nil
    }
}

// MARK: - Stubs

private final class StubUserAgentManager: UserAgentManaging {
    let stubbedUserAgent: String
    var capturedURL: URL?
    var capturedIsDesktop: Bool?

    init(stubbedUserAgent: String) {
        self.stubbedUserAgent = stubbedUserAgent
    }

    func extractAndSetDefaultUserAgent() async throws -> String { stubbedUserAgent }
    func setDefaultUserAgent(_ userAgent: String) {}
    func userAgent(isDesktop: Bool) -> String { stubbedUserAgent }

    func userAgent(isDesktop: Bool, url: URL?) -> String {
        capturedIsDesktop = isDesktop
        capturedURL = url
        return stubbedUserAgent
    }

    func safariOnlyUserAgent(isDesktop: Bool) -> String {
        stubbedUserAgent
    }

    func update(request: inout URLRequest, isDesktop: Bool) {}
    func update(webView: WKWebView, isDesktop: Bool, url: URL?) {}

    var applicationNameForUserAgent: String { "" }
}

private final class StubDownloadHandler: NSObject, DownloadHandling {
    var onDownloadComplete: DownloadCompletionHandler?

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        return nil
    }
}

private final class StubContextualModePixelHandler: AIChatContextualModePixelFiring {
    func fireSheetOpened() {}
    func fireSheetDismissed(hadUnsubmittedSelections: Bool) {}
    func fireSessionRestored() {}
    func fireSheetOpenedOnDeletedChat() {}
    func firePromptDepth(_ bucket: AIChatContextualPromptDepthBucket) {}
    func firePageContextOfferShown(reason: AIChatContextualPageContextOfferReason) {}
    func firePageContextOfferAccepted(reason: AIChatContextualPageContextOfferReason) {}
    func fireSelectionAttached() {}
    func fireSelectionLimitReached() {}
    func fireSelectionRemoved() {}
    func firePromptSubmittedWithSelections(count: Int) {}
    func fireSelectionToolDeliveryTimedOut() {}
    func fireExpandButtonTapped() {}
    func fireHeaderTitleTapped() {}
    func fireNewChatButtonTapped() {}
    func fireQuickActionSummarizeSelected() {}
    func fireQuickActionAskAboutPageShown() {}
    func fireQuickActionAskAboutPageSelected() {}
    func fireAskAboutPageSuggestionSelected(pageType: SuggestionsPageType) {}
    func fireSuggestionSelected(suggestionId: String, pageType: SuggestionsPageType) {}
    func fireSuggestionsViewed(isSmart: Bool,
                               pageType: SuggestionsPageType,
                               scope: ResolvePageSuggestionsInput.Scope,
                               surface: AIChatContextualSuggestionsSurface) {}
    func fireSuggestionsContextCollectionTimedOut() {}
    func fireRecentChatsMenuDisplayed() {}
    func fireRecentChatSelected() {}
    func fireViewAllChatsTapped() {}
    func fireFireButtonTapped() {}
    func fireFireButtonConfirmed() {}
    func fireAddressBarMenuShown() {}
    func fireAddressBarMenuNewChatSelected() {}
    func fireAddressBarMenuAskAboutPageSelected() {}
    func fireAddressBarMenuAskAboutSearchSelected() {}
    func fireAddressBarMenuRecentChatsSelected() {}
    func fireFloatingInputDismissedWithoutSubmission(hadUnsubmittedSelections: Bool) {}
    func fireFloatingInputPromotedToSheet() {}
    func firePageContextAutoAttached() {}
    func firePageContextUpdatedOnNavigation(url: String) {}
    func firePageContextManuallyAttachedNative() {}
    func firePageContextManuallyAttachedFrontend() {}
    func firePageContextRemovedNative() {}
    func firePageContextRemovedFrontend() {}
    func firePageContextCollectionEmpty() {}
    func fireTabAttachmentCollectionWaitTimedOut(reason: MultiTabCollectionWaitTimeoutPixel.Reason) {}
    func firePageContextCollectionUnavailable() {}
    func firePromptSubmittedWithContext() {}
    func firePromptSubmittedWithoutContext() {}
    func beginManualAttach() {}
    func endManualAttach() {}
    var isManualAttachInProgress: Bool { false }
    func reset() {}
}

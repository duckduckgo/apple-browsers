//
//  TabCrashRecoveryExtensionTests.swift
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

import AppKit
import Combine
import FeatureFlags_macOS
import Navigation
import PixelKit
import PrivacyConfig
import SharedTestUtilities
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// This WKWebView subclass allows for counting calls to `reload`.
final class ReloadCapturingWebView: WKWebView {
    override func reload() -> WKNavigation? {
        reloadCallsCount += 1
        return super.reload()
    }
    var reloadCallsCount: Int = 0
}

final class CapturingTabCrashLoopDetector: TabCrashLoopDetecting {
    func currentDate() -> Date { date }

    func isCrashLoop(for crashTimestamp: Date, lastCrashTimestamp: Date?) -> Bool {
        isCrashLoopCalls.append(.init(crashTimestamp, lastCrashTimestamp))
        return isCrashLoop(crashTimestamp, lastCrashTimestamp)
    }

    struct IsCrashLoopCall: Equatable {
        let crashTimestamp: Date
        let lastCrashTimestamp: Date?

        init(_ crashTimestamp: Date, _ lastCrashTimestamp: Date?) {
            self.crashTimestamp = crashTimestamp
            self.lastCrashTimestamp = lastCrashTimestamp
        }
    }

    var date: Date = Date()
    var isCrashLoop: (Date, Date?) -> Bool = { _, _ in false }
    var isCrashLoopCalls: [IsCrashLoopCall] = []
}

final class TabCrashRecoveryExtensionTests: XCTestCase {

    var tabCrashRecoveryExtension: TabCrashRecoveryExtension!
    var contentSubject: PassthroughSubject<Tab.TabContent, Never>!
    var webViewSubject: PassthroughSubject<WKWebView, Never>!
    var webViewErrorSubject: PassthroughSubject<WKError?, Never>!
    var internalUserDeciderStore: MockInternalUserStoring!
    var featureFlagger: MockFeatureFlagger!
    var crashLoopDetector: CapturingTabCrashLoopDetector!
    var window: MockWindow!
    var webView: ReloadCapturingWebView!

    var tabCrashTypes: [TabCrashType] = []
    var tabCrashErrorPayloads: [TabCrashErrorPayload] = []
    var cancellables: Set<AnyCancellable> = []

    var firePixelCallCount: Int = 0
    var firePixelHandler: (PixelKit.Event, [String: String]) -> Void = { _, _ in }
    var reportBrokenSiteCallCount = 0
    var reportBrokenSiteSourceWindow: NSWindow?

    @MainActor
    override func setUp() async throws {
        internalUserDeciderStore = MockInternalUserStoring()
        featureFlagger = MockFeatureFlagger(internalUserDecider: DefaultInternalUserDecider(store: internalUserDeciderStore))
        contentSubject = PassthroughSubject()
        webViewSubject = PassthroughSubject()
        webViewErrorSubject = PassthroughSubject()
        crashLoopDetector = CapturingTabCrashLoopDetector()
        window = MockWindow()
        webView = ReloadCapturingWebView()
        window.contentView = webView

        firePixelCallCount = 0
        firePixelHandler = { _, _ in }
        reportBrokenSiteCallCount = 0
        reportBrokenSiteSourceWindow = nil

        tabCrashErrorPayloads = []
        cancellables.forEach { $0.cancel() }
        cancellables = []

        tabCrashRecoveryExtension = TabCrashRecoveryExtension(
            featureFlagger: featureFlagger,
            contentPublisher: contentSubject.eraseToAnyPublisher(),
            webViewPublisher: webViewSubject.eraseToAnyPublisher(),
            webViewErrorPublisher: webViewErrorSubject.eraseToAnyPublisher(),
            crashLoopDetector: crashLoopDetector,
            firePixel: {
                self.firePixelCallCount += 1
                self.firePixelHandler($0, $1)
            },
            reportBrokenSite: { sourceWindow in
                self.reportBrokenSiteCallCount += 1
                self.reportBrokenSiteSourceWindow = sourceWindow
            },
            tabCrashAggregator: TabCrashAggregator()
        )

        tabCrashRecoveryExtension.tabCrashErrorPayloadPublisher
            .sink { [weak self] payload in
                self?.tabCrashErrorPayloads.append(payload)
            }
            .store(in: &cancellables)

        tabCrashRecoveryExtension.tabDidCrashPublisher
            .sink { [weak self] crashType in
                self?.tabCrashTypes.append(crashType)
            }
            .store(in: &cancellables)
    }

    private func setUpRegularTab() {
        webViewSubject.send(webView)
        contentSubject.send(.url(.duckDuckGo, credential: nil, source: .historyEntry))
    }

    private func makeNavigationAction(url: URL = .errorPageReportBrokenSite,
                                      isUserInitiated: Bool = true,
                                      sourceIsMainFrame: Bool = true,
                                      targetIsMainFrame: Bool = true,
                                      sourceURL: URL = .error) -> NavigationAction {
        NavigationAction(
            request: URLRequest(url: url),
            navigationType: .linkActivated(isMiddleClick: false),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: isUserInitiated,
            sourceFrame: FrameInfo(webView: webView,
                                   handle: FrameHandle(rawValue: 1 as UInt64)!,
                                   isMainFrame: sourceIsMainFrame,
                                   url: sourceURL,
                                   securityOrigin: .empty),
            targetFrame: FrameInfo(webView: webView,
                                   handle: FrameHandle(rawValue: 1 as UInt64)!,
                                   isMainFrame: targetIsMainFrame,
                                   url: sourceURL,
                                   securityOrigin: .empty),
            shouldDownload: false,
            mainFrameNavigation: nil
        )
    }

    @MainActor
    override func tearDown() {
        featureFlagger = nil
        internalUserDeciderStore = nil
        crashLoopDetector = nil
        window = nil
        webView = nil
        tabCrashRecoveryExtension = nil
        contentSubject = nil
        webViewSubject = nil
        webViewErrorSubject = nil
        cancellables = []
        tabCrashTypes = []
        tabCrashErrorPayloads = []
        firePixelCallCount = 0
        firePixelHandler = { _, _ in }
        reportBrokenSiteCallCount = 0
        reportBrokenSiteSourceWindow = nil
    }

    @MainActor
    func testWhenReportBrokenSiteNavigationIsEligibleThenItIsCancelledAndReportIsOpened() async {
        setUpRegularTab()
        webViewErrorSubject.send(WKError(.webContentProcessTerminated))
        var preferences = NavigationPreferences.default

        let policy = await tabCrashRecoveryExtension.decidePolicy(for: makeNavigationAction(), preferences: &preferences)

        XCTAssertEqual(policy.debugDescription, "cancel")
        XCTAssertEqual(reportBrokenSiteCallCount, 1)
        XCTAssertIdentical(reportBrokenSiteSourceWindow, window)
    }

    @MainActor
    func testWhenEligibleReportNavigationStartsAtOriginalURLThenReportIsOpened() async {
        setUpRegularTab()
        webViewErrorSubject.send(WKError(.webContentProcessTerminated))
        var preferences = NavigationPreferences.default
        let action = makeNavigationAction(sourceURL: .duckDuckGo)

        let policy = await tabCrashRecoveryExtension.decidePolicy(for: action, preferences: &preferences)

        XCTAssertEqual(policy.debugDescription, "cancel")
        XCTAssertEqual(reportBrokenSiteCallCount, 1)
    }

    @MainActor
    func testWhenReportBrokenSiteNavigationIsNotEligibleThenItIsCancelledWithoutOpeningReport() async {
        setUpRegularTab()
        webViewErrorSubject.send(WKError(.webContentProcessTerminated))
        var preferences = NavigationPreferences.default
        let actions = [
            makeNavigationAction(isUserInitiated: false),
            makeNavigationAction(sourceIsMainFrame: false),
            makeNavigationAction(targetIsMainFrame: false)
        ]

        for action in actions {
            let policy = await tabCrashRecoveryExtension.decidePolicy(for: action, preferences: &preferences)
            XCTAssertEqual(policy.debugDescription, "cancel")
        }

        XCTAssertEqual(reportBrokenSiteCallCount, 0)
    }

    @MainActor
    func testWhenReportBrokenSiteNavigationOccursWithoutTerminationErrorThenItIsCancelledWithoutOpeningReport() async {
        setUpRegularTab()
        var preferences = NavigationPreferences.default

        let policy = await tabCrashRecoveryExtension.decidePolicy(for: makeNavigationAction(), preferences: &preferences)

        XCTAssertEqual(policy.debugDescription, "cancel")
        XCTAssertEqual(reportBrokenSiteCallCount, 0)
    }

    @MainActor
    func testWhenNavigationDoesNotTargetReportBrokenSiteThenDecisionPassesToNextResponder() async {
        setUpRegularTab()
        webViewErrorSubject.send(WKError(.webContentProcessTerminated))
        var preferences = NavigationPreferences.default
        let action = makeNavigationAction(url: .duckDuckGo)

        let policy = await tabCrashRecoveryExtension.decidePolicy(for: action, preferences: &preferences)

        XCTAssertEqual(policy.debugDescription, "next")
        XCTAssertEqual(reportBrokenSiteCallCount, 0)
    }

    @MainActor
    func testWhenWebViewIsNotSetThenWebViewIsNotReloadedAndTabCrashErrorIsNotEmitted() async {
        internalUserDeciderStore.isInternalUser = false

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)
        XCTAssertEqual(webView.reloadCallsCount, 0)
        XCTAssertEqual(tabCrashErrorPayloads.count, 0)
    }

    @MainActor
    func testWhenCurrentWebViewErrorIsWebKitTerminationThenWebViewIsNotReloadedAndTabCrashErrorIsNotEmitted() async {
        setUpRegularTab()
        webViewErrorSubject.send(WKError(.webContentProcessTerminated))

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)
        XCTAssertEqual(webView.reloadCallsCount, 0)
        XCTAssertEqual(tabCrashErrorPayloads.count, 0)
    }

    @MainActor
    func testThatWebKitTerminationFiresPixel() async {
        let expectation = expectation(description: "pixel fired")
        firePixelHandler = { _, _ in
            expectation.fulfill()
        }
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)

        XCTAssertEqual(webView.reloadCallsCount, 1)
        XCTAssertEqual(tabCrashErrorPayloads.count, 0)
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(firePixelCallCount, 1)
    }

    @MainActor
    func testWhenWebKitTerminationOccursThenWebViewIsReloadedAndTabCrashErrorIsNotEmitted() async {
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)
        XCTAssertEqual(webView.reloadCallsCount, 1)
        XCTAssertEqual(tabCrashTypes, [.single])
        XCTAssertEqual(tabCrashErrorPayloads.count, 0)
    }

    @MainActor
    func testWhenWebKitTerminationOccursAndIsCrashLoopThenWebViewIsNotReloadedAndTabCrashErrorIsEmitted() async {
        crashLoopDetector.isCrashLoop = { _, _ in true }
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)
        XCTAssertEqual(webView.reloadCallsCount, 0)
        XCTAssertEqual(tabCrashTypes, [.crashLoop])
        XCTAssertEqual(tabCrashErrorPayloads.count, 1)
    }

    @MainActor
    func testThatLastCrashedAtIsRemembered() async {
        crashLoopDetector.isCrashLoop = { _, _ in false }
        setUpRegularTab()

        let firstCrashTimestamp = Date()
        crashLoopDetector.date = firstCrashTimestamp
        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)

        let secondCrashTimestamp = Date()
        crashLoopDetector.date = secondCrashTimestamp
        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)

        XCTAssertEqual(crashLoopDetector.isCrashLoopCalls, [
            .init(firstCrashTimestamp, nil),
            .init(secondCrashTimestamp, firstCrashTimestamp)
        ])
    }

    @MainActor
    func testThatCrashLoopFiresCrashLoopPixel() async {

        let expectation = expectation(description: "pixel fired")
        firePixelHandler = { event, _ in
            if case GeneralPixel.webKitTerminationLoop = event {
                expectation.fulfill()
            }
        }
        crashLoopDetector.isCrashLoop = { _, _ in true }
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)

        await fulfillment(of: [expectation], timeout: 1)
    }
}

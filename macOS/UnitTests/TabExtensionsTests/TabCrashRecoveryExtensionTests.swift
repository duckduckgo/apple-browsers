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

import BrowserServicesKit
import Combine
import FeatureFlags
import PixelKit
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
    var webView: ReloadCapturingWebView!

    var tabCrashTypes: [TabCrashType] = []
    var tabCrashErrorPayloads: [TabCrashErrorPayload] = []
    var cancellables: Set<AnyCancellable> = []

    var firePixelCallCount: Int = 0
    var firePixelHandler: (PixelKitEvent, [String: String]) -> Void = { _, _ in }

    @MainActor
    override func setUp() async throws {
        internalUserDeciderStore = MockInternalUserStoring()
        featureFlagger = MockFeatureFlagger(internalUserDecider: DefaultInternalUserDecider(store: internalUserDeciderStore))
        contentSubject = PassthroughSubject()
        webViewSubject = PassthroughSubject()
        webViewErrorSubject = PassthroughSubject()
        crashLoopDetector = CapturingTabCrashLoopDetector()
        webView = ReloadCapturingWebView()

        firePixelCallCount = 0
        firePixelHandler = { _, _ in }

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
            }
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

    @MainActor
    func testWhenWebViewIsNotSetThenWebViewIsNotReloadedAndTabCrashErrorIsNotEmitted() async {
        internalUserDeciderStore.isInternalUser = false
        featureFlagger.isFeatureOn = { _ in false }

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

    // MARK: Feature flag disabled

    @MainActor
    func testWhenFeatureFlagIsDisabledAndUserIsInternalThenWebViewIsReloadedAndTabCrashErrorIsNotEmitted() async {
        featureFlagger.isFeatureOn = { _ in false }
        internalUserDeciderStore.isInternalUser = true
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)
        XCTAssertEqual(webView.reloadCallsCount, 1)
        XCTAssertEqual(tabCrashTypes, [])
        XCTAssertEqual(tabCrashErrorPayloads.count, 0)
    }

    @MainActor
    func testWhenFeatureFlagIsDisabledAndUserIsInternalAndTabCrashDebuggingIsEnabledThenWebViewIsNotReloadedAndTabCrashErrorIsEmitted() async {
        featureFlagger.isFeatureOn = { flag in
            switch flag {
            case FeatureFlag.tabCrashDebugging:
                return true
            default:
                return false
            }
        }
        internalUserDeciderStore.isInternalUser = true
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)
        XCTAssertEqual(webView.reloadCallsCount, 0)
        XCTAssertEqual(tabCrashTypes, [])
        XCTAssertEqual(tabCrashErrorPayloads.count, 1)
    }

    @MainActor
    func testWhenFeatureFlagIsDisabledAndUserIsNotInternalThenWebViewIsNotReloadedAndTabCrashErrorIsEmitted() async {
        featureFlagger.isFeatureOn = { _ in false }
        internalUserDeciderStore.isInternalUser = false
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)
        XCTAssertEqual(webView.reloadCallsCount, 0)
        XCTAssertEqual(tabCrashTypes, [])
        XCTAssertEqual(tabCrashErrorPayloads.count, 1)
    }

    // MARK: Feature flag enabled

    @MainActor
    func testWhenFeatureFlagIsEnabledThenWebViewIsReloadedAndTabCrashErrorIsNotEmitted() async {
        featureFlagger.isFeatureOn = { _ in true }
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)
        XCTAssertEqual(webView.reloadCallsCount, 1)
        XCTAssertEqual(tabCrashTypes, [.single])
        XCTAssertEqual(tabCrashErrorPayloads.count, 0)
    }

    @MainActor
    func testWhenFeatureFlagIsEnabledAndIsCrashLoopThenWebViewIsNotReloadedAndTabCrashErrorIsEmitted() async {
        featureFlagger.isFeatureOn = { _ in true }
        crashLoopDetector.isCrashLoop = { _, _ in true }
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)
        XCTAssertEqual(webView.reloadCallsCount, 0)
        XCTAssertEqual(tabCrashTypes, [.crashLoop])
        XCTAssertEqual(tabCrashErrorPayloads.count, 1)
    }

    @MainActor
    func testThatLastCrashedAtIsRemembered() async {
        featureFlagger.isFeatureOn = { _ in true }
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
        featureFlagger.isFeatureOn = { _ in true }
        crashLoopDetector.isCrashLoop = { _, _ in true }
        setUpRegularTab()

        tabCrashRecoveryExtension.webContentProcessDidTerminate(with: nil)

        await fulfillment(of: [expectation], timeout: 1)
    }
}

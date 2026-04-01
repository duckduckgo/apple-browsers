//
//  TabSuspensionExtensionTests.swift
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

import Combine
import PrivacyConfig
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class TabSuspensionExtensionTests: XCTestCase {

    private var webViewPublisher: PassthroughSubject<WKWebView, Never>!
    private var contentPublisher: PassthroughSubject<Tab.TabContent, Never>!
    private var featureFlagger: MockFeatureFlagger!
    private var isPinned: Bool!

    private var sut: TabSuspensionExtension!

    override func setUp() {
        super.setUp()
        webViewPublisher = PassthroughSubject<WKWebView, Never>()
        contentPublisher = PassthroughSubject<Tab.TabContent, Never>()
        featureFlagger = MockFeatureFlagger()
        isPinned = false
    }

    override func tearDown() {
        sut = nil
        webViewPublisher = nil
        contentPublisher = nil
        featureFlagger = nil
        isPinned = nil
        super.tearDown()
    }

    @MainActor
    private func makeSUT() -> TabSuspensionExtension {
        TabSuspensionExtension(
            webViewPublisher: webViewPublisher,
            contentPublisher: contentPublisher,
            featureFlagger: featureFlagger,
            isTabPinned: { [unowned self] in self.isPinned }
        )
    }

    // MARK: - Feature Flag

    @MainActor
    func testWhenFeatureFlagDisabled_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        let webView = WKWebView(frame: .zero)
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenFeatureFlagEnabled_AndConditionsMet_ThenCanBeSuspendedIsTrue() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = WKWebView(frame: .zero)
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertTrue(sut.canBeSuspended)
    }

    // MARK: - Tab Content

    @MainActor
    func testWhenContentIsNone_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = WKWebView(frame: .zero)
        webViewPublisher.send(webView)
        contentPublisher.send(.none)

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenContentIsNewtab_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = WKWebView(frame: .zero)
        webViewPublisher.send(webView)
        contentPublisher.send(.newtab)

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenContentIsDuckPlayerURL_ThenCanBeSuspendedIsFalse() throws {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let duckPlayerURL = try XCTUnwrap(URL(string: "duck://player/abc123"))
        let webView = WKWebView(frame: .zero)
        webViewPublisher.send(webView)
        contentPublisher.send(.url(duckPlayerURL, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenContentIsRegularURL_ThenCanBeSuspendedIsTrue() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = WKWebView(frame: .zero)
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertTrue(sut.canBeSuspended)
    }

    // MARK: - Pinned State

    @MainActor
    func testWhenTabIsPinned_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        isPinned = true
        sut = makeSUT()

        let webView = WKWebView(frame: .zero)
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    // MARK: - WebView

    @MainActor
    func testWhenNoWebView_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }
}

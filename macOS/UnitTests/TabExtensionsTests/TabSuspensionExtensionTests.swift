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
import Common
import FoundationExtensions
@testable import Navigation
import PrivacyConfig
import PrivacyConfigTestsUtils
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class TabSuspensionExtensionTests: XCTestCase {

    private var webViewPublisher: PassthroughSubject<TabSuspensionWebViewChecking, Never>!
    private var contentPublisher: PassthroughSubject<Tab.TabContent, Never>!
    private var scriptsPublisher: PassthroughSubject<MockTabSuspensionUserScriptProvider, Never>!
    private var featureFlagger: MockFeatureFlagger!
    private var aiChatSessionStore: MockAIChatSessionStore!
    private var privacyConfigurationManager: MockPrivacyConfigurationManager!
    private var mockPrivacyConfig: MockPrivacyConfiguration!
    private var isPinned: Bool!
    private var tabID: TabIdentifier!

    private var sut: TabSuspensionExtension!

    override func setUp() {
        super.setUp()
        webViewPublisher = PassthroughSubject<TabSuspensionWebViewChecking, Never>()
        contentPublisher = PassthroughSubject<Tab.TabContent, Never>()
        scriptsPublisher = PassthroughSubject<MockTabSuspensionUserScriptProvider, Never>()
        featureFlagger = MockFeatureFlagger()
        aiChatSessionStore = MockAIChatSessionStore()
        mockPrivacyConfig = MockPrivacyConfiguration()
        privacyConfigurationManager = MockPrivacyConfigurationManager(privacyConfig: mockPrivacyConfig)
        isPinned = false
        tabID = "test-tab-id"
    }

    override func tearDown() {
        sut = nil
        webViewPublisher = nil
        contentPublisher = nil
        scriptsPublisher = nil
        featureFlagger = nil
        aiChatSessionStore = nil
        mockPrivacyConfig = nil
        privacyConfigurationManager = nil
        isPinned = nil
        tabID = nil
        super.tearDown()
    }

    @MainActor
    private func makeSUT() -> TabSuspensionExtension {
        TabSuspensionExtension(
            tabID: tabID,
            webViewPublisher: webViewPublisher,
            contentPublisher: contentPublisher,
            scriptsPublisher: scriptsPublisher,
            featureFlagger: featureFlagger,
            aiChatSessionStore: aiChatSessionStore,
            privacyConfigurationManager: privacyConfigurationManager,
            tld: TLD(),
            isTabPinned: { [unowned self] in self.isPinned }
        )
    }

    // MARK: - Feature Flag

    @MainActor
    func testWhenFeatureFlagDisabled_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenFeatureFlagEnabled_AndConditionsMet_ThenCanBeSuspendedIsTrue() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertTrue(sut.canBeSuspended)
    }

    // MARK: - Tab Content

    @MainActor
    func testWhenContentIsNone_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.none)

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenContentIsNewtab_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.newtab)

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenContentIsFileURL_ThenCanBeSuspendedIsFalse() throws {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test/document.html"))
        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(fileURL, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenContentIsDuckPlayerURL_ThenCanBeSuspendedIsFalse() throws {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let duckPlayerURL = try XCTUnwrap(URL(string: "duck://player/abc123"))
        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(duckPlayerURL, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenContentIsDuckAIURL_ThenCanBeSuspendedIsFalse() throws {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let duckAIURL = try XCTUnwrap(URL(string: "https://duck.ai"))
        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(duckAIURL, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenContentIsRegularURL_ThenCanBeSuspendedIsTrue() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertTrue(sut.canBeSuspended)
    }

    // MARK: - Privacy Configuration

    @MainActor
    func testWhenDomainIsInExceptionsList_ThenCanBeSuspendedIsFalse() throws {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        mockPrivacyConfig.isFeatureEnabledForDomainCheck = { feature, domain in
            if feature == .tabSuspension && domain == "example.com" {
                return false
            }
            return true
        }
        sut = makeSUT()

        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(url, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenDomainIsNotInExceptionsList_ThenCanBeSuspendedIsTrue() throws {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        mockPrivacyConfig.isFeatureEnabledForDomainCheck = { feature, _ in
            if feature == .tabSuspension {
                return true
            }
            return true
        }
        sut = makeSUT()

        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(url, credential: nil, source: .link))

        XCTAssertTrue(sut.canBeSuspended)
    }

    // MARK: - Pinned State

    @MainActor
    func testWhenTabIsPinned_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        isPinned = true
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    // MARK: - AI Chat Session

    @MainActor
    func testWhenTabHasActiveAIChatSession_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        _ = aiChatSessionStore.getOrCreateSession(for: tabID, burnerMode: .regular)

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

    // MARK: - Loading

    @MainActor
    func testWhenWebViewIsLoading_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webView.isLoading = true
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    // MARK: - Audio Playback

    @MainActor
    func testWhenWebViewIsPlayingAudio_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webView.isPlayingAudio = true
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    // MARK: - Audio Capture

    @MainActor
    func testWhenWebViewIsCapturingAudio_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webView.isCapturingAudio = true
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    // MARK: - Video Capture

    @MainActor
    func testWhenWebViewIsCapturingVideo_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webView.isCapturingVideo = true
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    // MARK: - Picture in Picture

    @MainActor
    func testWhenVideoIsInPictureInPicture_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()
        sut.hasVideoInPictureInPicture = true

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    // MARK: - PDF Display

    @MainActor
    func testWhenWebViewIsDisplayingPDF_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()
        sut.isDisplayingPDF = true

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        XCTAssertFalse(sut.canBeSuspended)
    }

    // MARK: - Page Reports Unable to Suspend

    @MainActor
    func testWhenPageReportsUnableToSuspend_ThenCanBeSuspendedIsFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        sut.tabSuspensionUserScript(TabSuspensionUserScript(), didReceiveCanBeSuspended: false)

        XCTAssertFalse(sut.canBeSuspended)
    }

    @MainActor
    func testWhenPageReportsCanBeSuspended_ThenCanBeSuspendedIsTrue() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        sut.tabSuspensionUserScript(TabSuspensionUserScript(), didReceiveCanBeSuspended: true)

        XCTAssertTrue(sut.canBeSuspended)
    }

    @MainActor
    func testWhenPageReportsUnableToSuspend_AndNavigationCommits_ThenFlagIsReset() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        sut.tabSuspensionUserScript(TabSuspensionUserScript(), didReceiveCanBeSuspended: false)
        XCTAssertTrue(sut.pageReportsUnableToSuspend)

        sut.didCommit(Navigation(identity: NavigationIdentity(nil), responders: ResponderChain(), state: .started, isCurrent: true))

        XCTAssertFalse(sut.pageReportsUnableToSuspend)
        XCTAssertTrue(sut.canBeSuspended)
    }

    @MainActor
    func testWhenPageReportsUnableToSuspend_AndNavigationFinishes_ThenFlagIsReset() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        sut = makeSUT()

        let webView = MockTabSuspensionWebView()
        webViewPublisher.send(webView)
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        sut.tabSuspensionUserScript(TabSuspensionUserScript(), didReceiveCanBeSuspended: false)
        XCTAssertTrue(sut.pageReportsUnableToSuspend)

        sut.navigationDidFinish(Navigation(identity: NavigationIdentity(nil), responders: ResponderChain(), state: .started, isCurrent: true))

        XCTAssertFalse(sut.pageReportsUnableToSuspend)
    }

    // MARK: - Suspension State

    @MainActor
    func testWhenLastSuspendedURLIsNil_ThenSuspensionStateIsNever() {
        sut = makeSUT()
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        sut.lastSuspendedURL = nil

        XCTAssertEqual(sut.lastSuspensionState, .never)
    }

    @MainActor
    func testWhenLastSuspendedURLMatchesCurrentURL_ThenSuspensionStateIsSameURL() {
        sut = makeSUT()
        contentPublisher.send(.url(.duckDuckGo, credential: nil, source: .link))

        sut.lastSuspendedURL = .duckDuckGo

        XCTAssertEqual(sut.lastSuspensionState, .sameURL)
    }

    @MainActor
    func testWhenLastSuspendedURLHasSamePathButDifferentQuery_ThenSuspensionStateIsSamePath() throws {
        let currentURL = try XCTUnwrap(URL(string: "https://duckduckgo.com/about?q=test"))
        let suspendedURL = try XCTUnwrap(URL(string: "https://duckduckgo.com/about?q=other"))
        sut = makeSUT()
        contentPublisher.send(.url(currentURL, credential: nil, source: .link))

        sut.lastSuspendedURL = suspendedURL

        XCTAssertEqual(sut.lastSuspensionState, .samePath)
    }

    @MainActor
    func testWhenLastSuspendedURLHasSameHostButDifferentPath_ThenSuspensionStateIsSameHostname() throws {
        let currentURL = try XCTUnwrap(URL(string: "https://duckduckgo.com/about"))
        let suspendedURL = try XCTUnwrap(URL(string: "https://duckduckgo.com/"))
        sut = makeSUT()
        contentPublisher.send(.url(currentURL, credential: nil, source: .link))

        sut.lastSuspendedURL = suspendedURL

        XCTAssertEqual(sut.lastSuspensionState, .sameHostname)
    }

    @MainActor
    func testWhenLastSuspendedURLHasSameETLDPlus1ButDifferentHost_ThenSuspensionStateIsSameDomain() throws {
        let currentURL = try XCTUnwrap(URL(string: "https://www.example.com/page"))
        let suspendedURL = try XCTUnwrap(URL(string: "https://mail.example.com/inbox"))
        sut = makeSUT()
        contentPublisher.send(.url(currentURL, credential: nil, source: .link))

        sut.lastSuspendedURL = suspendedURL

        XCTAssertEqual(sut.lastSuspensionState, .sameDomain)
    }

    @MainActor
    func testWhenLastSuspendedURLHasDifferentDomain_ThenSuspensionStateIsDifferentDomain() throws {
        let currentURL = try XCTUnwrap(URL(string: "https://example.com"))
        let suspendedURL = try XCTUnwrap(URL(string: "https://duckduckgo.com/"))
        sut = makeSUT()
        contentPublisher.send(.url(currentURL, credential: nil, source: .link))

        sut.lastSuspendedURL = suspendedURL

        XCTAssertEqual(sut.lastSuspensionState, .differentDomain)
    }

    @MainActor
    func testWhenLastSuspendedURLHasDifferentIPAddresses_ThenSuspensionStateIsDifferentDomain() throws {
        let currentURL = try XCTUnwrap(URL(string: "http://10.0.0.1"))
        let suspendedURL = try XCTUnwrap(URL(string: "https://10.0.0.2/"))
        sut = makeSUT()
        contentPublisher.send(.url(currentURL, credential: nil, source: .link))

        sut.lastSuspendedURL = suspendedURL

        XCTAssertEqual(sut.lastSuspensionState, .differentDomain)
    }

    @MainActor
    func testWhenLastSuspendedURLIsNotNilAndContentHasNoURL_ThenSuspensionStateIsDifferentDomain() {
        sut = makeSUT()
        contentPublisher.send(.none)

        sut.lastSuspendedURL = .duckDuckGo

        XCTAssertEqual(sut.lastSuspensionState, .differentDomain)
    }
}

// MARK: - MockTabSuspensionWebView

private final class MockTabSuspensionWebView: TabSuspensionWebViewChecking {
    var isLoading: Bool = false
    var isPlayingAudio: Bool = false
    var isCapturingAudio: Bool = false
    var isCapturingVideo: Bool = false
    var isDisplayingPDF: Bool = false
}

private struct MockTabSuspensionUserScriptProvider: TabSuspensionUserScriptProvider {
    let tabSuspensionScript = TabSuspensionUserScript()
}

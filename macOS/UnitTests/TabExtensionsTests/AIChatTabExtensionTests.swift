//
//  AIChatTabExtensionTests.swift
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
import BrowserServicesKitTestsUtils
import Combine
import DDGNavigation
@_spi(Testing) import PixelKit
import PrivacyConfig
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

private struct MockAIChatScriptsProvider: AIChatUserScriptProvider {
    var aiChatUserScript: AIChatUserScript?
    var duckAiNativeStorageUserScript: DuckAiNativeStorageUserScript?
}

@MainActor
final class AIChatTabExtensionTests: XCTestCase {

    private var tabExtension: AIChatTabExtension!
    private var content: CurrentValueSubject<TabContent, Never>!
    private var scripts: PassthroughSubject<MockAIChatScriptsProvider, Never>!
    private var preferencesStorage: MockAIChatPreferencesStorage!
    private var pixelFiring: PixelKitMock!

    private let duckAIURL = URL(string: "https://duck.ai/")!

    override func setUp() {
        super.setUp()
        content = CurrentValueSubject(.newtab)
        scripts = PassthroughSubject()
        preferencesStorage = MockAIChatPreferencesStorage()
        pixelFiring = PixelKitMock()
        tabExtension = makeTabExtension()
    }

    override func tearDown() {
        tabExtension = nil
        content = nil
        scripts = nil
        preferencesStorage = nil
        pixelFiring = nil
        super.tearDown()
    }

    private func makeTabExtension(isLoadedInSidebar: Bool = false) -> AIChatTabExtension {
        AIChatTabExtension(scriptsPublisher: scripts,
                           webViewPublisher: Empty<WKWebView, Never>(),
                           contentPublisher: content,
                           isLoadedInSidebar: isLoadedInSidebar,
                           isTabBurner: false,
                           featureDiscovery: MockFeatureDiscovery(),
                           featureFlagger: MockFeatureFlagger(),
                           duckAiNativeStorageHandler: nil,
                           burnerDuckAiStorageRegistry: nil,
                           preferencesStorage: preferencesStorage,
                           pixelFiring: pixelFiring)
    }

    private func makeNavigation(to url: URL,
                                type navigationType: NavigationType,
                                isUserInitiated: Bool = false,
                                from sourceURL: URL = URL(string: "https://example.com/")!) -> Navigation {
        let targetFrame = FrameInfo(webView: nil, handle: FrameHandle(rawValue: 1 as UInt64)!, isMainFrame: true, url: url, securityOrigin: .empty)
        let sourceFrame = FrameInfo(webView: nil, handle: FrameHandle(rawValue: 2 as UInt64)!, isMainFrame: true, url: sourceURL, securityOrigin: .empty)
        let action = NavigationAction(request: URLRequest(url: url), navigationType: navigationType, currentHistoryItemIdentity: nil,
                                      redirectHistory: [], isUserInitiated: isUserInitiated, sourceFrame: sourceFrame,
                                      targetFrame: targetFrame, shouldDownload: false, mainFrameNavigation: nil)
        return Navigation(identity: NavigationIdentity(nil), responders: ResponderChain(responderRefs: []), state: .started,
                          redirectHistory: [action], isCurrent: true, isCommitted: false)
    }

    private func perform(_ navigation: Navigation) {
        tabExtension.willStart(navigation)
        tabExtension.didCommit(navigation)
    }

    private var firedVias: [String?] {
        firedPixels.map { $0?["via"] }
    }

    private var firedPixels: [[String: String]?] {
        pixelFiring.actualFireCalls
            .filter { $0.pixel.name == "aichat_duck_ai_direct_navigation_macos" }
            .map { $0.pixel.parameters }
    }

    // MARK: - Via

    func testWhenDuckAIIsTypedThenViaIsTyped() {
        content.send(.aiChat(duckAIURL, source: .userEntered("duck.ai")))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))

        XCTAssertEqual(firedVias, ["typed"])
    }

    func testWhenDuckAIIsTypedIntoANewTabThenViaIsTyped() {
        // ⌘↩ opens the typed URL as plain `.url` content.
        content.send(.url(duckAIURL, source: .userEntered("duck.ai")))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))

        XCTAssertEqual(firedVias, ["typed"])
    }

    func testWhenAnAddressBarSuggestionForDuckAIIsPickedThenViaIsSuggestion() {
        tabExtension.noteAddressBarSuggestionNavigation(to: duckAIURL)
        content.send(.aiChat(duckAIURL, source: .userEntered("duck")))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))

        XCTAssertEqual(firedVias, ["suggestion"])
    }

    func testWhenTheSuggestionWasForAnotherURLThenViaIsTyped() {
        tabExtension.noteAddressBarSuggestionNavigation(to: URL(string: "https://example.com/")!)
        content.send(.aiChat(duckAIURL, source: .userEntered("duck.ai")))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))

        XCTAssertEqual(firedVias, ["typed"])
    }

    func testThatASuggestionCountsForOneNavigationOnly() {
        tabExtension.noteAddressBarSuggestionNavigation(to: duckAIURL)
        content.send(.aiChat(duckAIURL, source: .userEntered("duck")))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))

        XCTAssertEqual(firedVias, ["suggestion", "typed"])
    }

    func testWhenABookmarkOrFavoriteOpensDuckAIThenViaNamesWhichOne() {
        content.send(.aiChat(duckAIURL, source: .bookmark(isFavorite: false)))
        perform(makeNavigation(to: duckAIURL, type: .custom(.bookmark)))
        content.send(.aiChat(duckAIURL, source: .bookmark(isFavorite: true)))
        perform(makeNavigation(to: duckAIURL, type: .custom(.bookmark)))

        XCTAssertEqual(firedVias, ["bookmark", "favorite"])
    }

    func testWhenHistoryOrAnotherAppOpensDuckAIThenViaNamesIt() {
        perform(makeNavigation(to: duckAIURL, type: .custom(.historyEntry)))
        perform(makeNavigation(to: duckAIURL, type: .custom(.appOpenUrl)))

        XCTAssertEqual(firedVias, ["history", "external"])
    }

    func testWhenALinkOpensDuckAIThenViaIsLink() {
        perform(makeNavigation(to: duckAIURL, type: .custom(.link)))
        perform(makeNavigation(to: duckAIURL, type: .linkActivated(isMiddleClick: false)))
        perform(makeNavigation(to: duckAIURL, type: .other, isUserInitiated: true))

        XCTAssertEqual(firedVias, ["link", "link", "link"])
    }

    // MARK: - Tabs a page opens for a link

    func testWhenAPageOpensANewTabForALinkThenItsFirstLoadIsALink() {
        // WebKit's first load in the new tab is a plain, non-user-initiated `.other` with no source page.
        tabExtension.noteOpenedForLink(from: URL(string: "https://www.w3schools.com/")!)
        perform(makeNavigation(to: duckAIURL, type: .other, from: duckAIURL))

        XCTAssertEqual(firedVias, ["link"])
    }

    func testWhenTheOpenerPageIsUnknownThenTheNewTabStillCountsAsALink() {
        tabExtension.noteOpenedForLink(from: nil)
        perform(makeNavigation(to: duckAIURL, type: .other))

        XCTAssertEqual(firedVias, ["link"])
    }

    func testWhenDuckAIOrDuckDuckGoOpensANewTabThenNothingIsReported() {
        tabExtension.noteOpenedForLink(from: URL(string: "https://duck.ai/chat")!)
        perform(makeNavigation(to: duckAIURL, type: .other))
        tabExtension.noteOpenedForLink(from: URL(string: "https://duckduckgo.com/?q=test")!)
        perform(makeNavigation(to: duckAIURL, type: .other))

        XCTAssertEqual(firedVias, [])
    }

    func testThatTheLinkOpenerOnlyAppliesToTheNewTabsFirstLoad() {
        tabExtension.noteOpenedForLink(from: URL(string: "https://www.w3schools.com/")!)
        perform(makeNavigation(to: duckAIURL, type: .other))
        perform(makeNavigation(to: duckAIURL, type: .other))

        XCTAssertEqual(firedVias, ["link"])
    }

    // MARK: - Redirect pages

    func testWhenALinkGoesThroughALinkWrapperThenTheRedirectToDuckAIIsALink() {
        let wrapperURL = URL(string: "https://www.google.com/url?q=https://duck.ai/")!
        perform(makeNavigation(to: wrapperURL, type: .linkActivated(isMiddleClick: false), from: URL(string: "https://www.google.com/search?q=duck.ai")!))
        perform(makeNavigation(to: duckAIURL, type: .redirect(.client(delay: 0)), from: wrapperURL))

        XCTAssertEqual(firedVias, ["link"])
    }

    func testThatAChainOfRedirectPagesKeepsTheOriginalVia() {
        let firstWrapperURL = URL(string: "https://t.co/abc")!
        let secondWrapperURL = URL(string: "https://bit.ly/abc")!
        perform(makeNavigation(to: firstWrapperURL, type: .linkActivated(isMiddleClick: false)))
        perform(makeNavigation(to: secondWrapperURL, type: .redirect(.client(delay: 0)), from: firstWrapperURL))
        perform(makeNavigation(to: duckAIURL, type: .redirect(.client(delay: 0)), from: secondWrapperURL))

        XCTAssertEqual(firedVias, ["link"])
    }

    func testThatAClientRedirectAfterDuckAILoadedDoesNotCountAgain() {
        content.send(.aiChat(duckAIURL, source: .userEntered("duck.ai")))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))
        perform(makeNavigation(to: URL(string: "https://duck.ai/chat")!, type: .redirect(.client(delay: 0)), from: duckAIURL))

        XCTAssertEqual(firedVias, ["typed"])
    }

    func testThatAnotherNavigationDropsTheViaARedirectPageWouldHaveCarried() {
        let wrapperURL = URL(string: "https://www.google.com/url?q=https://duck.ai/")!
        perform(makeNavigation(to: wrapperURL, type: .linkActivated(isMiddleClick: false)))
        perform(makeNavigation(to: URL(string: "https://example.com/")!, type: .custom(.ui)))
        perform(makeNavigation(to: duckAIURL, type: .redirect(.client(delay: 0))))

        XCTAssertEqual(firedVias, [])
    }

    // MARK: - No pixel

    func testThatLoadsTheUserDidNotStartTowardDuckAIReportNothing() {
        let navigationTypes: [NavigationType] = [
            .custom(.ui),
            .reload,
            .backForward(distance: -1),
            .sessionRestoration,
            .redirect(.client(delay: 0)),
            .other,
            .formSubmitted,
        ]
        for navigationType in navigationTypes {
            perform(makeNavigation(to: duckAIURL, type: navigationType))
        }

        XCTAssertEqual(firedVias, [])
    }

    func testWhenTheContentWasNotTypedThenAUserEnteredNavigationReportsNothing() {
        content.send(.aiChat(duckAIURL, source: .ui))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))

        XCTAssertEqual(firedVias, [])
    }

    func testThatTheSidebarReportsNothing() {
        tabExtension = makeTabExtension(isLoadedInSidebar: true)
        content.send(.aiChat(duckAIURL, source: .userEntered("duck.ai")))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))

        XCTAssertEqual(firedVias, [])
    }

    func testThatLinksFromDuckAIOrDuckDuckGoReportNothing() {
        perform(makeNavigation(to: duckAIURL, type: .linkActivated(isMiddleClick: false), from: URL(string: "https://duck.ai/chat")!))
        perform(makeNavigation(to: duckAIURL, type: .linkActivated(isMiddleClick: false), from: URL(string: "https://duckduckgo.com/?q=test")!))

        XCTAssertEqual(firedVias, [])
    }

    func testThatAChatTheHomepageHandsOverReportsNothing() {
        let homepageFunnelURL = URL(string: "https://duck.ai/chat?ia=chat&duckai=1&home=1&prompt=1&origin=funnel_home_website&t=h_")!
        perform(makeNavigation(to: homepageFunnelURL, type: .linkActivated(isMiddleClick: false)))

        XCTAssertEqual(firedVias, [])
    }

    func testThatANavigationThatDoesNotLandOnDuckAIReportsNothing() {
        let url = URL(string: "https://example.com/")!
        content.send(.url(url, source: .userEntered("example.com")))
        perform(makeNavigation(to: url, type: .custom(.userEnteredUrl)))

        XCTAssertEqual(firedVias, [])
    }

    func testThatReloadingAfterADirectNavigationReportsNothingMore() {
        content.send(.aiChat(duckAIURL, source: .userEntered("duck.ai")))
        perform(makeNavigation(to: duckAIURL, type: .custom(.userEnteredUrl)))
        perform(makeNavigation(to: duckAIURL, type: .reload))

        XCTAssertEqual(firedVias, ["typed"])
    }

    // MARK: - Parameters

    func testThatTheSettingsAreReported() {
        let combinations: [(enabled: Bool, toggle: Bool)] = [(true, true), (true, false), (false, true), (false, false)]
        for combination in combinations {
            preferencesStorage.isAIFeaturesEnabled = combination.enabled
            preferencesStorage.showSearchAndDuckAIToggle = combination.toggle
            perform(makeNavigation(to: duckAIURL, type: .custom(.historyEntry)))
        }

        XCTAssertEqual(firedPixels.map { $0?["duckai_enabled"] }, ["true", "true", "false", "false"])
        XCTAssertEqual(firedPixels.map { $0?["toggle_enabled"] }, ["true", "false", "false", "false"])
    }

    func testThatThePixelFiresDailyAndCounted() {
        perform(makeNavigation(to: duckAIURL, type: .custom(.historyEntry)))

        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.frequency), [.dailyAndCount])
    }

    // MARK: - Chat source fallback

    func testThatTheChatGetsTheDirectNavigationAsItsFallbackSource() {
        let handler = MockAIChatUserScriptHandler()
        let userScript = AIChatUserScript(handler: handler, urlSettings: AIChatMockDebugSettings())
        scripts.send(MockAIChatScriptsProvider(aiChatUserScript: userScript))
        wait(until: self.tabExtension.aiChatUserScript === userScript)

        perform(makeNavigation(to: duckAIURL, type: .custom(.historyEntry)))

        XCTAssertEqual(handler.directNavigationFallback, .directHistory)
    }

    func testThatTheFallbackWaitsForTheChatsUserScript() {
        let handler = MockAIChatUserScriptHandler()
        let userScript = AIChatUserScript(handler: handler, urlSettings: AIChatMockDebugSettings())

        perform(makeNavigation(to: duckAIURL, type: .custom(.appOpenUrl)))
        scripts.send(MockAIChatScriptsProvider(aiChatUserScript: userScript))
        wait(until: handler.directNavigationFallback != nil)

        XCTAssertEqual(handler.directNavigationFallback, .directExternal)
    }

    private func wait(until condition: @escaping @autoclosure () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3)
    }
}

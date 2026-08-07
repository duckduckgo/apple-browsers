//
//  DuckAIVoiceSessionTrackerTests.swift
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

import Combine
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAIVoiceSessionTrackerTests: XCTestCase {

    /// Per-test private NotificationCenter so observers don't bleed across tests or pick up
    /// notifications from app code running in the same process.
    private var notificationCenter: NotificationCenter!
    private var tracker: DuckAIVoiceSessionTracker!
    /// Stand-in for `TabManager.controller(forWebView:)?.tabModel`: maps registered webViews to tabs.
    private var webViewToTab: [ObjectIdentifier: Tab] = [:]

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        webViewToTab = [:]
        tracker = DuckAIVoiceSessionTracker(notificationCenter: notificationCenter,
                                            tabForWebView: { [weak self] webView in
            self?.webViewToTab[ObjectIdentifier(webView)]
        }, deactivationDelay: 0)
    }

    override func tearDown() {
        tracker = nil
        notificationCenter = nil
        webViewToTab = [:]
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTab() -> Tab {
        Tab(desktop: false, fireTab: false)
    }

    /// Creates a webView, registers it as `tab`'s webView with the resolver, and returns it.
    private func registerWebView(for tab: Tab) -> WKWebView {
        let webView = WKWebView()
        webViewToTab[ObjectIdentifier(webView)] = tab
        return webView
    }

    // MARK: - Tracking

    func testWhenVoiceSessionStartsThenTabIsActive() {
        let tab = makeTab()
        let webView = registerWebView(for: tab)

        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: webView)

        XCTAssertTrue(tracker.isVoiceSessionActive(for: tab))
    }

    func testWhenVoiceSessionEndsThenTabIsInactive() {
        let tab = makeTab()
        let webView = registerWebView(for: tab)
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: webView)
        XCTAssertTrue(tracker.isVoiceSessionActive(for: tab))

        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: webView)

        XCTAssertFalse(tracker.isVoiceSessionActive(for: tab))
    }

    func testWhenTabHasNoVoiceSessionThenInactive() {
        XCTAssertFalse(tracker.isVoiceSessionActive(for: makeTab()))
    }

    func testWhenStartedWebViewDoesNotResolveToTabThenNothingTracked() {
        let unrelatedTab = makeTab()
        let strangerWebView = WKWebView() // never registered with the resolver

        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: strangerWebView)

        XCTAssertFalse(tracker.isVoiceSessionActive(for: unrelatedTab))
    }

    func testWhenStartedNotificationHasNoWebViewObjectThenNothingTracked() {
        let tab = makeTab()
        _ = registerWebView(for: tab) // tab is resolvable, but the post omits the webView

        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: nil)

        XCTAssertFalse(tracker.isVoiceSessionActive(for: tab))
    }

    func testWhenEndedArrivesForDifferentWebViewThenActiveTabRemains() {
        let activeTab = makeTab()
        let activeWebView = registerWebView(for: activeTab)
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: activeWebView)

        let otherTab = makeTab()
        let otherWebView = registerWebView(for: otherTab)
        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: otherWebView)

        XCTAssertTrue(tracker.isVoiceSessionActive(for: activeTab))
    }

    func testTracksMultipleTabsIndependently() {
        let tabA = makeTab()
        let tabB = makeTab()
        let webViewA = registerWebView(for: tabA)
        let webViewB = registerWebView(for: tabB)

        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: webViewA)
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: webViewB)
        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: webViewA)

        XCTAssertFalse(tracker.isVoiceSessionActive(for: tabA))
        XCTAssertTrue(tracker.isVoiceSessionActive(for: tabB))
    }

    // MARK: - changes publisher

    func testWhenVoiceSessionStartsThenChangesEmits() {
        let tab = makeTab()
        let webView = registerWebView(for: tab)
        var emissions = 0
        let cancellable = tracker.changes.sink { _ in emissions += 1 }

        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: webView)

        XCTAssertEqual(emissions, 1)
        cancellable.cancel()
    }

    func testWhenVoiceSessionEndsThenChangesEmits() {
        let tab = makeTab()
        let webView = registerWebView(for: tab)
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: webView)
        var emissions = 0
        let cancellable = tracker.changes.sink { _ in emissions += 1 }

        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: webView)

        XCTAssertEqual(emissions, 1)
        cancellable.cancel()
    }
}

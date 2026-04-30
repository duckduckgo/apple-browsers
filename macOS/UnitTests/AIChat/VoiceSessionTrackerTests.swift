//
//  VoiceSessionTrackerTests.swift
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
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class VoiceSessionTrackerTests: XCTestCase {

    /// Per-test private NotificationCenter so observers don't bleed across tests or
    /// pick up notifications from app code running in the same process.
    private var notificationCenter: NotificationCenter!
    private var windowControllersManager: WindowControllersManagerMock!
    private var tracker: VoiceSessionTracker!

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        windowControllersManager = WindowControllersManagerMock()
        tracker = VoiceSessionTracker(notificationCenter: notificationCenter,
                                      windowControllersManager: windowControllersManager)
    }

    override func tearDown() {
        tracker = nil
        windowControllersManager = nil
        notificationCenter = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Builds a `TabCollectionViewModel` containing the given tabs and registers it on the mock
    /// manager so the tracker can resolve `webView → Tab` and run window-scope checks.
    private func makeTabCollectionViewModel(with tabs: [Tab]) -> TabCollectionViewModel {
        let tcvm = TabCollectionViewModel(
            tabCollection: TabCollection(),
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            tabsPreferences: TabsPreferences(
                persistor: MockTabsPreferencesPersistor(),
                windowControllersManager: WindowControllersManagerMock()
            )
        )
        for tab in tabs { tcvm.append(tab: tab) }
        return tcvm
    }

    // MARK: - Tracking

    func testStartedNotification_TracksTabFromMatchingWebView() {
        // Given a single window with one Duck.ai tab the manager knows about.
        let tab = Tab(content: .none)
        windowControllersManager.customAllTabCollectionViewModels = [makeTabCollectionViewModel(with: [tab])]

        // When Duck.ai posts `voiceSessionStarted` carrying that tab's webView.
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: tab.webView)

        // Then querying with a source tab in the same window finds the tracked voice tab.
        XCTAssertTrue(tracker.findActiveVoiceTab(inWindowOf: tab) === tab)
    }

    func testEndedNotification_UntracksPreviouslyTrackedTab() {
        // Given a tab that was just marked active.
        let tab = Tab(content: .none)
        windowControllersManager.customAllTabCollectionViewModels = [makeTabCollectionViewModel(with: [tab])]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: tab.webView)
        XCTAssertNotNil(tracker.findActiveVoiceTab(inWindowOf: tab))

        // When the matching `voiceSessionEnded` arrives.
        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: tab.webView)

        // Then the tab is no longer reported as active.
        XCTAssertNil(tracker.findActiveVoiceTab(inWindowOf: tab))
    }

    func testStartedNotification_WithUnknownWebView_DoesNotTrackAnything() {
        // Given a known tab in the manager but a stranger webView arrives via the notification
        // (e.g. a sidebar webview the tracker isn't supposed to handle yet).
        let tab = Tab(content: .none)
        windowControllersManager.customAllTabCollectionViewModels = [makeTabCollectionViewModel(with: [tab])]
        let strangerWebView = WKWebView()

        // When
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: strangerWebView)

        // Then nothing is tracked.
        XCTAssertNil(tracker.findActiveVoiceTab(inWindowOf: tab))
    }

    // MARK: - Window scoping

    func testFindActiveVoiceTab_ReturnsNilWhenSourceTabIsNil() {
        let tab = Tab(content: .none)
        windowControllersManager.customAllTabCollectionViewModels = [makeTabCollectionViewModel(with: [tab])]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: tab.webView)

        // No source-tab context → no window scope to check against → fall back to "open new".
        XCTAssertNil(tracker.findActiveVoiceTab(inWindowOf: nil))
    }

    func testFindActiveVoiceTab_ReturnsNilWhenActiveTabIsInDifferentWindow() {
        // Given two windows: voice tab is in window A, source tab in window B.
        let voiceTab = Tab(content: .none)
        let sourceTab = Tab(content: .none)
        windowControllersManager.customAllTabCollectionViewModels = [
            makeTabCollectionViewModel(with: [voiceTab]),
            makeTabCollectionViewModel(with: [sourceTab])
        ]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: voiceTab.webView)

        // A voice tap originating in window B must not steal focus across windows.
        XCTAssertNil(tracker.findActiveVoiceTab(inWindowOf: sourceTab))
    }

    func testFindActiveVoiceTab_FindsActiveTabInSameWindowAlongsideOtherTabs() {
        // Given a window with two tabs, one of which has an active voice session.
        let voiceTab = Tab(content: .none)
        let neighbourTab = Tab(content: .none)
        windowControllersManager.customAllTabCollectionViewModels = [
            makeTabCollectionViewModel(with: [voiceTab, neighbourTab])
        ]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: voiceTab.webView)

        // Tapping voice from `neighbourTab` finds the existing voice tab in the same window.
        XCTAssertTrue(tracker.findActiveVoiceTab(inWindowOf: neighbourTab) === voiceTab)
    }

    // MARK: - Stale ended notifications

    func testEndedNotification_FromUnknownWebView_DoesNotEvictTrackedTab() {
        // Given an active voice tab.
        let tab = Tab(content: .none)
        windowControllersManager.customAllTabCollectionViewModels = [makeTabCollectionViewModel(with: [tab])]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: tab.webView)
        XCTAssertNotNil(tracker.findActiveVoiceTab(inWindowOf: tab))

        // When a stray `voiceSessionEnded` arrives carrying some other webView.
        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: WKWebView())

        // Then the tracked voice tab is still active.
        XCTAssertTrue(tracker.findActiveVoiceTab(inWindowOf: tab) === tab)
    }
}

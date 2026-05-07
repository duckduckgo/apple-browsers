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
        let tcvm = makeTabCollectionViewModel(with: [tab])
        windowControllersManager.customAllTabCollectionViewModels = [tcvm]

        // When Duck.ai posts `voiceSessionStarted` carrying that tab's webView.
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: tab.webView)

        // Then the tracker finds the voice tab when queried with the source TCVM.
        XCTAssertTrue(tracker.findActiveVoiceTab(in: tcvm) === tab)
    }

    func testEndedNotification_UntracksPreviouslyTrackedTab() {
        // Given a tab that was just marked active.
        let tab = Tab(content: .none)
        let tcvm = makeTabCollectionViewModel(with: [tab])
        windowControllersManager.customAllTabCollectionViewModels = [tcvm]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: tab.webView)
        XCTAssertNotNil(tracker.findActiveVoiceTab(in: tcvm))

        // When the matching `voiceSessionEnded` arrives.
        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: tab.webView)

        // Then the tab is no longer reported as active.
        XCTAssertNil(tracker.findActiveVoiceTab(in: tcvm))
    }

    func testStartedNotification_WithUnknownWebView_DoesNotTrackAnything() {
        // Given a known tab in the manager but a stranger webView arrives via the notification
        // (e.g. a webview not associated with any browser tab or sidebar).
        let tab = Tab(content: .none)
        let tcvm = makeTabCollectionViewModel(with: [tab])
        windowControllersManager.customAllTabCollectionViewModels = [tcvm]
        let strangerWebView = WKWebView()

        // When
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: strangerWebView)

        // Then nothing is tracked.
        XCTAssertNil(tracker.findActiveVoiceTab(in: tcvm))
    }

    // MARK: - Window scoping

    func testFindActiveVoiceTab_ReturnsNilWhenSourceCollectionIsNil() {
        let tab = Tab(content: .none)
        windowControllersManager.customAllTabCollectionViewModels = [makeTabCollectionViewModel(with: [tab])]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: tab.webView)

        // No source-window context → no scope to check against → fall back to "open new".
        XCTAssertNil(tracker.findActiveVoiceTab(in: nil))
    }

    func testFindActiveVoiceTab_ReturnsNilWhenActiveTabIsInDifferentWindow() {
        // Given two windows: voice tab is in window A, the request originates from window B.
        let voiceTab = Tab(content: .none)
        let sourceTab = Tab(content: .none)
        let windowATCVM = makeTabCollectionViewModel(with: [voiceTab])
        let windowBTCVM = makeTabCollectionViewModel(with: [sourceTab])
        windowControllersManager.customAllTabCollectionViewModels = [windowATCVM, windowBTCVM]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: voiceTab.webView)

        // A voice tap originating in window B must not steal focus across windows.
        XCTAssertNil(tracker.findActiveVoiceTab(in: windowBTCVM))
    }

    func testFindActiveVoiceTab_FindsActiveTabInSameWindowAlongsideOtherTabs() {
        // Given a window with two tabs, one of which has an active voice session.
        let voiceTab = Tab(content: .none)
        let neighbourTab = Tab(content: .none)
        let tcvm = makeTabCollectionViewModel(with: [voiceTab, neighbourTab])
        windowControllersManager.customAllTabCollectionViewModels = [tcvm]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: voiceTab.webView)

        // Tapping voice from anywhere in the same window finds the existing voice tab.
        XCTAssertTrue(tracker.findActiveVoiceTab(in: tcvm) === voiceTab)
    }

    // MARK: - Stale ended notifications

    func testEndedNotification_FromUnknownWebView_DoesNotEvictTrackedTab() {
        // Given an active voice tab.
        let tab = Tab(content: .none)
        let tcvm = makeTabCollectionViewModel(with: [tab])
        windowControllersManager.customAllTabCollectionViewModels = [tcvm]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: tab.webView)
        XCTAssertNotNil(tracker.findActiveVoiceTab(in: tcvm))

        // When a stray `voiceSessionEnded` arrives carrying some other webView.
        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: WKWebView())

        // Then the tracked voice tab is still active.
        XCTAssertTrue(tracker.findActiveVoiceTab(in: tcvm) === tab)
    }

    // MARK: - Pinned tabs (window-scope behaviour with the shared pinned collection)

    /// A pinned voice tab is findable when the source window queries the tracker via a TCVM
    /// whose pinned collection contains it. (In production the pinned collection is shared
    /// across all windows via `PinnedTabsManagerProviding`, so this holds for every window;
    /// in the test environment each TCVM has its own pinned collection, so we restrict the
    /// assertion to the TCVM we know contains the tab.) Skipped when the test environment
    /// doesn't expose a pinned tabs collection at all.
    func testFindActiveVoiceTab_FindsPinnedActiveTabInSourceWindow() throws {
        let unpinned = Tab(content: .none)
        let tcvm = makeTabCollectionViewModel(with: [unpinned])
        try XCTSkipIf(tcvm.pinnedTabsCollection == nil, "Pinned tabs collection unavailable in this test environment.")

        let pinnedVoiceTab = Tab(content: .none)
        tcvm.pinnedTabsCollection?.append(tab: pinnedVoiceTab)
        windowControllersManager.customAllTabCollectionViewModels = [tcvm]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: pinnedVoiceTab.webView)

        XCTAssertTrue(tracker.findActiveVoiceTab(in: tcvm) === pinnedVoiceTab)
    }

    /// Window-scope must hold even when the source window is queried via its TCVM but the source
    /// tab is itself pinned. Previously the lookup keyed by `Tab`, and pinned tabs being shared
    /// caused `tabCollectionViewModel(containing:)` to non-deterministically pick the first
    /// window's TCVM — defeating the "voice in window B doesn't pull you to window A" promise
    /// for the case where the active voice tab in window A was unpinned.
    func testFindActiveVoiceTab_DoesNotMatchAcrossWindowsWhenActiveIsUnpinnedInWindowA() {
        let unpinnedVoiceInA = Tab(content: .none)
        let unpinnedInB = Tab(content: .none)
        let tcvmA = makeTabCollectionViewModel(with: [unpinnedVoiceInA])
        let tcvmB = makeTabCollectionViewModel(with: [unpinnedInB])
        windowControllersManager.customAllTabCollectionViewModels = [tcvmA, tcvmB]
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: unpinnedVoiceInA.webView)

        // Voice request from window B must not focus window A's voice tab.
        XCTAssertNil(tracker.findActiveVoiceTab(in: tcvmB))
        // …but from window A it still does.
        XCTAssertTrue(tracker.findActiveVoiceTab(in: tcvmA) === unpinnedVoiceInA)
    }
}

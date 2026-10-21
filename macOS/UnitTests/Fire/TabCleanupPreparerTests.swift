//
//  TabCleanupPreparerTests.swift
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

import Foundation
import Testing
import WebKit

@testable import DuckDuckGo_Privacy_Browser

/// A burn waits for every tab to load a blank page before clearing. A tab that never reports back used
/// to hold the burn — and the Fire button — for the rest of the session.
@MainActor
struct TabCleanupPreparerTests {

    /// Stands in for a tab whose blank load never completes: the web content process died, or the tab
    /// was closed mid-burn.
    private final class SilentTab: TabDataClearing {
        func prepareForDataClearing(caller: TabCleanupPreparer) {}
    }

    private final class UnloadedTab: TabDataClearing {
        func prepareForDataClearing(caller: TabCleanupPreparer) {
            caller.reportNoWebViewToClear()
        }
    }

    /// Hands the test its web view so the navigation callbacks can be driven directly.
    private final class WebViewTab: TabDataClearing {
        let webView = WKWebView()
        func prepareForDataClearing(caller: TabCleanupPreparer) {}
    }

    private let cancelled = URLError(.cancelled)

    // MARK: - Never hangs

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenATabNeverReportsBack_thenPreparationStillFinishes() async {
        let preparer = TabCleanupPreparer(timeout: 0.2)

        await preparer.prepareTabsForCleanup([SilentTab(), UnloadedTab()])
        // Reaching here is the assertion: before the timeout this awaited forever.
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenAllTabsHaveNoWebView_thenPreparationFinishesWithoutWaitingForTheTimeout() async {
        let preparer = TabCleanupPreparer(timeout: 60)
        let start = Date()

        await preparer.prepareTabsForCleanup([UnloadedTab(), UnloadedTab()])

        #expect(Date().timeIntervalSince(start) < 5)
    }

    // MARK: - Callbacks that used to go uncounted

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenABlankLoadFailsBeforeCommitting_thenTheTabCountsAsProcessed() async {
        let preparer = TabCleanupPreparer(timeout: 60)
        let tab = WebViewTab()
        let preparation = Task { await preparer.prepareTabsForCleanup([tab]) }
        await Task.yield()

        preparer.webView(tab.webView, didFailProvisionalNavigation: nil, withError: cancelled)

        await preparation.value
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenTheWebContentProcessDies_thenTheTabCountsAsProcessed() async {
        let preparer = TabCleanupPreparer(timeout: 60)
        let tab = WebViewTab()
        let preparation = Task { await preparer.prepareTabsForCleanup([tab]) }
        await Task.yield()

        preparer.webViewWebContentProcessDidTerminate(tab.webView)

        await preparation.value
    }

    // MARK: - Counting

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenOneTabReportsTwice_thenItDoesNotCountForAnotherTab() async throws {
        let preparer = TabCleanupPreparer(timeout: 60)
        let reportsTwice = WebViewTab()
        let stillLoading = WebViewTab()
        var didFinish = false
        let preparation = Task {
            await preparer.prepareTabsForCleanup([reportsTwice, stillLoading])
            didFinish = true
        }
        await Task.yield()

        // A dying process reports termination and then the failed navigation for the same web view.
        preparer.webViewWebContentProcessDidTerminate(reportsTwice.webView)
        preparer.webView(reportsTwice.webView, didFailProvisionalNavigation: nil, withError: cancelled)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(!didFinish, "Two reports from one tab must not stand in for the tab that is still loading")

        preparer.webView(stillLoading.webView, didFinish: nil)
        await preparation.value
        #expect(didFinish)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenPreparationIsReused_thenAnEarlierUnfinishedWaitIsReleased() async {
        let preparer = TabCleanupPreparer(timeout: 60)
        var firstFinished = false
        let first = Task {
            await preparer.prepareTabsForCleanup([SilentTab()])
            firstFinished = true
        }
        await Task.yield()

        // Fire's re-entry guard should make this impossible; if it ever isn't, the first wait must not
        // be left on a continuation nobody resumes.
        await preparer.prepareTabsForCleanup([UnloadedTab()])

        await first.value
        #expect(firstFinished)
    }

}

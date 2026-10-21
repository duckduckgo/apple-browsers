//
//  TabCleanupPreparer.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import os.log
import PixelKit
import WebKit

protocol TabCleanupPreparing {
    @MainActor func prepareTabsForCleanup(_ tabs: [any TabDataClearing]) async
}

protocol TabDataClearing {
    @MainActor func prepareForDataClearing(caller: TabCleanupPreparer)
}

/**
 Initiates cleanup of WebKit related data from Tabs:
 - Detach listeners and observers.
 - Flush WebView data by navigating to empty page.

 Once done, remove Tab objects.
 */
final class TabCleanupPreparer: NSObject, WKNavigationDelegate, TabCleanupPreparing {

    /// The blank load is best-effort hygiene ahead of the real clearing. A tab that never reports back —
    /// its web content process died, or the user closed it mid-burn — used to hold the burn forever.
    private let timeout: TimeInterval

    private var numberOfTabs = 0
    /// Per web view, so a tab reporting twice (process death, then the failed navigation) can't
    /// complete the wait while other tabs are still loading.
    private var finishedWebViews = Set<ObjectIdentifier>()
    private var tabsWithoutWebView = 0

    private var completion: (@MainActor () -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?

    init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    @MainActor
    func prepareTabsForCleanup(_ tabs: [any TabDataClearing]) async {
        guard !tabs.isEmpty else { return }

        // Never leave an earlier wait on a continuation nobody will resume.
        finish()

        numberOfTabs = tabs.count
        finishedWebViews = []
        tabsWithoutWebView = 0

        await withCheckedContinuation { continuation in
            self.completion = {
                continuation.resume()
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.completion != nil else { return }

                Logger.fire.error("Gave up waiting for \(self.numberOfTabs - self.processedTabs) tab(s) to load a blank page before burning")
                PixelKit.fire(DebugEvent(GeneralPixel.blankNavigationOnBurnTimedOut), frequency: .dailyAndStandard)
                self.finish()
            }
            timeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)

            tabs.forEach { $0.prepareForDataClearing(caller: self) }
        }
    }

    private var processedTabs: Int {
        finishedWebViews.count + tabsWithoutWebView
    }

    private func notifyIfDone() {
        guard processedTabs >= numberOfTabs else { return }
        finish()
    }

    /// Resumes the pending wait, at most once.
    private func finish() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        let completion = self.completion
        self.completion = nil
        completion?()
    }

    private func markFinished(_ webView: WKWebView) {
        finishedWebViews.insert(ObjectIdentifier(webView))
        notifyIfDone()
    }

    /// Signal that a tab has no WebView to clear (e.g. unloaded tabs).
    @MainActor
    func reportNoWebViewToClear() {
        tabsWithoutWebView += 1
        notifyIfDone()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        markFinished(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        PixelKit.fire(DebugEvent(GeneralPixel.blankNavigationOnBurnFailed, error: error))
        markFinished(webView)
    }

    /// A blank load that fails before committing reports here, not through `didFail`.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        PixelKit.fire(DebugEvent(GeneralPixel.blankNavigationOnBurnFailed, error: error))
        markFinished(webView)
    }

    /// With the delegate swapped to us, the tab's own crash recovery never sees this.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        markFinished(webView)
    }

}

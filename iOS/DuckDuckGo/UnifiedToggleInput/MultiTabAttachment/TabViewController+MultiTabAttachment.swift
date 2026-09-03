//
//  TabViewController+MultiTabAttachment.swift
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

import AIChat
import Combine
import Foundation
import os.log

/// Fills the multi-tab attachment cache from every tab, not only from the tab whose contextual
/// sheet is open.
///
/// The page only pushes a result after the first `collect()` call, and only the contextual sheet
/// makes that call today. This extension makes the call once per page load, for every tab, so a
/// background tab still has content the user can attach.
extension TabViewController {

    /// Subscribes to this tab's page-context script. Call again after the user scripts are
    /// reinstalled, because the subscription points at the previous script instance.
    ///
    /// Two subscribers to one publisher are fine: the contextual sheet keeps its own.
    func startObservingPageContextForMultiTabAttachment() {
        multiTabAttachmentCancellable = nil

        guard let context = multiTabAttachmentContext, context.isEnabled else { return }
        guard let script = userScripts?.pageContextUserScript else {
            Logger.aiChat.debug("[MultiTabAttachment] no page context script - cache stays empty for this tab")
            Swift.print("🇱🇻 observe skipped - no page context script for tab \(tabModel.uid)")
            return
        }

        let tabId = tabModel.uid
        multiTabAttachmentCancellable = script.collectionResultPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }
                guard case .collected(let pageContext) = result else { return }
                guard let url = URL(string: pageContext.url) else {
                    Logger.aiChat.debug("[MultiTabAttachment] collected context has no usable URL - not cached")
                    return
                }
                context.cache.store(context: pageContext, url: url, forTabId: tabId)
                Logger.aiChat.debug("[MultiTabAttachment] cached context for tab \(tabId) - content length: \(pageContext.content.count)")
                Swift.print("🇱🇻 CACHED tab=\(tabId) contentLength=\(pageContext.content.count) url=\(url.absoluteString)")
            }
    }

    /// Activates auto-capture on this page. The page pushes a fresh result on every later
    /// navigation, so one call per load is enough.
    func requestPageContextForMultiTabAttachment() {
        guard let context = multiTabAttachmentContext, context.isEnabled else {
            Swift.print("🇱🇻 collect skipped - gate off or no context for tab \(tabModel.uid)")
            return
        }

        guard let script = userScripts?.pageContextUserScript else {
            Logger.aiChat.debug("[MultiTabAttachment] collect skipped - no page context script")
            Swift.print("🇱🇻 collect skipped - no page context script for tab \(tabModel.uid)")
            return
        }
        guard let webView else {
            Logger.aiChat.debug("[MultiTabAttachment] collect skipped - no web view")
            Swift.print("🇱🇻 collect skipped - no web view for tab \(tabModel.uid)")
            return
        }
        guard let url = webView.url, !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else { return }

        if multiTabAttachmentCancellable == nil {
            startObservingPageContextForMultiTabAttachment()
        }

        // The contextual sheet clears this reference when it stops collecting, so set it every time.
        script.webView = webView
        script.collect()
        Swift.print("🇱🇻 COLLECT sent tab=\(tabModel.uid) url=\(url.absoluteString)")
        reportMissingPageContextIfNeeded(for: url, context: context)
    }

    /// Reports a collect that produced nothing.
    ///
    /// The page drops a `collect` that arrives before its own handler is registered. The result is
    /// a silent miss, which the user only sees as a tab that attaches URL and title alone.
    private func reportMissingPageContextIfNeeded(for url: URL, context: MultiTabAttachmentContext) {
        let tabId = tabModel.uid
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.multiTabAttachmentCollectTimeout) { [weak self] in
            // A navigation inside the window replaces the expectation. That load reports for itself,
            // so this check would otherwise compare the cache against a URL the tab already left.
            guard self?.webView?.url == url else { return }
            guard context.cache.context(forTabId: tabId)?.url != url else { return }
            Logger.aiChat.error("[MultiTabAttachment] no context arrived for tab \(tabId) - the collect was probably dropped by the page")
            Swift.print("🇱🇻 COLLECT LOST tab=\(tabId) - nothing arrived within the timeout")
        }
    }

    private static let multiTabAttachmentCollectTimeout: TimeInterval = 5
}

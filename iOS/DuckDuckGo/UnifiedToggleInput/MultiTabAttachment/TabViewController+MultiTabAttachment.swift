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
import WebKit

/// Collects live attachment content and keeps the hack-phase cache updated between submissions.
extension TabViewController {

    /// Materialization starts loading; a restored background web view may still need a reload.
    func collectPageContextForMultiTabAttachment(navigationTimeout: TimeInterval = 5,
                                                 collectTimeout: TimeInterval = 5) async -> AIChatPageContextData? {
        guard let webView, !Task.isCancelled else { return nil }
        let loadedPage = didFinishURLPublisher
            .combineLatest(webView.publisher(for: \.isLoading))
            .compactMap { [weak self] finishedURL, isLoading -> URL? in
                guard let self, let finishedURL, !isLoading, !self.isError,
                      webView.url == finishedURL else { return nil }
                return finishedURL
            }
            .eraseToAnyPublisher()

        Swift.print("🇱🇻🟢 waiting for background tab navigation tab=\(tabModel.uid)")
        let loadedURL = await MultiTabAttachmentWaiter.firstValue(from: loadedPage, timeout: navigationTimeout) {
            // A URL restored from interactionState is not proof that its document has loaded.
            // No URL means attachWebView is still preparing its initial request; do not restart it.
            if webView.url != nil, !webView.isLoading {
                var alreadyFinished = false
                let observation = loadedPage.sink { _ in alreadyFinished = true }
                if !alreadyFinished { webView.reload() }
                observation.cancel()
            }
        }
        guard let loadedURL, !Task.isCancelled, webView.url == loadedURL else {
            Swift.print("🇱🇻🟢 navigation unavailable after waiting tab=\(tabModel.uid) - timed out, cancelled or URL changed")
            return nil
        }

        // Reuse the current-page policy, document handling and favicon enrichment without
        // changing the source tab's contextual chat attachment state.
        let handler = makePageContextHandler()
        let updates = handler.contextPublisher.dropFirst().eraseToAnyPublisher()
        let context = await MultiTabAttachmentWaiter.firstValue(from: updates, timeout: collectTimeout) {
            handler.triggerContextCollection(trigger: .userRequest)
        }
        guard !Task.isCancelled, webView.url == loadedURL, !webView.isLoading, !isError,
              let context = context ?? nil, context.contextData.url == loadedURL.absoluteString else { return nil }
        return context.contextData
    }

    /// Subscribes to this tab's page-context script. Call again after the user scripts are
    /// reinstalled, because the subscription points at the previous script instance.
    ///
    /// Two subscribers to one publisher are fine: the contextual sheet keeps its own.
    func startObservingPageContextForMultiTabAttachment() {
        multiTabAttachmentCancellable = nil

        guard let context = multiTabAttachmentContext, context.isEnabled else { return }
        guard let script = userScripts?.pageContextUserScript else {
            Swift.print("🇱🇻🟢 observe skipped - no page context script for tab \(tabModel.uid) no page context script - cache stays empty for this tab")
            return
        }

        let tabId = tabModel.uid
        multiTabAttachmentCancellable = script.collectionResultPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }
                guard case .collected(let pageContext) = result else { return }
                guard let url = URL(string: pageContext.url) else {
                    Swift.print("🇱🇻🟢 collected context has no usable URL tab=\(tabId) - not cached")
                    return
                }
                context.cache.store(context: pageContext, url: url, forTabId: tabId)
                Swift.print("🇱🇻🟢 CACHED tab=\(tabId) contentLength=\(pageContext.content.count) url=\(url.absoluteString)")
            }
    }

    /// Activates auto-capture on this page. The page pushes a fresh result on every later
    /// navigation, so one call per load is enough.
    func requestPageContextForMultiTabAttachment() {
        guard let context = multiTabAttachmentContext, context.isEnabled else {
            Swift.print("🇱🇻🟢 collect skipped - gate off or no context for tab \(tabModel.uid)")
            return
        }

        guard let script = userScripts?.pageContextUserScript else {
            Swift.print("🇱🇻🟢 collect skipped - no page context script for tab \(tabModel.uid)")
            return
        }
        guard let webView else {
            Swift.print("🇱🇻🟢 collect skipped - no web view for tab \(tabModel.uid)")
            return
        }
        guard let url = webView.url, !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else { return }

        if multiTabAttachmentCancellable == nil {
            startObservingPageContextForMultiTabAttachment()
        }

        // The contextual sheet clears this reference when it stops collecting, so set it every time.
        script.webView = webView
        script.collect()
        Swift.print("🇱🇻🟢 COLLECT sent tab=\(tabModel.uid) url=\(url.absoluteString)")
        reportMissingPageContextIfNeeded(for: url, context: context)
    }

    /// Reports a collect that produced nothing.
    ///
    /// The page drops a `collect` that arrives before its own handler is registered.
    private func reportMissingPageContextIfNeeded(for url: URL, context: MultiTabAttachmentContext) {
        let tabId = tabModel.uid
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.multiTabAttachmentCollectTimeout) { [weak self] in
            // A navigation inside the window replaces the expectation. That load reports for itself,
            // so this check would otherwise compare the cache against a URL the tab already left.
            guard self?.webView?.url == url else { return }
            guard context.cache.context(forTabId: tabId)?.url != url else { return }
            Swift.print("🇱🇻🟢 COLLECT LOST tab=\(tabId) - nothing arrived within the timeout [MultiTabAttachment] no context arrived for tab \(tabId) - the collect was probably dropped by the page")
        }
    }

    private static let multiTabAttachmentCollectTimeout: TimeInterval = 5
}

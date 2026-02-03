//
//  AIChatPageContextHandler.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import os.log
import UIKit
import WebKit

// MARK: - Page Context DTO

/// Page context wrapper for UI display.
struct AIChatPageContext {
    let title: String
    let favicon: UIImage?
    let contextData: AIChatPageContextData

    init(contextData: AIChatPageContextData, favicon: UIImage?) {
        self.title = contextData.title
        self.favicon = favicon
        self.contextData = contextData
    }
}

// MARK: - Provider Typealiases

typealias WebViewProvider = () -> WKWebView?
typealias UserScriptProvider = () -> PageContextUserScript?
typealias FaviconProvider = (URL) -> String?

// MARK: - Protocols

/// Interface for page context handling (collection, storage, updates).
/// Only the coordinator should access this type directly. Other components receive closures.
protocol AIChatPageContextHandling: AnyObject {
    /// Publisher for context updates. Subscribe to receive results after triggering collection.
    var contextPublisher: AnyPublisher<AIChatPageContext?, Never> { get }

    /// Triggers context collection from JS. Does not return the result directly.
    /// Callers should subscribe to `contextPublisher` for results.
    /// Note: First call also starts observing auto-updates from the page.
    @discardableResult func triggerContextCollection() -> Bool

    /// Clears stored context and cancels active subscriptions.
    func clear()
}

// MARK: - Implementation

@MainActor
final class AIChatPageContextHandler: @MainActor AIChatPageContextHandling {

    // MARK: - Properties

    private let webViewProvider: WebViewProvider
    private let userScriptProvider: UserScriptProvider
    private let faviconProvider: FaviconProvider

    private let contextSubject = CurrentValueSubject<AIChatPageContext?, Never>(nil)
    private var updatesCancellable: AnyCancellable?

    // MARK: - AIChatPageContextHandling

    var contextPublisher: AnyPublisher<AIChatPageContext?, Never> {
        contextSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(webViewProvider: @escaping WebViewProvider,
         userScriptProvider: @escaping UserScriptProvider,
         faviconProvider: @escaping FaviconProvider) {
        self.webViewProvider = webViewProvider
        self.userScriptProvider = userScriptProvider
        self.faviconProvider = faviconProvider
    }

    @discardableResult
    func triggerContextCollection() -> Bool {
        Logger.aiChat.debug("[PageContext] Collection triggered")

        guard let script = userScriptProvider() else {
            Logger.aiChat.debug("[PageContext] Collection skipped - no user script available")
            return false
        }

        script.webView = webViewProvider()
        startObservingUpdates()
        script.collect()
        return true
    }

    func clear() {
        Logger.aiChat.debug("[PageContext] Clearing stored context and cancelling subscriptions")
        updatesCancellable?.cancel()
        updatesCancellable = nil
        contextSubject.send(nil)

        if let script = userScriptProvider() {
            script.webView = nil
        }
    }
}

// MARK: - Private Methods

private extension AIChatPageContextHandler {

    func startObservingUpdates() {
        guard updatesCancellable == nil,
              let script = userScriptProvider() else { return }

        updatesCancellable = script.collectionResultPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pageContext in
                guard let self else { return }

                guard let pageContext else {
                    Logger.aiChat.debug("[PageContext] Context collection returned nil - publishing nil to subscribers")
                    self.contextSubject.send(nil)
                    return
                }

                self.publishContextUpdate(pageContext)
            }
    }

    func publishContextUpdate(_ context: AIChatPageContextData) {
        Logger.aiChat.debug("[PageContext] Context received - title: \(context.title.prefix(50)), content: \(context.content.count) chars, truncated: \(context.truncated)")
        let enriched = self.enrichWithFavicon(context)
        let favicon = decodeFaviconImage(from: enriched.favicon)
        let pageContextWrapper = AIChatPageContext(contextData: enriched, favicon: favicon)
        contextSubject.send(pageContextWrapper)
    }

    func enrichWithFavicon(_ context: AIChatPageContextData) -> AIChatPageContextData {
        guard let url = URL(string: context.url) else {
            return context
        }

        guard let faviconBase64 = faviconProvider(url) else {
            return context
        }

        let favicon = AIChatPageContextData.PageContextFavicon(href: faviconBase64, rel: "icon")
        return AIChatPageContextData(
            title: context.title,
            favicon: [favicon],
            url: context.url,
            content: context.content,
            truncated: context.truncated,
            fullContentLength: context.fullContentLength
        )
    }

    func decodeFaviconImage(from favicons: [AIChatPageContextData.PageContextFavicon]) -> UIImage? {
        guard let favicon = favicons.first,
              favicon.href.hasPrefix("data:image"),
              let dataRange = favicon.href.range(of: "base64,"),
              let imageData = Data(base64Encoded: String(favicon.href[dataRange.upperBound...])) else {
            return nil
        }
        return UIImage(data: imageData)
    }
}

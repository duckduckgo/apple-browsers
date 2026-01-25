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

// MARK: - Provider Typealiases

typealias WebViewProvider = () -> WKWebView?
typealias UserScriptProvider = () -> PageContextUserScript?
typealias FaviconProvider = (URL) -> String?

// MARK: - Protocols

/// Interface for page context handling (collection, storage, updates).
/// Only the coordinator should access this type directly. Other components receive closures.
protocol AIChatPageContextHandling: AnyObject {
    /// The latest page context collected from the current tab.
    var latestContext: AIChatPageContextData? { get }

    /// Decoded favicon image from the latest context, cached for chip display.
    var latestFavicon: UIImage? { get }

    /// Returns whether there is context available.
    var hasContext: Bool { get }

    /// Publisher for context updates. Subscribe to receive results after triggering collection.
    var contextPublisher: AnyPublisher<AIChatPageContextData?, Never> { get }

    /// Triggers context collection from JS. Does not return the result directly.
    /// Callers should subscribe to `contextPublisher` for results.
    /// Note: First call also starts observing auto-updates from the page.
    func triggerContextCollection() async

    /// Clear stored context and stop observing updates.
    func clear()
}

// MARK: - Implementation

@MainActor
final class AIChatPageContextHandler: AIChatPageContextHandling {

    // MARK: - Constants

    private enum Constants {
        static let collectionTimeout: TimeInterval = 2
    }

    // MARK: - Properties

    private let webViewProvider: WebViewProvider
    private let userScriptProvider: UserScriptProvider
    private let faviconProvider: FaviconProvider

    private var storedContext: AIChatPageContextData?
    private var storedFavicon: UIImage?
    private let contextSubject = CurrentValueSubject<AIChatPageContextData?, Never>(nil)
    private var updatesCancellable: AnyCancellable?

    // MARK: - AIChatPageContextHandling

    var latestContext: AIChatPageContextData? {
        storedContext
    }

    var latestFavicon: UIImage? {
        storedFavicon
    }

    var hasContext: Bool {
        storedContext != nil
    }

    var contextPublisher: AnyPublisher<AIChatPageContextData?, Never> {
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

    func triggerContextCollection() async {
        Logger.aiChat.debug("[PageContext] Collection triggered")

        guard let script = userScriptProvider() else {
            Logger.aiChat.debug("[PageContext] Collection skipped - no user script available")
            return
        }

        script.webView = webViewProvider()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var cancellable: AnyCancellable?
            var didResume = false

            cancellable = script.collectionResultPublisher
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] pageContext in
                    guard !didResume else { return }
                    didResume = true
                    cancellable?.cancel()

                    let enriched = self?.enrichWithFavicon(pageContext)
                    if let enriched {
                        self?.updateInternal(enriched)
                    }
                    continuation.resume()
                }

            script.collect()

            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.collectionTimeout) {
                guard !didResume else { return }
                didResume = true
                cancellable?.cancel()
                continuation.resume()
            }
        }

        startObservingUpdates()
    }

    func clear() {
        Logger.aiChat.debug("[PageContext] Context cleared")
        stopObservingUpdates()
        storedContext = nil
        storedFavicon = nil
        contextSubject.send(nil)
    }

    // MARK: - Private Methods

    private func startObservingUpdates() {
        guard updatesCancellable == nil,
              let script = userScriptProvider() else { return }

        updatesCancellable = script.collectionResultPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pageContext in
                guard let self, let pageContext else { return }

                let enriched = self.enrichWithFavicon(pageContext)
                if let enriched {
                    self.updateInternal(enriched)
                }
            }
    }

    private func stopObservingUpdates() {
        updatesCancellable?.cancel()
        updatesCancellable = nil
    }

    private func updateInternal(_ context: AIChatPageContextData?) {
        if let context {
            Logger.aiChat.debug("[PageContext] Context received - title: \(context.title.prefix(50)), content: \(context.content.count) chars, truncated: \(context.truncated)")
        }
        storedContext = context
        storedFavicon = context.flatMap { decodeFaviconImage(from: $0.favicon) }
        contextSubject.send(context)
    }

    private func enrichWithFavicon(_ context: AIChatPageContextData?) -> AIChatPageContextData? {
        guard let context = context,
              let url = URL(string: context.url) else {
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

    private func decodeFaviconImage(from favicons: [AIChatPageContextData.PageContextFavicon]) -> UIImage? {
        guard let favicon = favicons.first,
              favicon.href.hasPrefix("data:image"),
              let dataRange = favicon.href.range(of: "base64,"),
              let imageData = Data(base64Encoded: String(favicon.href[dataRange.upperBound...])) else {
            return nil
        }
        return UIImage(data: imageData)
    }
}

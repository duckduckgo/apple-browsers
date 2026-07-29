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
struct AIChatPageContext: Equatable {
    let title: String
    let favicon: UIImage?
    let contextData: AIChatPageContextData

    init(contextData: AIChatPageContextData, favicon: UIImage?) {
        self.title = contextData.title
        self.favicon = favicon
        self.contextData = contextData
    }

    static func == (lhs: AIChatPageContext, rhs: AIChatPageContext) -> Bool {
        lhs.contextData == rhs.contextData
    }
}

// MARK: - Provider Typealiases

typealias WebViewProvider = () -> WKWebView?
typealias UserScriptProvider = () -> PageContextCollecting?
typealias FaviconProvider = (URL) -> String?

/// `nil` when the `aiPageContextBlocklist` config is absent/malformed (kill-switch: gate + measurement no-op).
typealias AttachabilityPolicyProvider = () -> PageContextAttachabilityPolicy?

typealias PageContextURLProvider = () -> URL?

/// `nil` when unknown (restored / cached / back-forward navigations with no observed response).
typealias PageContextMIMETypeProvider = (URL) -> String?

// MARK: - Page Context Collection Protocol

/// Protocol for page context collection, enabling dependency injection and testing.
protocol PageContextCollecting: AnyObject {
    var collectionResultPublisher: AnyPublisher<AIChatPageContextData?, Never> { get }
    var webView: WKWebView? { get set }
    func collect()
}

extension PageContextUserScript: PageContextCollecting {}

// MARK: - Protocols

/// Interface for page context handling (collection, storage, updates).
/// Only the coordinator should access this type directly. Other components receive closures.
protocol AIChatPageContextHandling: AnyObject {
    /// Publisher for context updates. Subscribe to receive results after triggering collection.
    var contextPublisher: AnyPublisher<AIChatPageContext?, Never> { get }

    /// Triggers context collection from JS. Does not return the result directly.
    /// Callers should subscribe to `contextPublisher` for results.
    /// Note: First call also starts observing auto-updates from the page.
    @discardableResult func triggerContextCollection(trigger: PageContextExtractionTrigger) -> Bool

    /// Whether the current page can be attached; `true` when no blocklist config (fail-open).
    func isCurrentPageAttachable() -> Bool

    /// Fires the `prevented` measurement if the current page is non-attachable, without collecting.
    /// Call when the sheet becomes active / navigates so non-attachable pages are still measured.
    func reportAttachabilityMeasurement(trigger: PageContextExtractionTrigger)

    /// Clears stored context and cancels active subscriptions.
    func clear()

    /// Resubscribes to the current script's publisher after content blocking assets are reinstalled.
    func resubscribe()

    /// Clears the buffered attached context (emits nil) without cancelling active subscriptions.
    /// Used when the user manually detaches a page from within the contextual chat session.
    func clearAttachedContext()
}

// MARK: - Implementation

@MainActor
final class AIChatPageContextHandler: AIChatPageContextHandling {

    // MARK: - Properties

    private let webViewProvider: WebViewProvider
    private let userScriptProvider: UserScriptProvider
    private let faviconProvider: FaviconProvider
    private let pixelHandler: AIChatContextualModePixelFiring

    private let attachabilityPolicyProvider: AttachabilityPolicyProvider
    private let currentURLProvider: PageContextURLProvider
    private let mimeTypeProvider: PageContextMIMETypeProvider
    private let extractionPixelHandler: PageContextExtractionPixelFiring

    /// FIFO-pairs collect requests with results so pixels carry the right trigger/latency; reset on navigation.
    private var extractionResolver = PageContextExtractionResolver()

    /// Reports one extraction pixel per navigation despite its overlapping collects; reset on new URL.
    private var didReportExtractionForCurrentNavigation = false

    private var lastCollectedURL: URL?

    /// Safety-net for a fire-and-forget collect that never resolves → reported as `.timeout`.
    private static let collectionTimeout: TimeInterval = 30

    private let contextSubject = CurrentValueSubject<AIChatPageContext?, Never>(nil)
    private var updatesCancellable: AnyCancellable?

    // MARK: - AIChatPageContextHandling

    var contextPublisher: AnyPublisher<AIChatPageContext?, Never> {
        contextSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(webViewProvider: @escaping WebViewProvider,
         userScriptProvider: @escaping UserScriptProvider,
         faviconProvider: @escaping FaviconProvider,
         pixelHandler: AIChatContextualModePixelFiring = AIChatContextualModePixelHandler(),
         attachabilityPolicyProvider: @escaping AttachabilityPolicyProvider = { nil },
         currentURLProvider: PageContextURLProvider? = nil,
         mimeTypeProvider: @escaping PageContextMIMETypeProvider = { _ in nil },
         extractionPixelHandler: PageContextExtractionPixelFiring = PageContextExtractionPixelHandler()) {
        self.webViewProvider = webViewProvider
        self.userScriptProvider = userScriptProvider
        self.faviconProvider = faviconProvider
        self.pixelHandler = pixelHandler
        self.attachabilityPolicyProvider = attachabilityPolicyProvider
        self.currentURLProvider = currentURLProvider ?? { webViewProvider()?.url }
        self.mimeTypeProvider = mimeTypeProvider
        self.extractionPixelHandler = extractionPixelHandler
    }

    @discardableResult
    func triggerContextCollection(trigger: PageContextExtractionTrigger) -> Bool {
        Logger.aiChat.debug("[PageContext] Collection triggered (trigger: \(trigger.rawValue))")

        let url = currentURLProvider()
        resetExtractionStateIfNavigated(to: url)

        // Gate: skip collection + deliver nil (iOS has no native attachable:false path) for blocklisted pages.
        if firePreventedIfNonAttachable(for: url, trigger: trigger) {
            contextSubject.send(nil)
            return false
        }

        guard let script = userScriptProvider() else {
            Logger.aiChat.debug("[PageContext] Collection skipped - no user script available")
            pixelHandler.firePageContextCollectionUnavailable()
            fireExtractionPixel(.failure(.noWebView), trigger: trigger, latency: nil)
            return false
        }

        guard let webView = webViewProvider() else {
           Logger.aiChat.debug("[PageContext] Collection skipped - no web view available")
           fireExtractionPixel(.failure(.noWebView), trigger: trigger, latency: nil)
           return false
       }

        script.webView = webView
        startObservingUpdates()
        extractionResolver.requested(trigger: trigger)
        Logger.aiChat.debug("[PageContext] ✅ gate: attachable, collecting (trigger: \(trigger.rawValue))")
        script.collect()
        scheduleCollectionTimeout()
        return true
    }

    func isCurrentPageAttachable() -> Bool {
        guard let policy = attachabilityPolicyProvider() else { return true }
        let url = currentURLProvider()
        return policy.verdict(url: url, mimeType: url.flatMap { mimeTypeProvider($0) }).isAttachable
    }

    func reportAttachabilityMeasurement(trigger: PageContextExtractionTrigger) {
        let url = currentURLProvider()
        resetExtractionStateIfNavigated(to: url)
        _ = firePreventedIfNonAttachable(for: url, trigger: trigger)
    }

    func clear() {
        Logger.aiChat.debug("[PageContext] Clearing stored context and cancelling subscriptions")
        updatesCancellable?.cancel()
        updatesCancellable = nil
        resetExtractionState()
        contextSubject.send(nil)

        if let script = userScriptProvider() {
            script.webView = nil
        }
    }

    func clearAttachedContext() {
        Logger.aiChat.debug("[PageContext] Clearing attached context (preserving subscriptions)")
        contextSubject.send(nil)
    }

    /// Resubscribes to the current PageContextUserScript's publisher.
    /// Call when content blocking assets are reinstalled and a new script instance is created.
    func resubscribe() {
        Logger.aiChat.debug("[PageContext] Resubscribe called - cancelling existing subscription")
        updatesCancellable?.cancel()
        updatesCancellable = nil
        resetExtractionState()
        startObservingUpdates()
    }
}

// MARK: - Private Methods

private extension AIChatPageContextHandler {

    // MARK: - Extraction measurement

    var isExtractionMeasurementEnabled: Bool {
        attachabilityPolicyProvider() != nil
    }

    /// Fires `.prevented` for a non-attachable page; returns whether it did. Shared by the collection
    /// gate and the standalone sheet-open/navigation measurement.
    @discardableResult
    func firePreventedIfNonAttachable(for url: URL?, trigger: PageContextExtractionTrigger) -> Bool {
        guard let policy = attachabilityPolicyProvider() else { return false }
        let verdict = policy.verdict(url: url, mimeType: url.flatMap { mimeTypeProvider($0) })
        guard !verdict.isAttachable else { return false }
        let reason = verdict.preventionReason ?? PageContextExtractionOutcome.internalPageCategory
        Logger.aiChat.debug("[PageContext] 🚫 gate: prevented attach (reason: \(reason))")
        fireExtractionPixel(.prevented(reason), trigger: trigger, latency: nil)
        return true
    }

    /// On navigation to a new URL, drops stale pending collects so they can't mis-attribute the next page's result.
    func resetExtractionStateIfNavigated(to url: URL?) {
        guard url != lastCollectedURL else { return }
        resetExtractionState()
        lastCollectedURL = url
    }

    /// Drops any pending collect + navigation dedupe state. Called on clear/resubscribe so a stale
    /// entry can't pair with a later collect or emit a spurious timeout pixel.
    func resetExtractionState() {
        extractionResolver.reset()
        didReportExtractionForCurrentNavigation = false
        lastCollectedURL = nil
    }

    /// No pending request => a duplicate or a collect we didn't initiate; skip.
    func fireExtractionOutcome(for pageContext: AIChatPageContextData?) {
        guard let resolution = extractionResolver.resolve(pageContext: pageContext) else { return }
        fireExtractionPixel(resolution.outcome, trigger: resolution.trigger, latency: resolution.latency)
    }

    func fireExtractionPixel(_ outcome: PageContextExtractionOutcome,
                             trigger: PageContextExtractionTrigger,
                             latency: PageContextExtractionLatencyBucket?) {
        guard isExtractionMeasurementEnabled else { return }
        // Report only the first of a navigation's overlapping collects; .userRequest / .auto always report.
        if trigger == .navigation || trigger == .tabContent {
            guard !didReportExtractionForCurrentNavigation else { return }
            didReportExtractionForCurrentNavigation = true
        }
        Logger.aiChat.debug("[PageContext] 📊 extraction outcome: \(String(describing: outcome)) trigger: \(trigger.rawValue)")
        extractionPixelHandler.fire(outcome, trigger: trigger, latency: latency)
    }

    /// Fires `.timeout` (and clears the pending entry) for a collect that never resolved within the window.
    func scheduleCollectionTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collectionTimeout) { [weak self] in
            guard let self else { return }
            for resolution in self.extractionResolver.expireCollections(olderThan: Self.collectionTimeout) {
                self.fireExtractionPixel(resolution.outcome, trigger: resolution.trigger, latency: resolution.latency)
            }
        }
    }

    func startObservingUpdates() {
        guard updatesCancellable == nil else {
            Logger.aiChat.debug("[PageContext] startObservingUpdates skipped - already subscribed")
            return
        }
        guard let script = userScriptProvider() else {
            Logger.aiChat.debug("[PageContext] startObservingUpdates skipped - no script available")
            return
        }

        Logger.aiChat.debug("[PageContext] startObservingUpdates - subscribing to new script instance")
        updatesCancellable = script.collectionResultPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pageContext in
                guard let self else { return }

                self.fireExtractionOutcome(for: pageContext)

                guard let pageContext else {
                    Logger.aiChat.debug("[PageContext] Context collection returned nil - decode failure, publishing nil to subscribers")
                    self.contextSubject.send(nil)
                    return
                }

                guard !pageContext.isEmpty() else {
                    Logger.aiChat.debug("[PageContext] Context collection returned empty content - publishing nil to subscribers")
                    self.pixelHandler.firePageContextCollectionEmpty()
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
        // Preserve pageTypeSignals/attached/tabId when re-building the context with an encoded favicon
        return AIChatPageContextData(
            title: context.title,
            favicon: [favicon],
            url: context.url,
            content: context.content,
            truncated: context.truncated,
            fullContentLength: context.fullContentLength,
            attachable: context.attachable,
            tabId: context.tabId,
            pageTypeSignals: context.pageTypeSignals,
            attached: context.attached
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

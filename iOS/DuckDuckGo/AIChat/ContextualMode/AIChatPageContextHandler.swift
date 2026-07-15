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

/// Supplies the attachability policy built from the current `aiPageContextBlocklist` privacy config,
/// or `nil` when the config is absent/malformed. `nil` is the kill-switch: gating and extraction
/// telemetry become no-ops (fail-open). Mirrors macOS `PageContextTabExtension.currentAttachabilityPolicy()`.
typealias AttachabilityPolicyProvider = () -> PageContextAttachabilityPolicy?

/// Supplies the URL of the page about to be collected (production: the web view's current URL).
typealias PageContextURLProvider = () -> URL?

/// Supplies the main-frame response MIME type for a given URL, or `nil` when unknown
/// (restored / cached / back-forward navigations where no response was observed).
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
    /// - Parameter trigger: what initiated the collection, used for extraction telemetry.
    @discardableResult func triggerContextCollection(trigger: PageContextExtractionTrigger) -> Bool

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

    /// Pairs collect requests with their results (FIFO) so extraction pixels carry the right
    /// trigger/latency when collects overlap. Reset on navigation to a new URL.
    private var extractionResolver = PageContextExtractionResolver()

    /// Set once a navigation/tab-content extraction outcome is reported for the current URL, so the
    /// overlapping collects triggered by one navigation don't each fire a pixel. Reset on new URL.
    private var didReportExtractionForCurrentNavigation = false

    /// The URL of the most recent collection, used to detect navigation and reset the resolver.
    private var lastCollectedURL: URL?

    /// Safety-net window for a fire-and-forget `collect()` whose result never arrives (hung JS, torn-
    /// down page). After it, the pending entry is dropped and reported as `.timeout`. Kept generous —
    /// a slow collect resolving after this window is still delivered via `handle`, but its pending
    /// entry is already gone, so it can be mislabeled `.timeout`; a high value makes that rare while
    /// bounding the queue (navigation also clears it via `extractionResolver.reset()`). Independent of
    /// the coordinator's 5s synchronous FE-bridge timeout. Mirrors macOS `collectionTimeout`.
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

        // Attachability gate. When the blocklist config is present and the page is not attachable,
        // skip collection, deliver nil (no auto-attach — iOS native UI has no attachable:false path),
        // and fire the `prevented` extraction pixel. Config absent/malformed => policy nil => no-op.
        if let policy = attachabilityPolicyProvider() {
            let mimeType = url.flatMap { mimeTypeProvider($0) }
            let verdict = policy.verdict(url: url, mimeType: mimeType)
            if !verdict.isAttachable {
                let reason = verdict.preventionReason ?? PageContextExtractionOutcome.internalPageCategory
                Logger.aiChat.debug("[PageContext] 🚫 gate: prevented attach (reason: \(reason))")
                fireExtractionPixel(.prevented(reason), trigger: trigger, latency: nil)
                contextSubject.send(nil)
                return false
            }
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

    func clear() {
        Logger.aiChat.debug("[PageContext] Clearing stored context and cancelling subscriptions")
        updatesCancellable?.cancel()
        updatesCancellable = nil
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
        startObservingUpdates()
    }
}

// MARK: - Private Methods

private extension AIChatPageContextHandler {

    // MARK: - Extraction telemetry

    /// Telemetry (and gating) is active only while the `aiPageContextBlocklist` config is present.
    /// Matches macOS: the extraction pixels give a baseline only where the blocklist is deployed.
    var isExtractionMeasurementEnabled: Bool {
        attachabilityPolicyProvider() != nil
    }

    /// Drops the previous page's outstanding collects and clears the once-per-navigation guard when the
    /// collection URL changes, so a slow/never-resolving collect can't pair (FIFO) with the next page's
    /// result and mis-attribute its trigger/latency/outcome. Mirrors macOS `extractionResolver.reset()`.
    func resetExtractionStateIfNavigated(to url: URL?) {
        guard url != lastCollectedURL else { return }
        extractionResolver.reset()
        didReportExtractionForCurrentNavigation = false
        lastCollectedURL = url
    }

    /// Resolves a collection result against the pending request queue and fires its outcome pixel.
    /// No pending request => a duplicate or a collect we didn't initiate; skip.
    func fireExtractionOutcome(for pageContext: AIChatPageContextData?) {
        guard let resolution = extractionResolver.resolve(pageContext: pageContext) else { return }
        fireExtractionPixel(resolution.outcome, trigger: resolution.trigger, latency: resolution.latency)
    }

    func fireExtractionPixel(_ outcome: PageContextExtractionOutcome,
                             trigger: PageContextExtractionTrigger,
                             latency: PageContextExtractionLatencyBucket?) {
        guard isExtractionMeasurementEnabled else { return }
        // A navigation drives several automatic collects (navigation re-collect + signals-only);
        // report only the first. User/setting collects (.userRequest / .auto) always report.
        if trigger == .navigation || trigger == .tabContent {
            guard !didReportExtractionForCurrentNavigation else { return }
            didReportExtractionForCurrentNavigation = true
        }
        Logger.aiChat.debug("[PageContext] 📊 extraction outcome: \(String(describing: outcome)) trigger: \(trigger.rawValue)")
        extractionPixelHandler.fire(outcome, trigger: trigger, latency: latency)
    }

    /// Fires `.timeout` for any collect that hasn't produced a result within the timeout window and
    /// clears its pending entry, so a never-resolving collect neither loses its pixel nor lets a
    /// stale entry mis-attribute a later navigation. Mirrors macOS `scheduleCollectionTimeout`.
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

                // Extraction telemetry (success / empty / deserialize failure), paired with its
                // triggering collect. Independent of the auto-attach handling below.
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

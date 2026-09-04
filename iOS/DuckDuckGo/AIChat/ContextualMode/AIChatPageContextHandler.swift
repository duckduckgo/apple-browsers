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
import DesignResourcesKitIcons
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
        // A PDF is identified by its file type, not by whoever served it, so the chip shows the
        // document icon rather than the host's favicon.
        self.favicon = contextData.mimeType == AIChatPageContextData.pdfMIMEType
            ? DesignSystemImages.Color.Size24.filePDF
            : favicon
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

typealias DocumentContextMaking = @MainActor (MainResourceDataProviding, URL, String) async -> DocumentPageContextProvider.Result

// MARK: - Page Context Collection Protocol

/// Protocol for page context collection, enabling dependency injection and testing.
protocol PageContextCollecting: AnyObject {
    var collectionResultPublisher: AnyPublisher<PageContextCollectionResult, Never> { get }
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

    /// True while a document tab's bytes are being read;
    var documentReadInProgressPublisher: AnyPublisher<Bool, Never> { get }

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

    private let isDocumentContextEnabled: () -> Bool
    private let makeDocumentContext: DocumentContextMaking

    /// FIFO-pairs collect requests with results so pixels carry the right trigger/latency; reset on navigation.
    private var extractionResolver = PageContextExtractionResolver()

    /// Reports one extraction pixel per navigation despite its overlapping collects; reset on new URL.
    private var didReportExtractionForCurrentNavigation = false

    private var lastCollectedURL: URL?

    /// Safety-net for a fire-and-forget collect that never resolves → reported as `.timeout`.
    private static let collectionTimeout: TimeInterval = 30

    private let contextSubject = CurrentValueSubject<AIChatPageContext?, Never>(nil)
    private let documentReadInProgressSubject = CurrentValueSubject<Bool, Never>(false)
    private var updatesCancellable: AnyCancellable?

    // MARK: - AIChatPageContextHandling

    var contextPublisher: AnyPublisher<AIChatPageContext?, Never> {
        contextSubject.eraseToAnyPublisher()
    }

    var documentReadInProgressPublisher: AnyPublisher<Bool, Never> {
        documentReadInProgressSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(webViewProvider: @escaping WebViewProvider,
         userScriptProvider: @escaping UserScriptProvider,
         faviconProvider: @escaping FaviconProvider,
         pixelHandler: AIChatContextualModePixelFiring = AIChatContextualModePixelHandler(),
         attachabilityPolicyProvider: @escaping AttachabilityPolicyProvider = { nil },
         currentURLProvider: PageContextURLProvider? = nil,
         mimeTypeProvider: @escaping PageContextMIMETypeProvider = { _ in nil },
         extractionPixelHandler: PageContextExtractionPixelFiring = PageContextExtractionPixelHandler(),
         isDocumentContextEnabled: @escaping () -> Bool = { false },
         makeDocumentContext: DocumentContextMaking? = nil) {
        self.webViewProvider = webViewProvider
        self.userScriptProvider = userScriptProvider
        self.faviconProvider = faviconProvider
        self.pixelHandler = pixelHandler
        self.attachabilityPolicyProvider = attachabilityPolicyProvider
        self.currentURLProvider = currentURLProvider ?? { webViewProvider()?.url }
        self.mimeTypeProvider = mimeTypeProvider
        self.extractionPixelHandler = extractionPixelHandler
        self.isDocumentContextEnabled = isDocumentContextEnabled
        self.makeDocumentContext = makeDocumentContext ?? { webView, url, title in
            await DocumentPageContextProvider.makeDocumentContext(webView: webView, url: url, title: title)
        }
    }

    @discardableResult
    func triggerContextCollection(trigger: PageContextExtractionTrigger) -> Bool {
        Logger.aiChat.debug("[PageContext] Collection triggered (trigger: \(trigger.rawValue))")

        let url = currentURLProvider()
        resetExtractionStateIfNavigated(to: url)

        // A document tab (PDF) is handed over as bytes —
        // On the signals-only collect push metadata so the FE chip can show
        if let url, isDocumentTab(url) {
            if trigger == .tabContent {
                publishDocumentMetadata(for: url)
            } else {
                collectDocumentContext(for: url, trigger: trigger)
            }
            return true
        }

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
        let url = currentURLProvider()
        if let url, isDocumentTab(url) { return true }
        guard let policy = attachabilityPolicyProvider() else { return true }
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
        if let url, isDocumentTab(url) { return false }
        guard let policy = attachabilityPolicyProvider() else { return false }
        let verdict = policy.verdict(url: url, mimeType: url.flatMap { mimeTypeProvider($0) })
        guard !verdict.isAttachable else { return false }
        let reason = verdict.preventionReason ?? PageContextExtractionOutcome.internalPageCategory
        Logger.aiChat.debug("[PageContext] 🚫 gate: prevented attach (reason: \(reason))")
        fireExtractionPixel(.prevented(reason), trigger: trigger, latency: nil)
        return true
    }

    // MARK: - Document Context (PDF)

    /// Whether this tab's page goes to Duck.ai as document bytes rather than markdown.
    func isDocumentTab(_ url: URL) -> Bool {
        isDocumentContextEnabled()
            && DocumentPageContextProvider.isSupportedDocument(mimeType: mimeTypeProvider(url), url: url)
    }

    /// A document context with no bytes: the chip can name the tab, and the bytes follow once
    /// the user asks for them. Used for the signals-only collect while auto-attach is off.
    func publishDocumentMetadata(for url: URL) {
        let context = DocumentPageContextProvider.metadataContext(
            url: url,
            title: documentTitle(for: url),
            attachable: true,
            attached: false
        )
        Logger.aiChat.debug("[PageContext] Document metadata only (deferring bytes until attach)")
        publishContextUpdate(context)
    }

    func collectDocumentContext(for url: URL, trigger: PageContextExtractionTrigger) {
        guard let webView = webViewProvider() else {
            Logger.aiChat.debug("[PageContext] Document collect skipped - no web view available")
            fireExtractionPixel(.failure(.noWebView), trigger: trigger, latency: nil)
            contextSubject.send(nil)
            return
        }

        let title = documentTitle(for: url, webView: webView)
        let startedAt = Date()
        documentReadInProgressSubject.send(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.documentReadInProgressSubject.send(false) }
            let result = await self.makeDocumentContext(webView, url, title)
            let latency = PageContextExtractionLatencyBucket(seconds: Date().timeIntervalSince(startedAt))

            // The read is async: the tab may have navigated while it was in flight. Delivering now
            // would attach this document to whatever page the user is on instead.
            guard self.currentURLProvider() == url else {
                Logger.aiChat.debug("[PageContext] Navigated away while reading document - dropping")
                return
            }

            switch result {
            case .document(let context):
                Logger.aiChat.debug("[PageContext] Document attached")
                self.publishContextUpdate(context)
                self.fireExtractionPixel(.success, trigger: trigger, latency: latency)
            case .tooLarge:
                Logger.aiChat.debug("[PageContext] Document over size ceiling - not attaching")
                self.contextSubject.send(nil)
                self.fireExtractionPixel(.prevented(PageContextExtractionOutcome.documentTooLargeCategory), trigger: trigger, latency: latency)
            case .unavailable:
                Logger.aiChat.debug("[PageContext] Document bytes unavailable")
                self.contextSubject.send(nil)
                self.fireExtractionPixel(.failure(.documentUnavailable), trigger: trigger, latency: latency)
            }
        }
    }

    func documentTitle(for url: URL, webView: WKWebView? = nil) -> String {
        let webViewTitle = (webView ?? webViewProvider())?.title ?? ""
        return webViewTitle.isEmpty ? url.lastPathComponent : webViewTitle
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
        documentReadInProgressSubject.send(false)
    }

    /// No pending request => a duplicate or a collect we didn't initiate; skip.
    func fireExtractionOutcome(for result: PageContextCollectionResult) {
        guard let resolution = extractionResolver.resolve(result) else { return }
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
            .sink { [weak self] result in
                guard let self else { return }

                self.fireExtractionOutcome(for: result)

                guard let pageContext = result.pageContext else {
                    Logger.aiChat.debug("[PageContext] Context collection failed (\(String(describing: result))) - publishing nil to subscribers")
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
        // Copy preserves every other field — including a document context's mimeType/data.
        return context.withFavicon([favicon])
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

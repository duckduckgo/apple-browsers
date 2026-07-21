//
//  PageContextTabExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Navigation
import os.log
import PrivacyConfig
import WebKit

protocol PageContextUserScriptProvider {
    var pageContextUserScript: PageContextUserScript? { get }
}
extension UserScripts: PageContextUserScriptProvider {}

/// This tab extension is responsible for managing page context
/// collected by `PageContextUserScript` and passing it to the
/// sidebar.
///
/// It only works for non-sidebar tabs. When in sidebar, it's not fully initialized
/// and is a no-op.
///
final class PageContextTabExtension {

    private var cancellables = Set<AnyCancellable>()
    private var userScriptCancellables = Set<AnyCancellable>()
    private var sidebarCancellables = Set<AnyCancellable>()
    private let tabID: TabIdentifier
    private var content: Tab.TabContent = .none
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let extractionPixelHandler: PageContextExtractionPixelFiring
    private var mainFrameMIMECache = MainFrameMIMECache()
    private var pendingSettledNavigationURL: URL?

    private var extractionResolver = PageContextExtractionResolver()

    /// Set once an automatic (page-load) extraction outcome is reported for the current navigation,
    /// so its overlapping navigation/signals-only collects don't each fire a pixel. Reset on new URL.
    private var didReportExtractionForCurrentNavigation = false

    private var didReportSidebarOpenOutcomeForCurrentNavigation = false

    /// Safety-net window for a fire-and-forget `collect()` whose result never arrives (hung JS,
    /// torn-down page). After it, `scheduleCollectionTimeout` fires `.timeout` and drops the pending
    /// entry so the queue can't leak.
    ///
    /// Kept deliberately generous: a slow collect that resolves *after* this window is still
    /// delivered to Duck.ai via `handle`, but its pending entry is already gone, so `resolve` finds
    /// no match and it's mis-recorded as a `.timeout` with no offsetting success pixel. A high value
    /// makes that late-success mislabeling rare while still bounding the queue (navigation also
    /// clears it via `extractionResolver.reset()`). Independent of `collectAndWait`'s 5s default —
    /// that's a separate, synchronous tab-picker path.
    private static let collectionTimeout: TimeInterval = 30

    private let aiChatSessionStore: AIChatSessionStoring
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private let isLoadedInSidebar: Bool
    private let faviconManagement: FaviconManagement
    private var cachedPageContext: AIChatPageContextData?

    /// Text selections ("Attach to Duck.ai") buffered until the sidebar chat VC exists. Lives on
    /// its own channel, independent of the single page-context slot above — it never touches
    /// `cachedPageContext` or triggers page collection. Once flushed, the duck.ai web app owns the list.
    private var pendingSelectionContexts: [AIChatSelectionContextData] = []

    /// Tracks whether a prompt has been submitted in the current chat session.
    /// When true, navigating with auto-collect OFF will send a nil signal so the
    /// frontend can show "Add page content" for the new page.
    private var hasContextBeenConsumedByChat: Bool = false

    /// This flag is set when context collection was requested by the user from the sidebar.
    ///
    /// It allows to override the AI Features setting for automatic context collection.
    /// The flag is automatically cleared after receiving a `collectionResult` message.
    private var shouldForceContextCollection: Bool = false

    /// Set when we trigger a collection purely to harvest Content-Scope-Scripts page-type signals
    /// while auto-attach is OFF. The collectionResult is then delivered as a signals-only payload
    /// (content stripped, attached:false). Cleared when that result arrives.
    private var pendingSignalsOnlyCollection: Bool = false

    /// Set when the user explicitly removes page context from the chat.
    /// Suppresses auto-collection on the current page until the next navigation.
    private var userRemovedContext: Bool = false

    private weak var webView: WKWebView?
    private weak var pageContextUserScript: PageContextUserScript? {
        didSet {
            subscribeToCollectionResult()
        }
    }
    private weak var session: AIChatSession? {
        didSet {
            subscribeToCollectionRequest()
        }
    }

    init(
        scriptsPublisher: some Publisher<some PageContextUserScriptProvider, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>,
        contentPublisher: some Publisher<Tab.TabContent, Never>,
        tabID: TabIdentifier,
        featureFlagger: FeatureFlagger,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        extractionPixelHandler: PageContextExtractionPixelFiring,
        aiChatSessionStore: AIChatSessionStoring,
        aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
        isLoadedInSidebar: Bool,
        faviconManagement: FaviconManagement
    ) {
        self.tabID = tabID
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.extractionPixelHandler = extractionPixelHandler
        self.aiChatSessionStore = aiChatSessionStore
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.isLoadedInSidebar = isLoadedInSidebar
        self.faviconManagement = faviconManagement

        guard !isLoadedInSidebar else {
            return
        }
        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
            self?.pageContextUserScript?.webView = webView
        }.store(in: &cancellables)

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.pageContextUserScript = scripts.pageContextUserScript
                self?.pageContextUserScript?.webView = self?.webView
            }
        }.store(in: &cancellables)

        contentPublisher.removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] tabContent in
                guard let self else { return }

                let previousContent = self.content
                self.content = tabContent
                // Reset user-removed suppression when navigating to a new URL so
                // auto-collect resumes on the next page, regardless of feature flag state.
                // Also drop the previous page's cached context so a stale snapshot
                // can't be re-pushed to the sidebar before the new page is collected.
                if case .url = tabContent {
                    self.userRemovedContext = false
                    self.cachedPageContext = nil
                    // Selections are tied to the page they were made on — drop any not-yet-flushed ones.
                    self.pendingSelectionContexts = []
                    // Drop the previous page's outstanding collects so a slow or never-resolving
                    // collect can't pair (FIFO) with this page's result and mis-attribute its
                    // extraction measurement (trigger/latency/outcome).
                    self.extractionResolver.reset()
                    self.didReportExtractionForCurrentNavigation = false
                    self.didReportSidebarOpenOutcomeForCurrentNavigation = false
                }
                self.handleNavigationForMultipleContexts(from: previousContent, to: tabContent)
                self.sendNonAttachableContextIfNeeded()
                // A settled navigation that beat this debounced update deferred its re-collect; now
                // that `content` matches, run it (a fast / back-forward restore the delegate missed).
                self.runPendingSettledNavigationReCollectIfNeeded()
                // Signals-only collection is driven from `navigationDidFinish` (post-load, parsed
                // markup). Collecting here at didCommit too would race the post-load re-collect for
                // the single-shot `pendingSignalsOnlyCollection` flag and let stale signals win.
            }
            .store(in: &cancellables)

        aiChatSessionStore.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .map { $0[tabID] != nil }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self, weak aiChatSessionStore] _ in
                guard let self else {
                    return
                }
                session = aiChatSessionStore?.sessions[tabID]

                // Flush any selections attached while the sidebar was opening. Deferred so the
                // chat VC exists after `showSidebar` finishes. Independent of page context below.
                Task { @MainActor [weak self] in self?.flushPendingSelectionContexts() }

                self.deliverContextToCurrentSidebar()
            }
            .store(in: &cancellables)

        aiChatMenuConfiguration.valuesChangedPublisher
            .map { aiChatMenuConfiguration.shouldAutomaticallySendPageContext }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self else {
                    return
                }
                if isEnabled {
                    /// Proactively collect page context when page context setting was enabled
                    if let cachedPageContext {
                        Task { await self.handle(cachedPageContext) }
                    } else {
                        collectPageContextIfNeeded(trigger: .auto)
                    }
                }
            }
            .store(in: &cancellables)

    }

    private func subscribeToCollectionResult() {
        userScriptCancellables.removeAll()
        guard let pageContextUserScript else {
            return
        }

        pageContextUserScript.collectionResultPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pageContext in
                guard let self else {
                    return
                }
                /// Process full collection when auto-collect is enabled (or the user explicitly
                /// requested context). When auto-collect is OFF but we requested a signals-only
                /// collection, deliver just the page-type signals (content stripped). Otherwise
                /// ignore unsolicited results so they can't overwrite attached context with nil.
                if self.isContextCollectionEnabled {
                    self.pendingSignalsOnlyCollection = false
                    let wasForced = self.shouldForceContextCollection
                    self.shouldForceContextCollection = false
                    self.fireExtractionOutcome(for: pageContext)
                    if Self.shouldDeliverCollectionResult(pageContext, wasForced: wasForced, cached: self.cachedPageContext) {
                        Task {
                            await self.handle(pageContext)
                        }
                    }
                } else if self.pendingSignalsOnlyCollection {
                    self.pendingSignalsOnlyCollection = false
                    Task {
                        await self.handleSignalsOnly(pageContext)
                    }
                }
            }
            .store(in: &userScriptCancellables)
    }

    /// handle view controller changes when the sidebar is closed and reopened.
    private func subscribeToCollectionRequest() {
        sidebarCancellables.removeAll()
        guard let session else {
            return
        }

        session.chatViewControllerPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chatViewController in
                guard let self, chatViewController != nil else { return }
                self.deliverContextToCurrentSidebar()
            }
            .store(in: &sidebarCancellables)

        session.pageContextRequestedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.shouldForceContextCollection = true
                self?.collectPageContextIfNeeded(trigger: .userRequest)
            }
            .store(in: &sidebarCancellables)

        session.pageContextConsumedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.hasContextBeenConsumedByChat = true
            }
            .store(in: &sidebarCancellables)

        session.pageContextRemovedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                // The FE fires this for both user X-click and the auto-clear after submit.
                // After submit the context was already consumed; pushing nil back would
                // make the FE re-show "Add page content" on the same URL.
                guard !self.hasContextBeenConsumedByChat else { return }
                self.userRemovedContext = true
                self.cachedPageContext = nil
                // Clear the stored pageContext too, so a later FE `getAIChatPageContext`
                // returns nil and triggers a fresh collect instead of the stale snapshot.
                self.aiChatSessionStore.sessions[self.tabID]?.chatViewController?.setPageContext(nil)
            }
            .store(in: &sidebarCancellables)
    }

    /// Results with content always deliver. Empty/nil results deliver only for a forced
    /// (user-requested) collect — the FE awaits the `getAIChatPageContext` response, so dropping
    /// them would leave it hanging — and never when they'd replace attached content.
    static func shouldDeliverCollectionResult(_ result: AIChatPageContextData?, wasForced: Bool, cached: AIChatPageContextData?) -> Bool {
        if result?.content.isEmpty == false { return true }
        return wasForced && cached?.content.isEmpty != false
    }

    /// This is the main place where page context handling happens.
    /// We always cache the latest context, and if sidebar is open,
    /// we're passing the context to it.
    @MainActor
    private func handle(_ pageContext: AIChatPageContextData?) async {
        guard featureFlagger.isFeatureOn(.aiChatPageContext) else {
            return
        }
        shouldForceContextCollection = false
        let gatedPageContext = forcingNonAttachableIfNeeded(pageContext)
        // Page-type signals (for duck.ai page shortcuts) ride the collected payload from
        // Content-Scope-Scripts (includePageTypeSignals) and are preserved through favicon encoding.
        cachedPageContext = replaceFaviconURLWithEncodedData(gatedPageContext)
        if let chatViewController = aiChatSessionStore.sessions[tabID]?.chatViewController {
            chatViewController.setPageContext(cachedPageContext)
            if gatedPageContext != nil, gatedPageContext?.attachable != false {
                // New attachable context pushed — reset the consumed flag so navigation
                // won't clear it until the next prompt is submitted.
                hasContextBeenConsumedByChat = false
            }
        }
    }

    private func forcingNonAttachableIfNeeded(_ pageContext: AIChatPageContextData?) -> AIChatPageContextData? {
        guard let pageContext,
              case .url(let url, _, _) = content,
              preventedAttachReason(for: url) != nil,
              pageContext.attachable != false else {
            return pageContext
        }
        return AIChatPageContextData(
            title: pageContext.title,
            favicon: pageContext.favicon,
            url: pageContext.url,
            content: pageContext.content,
            truncated: pageContext.truncated,
            fullContentLength: pageContext.fullContentLength,
            attachable: false,
            tabId: pageContext.tabId,
            pageTypeSignals: pageContext.pageTypeSignals,
            attached: pageContext.attached
        )
    }

    private func deliverContextToCurrentSidebar() {
        reportSidebarOpenExtractionOutcome()
        if let cachedPageContext, isContextCollectionEnabled {
            Task { await self.handle(cachedPageContext) }
        } else {
            sendNonAttachableContextIfNeeded()
            requestSignalsOnlyCollectionIfNeeded()
        }
    }

    // MARK: - Attachability gate

    private func currentAttachabilityPolicy() -> PageContextAttachabilityPolicy? {
        let settings = privacyConfigurationManager.privacyConfig.settings(for: .pageContext)
        guard let blocklist = PageContextBlocklistSettings(blocklist: settings["aiPageContextBlocklist"]) else {
            return nil
        }
        return PageContextAttachabilityPolicy(settings: blocklist)
    }

    /// Extraction measurement (success / failure / prevented / timeout) is only reported once the
    /// `aiPageContextBlocklist` privacy config is present
    private var isExtractionMeasurementEnabled: Bool {
        currentAttachabilityPolicy() != nil
    }

    private var isSidebarVisibleForTab: Bool {
        aiChatSessionStore.sessions[tabID]?.chatViewController != nil
    }

    private func reportSidebarOpenExtractionOutcome() {
        guard isSidebarVisibleForTab,
              isExtractionMeasurementEnabled,
              !didReportExtractionForCurrentNavigation,
              !didReportSidebarOpenOutcomeForCurrentNavigation else {
            return
        }
        didReportSidebarOpenOutcomeForCurrentNavigation = true

        guard case .url(let url, _, _) = content else {
            fireExtractionPixel(.prevented(PageContextExtractionOutcome.internalPageCategory), trigger: .navigation, latency: nil)
            return
        }
        if let reason = preventedAttachReason(for: url) {
            deliverPreventedContext(for: url, reason: reason, trigger: .navigation)
            return
        }
        if isContextCollectionEnabled, !extractionResolver.hasPendingCollections {
            collectPageContextIfNeeded(trigger: .auto)
        }
    }

    private func preventedAttachReason(for url: URL) -> String? {
        guard let policy = currentAttachabilityPolicy() else { return nil }
        let verdict = policy.verdict(url: url, mimeType: mainFrameMIMECache[url])
        return verdict.isAttachable ? nil : (verdict.preventionReason ?? PageContextExtractionOutcome.internalPageCategory)
    }

    private func deliverPreventedContext(for url: URL, reason: String, trigger: PageContextExtractionTrigger) {
        let context = AIChatPageContextData(
            title: content.title ?? "",
            favicon: [],
            url: url.absoluteString,
            content: "",
            truncated: false,
            fullContentLength: 0,
            attachable: false
        )
        Task { await handle(context) }
        fireExtractionPixel(.prevented(reason), trigger: trigger, latency: nil)
    }

    private func fireExtractionOutcome(for pageContext: AIChatPageContextData?) {
        // No pending request → duplicate or a collect we didn't initiate; skip the pixel.
        guard let resolution = extractionResolver.resolve(pageContext: pageContext) else {
            return
        }
        fire(resolution)
    }

    private func fire(_ resolution: PageContextExtractionResolver.Resolution) {
        fireExtractionPixel(resolution.outcome, trigger: resolution.trigger, latency: resolution.latency)
    }

    private func fireExtractionPixel(_ outcome: PageContextExtractionOutcome,
                                     trigger: PageContextExtractionTrigger,
                                     latency: PageContextExtractionLatencyBucket?) {
        guard isExtractionMeasurementEnabled else { return }
        guard isSidebarVisibleForTab else { return }
        if case .failure(.emptyContent) = outcome, trigger != .userRequest { return }
        // A navigation triggers several automatic collects (navigation re-collect + signals-only);
        // report only the first. User/setting collects (.userRequest / .auto) always report.
        if trigger == .navigation || trigger == .tabContent {
            guard !didReportExtractionForCurrentNavigation else { return }
            didReportExtractionForCurrentNavigation = true
        }
        Logger.aiChat.debug("📊 PageContext extraction outcome: \(String(describing: outcome), privacy: .public) trigger=\(trigger.rawValue, privacy: .public) latency=\(latency?.rawValue ?? "nil", privacy: .public)")
        extractionPixelHandler.fire(outcome, trigger: trigger, latency: latency)
    }

    /// Fires `.timeout` for any collect that hasn't produced a result within the timeout window and
    /// clears its pending entry, so a never-resolving collect neither loses its pixel nor lets a
    /// stale entry mis-attribute a later navigation.
    private func scheduleCollectionTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collectionTimeout) { [weak self] in
            guard let self else { return }
            self.extractionResolver.expireCollections(olderThan: Self.collectionTimeout).forEach { self.fire($0) }
        }
    }

    private func collectPageContextIfNeeded(trigger: PageContextExtractionTrigger) {
        guard case .url(let url, _, _) = content, isContextCollectionEnabled else {
            return
        }
        if let reason = preventedAttachReason(for: url) {
            Logger.aiChat.debug("🚫 PageContext gate: prevented attach (reason=\(reason, privacy: .public)) host=\(url.host ?? "nil", privacy: .public)")
            deliverPreventedContext(for: url, reason: reason, trigger: trigger)
            return
        }
        // Skip automatic collects while the webview still shows the previous document (debounced
        // `Tab.$content` races the swap on back/forward); the settled-navigation re-collect covers it.
        if trigger == .navigation || trigger == .tabContent,
           let webViewURL = webView?.url, webViewURL != url {
            Logger.aiChat.debug("⏭️ PageContext gate: document mismatch (webView=\(webViewURL.host ?? "nil", privacy: .public) content=\(url.host ?? "nil", privacy: .public)), skipping collect")
            return
        }
        guard let pageContextUserScript, webView != nil else {
            Logger.aiChat.debug("⚠️ PageContext gate: no webview/user script, cannot collect host=\(url.host ?? "nil", privacy: .public)")
            fireExtractionPixel(.failure(.noWebView), trigger: trigger, latency: nil)
            return
        }
        extractionResolver.requested(trigger: trigger)
        Logger.aiChat.debug("✅ PageContext gate: attachable, collecting host=\(url.host ?? "nil", privacy: .public) trigger=\(trigger.rawValue, privacy: .public)")
        pageContextUserScript.collect()
        scheduleCollectionTimeout()
    }

    // MARK: - Selection Context ("Attach to Duck.ai")

    /// Queues a selection item for the sidebar and flushes it. Independent of the page-context
    /// slot — never touches `cachedPageContext` or triggers `collect()`. If the sidebar chat VC
    /// isn't up yet, the item stays buffered and the `sessionsPublisher` sink flushes it once the
    /// sidebar is shown.
    @MainActor
    func appendSelectionContext(_ selection: AIChatSelectionContextData) {
        pendingSelectionContexts.append(selectionWithEncodedFavicon(selection))
        // Defer so a just-revealed sidebar's chat VC exists before we push (matches page-context timing).
        Task { @MainActor [weak self] in self?.flushPendingSelectionContexts() }
    }

    /// Stamps the source page's base64-encoded favicon onto the selection (raw favicon URLs get
    /// CSP-blocked in the sidebar). Mirrors `replaceFaviconURLWithEncodedData`; returns the item
    /// unchanged when no favicon is cached.
    @MainActor
    private func selectionWithEncodedFavicon(_ selection: AIChatSelectionContextData) -> AIChatSelectionContextData {
        guard let pageURL = URL(string: selection.url),
              let favicon = faviconManagement.getCachedFavicon(for: pageURL, sizeCategory: .small)?.image,
              let base64Favicon = favicon.base64PNGDataURL else {
            return selection
        }

        let faviconEntry = AIChatPageContextData.PageContextFavicon(href: base64Favicon, rel: "icon")
        return AIChatSelectionContextData(
            id: selection.id,
            title: selection.title,
            favicon: [faviconEntry],
            url: selection.url,
            content: selection.content,
            truncated: selection.truncated,
            fullContentLength: selection.fullContentLength,
            wordCount: selection.wordCount
        )
    }

    /// Pushes buffered selection items to the sidebar chat VC (if it exists) and clears the buffer.
    @MainActor
    private func flushPendingSelectionContexts() {
        guard !pendingSelectionContexts.isEmpty,
              let chatViewController = aiChatSessionStore.sessions[tabID]?.chatViewController else {
            return
        }
        let items = pendingSelectionContexts
        pendingSelectionContexts = []
        items.forEach { chatViewController.submitSelectionContext($0) }
    }

    // MARK: - Multiple Page Contexts

    /// Determines the appropriate action when the browser tab navigates to a new URL
    /// while the sidebar has an active chat session.
    private enum NavigationContextAction {
        /// Auto-collect is enabled — collect and push the new page's context.
        case collectNewContext
        /// A prompt was already submitted — send nil so the frontend shows "Add page content".
        case sendNavigationSignal
        /// Context hasn't been consumed yet — keep the existing attached context.
        case keepExistingContext
    }

    private func navigationAction(autoCollectEnabled: Bool, contextConsumed: Bool, fromAttachablePage: Bool = true) -> NavigationContextAction {
        if autoCollectEnabled {
            return .collectNewContext
        } else if contextConsumed || !fromAttachablePage {
            return .sendNavigationSignal
        } else {
            return .keepExistingContext
        }
    }

    /// Handles navigation events for the multiple page contexts feature.
    /// When enabled, pushes new page context or signals the frontend depending on settings.
    private func handleNavigationForMultipleContexts(from previousContent: Tab.TabContent?, to newContent: Tab.TabContent) {
        guard featureFlagger.isFeatureOn(.aiChatMultiplePageContexts),
              case .url(let newURL, _, _) = newContent,
              let session = aiChatSessionStore.sessions[tabID],
              session.state.presentationMode != .hidden,
              session.chatViewController != nil else {
            return
        }

        // When the previous page was also a URL, skip if the URL hasn't changed.
        // When coming from a non-URL page (NTP, settings, etc.) always proceed —
        // the attachability just changed from false to true, so the sidebar needs a signal.
        let previousWasURL: Bool
        if case .url(let oldURL, _, _) = previousContent {
            guard oldURL != newURL else { return }
            previousWasURL = true
        } else {
            previousWasURL = false
        }

        switch navigationAction(autoCollectEnabled: isContextCollectionEnabled,
                                contextConsumed: hasContextBeenConsumedByChat,
                                fromAttachablePage: previousWasURL) {
        case .collectNewContext:
            collectPageContextIfNeeded(trigger: .navigation)
        case .sendNavigationSignal:
            session.chatViewController?.setPageContext(nil)
        case .keepExistingContext:
            break
        }
    }

    /// Sends a non-attachable page context to the sidebar when on a non-content page (NTP, settings, bookmarks, etc.).
    /// This tells the FE to hide the page context chip since there's nothing useful to attach.
    private func sendNonAttachableContextIfNeeded() {
        if case .url = content { return }
        guard aiChatSessionStore.sessions[tabID] != nil else { return }

        cachedPageContext = nil
        let nonAttachableContext = AIChatPageContextData(
            title: content.title ?? "",
            favicon: [],
            url: content.urlForWebView?.absoluteString ?? "",
            content: "",
            truncated: false,
            fullContentLength: 0,
            attachable: false
        )
        Task {
            await handle(nonAttachableContext)
        }
    }

    /// Context collection is allowed when it's set to automatic in AI Features Settings
    /// or when we allow one-time collection requested by the user.
    /// Suppressed when the user explicitly removed context on the current page.
    private var isContextCollectionEnabled: Bool {
        if shouldForceContextCollection { return true }
        if userRemovedContext { return false }
        return aiChatMenuConfiguration.shouldAutomaticallySendPageContext
    }

    @MainActor private func replaceFaviconURLWithEncodedData(_ pageContext: AIChatPageContextData?) -> AIChatPageContextData? {
        guard let pageContext = pageContext,
              let pageURL = URL(string: pageContext.url),
              let favicon = faviconManagement.getCachedFavicon(for: pageURL, sizeCategory: .small)?.image,
              let base64Favicon = favicon.base64PNGDataURL else {
            return pageContext
        }

        let faviconEntry = AIChatPageContextData.PageContextFavicon(href: base64Favicon, rel: "icon")
        return AIChatPageContextData(
            title: pageContext.title,
            favicon: [faviconEntry],
            url: pageContext.url,
            content: pageContext.content,
            truncated: pageContext.truncated,
            fullContentLength: pageContext.fullContentLength,
            attachable: pageContext.attachable,
            tabId: pageContext.tabId,
            pageTypeSignals: pageContext.pageTypeSignals,
            attached: pageContext.attached
        )
    }

    // MARK: - Page Type Signals (duck.ai page shortcuts)

    /// When auto-attach is OFF, trigger a page-context collection solely to harvest
    /// Content-Scope-Scripts page-type signals; the result is delivered as a signals-only payload
    /// (content stripped) via `handleSignalsOnly`. No-op when auto-attach is ON (the full-content
    /// path already carries the signals) or when off a real web page.
    private func requestSignalsOnlyCollectionIfNeeded() {
        guard featureFlagger.isFeatureOn(.aiChatPageContext),
              featureFlagger.isFeatureOn(.sidebarSuggestedPrompts),
              case .url(let url, _, _) = content,
              !isContextCollectionEnabled,
              aiChatSessionStore.sessions[tabID]?.chatViewController != nil,
              let pageContextUserScript else {
            return
        }
        if let reason = preventedAttachReason(for: url) {
            Logger.aiChat.debug("🚫 PageContext gate (signals-only): prevented (reason=\(reason, privacy: .public)) host=\(url.host ?? "nil", privacy: .public)")
            deliverPreventedContext(for: url, reason: reason, trigger: .tabContent)
            return
        }
        pendingSignalsOnlyCollection = true
        pageContextUserScript.collect()
    }

    /// Delivers a signals-only payload from a collected context: keeps the Content-Scope-Scripts
    /// page-type signals + metadata, strips the page content, and marks `attached:false` /
    /// `attachable:true` so the duck.ai web app shows page shortcuts plus the Ask-About-Page chip
    /// without attaching content.
    @MainActor
    private func handleSignalsOnly(_ pageContext: AIChatPageContextData?) async {
        guard featureFlagger.isFeatureOn(.aiChatPageContext),
              let pageContext,
              let session = aiChatSessionStore.sessions[tabID],
              session.chatViewController != nil else {
            return
        }
        let signalsOnly = AIChatPageContextData(
            title: pageContext.title,
            favicon: [],
            url: pageContext.url,
            content: "",
            truncated: false,
            fullContentLength: 0,
            attachable: true,
            pageTypeSignals: pageContext.pageTypeSignals,
            attached: false
        )
        session.chatViewController?.setPageContext(signalsOnly)
    }
}

/// Main-frame MIME types keyed by URL (bounded FIFO). Back/forward cache restores don't re-fire
/// `decidePolicy(for navigationResponse:)`, so a single "last response" slot loses the MIME on the way back.
struct MainFrameMIMECache {
    private var mimeTypes: [URL: String] = [:]
    private var order: [URL] = []
    private let capacity: Int

    init(capacity: Int = 100) {
        self.capacity = capacity
    }

    subscript(url: URL) -> String? {
        mimeTypes[url]
    }

    /// Empty/nil MIMEs are ignored — the attachability gate falls back to the URL extension for those.
    mutating func record(_ mimeType: String?, for url: URL) {
        guard let mimeType, !mimeType.isEmpty else { return }
        if mimeTypes[url] == nil {
            order.append(url)
            if order.count > capacity {
                mimeTypes[order.removeFirst()] = nil
            }
        }
        mimeTypes[url] = mimeType
    }
}

protocol PageContextProtocol: AnyObject, NavigationResponder {
    /// Appends a user text selection to the sidebar's selection-context list. See the
    /// implementation in `PageContextTabExtension` for buffering/lifecycle semantics.
    @MainActor func appendSelectionContext(_ selection: AIChatSelectionContextData)
}

extension PageContextTabExtension: PageContextProtocol, TabExtension {
    func getPublicProtocol() -> PageContextProtocol { self }
}

extension PageContextTabExtension: NavigationResponder {
    /// Re-collect page context once the new page has finished loading. The `Tab.$content` trigger
    /// fires at `didCommit` — before the page's markup (JSON-LD / og:type) is parsed — so page-type
    /// signals would otherwise reflect the previous page and the sidebar's suggestions wouldn't
    /// update on same-tab navigation. Mirrors Windows' `NavigationCompleted` re-collect.
    func navigationDidFinish(_ navigation: Navigation) {
        guard !isLoadedInSidebar else { return }
        reCollectForSettledNavigation(navigation)
    }

    /// Back/forward cache restores can end in `didFail` (NSURLError -999) after committing — the page
    /// is displayed but `navigationDidFinish` never fires, so committed failures must re-collect too.
    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard !isLoadedInSidebar, navigation.isCommitted else { return }
        reCollectForSettledNavigation(navigation)
    }

    /// Collects only once the debounced `Tab.$content` matches this navigation — on fast loads it may
    /// still reference the previous page, and collecting then would extract the wrong document.
    @MainActor
    private func reCollectForSettledNavigation(_ navigation: Navigation) {
        guard case .url(let url, _, _) = content, url == navigation.url else {
            pendingSettledNavigationURL = navigation.url
            return
        }
        pendingSettledNavigationURL = nil
        collectPageContextIfNeeded(trigger: .navigation)
        requestSignalsOnlyCollectionIfNeeded()
    }

    private func runPendingSettledNavigationReCollectIfNeeded() {
        guard let pendingURL = pendingSettledNavigationURL else { return }
        guard case .url(let url, _, _) = content, url == pendingURL else {
            pendingSettledNavigationURL = nil
            return
        }
        pendingSettledNavigationURL = nil
        guard !extractionResolver.hasPendingCollections else { return }
        collectPageContextIfNeeded(trigger: .navigation)
        requestSignalsOnlyCollectionIfNeeded()
    }

    @MainActor
    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        guard !isLoadedInSidebar, navigationResponse.isForMainFrame else { return .next }
        mainFrameMIMECache.record(navigationResponse.response.mimeType, for: navigationResponse.url)
        Logger.aiChat.debug("📄 PageContext MIME captured: \(navigationResponse.response.mimeType ?? "nil", privacy: .public) host=\(navigationResponse.url.host ?? "nil", privacy: .public)")
        return .next
    }
}

extension TabExtensions {
    var pageContext: PageContextProtocol? { resolve(PageContextTabExtension.self) }
}

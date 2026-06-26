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
        aiChatSessionStore: AIChatSessionStoring,
        aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
        isLoadedInSidebar: Bool,
        faviconManagement: FaviconManagement
    ) {
        self.tabID = tabID
        self.featureFlagger = featureFlagger
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
                }
                self.handleNavigationForMultipleContexts(from: previousContent, to: tabContent)
                self.sendNonAttachableContextIfNeeded()
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

                /// This closure is responsible for passing cached page context to the newly displayed sidebar.
                /// It's only called when sidebar for tabID is non-nil.
                /// Additionally, we're only calling `handle` if there's a cached page context.
                if let cachedPageContext, isContextCollectionEnabled {
                    Task {
                        await self.handle(cachedPageContext)
                    }
                } else {
                    sendNonAttachableContextIfNeeded()
                }
            }
            .store(in: &cancellables)

        aiChatMenuConfiguration.valuesChangedPublisher
            .map { aiChatMenuConfiguration.shouldAutomaticallySendPageContext }
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else {
                    return
                }
                if isEnabled {
                    /// Proactively collect page context when page context setting was enabled
                    if let cachedPageContext {
                        Task { await self.handle(cachedPageContext) }
                    } else {
                        collectPageContextIfNeeded()
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
                /// Only process the collection result when auto-collect is enabled or the user
                /// explicitly requested context. Unsolicited results from the page script
                /// should not overwrite previously attached context with nil.
                guard self.isContextCollectionEnabled else {
                    return
                }
                Task {
                    await self.handle(pageContext)
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

        session.pageContextRequestedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.shouldForceContextCollection = true
                self?.collectPageContextIfNeeded()
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

    /// This is the main place where page context handling happens.
    /// We always cache the latest context, and if sidebar is open,
    /// we're passing the context to it.
    @MainActor
    private func handle(_ pageContext: AIChatPageContextData?) async {
        guard featureFlagger.isFeatureOn(.aiChatPageContext) else {
            return
        }
        shouldForceContextCollection = false
        cachedPageContext = replaceFaviconURLWithEncodedData(pageContext)
        if let chatViewController = aiChatSessionStore.sessions[tabID]?.chatViewController {
            chatViewController.setPageContext(cachedPageContext)
            if pageContext != nil, pageContext?.attachable != false {
                // New attachable context pushed — reset the consumed flag so navigation
                // won't clear it until the next prompt is submitted.
                hasContextBeenConsumedByChat = false
            }
        }
    }

    private func collectPageContextIfNeeded() {
        guard case .url = content, isContextCollectionEnabled else {
            return
        }
        pageContextUserScript?.collect()
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
            collectPageContextIfNeeded()
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
            attachable: pageContext.attachable
        )
    }
}

protocol PageContextProtocol: AnyObject {
    /// Appends a user text selection to the sidebar's selection-context list. See the
    /// implementation in `PageContextTabExtension` for buffering/lifecycle semantics.
    @MainActor func appendSelectionContext(_ selection: AIChatSelectionContextData)
}

extension PageContextTabExtension: PageContextProtocol, TabExtension {
    func getPublicProtocol() -> PageContextProtocol { self }
}

extension TabExtensions {
    var pageContext: PageContextProtocol? { resolve(PageContextTabExtension.self) }
}

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

    /// One-shot priority page context built from a user text selection ("Attach to Duck.ai").
    /// When set, it takes precedence over auto-collected full-page context for the sidebar and
    /// survives until the chat consumes/removes it or the tab navigates away. Mirrors the
    /// Windows selection-context cache + get-and-clear behaviour.
    private var selectionContextOverride: AIChatPageContextData?

    private enum Constants {
        /// Matches `maxContentLength` default in content-scope-scripts (page-context.js).
        static let maxSelectionContextLength = 9500
    }

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
                    // A text selection is tied to the page it was made on — drop it on navigation.
                    self.selectionContextOverride = nil
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

                /// This closure is responsible for passing cached page context to the newly displayed sidebar.
                /// It's only called when sidebar for tabID is non-nil.
                /// Additionally, we're only calling `handle` if there's a cached page context.
                if let selectionContextOverride {
                    pushSelectionContextOverride(selectionContextOverride)
                } else if let cachedPageContext, isContextCollectionEnabled {
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
                // A selection override owns the sidebar context until consumed — don't let an
                // auto-collect toggle replace it with the full page.
                guard self.selectionContextOverride == nil else { return }
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
                /// A selection override owns the sidebar context until consumed — never let a
                /// late/auto full-page collection overwrite it.
                guard self.selectionContextOverride == nil else {
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
                // Selection context is one-shot: once the chat consumed it, normal auto-collect resumes.
                self?.selectionContextOverride = nil
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
                self.selectionContextOverride = nil
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
        // While a selection override is active it owns the sidebar context — don't collect.
        guard selectionContextOverride == nil else { return }
        guard case .url = content, isContextCollectionEnabled else {
            return
        }
        pageContextUserScript?.collect()
    }

    // MARK: - Selection Context ("Attach to Duck.ai")

    /// Builds a selection-based page context (truncated, `contentType: "selection"`, generic
    /// "Text selection" title) and makes it the sidebar's active context, taking precedence
    /// over auto-collected full-page content until the chat consumes/removes it or the tab
    /// navigates. Caller is responsible for revealing the sidebar afterwards.
    @MainActor
    func attachSelectionContext(text: String, url: URL?, title: String?) {
        let truncated = text.count > Constants.maxSelectionContextLength
        let content = truncated ? String(text.prefix(Constants.maxSelectionContextLength)) : text
        let context = AIChatPageContextData(
            title: UserText.aiChatTextSelection,
            favicon: [],
            url: url?.absoluteString ?? "",
            content: content,
            truncated: truncated,
            fullContentLength: text.count,
            attachable: true,
            contentType: "selection"
        )
        selectionContextOverride = context
        // A fresh selection supersedes any prior removal/consumption state for this tab.
        userRemovedContext = false
        hasContextBeenConsumedByChat = false

        // If the sidebar is already showing, push immediately; otherwise the `sessionsPublisher`
        // sink delivers it once the session/VC is created (see `pushSelectionContextOverride`).
        if aiChatSessionStore.sessions[tabID]?.chatViewController != nil {
            pushSelectionContextOverride(context)
        }
    }

    /// Pushes the selection override to the (possibly just-created) sidebar chat VC. Deferred to
    /// the next runloop tick so the VC exists after `showSidebar` finishes — the same timing the
    /// auto-collect `handle(...)` path relies on.
    private func pushSelectionContextOverride(_ context: AIChatPageContextData) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.aiChatSessionStore.sessions[self.tabID]?.chatViewController?.setPageContext(context)
        }
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

    private func navigationAction(autoCollectEnabled: Bool, contextConsumed: Bool) -> NavigationContextAction {
        if autoCollectEnabled {
            return .collectNewContext
        } else if contextConsumed {
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
              case .url(let oldURL, _, _) = previousContent,
              newURL != oldURL,
              let session = aiChatSessionStore.sessions[tabID],
              session.state.presentationMode != .hidden,
              session.chatViewController != nil else {
            return
        }

        switch navigationAction(autoCollectEnabled: isContextCollectionEnabled, contextConsumed: hasContextBeenConsumedByChat) {
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
            attachable: pageContext.attachable,
            contentType: pageContext.contentType
        )
    }
}

protocol PageContextProtocol: AnyObject {
    /// Attaches the given selected text as the sidebar's page context. See the implementation
    /// in `PageContextTabExtension` for precedence/lifecycle semantics.
    @MainActor func attachSelectionContext(text: String, url: URL?, title: String?)
}

extension PageContextTabExtension: PageContextProtocol, TabExtension {
    func getPublicProtocol() -> PageContextProtocol { self }
}

extension TabExtensions {
    var pageContext: PageContextProtocol? { resolve(PageContextTabExtension.self) }
}

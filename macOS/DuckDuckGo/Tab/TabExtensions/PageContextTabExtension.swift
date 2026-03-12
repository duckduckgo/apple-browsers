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
    private let aiChatSessionStore: AIChatSessionStoring
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private let isLoadedInSidebar: Bool
    private let faviconManagement: FaviconManagement
    private var cachedPageContext: AIChatPageContextData?

    /// Tracks whether the frontend has consumed page context into an active chat.
    /// When true, navigating with auto-collect OFF will send a nil signal so the
    /// frontend can show "Add page content" for the new page.
    private var hasContextBeenConsumedByChat: Bool = false

    /// This flag is set when context collection was requested by the user from the sidebar.
    ///
    /// It allows to override the AI Features setting for automatic context collection.
    /// The flag is automatically cleared after receiving a `collectionResult` message.
    private var shouldForceContextCollection: Bool = false


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
                let previousContent = self?.content
                Logger.aiChat.debug("[PageContextExt] contentPublisher: \(String(describing: previousContent)) -> \(String(describing: tabContent))")
                self?.content = tabContent
                self?.handleNavigationForMultipleContexts(from: previousContent, to: tabContent)
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
                Logger.aiChat.debug("[PageContextExt] sessionAppeared: hasCachedContext=\(self.cachedPageContext != nil), isCollectionEnabled=\(self.isContextCollectionEnabled)")
                guard let cachedPageContext, isContextCollectionEnabled else {
                    return
                }
                Task {
                    await self.handle(cachedPageContext)
                }
            }
            .store(in: &cancellables)

        aiChatMenuConfiguration.valuesChangedPublisher
            .map { aiChatMenuConfiguration.shouldAutomaticallySendPageContext }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                /// Proactively collect page context when page context setting was enabled
                collectPageContextIfNeeded()
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
                let isEnabled = self.isContextCollectionEnabled
                Logger.aiChat.debug("[PageContextExt] collectionResult: title=\(pageContext?.title ?? "nil"), isEnabled=\(isEnabled)")
                guard isEnabled else {
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
                Logger.aiChat.debug("[PageContextExt] pageContextRequested (user action)")
                self?.shouldForceContextCollection = true
                self?.collectPageContextIfNeeded()
            }
            .store(in: &sidebarCancellables)

        session.pageContextConsumedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Logger.aiChat.debug("[PageContextExt] pageContextConsumed — chat has active context")
                self?.hasContextBeenConsumedByChat = true
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
        Logger.aiChat.debug("[PageContextExt] handle: pushing context title=\(pageContext?.title ?? "nil") to sidebar (hasChatVC=\(self.aiChatSessionStore.sessions[self.tabID]?.chatViewController != nil))")
        if let chatViewController = aiChatSessionStore.sessions[tabID]?.chatViewController {
            chatViewController.setPageContext(cachedPageContext)
            if pageContext != nil {
                // New context attached — reset the consumed flag so navigation
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

    /// When the browser tab navigates to a new URL while the sidebar has an active chat,
    /// push the new page's context to the frontend so the user can reference multiple pages.
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

        Logger.aiChat.debug("[PageContextExt] multiContextNav: \(oldURL.absoluteString) -> \(newURL.absoluteString), autoCollect=\(self.isContextCollectionEnabled), consumed=\(self.hasContextBeenConsumedByChat)")
        if isContextCollectionEnabled {
            collectPageContextIfNeeded()
        } else if hasContextBeenConsumedByChat {
            // Auto-collect OFF, but context was already consumed into an active chat.
            // Send nil to signal the frontend that a new page is available.
            Logger.aiChat.debug("[PageContextExt] multiContextNav: sending nil navigation signal (context was consumed by chat)")
            session.chatViewController?.setPageContext(nil)
        } else {
            Logger.aiChat.debug("[PageContextExt] multiContextNav: auto-collect OFF, context not yet consumed, keeping")
        }
    }

    /// Context collection is allowed when it's set to automatic in AI Features Settings
    /// or when we allow one-time collection requested by the user.
    private var isContextCollectionEnabled: Bool {
        aiChatMenuConfiguration.shouldAutomaticallySendPageContext || shouldForceContextCollection
    }

    @MainActor private func replaceFaviconURLWithEncodedData(_ pageContext: AIChatPageContextData?) -> AIChatPageContextData? {
        guard let pageContext = pageContext,
              let pageURL = URL(string: pageContext.url),
              let favicon = getCurrentFavicon(for: pageURL),
              let base64Favicon = makeBase64EncodedFavicon(from: favicon) else {
            return pageContext
        }

        // Replace the favicon array with a single data URL entry
        let faviconData = AIChatPageContextData.PageContextFavicon(href: base64Favicon, rel: "icon")
        return AIChatPageContextData(
            title: pageContext.title,
            favicon: [faviconData],
            url: pageContext.url,
            content: pageContext.content,
            truncated: pageContext.truncated,
            fullContentLength: pageContext.fullContentLength
        )
    }

    @MainActor private func getCurrentFavicon(for url: URL) -> NSImage? {
        faviconManagement.getCachedFavicon(for: url, sizeCategory: .small)?.image
    }

    private func makeBase64EncodedFavicon(from image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }

        let base64String = pngData.base64EncodedString()
        return "data:image/png;base64,\(base64String)"
    }
}

protocol PageContextProtocol: AnyObject {
}

extension PageContextTabExtension: PageContextProtocol, TabExtension {
    func getPublicProtocol() -> PageContextProtocol { self }
}

extension TabExtensions {
    var pageContext: PageContextProtocol? { resolve(PageContextTabExtension.self) }
}

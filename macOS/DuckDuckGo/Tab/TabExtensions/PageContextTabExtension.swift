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
import BrowserServicesKit
import Combine
import Foundation
import Navigation
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
    private let aiChatSidebarProvider: AIChatSidebarProviding
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private let isLoadedInSidebar: Bool
    private var cachedPageContext: AIChatPageContextData?

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
    private weak var sidebar: AIChatSidebar? {
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
        aiChatSidebarProvider: AIChatSidebarProviding,
        aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
        isLoadedInSidebar: Bool
    ) {
        self.tabID = tabID
        self.featureFlagger = featureFlagger
        self.aiChatSidebarProvider = aiChatSidebarProvider
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.isLoadedInSidebar = isLoadedInSidebar

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
                self?.content = tabContent
            }
            .store(in: &cancellables)

        aiChatSidebarProvider.sidebarsByTabPublisher
            .receive(on: DispatchQueue.main)
            .map { $0[tabID] != nil }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self, weak aiChatSidebarProvider] _ in
                guard let self else {
                    return
                }
                sidebar = aiChatSidebarProvider?.sidebarsByTab[tabID]

                /// This closure is responsible for passing cached page context to the newly displayed sidebar.
                /// It's only called when sidebar for tabID is non-nil.
                /// Additionally, we're only calling `handle` if there's a cached page context.
                guard let cachedPageContext, aiChatMenuConfiguration.shouldAutomaticallySendPageContext || shouldForceContextCollection else {
                    return
                }
                handle(cachedPageContext)
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
                /// This closure is responsible for handling page context received from the user script.
                handle(isContextCollectionEnabled ? pageContext : nil)
            }
            .store(in: &userScriptCancellables)
    }

    private func subscribeToCollectionRequest() {
        sidebarCancellables.removeAll()
        guard let sidebar else {
            return
        }

        sidebar.sidebarViewController.pageContextRequestedPublisher?
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.shouldForceContextCollection = true
                self?.collectPageContextIfNeeded()
            }
            .store(in: &sidebarCancellables)
    }

    /// This is the main place where page context handling happens.
    /// We always cache the latest context, and if sidebar is open,
    /// we're passing the context to it.
    private func handle(_ pageContext: AIChatPageContextData?) {
        guard featureFlagger.isFeatureOn(.aiChatPageContext) else {
            return
        }
        shouldForceContextCollection = false
        cachedPageContext = pageContext
        if let sidebar = aiChatSidebarProvider.getSidebar(for: tabID) {
            sidebar.sidebarViewController.setPageContext(pageContext)
        }
    }

    private func collectPageContextIfNeeded() {
        guard case .url = content, isContextCollectionEnabled else {
            return
        }
        pageContextUserScript?.collect()
    }

    /// Context collection is allowed when it's set to automatic in AI Features Settings
    /// or when we allow one-time collection requested by the user.
    private var isContextCollectionEnabled: Bool {
        aiChatMenuConfiguration.shouldAutomaticallySendPageContext || shouldForceContextCollection
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

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
    private let tabID: TabIdentifier
    private var content: Tab.TabContent = .none
    private let aiChatSidebarProvider: AIChatSidebarProviding
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private let isLoadedInSidebar: Bool
    private var cachedPageContext: AIChatPageContextData?

    private weak var webView: WKWebView?
    private weak var pageContextUserScript: PageContextUserScript? {
        didSet {
            subscribeToCollectionResult()
        }
    }

    init(
        scriptsPublisher: some Publisher<some PageContextUserScriptProvider, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>,
        contentPublisher: some Publisher<Tab.TabContent, Never>,
        tabID: TabIdentifier,
        aiChatSidebarProvider: AIChatSidebarProviding,
        aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
        isLoadedInSidebar: Bool
    ) {
        self.tabID = tabID
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
            .sink { [weak self] _ in
                /// This closure is responsible for passing cached page context to the newly displayed sidebar.
                /// It's only called when sidebar for tabID is non-nil.
                /// Additionally, we're only calling `handle` if there's a cached page context.
                guard let self, let cachedPageContext else {
                    return
                }
                handle(cachedPageContext)
            }
            .store(in: &cancellables)

        aiChatMenuConfiguration.valuesChangedPublisher
            .map { aiChatMenuConfiguration.isPageContextEnabled }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                /// Proactively collect page context when page context setting was enabled
                self?.collectPageContextIfNeeded()
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
                /// This closure is responsible for handling page context received from the user script.
                self?.handle(pageContext)
            }
            .store(in: &userScriptCancellables)
    }

    /// This is the main place where page context handling happens.
    /// We always cache the latest context, and if sidebar is open,
    /// we're passing the context to it.
    private func handle(_ pageContext: AIChatPageContextData) {
        guard aiChatMenuConfiguration.isPageContextEnabled else {
            return
        }
        cachedPageContext = pageContext
        if let sidebar = aiChatSidebarProvider.getSidebar(for: tabID) {
            sidebar.sidebarViewController.setPageContext(pageContext)
        }
    }

    private func collectPageContextIfNeeded() {
        guard case .url = content, aiChatMenuConfiguration.isPageContextEnabled else {
            return
        }
        pageContextUserScript?.collect()
    }
}

extension PageContextTabExtension: NavigationResponder {
    func navigationDidFinish(_ navigation: Navigation) {
        guard !isLoadedInSidebar else {
            return
        }
        collectPageContextIfNeeded()
    }

    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {
        guard !isLoadedInSidebar, navigationType != .anchorNavigation, navigationType != .sessionStateReplace else {
            return
        }
        collectPageContextIfNeeded()
    }
}

protocol PageContextProtocol: AnyObject, NavigationResponder {
}

extension PageContextTabExtension: PageContextProtocol, TabExtension {
    func getPublicProtocol() -> PageContextProtocol { self }
}

extension TabExtensions {
    var pageContext: PageContextProtocol? { resolve(PageContextTabExtension.self) }
}

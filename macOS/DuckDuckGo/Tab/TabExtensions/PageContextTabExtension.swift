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

final class PageContextTabExtension {

    private var cancellables = Set<AnyCancellable>()
    private var userScriptCancellables = Set<AnyCancellable>()
    private let tabID: TabIdentifier
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

        aiChatSidebarProvider.sidebarsByTabPublisher
            .receive(on: DispatchQueue.main)
            .filter { $0[tabID] != nil }
            .sink { [weak self] _ in
                guard let self, let cachedPageContext else {
                    return
                }
                handle(cachedPageContext)
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
                guard let self, aiChatMenuConfiguration.isPageContextEnabled else {
                    return
                }
                handle(pageContext)
            }
            .store(in: &userScriptCancellables)
    }

    private func handle(_ pageContext: AIChatPageContextData) {
        cachedPageContext = pageContext
        if let sidebar = aiChatSidebarProvider.getSidebar(for: tabID) {
            sidebar.sidebarViewController.setPageContext(pageContext)
        }
    }
}

extension PageContextTabExtension: NavigationResponder {
    func navigationDidFinish(_ navigation: Navigation) {
        guard !isLoadedInSidebar, aiChatMenuConfiguration.isPageContextEnabled else {
            return
        }
        pageContextUserScript?.collect()
    }

    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {
        guard !isLoadedInSidebar, aiChatMenuConfiguration.isPageContextEnabled, navigationType != .anchorNavigation, navigationType != .sessionStateReplace else {
            return
        }
        pageContextUserScript?.collect()
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

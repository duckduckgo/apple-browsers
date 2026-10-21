//
//  ReaderModeTabExtension.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Combine
import DDGNavigation
import Foundation
import ReaderMode
import WebKit

enum ReaderModeState: Equatable {
    case unavailable
    case available(ReaderArticle)
    case active(ReaderArticle)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

@MainActor
final class ReaderModeTabExtension {

    enum Event: Equatable {
        /// The page changed or failed: any extracted article no longer describes it.
        case reset
        case extracted(ReaderArticle?)
        case toggle
        case exit
    }

    nonisolated static func reduce(_ state: ReaderModeState, _ event: Event) -> ReaderModeState {
        switch (state, event) {
        case (_, .reset):
            return .unavailable
        case (.unavailable, .extracted(let article)):
            return article.map(ReaderModeState.available) ?? .unavailable
        case (.available(let article), .toggle):
            return .active(article)
        case (.active(let article), .toggle), (.active(let article), .exit):
            return .available(article)
        case (_, .extracted), (_, .toggle), (_, .exit):
            return state
        }
    }

    @Published private(set) var state: ReaderModeState = .unavailable

    private let extract: @Sendable (String, URL) -> ReaderArticle?
    private weak var webView: WKWebView?
    private var extraction: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(webViewPublisher: some Publisher<WKWebView, Never>,
         contentPublisher: some Publisher<Tab.TabContent, Never>,
         extract: @escaping @Sendable (String, URL) -> ReaderArticle? = { ReaderModeExtractor().article(fromHTML: $0, url: $1) }) {
        self.extract = extract

        webViewPublisher
            .sink { [weak self] webView in
                self?.webView = webView
            }
            .store(in: &cancellables)

        // Covers content shown outside the web view (Settings, Bookmarks...), which never starts a navigation.
        // In-page anchor jumps only change the fragment and keep the article.
        contentPublisher
            .map { $0.urlForWebView?.absoluteString.prefix { $0 != "#" } }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.handle(.reset)
            }
            .store(in: &cancellables)
    }

    func handle(_ event: Event) {
        if event == .reset {
            extraction?.cancel()
            extraction = nil
        }
        state = Self.reduce(state, event)
    }

    private func extractArticle(from webView: WKWebView, url: URL) {
        extraction?.cancel()
        let extract = self.extract
        extraction = Task { [weak self, weak webView] in
            guard let webView,
                  await webView.mimeType == "text/html",
                  let html = try? await webView.callAsyncJavaScript("return document.documentElement.outerHTML",
                                                                    arguments: [:],
                                                                    in: nil,
                                                                    contentWorld: .defaultClient) as? String,
                  !Task.isCancelled else { return }

            let article = await Task.detached(priority: .userInitiated) { extract(html, url) }.value
            guard !Task.isCancelled, webView.url == url else { return }
            self?.handle(.extracted(article))
        }
    }
}

extension ReaderModeTabExtension: NavigationResponder {

    func didStart(_ navigation: Navigation) {
        handle(.reset)
    }

    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {
        if [.sessionStatePush, .sessionStatePop].contains(navigationType) {
            handle(.reset)
        }
    }

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        handle(.reset)
    }

    func navigationDidFinish(_ navigation: Navigation) {
        guard navigation.navigationAction.isForMainFrame,
              let webView, let url = webView.url,
              url.isHttp || url.isHttps else { return }
        extractArticle(from: webView, url: url)
    }
}

@MainActor
protocol ReaderModeProtocol: AnyObject, NavigationResponder {
    var state: ReaderModeState { get }
    var statePublisher: AnyPublisher<ReaderModeState, Never> { get }

    func toggle()
    func exit()
}

extension ReaderModeTabExtension: TabExtension, ReaderModeProtocol {
    typealias PublicProtocol = ReaderModeProtocol
    nonisolated func getPublicProtocol() -> PublicProtocol { self }

    var statePublisher: AnyPublisher<ReaderModeState, Never> {
        $state.removeDuplicates().eraseToAnyPublisher()
    }

    func toggle() {
        handle(.toggle)
    }

    func exit() {
        handle(.exit)
    }
}

extension TabExtensions {
    var readerMode: ReaderModeProtocol? {
        resolve(ReaderModeTabExtension.self, .nullable)
    }
}

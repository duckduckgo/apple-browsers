//
//  ReaderModeTabExtensionTests.swift
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
import ReaderMode
import Testing
import WebKit

@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct ReaderModeTabExtensionTests {

    private typealias Event = ReaderModeTabExtension.Event

    private let article = ReaderArticle(url: URL(string: "https://example.com/article")!,
                                        title: "Title",
                                        siteName: nil,
                                        contentHTML: "<p>Body</p>",
                                        textLength: 4)
    private let content = CurrentValueSubject<Tab.TabContent, Never>(.contentFromURL(URL(string: "https://example.com/article")!, source: .link))

    private func makeExtension() -> ReaderModeTabExtension {
        ReaderModeTabExtension(webViewPublisher: Empty<WKWebView, Never>(), contentPublisher: content, extract: { _, _ in nil })
    }

    private func reduce(_ state: ReaderModeState, _ events: Event...) -> ReaderModeState {
        events.reduce(state, ReaderModeTabExtension.reduce)
    }

    // MARK: - Transitions

    @available(macOS 13, *)
    @Test("An extracted article makes Reader available, a missing one keeps it unavailable", .timeLimit(.minutes(1)))
    func extractionResult() {
        #expect(reduce(.unavailable, .extracted(article)) == .available(article))
        #expect(reduce(.unavailable, .extracted(nil)) == .unavailable)
    }

    @available(macOS 13, *)
    @Test("Toggle switches between available and active", .timeLimit(.minutes(1)))
    func toggle() {
        #expect(reduce(.available(article), .toggle) == .active(article))
        #expect(reduce(.active(article), .toggle) == .available(article))
        #expect(reduce(.unavailable, .toggle) == .unavailable)
    }

    @available(macOS 13, *)
    @Test("Exit leaves Reader but keeps it available", .timeLimit(.minutes(1)))
    func exit() {
        #expect(reduce(.active(article), .exit) == .available(article))
        #expect(reduce(.available(article), .exit) == .available(article))
        #expect(reduce(.unavailable, .exit) == .unavailable)
    }

    @available(macOS 13, *)
    @Test("Reset makes Reader unavailable from any state", .timeLimit(.minutes(1)))
    func reset() {
        #expect(reduce(.active(article), .reset) == .unavailable)
        #expect(reduce(.available(article), .reset) == .unavailable)
    }

    @available(macOS 13, *)
    @Test("A late extraction result does not replace the article being read", .timeLimit(.minutes(1)))
    func lateExtractionKeepsActiveArticle() {
        let other = ReaderArticle(url: article.url, title: "Other", siteName: nil, contentHTML: "", textLength: 0)
        #expect(reduce(.active(article), .extracted(other)) == .active(article))
        #expect(reduce(.active(article), .extracted(nil)) == .active(article))
    }

    // MARK: - Navigation

    @available(macOS 13, *)
    @Test("Starting a navigation closes Reader", .timeLimit(.minutes(1)))
    func navigationStartCloses() {
        let tabExtension = makeExtension()
        tabExtension.handle(.extracted(article))
        tabExtension.toggle()
        #expect(tabExtension.state == .active(article))

        tabExtension.didStart(makeNavigation())

        #expect(tabExtension.state == .unavailable)
    }

    @available(macOS 13, *)
    @Test("History push and pop close Reader, anchor jumps do not", .timeLimit(.minutes(1)))
    func sameDocumentNavigation() {
        let tabExtension = makeExtension()
        tabExtension.handle(.extracted(article))
        tabExtension.toggle()

        tabExtension.navigation(makeNavigation(), didSameDocumentNavigationOf: .anchorNavigation)
        #expect(tabExtension.state == .active(article))

        tabExtension.navigation(makeNavigation(), didSameDocumentNavigationOf: .sessionStatePush)
        #expect(tabExtension.state == .unavailable)

        tabExtension.handle(.extracted(article))
        tabExtension.navigation(makeNavigation(), didSameDocumentNavigationOf: .sessionStatePop)
        #expect(tabExtension.state == .unavailable)
    }

    @available(macOS 13, *)
    @Test("Tab content moving to another page closes Reader, a fragment change does not", .timeLimit(.minutes(1)))
    func contentChange() {
        let tabExtension = makeExtension()
        tabExtension.handle(.extracted(article))
        tabExtension.toggle()

        content.send(.contentFromURL(URL(string: "https://example.com/article#section")!, source: .webViewUpdated))
        #expect(tabExtension.state == .active(article))

        content.send(.settings(pane: nil))
        #expect(tabExtension.state == .unavailable)
    }

    // MARK: - Extraction

    @available(macOS 13, *)
    @Test("A finished article page is read from the web view and becomes available", .timeLimit(.minutes(1)))
    func finishedArticlePageBecomesAvailable() async throws {
        let paragraphs = (1...8).map { "<p>Paragraph \($0) of a long article that keeps going with enough words to read like real prose.</p>" }
        let html = "<html><head><title>Long Read</title></head><body><article>\(paragraphs.joined())</article></body></html>"
        let webView = WKWebView()
        let loader = HTMLLoader()
        try await loader.load(html, baseURL: article.url, in: webView)

        let tabExtension = ReaderModeTabExtension(webViewPublisher: Just(webView), contentPublisher: content)
        tabExtension.navigationDidFinish(makeNavigation(targetFrame: .mainFrame(for: webView)))

        let state = await tabExtension.$state.first { $0 != .unavailable }.values.first { _ in true }
        guard case .available(let extracted) = state else {
            Issue.record("Expected an available article, got \(String(describing: state))")
            return
        }
        #expect(extracted.title == "Long Read")
        #expect(extracted.url == article.url)
        #expect(extracted.contentHTML.contains("Paragraph 8"))
    }
}

private extension ReaderModeTabExtensionTests {

    func makeNavigation(targetFrame: FrameInfo? = nil) -> Navigation {
        let action = NavigationAction(request: URLRequest(url: article.url),
                                      navigationType: .custom(.userEnteredUrl),
                                      currentHistoryItemIdentity: nil,
                                      redirectHistory: nil,
                                      isUserInitiated: true,
                                      sourceFrame: FrameInfo(frame: .mock()),
                                      targetFrame: targetFrame,
                                      shouldDownload: false,
                                      mainFrameNavigation: nil)

        return Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [action], isCurrent: true, isCommitted: false)
    }
}

@MainActor
private final class HTMLLoader: NSObject, WKNavigationDelegate {

    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, baseURL: URL, in webView: WKWebView) async throws {
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

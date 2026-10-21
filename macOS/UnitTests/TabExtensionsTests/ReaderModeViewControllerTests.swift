//
//  ReaderModeViewControllerTests.swift
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

import ReaderMode
import Testing
import WebKit

@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct ReaderModeViewControllerTests {

    private let article = ReaderArticle(url: URL(string: "https://example.com/article")!,
                                        title: "Reader Title",
                                        siteName: "Example",
                                        contentHTML: "<p>Body <a href=\"https://example.com/next\">next</a> <a href=\"#notes\">notes</a></p><h2 id=\"notes\">Notes</h2>",
                                        textLength: 10)

    @available(macOS 13, *)
    @Test("The reader document loads into the reader web view", .timeLimit(.minutes(1)))
    func documentLoads() async throws {
        let viewController = ReaderModeViewController(article: article) { _ in }
        let webView = try #require(viewController.view as? WKWebView)

        var title: String?
        for _ in 0..<100 {
            title = webView.title
            if title == article.title { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(title == article.title)
        #expect(webView.url == article.url)
    }

    @available(macOS 13, *)
    @Test("Clicking a link opens it in the tab instead of the reader", .timeLimit(.minutes(1)))
    func linkOpensInTab() async throws {
        var openedURLs = [URL]()
        let viewController = ReaderModeViewController(article: article) { openedURLs.append($0) }
        let webView = try #require(viewController.view as? WKWebView)
        let next = URL(string: "https://example.com/next")!

        let policy = await viewController.webView(webView, decidePolicyFor: NavigationActionMock(url: next, type: .linkActivated))

        #expect(policy == .cancel)
        #expect(openedURLs == [next])
    }

    @available(macOS 13, *)
    @Test("In-page links stay in the reader", .timeLimit(.minutes(1)))
    func fragmentLinkStaysInReader() async throws {
        var openedURLs = [URL]()
        let viewController = ReaderModeViewController(article: article) { openedURLs.append($0) }
        let webView = try #require(viewController.view as? WKWebView)

        let policy = await viewController.webView(webView, decidePolicyFor: NavigationActionMock(url: URL(string: "https://example.com/article#notes")!, type: .linkActivated))

        #expect(policy == .allow)
        #expect(openedURLs.isEmpty)
    }

    @available(macOS 13, *)
    @Test("Navigations the user did not start are blocked", .timeLimit(.minutes(1)))
    func otherNavigationsAreBlocked() async throws {
        var openedURLs = [URL]()
        let viewController = ReaderModeViewController(article: article) { openedURLs.append($0) }
        let webView = try #require(viewController.view as? WKWebView)

        let policy = await viewController.webView(webView, decidePolicyFor: NavigationActionMock(url: URL(string: "https://tracker.example/")!, type: .other))

        #expect(policy == .cancel)
        #expect(openedURLs.isEmpty)
    }
}

private final class NavigationActionMock: WKNavigationAction {
    private let mockRequest: URLRequest
    private let mockType: WKNavigationType

    init(url: URL, type: WKNavigationType) {
        mockRequest = URLRequest(url: url)
        mockType = type
        super.init()
    }

    override var request: URLRequest { mockRequest }
    override var navigationType: WKNavigationType { mockType }
}

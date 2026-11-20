//
//  LocalUITestWebsite.swift
//  DuckDuckGo
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

import Swifter
import UITestingSupport
import XCTest

final class LocalUITestWebsite {
    static let childLinkTitle = "Open child test page"
    static let refreshedHeading = "Refreshed browsing test page"

    struct Page {
        let path: String
        let title: String

        static let first = Page(path: "/first-test-page", title: "First test page")
        static let second = Page(path: "/second-test-page", title: "Second test page")
        static let child = Page(path: "/child-test-page", title: "Child test page")
        static let browsing = Page(path: "/browsing-test", title: "Browsing test page")

        static func bookmark(_ index: Int) -> Page {
            Page(path: "/bookmark-\(index)", title: "Bookmark test page \(index)")
        }
    }

    private let server: HttpServer
    private let state: PageState
    let hostAndPort: String

    init() throws {
        let server = HttpServer()
        let state = PageState()
        let pages: [Page] = [.first, .second, .child] + (0..<4).map(Page.bookmark)
        for page in pages {
            // The child-tab test opens the link through the browser's context menu.
            let childLink = page.path == Page.first.path
                ? "<a href=\"\(Page.child.path)\" onclick=\"event.preventDefault()\">\(Self.childLinkTitle)</a>"
                : ""
            let html = "<title>\(page.title)</title><h1>\(page.title)</h1>\(childLink)"
            server[page.path] = { _ in
                state.receivedRequest(for: page.path)
                return .ok(.htmlBody(html))
            }
        }
        server[Page.browsing.path] = { _ in
            state.receivedRequest(for: Page.browsing.path)
            let heading = state.browsingHeading
            let body = Array("<!doctype html><title>Browsing test</title><h1>\(heading)</h1>".utf8)
            return .raw(200, "OK", [
                "Cache-Control": "no-store",
                "Content-Type": "text/html; charset=utf-8",
                "Content-Length": String(body.count),
            ]) { try $0.write(body) }
        }
        server.listenAddressIPv4 = "127.0.0.1"
        try server.start(0, forceIPv4: true, priority: .userInitiated)
        do {
            hostAndPort = "127.0.0.1:\(try server.port())"
        } catch {
            server.stop()
            throw error
        }
        self.server = server
        self.state = state
    }

    deinit {
        server.stop()
    }

    func open(_ page: Page, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        navigate(to: page, in: app, file: file, line: line)
        app.assertPageContains(page.title, file: file, line: line)
    }

    func navigate(to page: Page, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            request(page, in: app, timeout: UITestTimeouts.navigation, file: file, line: line),
            "Browser did not request the local page \(page.path).",
            file: file,
            line: line)
    }

    func request(_ page: Page, in app: XCUIApplication, timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let request = state.expectRequest(for: page.path)
        app.enterSearchText("http://\(hostAndPort)\(page.path)\r", file: file, line: line)
        return XCTWaiter.wait(for: [request], timeout: timeout) == .completed
    }

    func updateBrowsingPage() {
        state.updateBrowsingPage()
    }

    private final class PageState {
        private let lock = NSLock()
        private var pending: [String: XCTestExpectation] = [:]
        private var didUpdateBrowsingPage = false

        var browsingHeading: String {
            lock.withLock { didUpdateBrowsingPage ? LocalUITestWebsite.refreshedHeading : Page.browsing.title }
        }

        func updateBrowsingPage() {
            lock.withLock { didUpdateBrowsingPage = true }
        }

        func expectRequest(for path: String) -> XCTestExpectation {
            let expectation = XCTestExpectation(description: "Request for \(path)")
            lock.withLock { pending[path] = expectation }
            return expectation
        }

        func receivedRequest(for path: String) {
            let expectation = lock.withLock { pending.removeValue(forKey: path) }
            expectation?.fulfill()
        }
    }
}

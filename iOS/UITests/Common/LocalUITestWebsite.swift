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
import XCTest

final class LocalUITestWebsite {
    static let childLinkTitle = "Open child test page"

    struct Page {
        let path: String
        let title: String

        static let first = Page(path: "/first-test-page", title: "First test page")
        static let second = Page(path: "/second-test-page", title: "Second test page")
        static let child = Page(path: "/child-test-page", title: "Child test page")

        static func bookmark(_ index: Int) -> Page {
            Page(path: "/bookmark-\(index)", title: "Bookmark test page \(index)")
        }
    }

    private let server: HttpServer
    let hostAndPort: String

    init() throws {
        let server = HttpServer()
        let pages: [Page] = [.first, .second, .child] + (0..<4).map(Page.bookmark)
        for page in pages {
            let childLink = page.path == Page.first.path
                ? "<a href=\"\(Page.child.path)\">\(Self.childLinkTitle)</a>"
                : ""
            let html = "<title>\(page.title)</title><h1>\(page.title)</h1>\(childLink)"
            server[page.path] = { _ in .ok(.htmlBody(html)) }
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
    }

    deinit {
        server.stop()
    }

    func open(_ page: Page, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.openURL("http://\(hostAndPort)\(page.path)", expecting: page.title, file: file, line: line)
    }
}

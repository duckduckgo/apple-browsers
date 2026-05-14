//
//  TabContentDisplayTitleTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class TabContentDisplayTitleTests: XCTestCase {

    // MARK: - Content-type titles

    func testContentTypeWithKnownTitleIgnoresPageTitleAndURL() {
        let content = Tab.TabContent.bookmarks
        XCTAssertEqual(content.displayTitle(pageTitle: "Ignored", pageURL: URL(string: "https://example.com")), UserText.tabBookmarksTitle)
    }

    func testNewtabReturnsHomeTitle() {
        let content = Tab.TabContent.newtab
        XCTAssertEqual(content.displayTitle(pageTitle: nil, pageURL: nil), UserText.tabHomeTitle)
    }

    // MARK: - URL fallback chain

    func testPageTitleIsUsedWhenAvailable() {
        let content = Tab.TabContent.url(.duckDuckGo, source: .link)
        XCTAssertEqual(content.displayTitle(pageTitle: "My Page", pageURL: URL(string: "https://example.com")), "My Page")
    }

    func testWhitespaceOnlyTitleFallsThroughToHost() {
        let content = Tab.TabContent.url(.duckDuckGo, source: .link)
        XCTAssertEqual(content.displayTitle(pageTitle: "   ", pageURL: URL(string: "https://example.com")), "example.com")
    }

    func testNilTitleFallsThroughToHost() {
        let content = Tab.TabContent.url(URL(string: "https://example.com/doc.pdf")!, source: .link)
        XCTAssertEqual(content.displayTitle(pageTitle: nil, pageURL: URL(string: "https://example.com/doc.pdf")), "example.com")
    }

    func testFileURLFallsThroughToFilename() {
        let fileURL = URL(fileURLWithPath: "/path/to/doc.pdf")
        let content = Tab.TabContent.url(fileURL, source: .link)
        XCTAssertEqual(content.displayTitle(pageTitle: nil, pageURL: fileURL), "doc.pdf")
    }

    func testNoTitleNoURLReturnsUntitled() {
        let content = Tab.TabContent.url(.blankPage, source: .link)
        XCTAssertEqual(content.displayTitle(pageTitle: nil, pageURL: nil), UserText.tabUntitledTitle)
    }
}

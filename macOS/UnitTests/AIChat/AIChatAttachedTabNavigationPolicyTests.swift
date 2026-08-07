//
//  AIChatAttachedTabNavigationPolicyTests.swift
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

import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AIChatAttachedTabNavigationPolicyTests: XCTestCase {

    private let attachedURL = URL(string: "https://example.com/article")!
    private let newURL = URL(string: "https://apple.com")!

    private func attachment(title: String = "Article", url: URL? = nil, favicon: NSImage? = nil) -> AIChatTabAttachment {
        AIChatTabAttachment(id: "tab-1", title: title, url: url ?? attachedURL, favicon: favicon)
    }

    private func content(_ url: URL, source: Tab.TabContent.URLSource = .ui) -> Tab.TabContent {
        .url(url, credential: nil, source: source)
    }

    // MARK: - Navigating away → the card follows the tab

    func testNavigationToAnotherSiteRefreshesTheAttachment() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(favicon: NSImage()),
                                                             page: AIChatAttachedTabPage(content: content(newURL), title: "Apple", favicon: NSImage()))

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1", title: "apple.com", url: newURL, favicon: nil)),
                       "The published title still describes the page being left, and the icon belongs to the old site")
    }

    func testNavigationWithinTheSameSiteKeepsTheFavicon() {
        let favicon = NSImage()
        let otherPage = URL(string: "https://example.com/other")!

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(favicon: favicon),
                                                             page: AIChatAttachedTabPage(content: content(otherPage), title: "Article", favicon: favicon))

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1", title: "example.com", url: otherPage, favicon: favicon)),
                       "A favicon belongs to the site, so moving within it keeps the icon while the title resets")
    }

    // MARK: - Same page

    func testSamePageWithUnchangedTitleAndFaviconIsKept() {
        let favicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(favicon: favicon),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: "Article", favicon: favicon))

        XCTAssertEqual(action, .keep)
    }

    func testSamePageWithNoTitleYetKeepsTheAttachedTitle() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(title: "Article"),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: nil, favicon: nil))

        XCTAssertEqual(action, .keep, "A missing title must not overwrite the attached one with the host")
    }

    func testSamePageWithLateArrivingTitleRefreshesTheTitle() {
        let favicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(title: "example.com", favicon: favicon),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: "Article", favicon: favicon))

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1",
                                                            title: "Article",
                                                            url: attachedURL,
                                                            favicon: favicon)))
    }

    func testSamePageWithLateArrivingFaviconRefreshesTheFavicon() {
        let favicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(favicon: nil),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: "Article", favicon: favicon))

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1", title: "Article", url: attachedURL, favicon: favicon)),
                       "The icon lands after the page it belongs to — the card has to pick it up")
    }

    func testSamePageWithNoFaviconYetKeepsTheAttachedOne() {
        let attachedFavicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(favicon: attachedFavicon),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: "Article", favicon: nil))

        XCTAssertEqual(action, .keep, "A missing favicon must not blank out the one already on the card")
    }

    // MARK: - Landing somewhere unattachable

    func testNavigationToDuckAIDropsTheAttachment() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             page: AIChatAttachedTabPage(content: content(URL(string: "https://duckduckgo.com/?ia=chat")!), title: "Duck.ai", favicon: nil))

        XCTAssertEqual(action, .drop)
    }

    func testNavigationToNonURLContentDropsAttachment() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             page: AIChatAttachedTabPage(content: .newtab, title: nil, favicon: nil))

        XCTAssertEqual(action, .drop, "A new tab page isn't attachable")
    }
}

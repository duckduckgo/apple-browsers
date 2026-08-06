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

    private func content(_ url: URL) -> Tab.TabContent {
        .url(url, credential: nil, source: .ui)
    }

    // MARK: - Navigating with the setting on → the card follows the tab

    func testNavigationRefreshesAttachmentWhenAutomaticallySendingPageContext() {
        let favicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             content: content(newURL),
                                                             title: "Apple",
                                                             favicon: favicon,
                                                             automaticallySendsPageContext: true)

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1", title: "Apple", url: newURL, favicon: favicon)))
    }

    func testNavigationWithoutATitleYetFallsBackToTheHost() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             content: content(newURL),
                                                             title: nil,
                                                             favicon: nil,
                                                             automaticallySendsPageContext: true)

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1", title: "apple.com", url: newURL, favicon: nil)))
    }

    // MARK: - Navigating with the setting off → the explicit pick is dropped

    func testNavigationDropsAttachmentWhenNotAutomaticallySendingPageContext() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             content: content(newURL),
                                                             title: "Apple",
                                                             favicon: nil,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .drop)
    }

    // MARK: - Same page

    func testSamePageWithUnchangedTitleIsKept() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             content: content(attachedURL),
                                                             title: "Article",
                                                             favicon: NSImage(),
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .keep)
    }

    func testSamePageWithNoTitleYetKeepsTheAttachedTitle() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(title: "Article"),
                                                             content: content(attachedURL),
                                                             title: nil,
                                                             favicon: nil,
                                                             automaticallySendsPageContext: true)

        XCTAssertEqual(action, .keep, "A missing title must not overwrite the attached one with the host")
    }

    func testSamePageWithLateArrivingTitleRefreshesTitleAndKeepsTheAttachedFavicon() {
        let attachedFavicon = NSImage()
        let tabFavicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(title: "example.com", favicon: attachedFavicon),
                                                             content: content(attachedURL),
                                                             title: "Article",
                                                             favicon: tabFavicon,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1",
                                                            title: "Article",
                                                            url: attachedURL,
                                                            favicon: attachedFavicon)))
    }

    // MARK: - Landing somewhere unattachable → dropped either way

    func testNavigationToDuckAIDropsAttachmentEvenWhenAutomaticallySendingPageContext() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             content: content(URL(string: "https://duckduckgo.com/?ia=chat")!),
                                                             title: "Duck.ai",
                                                             favicon: nil,
                                                             automaticallySendsPageContext: true)

        XCTAssertEqual(action, .drop)
    }

    func testNavigationToNonURLContentDropsAttachment() {
        for automaticallySendsPageContext in [true, false] {
            let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                                 content: .newtab,
                                                                 title: nil,
                                                                 favicon: nil,
                                                                 automaticallySendsPageContext: automaticallySendsPageContext)

            XCTAssertEqual(action, .drop, "New tab page isn't attachable (auto-send: \(automaticallySendsPageContext))")
        }
    }
}

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

    // MARK: - Navigating with the setting on → the card follows the tab

    func testNavigationRefreshesAttachmentWhenAutomaticallySendingPageContext() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             page: AIChatAttachedTabPage(content: content(newURL), title: "Apple", favicon: NSImage()),
                                                             isSettlingLoadFromAttachTime: false,
                                                             automaticallySendsPageContext: true)

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1", title: "apple.com", url: newURL, favicon: nil)),
                       "Title and favicon still describe the page being left, so the new URL starts from the host")
    }

    // MARK: - Navigating with the setting off → the explicit pick is dropped

    func testNavigationDropsAttachmentWhenNotAutomaticallySendingPageContext() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             page: AIChatAttachedTabPage(content: content(newURL), title: "Apple", favicon: nil),
                                                             isSettlingLoadFromAttachTime: false,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .drop)
    }

    // MARK: - Same page

    func testSamePageWithUnchangedTitleAndFaviconIsKept() {
        let favicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(favicon: favicon),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: "Article", favicon: favicon),
                                                             isSettlingLoadFromAttachTime: false,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .keep)
    }

    func testSamePageWithNoTitleYetKeepsTheAttachedTitle() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(title: "Article"),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: nil, favicon: nil),
                                                             isSettlingLoadFromAttachTime: false,
                                                             automaticallySendsPageContext: true)

        XCTAssertEqual(action, .keep, "A missing title must not overwrite the attached one with the host")
    }

    func testSamePageWithLateArrivingTitleRefreshesTheTitle() {
        let favicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(title: "example.com", favicon: favicon),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: "Article", favicon: favicon),
                                                             isSettlingLoadFromAttachTime: false,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1",
                                                            title: "Article",
                                                            url: attachedURL,
                                                            favicon: favicon)))
    }

    func testSamePageWithLateArrivingFaviconRefreshesTheFavicon() {
        let favicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(favicon: nil),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: "Article", favicon: favicon),
                                                             isSettlingLoadFromAttachTime: false,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1", title: "Article", url: attachedURL, favicon: favicon)),
                       "The icon lands after the page it belongs to — the card has to pick it up")
    }

    func testSamePageWithNoFaviconYetKeepsTheAttachedOne() {
        let attachedFavicon = NSImage()

        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(favicon: attachedFavicon),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL), title: "Article", favicon: nil),
                                                             isSettlingLoadFromAttachTime: false,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .keep, "A missing favicon must not blank out the one already on the card")
    }

    // MARK: - Attached mid-load → the load settling is the same pick, not a navigation away

    func testLoadInFlightAtAttachTimeRebasesTheAttachmentEvenWithAutoSendOff() {
        // Attaching a loading tab captures its pre-redirect URL; the committed one lands moments later.
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(url: URL(string: "http://example.com")!),
                                                             page: AIChatAttachedTabPage(content: content(attachedURL, source: .webViewUpdated), title: "Article", favicon: nil),
                                                             isSettlingLoadFromAttachTime: true,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .refresh(AIChatTabAttachment(id: "tab-1", title: "example.com", url: attachedURL, favicon: nil)),
                       "Dropping here would lose the tab the user just attached")
    }

    func testUserNavigationWhileTheAttachTimeLoadIsStillRunningIsNotTreatedAsSettling() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             page: AIChatAttachedTabPage(content: content(newURL, source: .userEntered("apple.com")), title: nil, favicon: nil),
                                                             isSettlingLoadFromAttachTime: true,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .drop, "The user drove this one, so it is a page change and not the load settling")
    }

    func testLoadInFlightAtAttachTimeStillDropsWhenItLandsSomewhereUnattachable() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             page: AIChatAttachedTabPage(content: content(URL(string: "https://duckduckgo.com/?ia=chat")!, source: .webViewUpdated), title: nil, favicon: nil),
                                                             isSettlingLoadFromAttachTime: true,
                                                             automaticallySendsPageContext: false)

        XCTAssertEqual(action, .drop)
    }

    // MARK: - Landing somewhere unattachable → dropped either way

    func testNavigationToDuckAIDropsAttachmentEvenWhenAutomaticallySendingPageContext() {
        let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                             page: AIChatAttachedTabPage(content: content(URL(string: "https://duckduckgo.com/?ia=chat")!), title: "Duck.ai", favicon: nil),
                                                             isSettlingLoadFromAttachTime: false,
                                                             automaticallySendsPageContext: true)

        XCTAssertEqual(action, .drop)
    }

    func testNavigationToNonURLContentDropsAttachment() {
        for automaticallySendsPageContext in [true, false] {
            let action = AIChatAttachedTabNavigationPolicy.action(for: attachment(),
                                                                 content: .newtab,
                                                                 title: nil,
                                                                 favicon: nil,
                                                                 isSettlingLoadFromAttachTime: false,
                                                             automaticallySendsPageContext: automaticallySendsPageContext)

            XCTAssertEqual(action, .drop, "New tab page isn't attachable (auto-send: \(automaticallySendsPageContext))")
        }
    }
}

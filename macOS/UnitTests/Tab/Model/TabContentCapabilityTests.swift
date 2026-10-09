//
//  TabContentCapabilityTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class TabContentCapabilityTests: XCTestCase {

    private let url = URL(string: "https://example.com")!

    // MARK: - canBeDuplicated

    func testCanBeDuplicated() {
        let cases: [(Tab.TabContent, Bool)] = [
            (.newtab, true),
            (.url(.duckDuckGo, source: .link), true),
            (.settings(pane: nil), false),
            (.bookmarks, true),
            (.history(pane: nil), true),
            (.onboarding, false),
            (.none, true),
            (.dataBrokerProtection, false),
            (.subscription(url), false),
            (.identityTheftRestoration(url), false),
            (.releaseNotes, false),
            (.webExtensionUrl(url), true),
            (.aiChat(url), true),
        ]
        for (content, expected) in cases {
            XCTAssertEqual(content.canBeDuplicated, expected, "\(content)")
        }
    }

    // MARK: - canBePinned

    func testCanBePinned() {
        let cases: [(Tab.TabContent, Bool)] = [
            (.newtab, true),
            (.url(.duckDuckGo, source: .link), true),
            (.settings(pane: nil), true),
            (.bookmarks, true),
            (.history(pane: nil), true),
            (.onboarding, false),
            (.none, false),
            (.dataBrokerProtection, true),
            (.subscription(url), true),
            (.identityTheftRestoration(url), true),
            (.releaseNotes, false),
            (.webExtensionUrl(url), false),
            (.aiChat(url), true),
        ]
        for (content, expected) in cases {
            XCTAssertEqual(content.canBePinned, expected, "\(content)")
        }
    }

    // MARK: - canBeBookmarked

    func testCanBeBookmarked() {
        let cases: [(Tab.TabContent, Bool)] = [
            (.newtab, false),
            (.url(.duckDuckGo, source: .link), true),
            (.settings(pane: nil), false),
            (.bookmarks, false),
            (.history(pane: nil), false),
            (.onboarding, false),
            (.none, false),
            (.dataBrokerProtection, true),
            (.subscription(url), true),
            (.identityTheftRestoration(url), true),
            (.releaseNotes, true),
            (.webExtensionUrl(url), true),
            (.aiChat(url), true),
        ]
        for (content, expected) in cases {
            XCTAssertEqual(content.canBeBookmarked, expected, "\(content)")
        }
    }

    // MARK: - Duck.ai navigation source

    private let duckAIURL = URL(string: "https://duck.ai/chat")!

    func testThatDuckAIContentKeepsOnlyTheSourcesThatTellHowItWasReached() {
        let cases: [(Tab.TabContent.URLSource, Tab.TabContent.URLSource)] = [
            (.userEntered("duck.ai"), .userEntered("duck.ai")),
            (.userEntered("duck.ai", downloadRequested: true), .userEntered("duck.ai")),
            (.bookmark(isFavorite: true), .bookmark(isFavorite: true)),
            (.historyEntry, .historyEntry),
            (.appOpenUrl, .appOpenUrl),
            (.link, .link),
            (.attributedUI(.duckAILink), .attributedUI(.duckAILink)),
            (.ui, .ui),
            (.pendingStateRestoration, .ui),
            (.loadedByStateRestoration, .ui),
            (.reload, .ui),
            (.switchToOpenTab, .ui),
            (.webViewUpdated, .ui),
        ]
        for (source, expected) in cases {
            let content = Tab.TabContent.contentFromURL(duckAIURL, source: source)
            XCTAssertEqual(content, .aiChat(duckAIURL, source: expected), "\(source)")
            XCTAssertEqual(content.source, expected, "\(source)")
        }
    }

    func testThatTypedDuckAILoadsAsAUserEnteredNavigationNotADownload() {
        let content = Tab.TabContent.contentFromURL(duckAIURL, source: .userEntered("duck.ai", downloadRequested: true))

        XCTAssertEqual(content.source.navigationType, .custom(.userEnteredUrl))
        XCTAssertFalse(content.isUserRequestedPageDownload)
    }

    func testThatDuckAIAlwaysLoadsWithTheUICachePolicy() {
        XCTAssertEqual(Tab.TabContent.aiChat(duckAIURL, source: .historyEntry).cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(Tab.TabContent.url(url, source: .historyEntry).cachePolicy, .returnCacheDataElseLoad)
    }

    func testThatUserEnteredHelpersStayURLOnly() {
        let typed = Tab.TabContent.aiChat(duckAIURL, source: .userEntered("duck.ai"))

        XCTAssertNil(typed.userEnteredValue)
        XCTAssertFalse(typed.isUserEnteredUrl)
    }

    func testThatResettingTheSourceOnlyAffectsDuckAI() {
        XCTAssertEqual(Tab.TabContent.aiChat(duckAIURL, source: .userEntered("duck.ai")).resettingAIChatSource, .aiChat(duckAIURL))
        XCTAssertEqual(Tab.TabContent.url(url, source: .link).resettingAIChatSource, .url(url, source: .link))
    }

    func testThatReopeningOrReloadingDuckAIDropsItsSource() {
        let typed = Tab.TabContent.aiChat(duckAIURL, source: .userEntered("duck.ai"))

        XCTAssertEqual(typed.loadedFromCache(), .aiChat(duckAIURL))
        XCTAssertEqual(typed.forceReload(), .aiChat(duckAIURL))
    }

    func testThatAnAttributedUISourceLoadsLikeUI() {
        let attributed = Tab.TabContent.URLSource.attributedUI(.directNewTabPage)

        XCTAssertEqual(attributed.navigationType, Tab.TabContent.URLSource.ui.navigationType)
        XCTAssertEqual(attributed.cachePolicy, Tab.TabContent.URLSource.ui.cachePolicy)
        XCTAssertEqual(Tab.TabContent.aiChat(duckAIURL, source: attributed).loadedFromCache(), .aiChat(duckAIURL))
        XCTAssertEqual(Tab.TabContent.aiChat(duckAIURL, source: attributed).forceReload(), .aiChat(duckAIURL))
    }

    func testThatOnlyDuckAIsOwnLinksAmongAttributedSourcesSwitchToAnOpenTab() {
        XCTAssertTrue(Tab.TabContent.URLSource.switchToOpenTab.switchesToOpenTab)
        XCTAssertTrue(Tab.TabContent.URLSource.appOpenUrl.switchesToOpenTab)
        XCTAssertTrue(Tab.TabContent.URLSource.attributedUI(.duckAILink).switchesToOpenTab)
        XCTAssertFalse(Tab.TabContent.URLSource.attributedUI(.directNewTabPage).switchesToOpenTab)
        XCTAssertFalse(Tab.TabContent.URLSource.ui.switchesToOpenTab)
        XCTAssertFalse(Tab.TabContent.URLSource.link.switchesToOpenTab)
    }

    func testThatReopeningOrReloadingURLContentIsUnchanged() {
        XCTAssertEqual(Tab.TabContent.url(url, source: .link).loadedFromCache(), .url(url, source: .pendingStateRestoration))
        XCTAssertEqual(Tab.TabContent.url(url, source: .link).forceReload(), .url(url, source: .reload))
    }
}

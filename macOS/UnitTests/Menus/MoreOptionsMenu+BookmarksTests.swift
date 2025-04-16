//
//  MoreOptionsMenu+BookmarksTests.swift
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

final class MoreOptionsMenu_BookmarksTests: XCTestCase {

    @MainActor
    func testWhenBookmarkSubmenuIsInitThenBookmarkAllTabsKeyIsCmdShiftD() throws {
        // GIVEN
        let sut = BookmarksSubMenu(targetting: self, tabCollectionViewModel: .init(), moreOptionsMenuIconsProvider: MockMoreOpationsMenuIconProvider())

        // WHEN
        let result = try XCTUnwrap(sut.item(withTitle: UserText.bookmarkAllTabs))

        // THEN
        XCTAssertEqual(result.keyEquivalent, "d")
        XCTAssertEqual(result.keyEquivalentModifierMask, [.command, .shift])
    }

    @MainActor
    func testWhenTabCollectionCanBookmarkAllTabsThenBookmarkAllTabsMenuItemIsEnabled() throws {
        // GIVEN
        let tab1 = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui))
        let tab2 = Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui))
        let sut = BookmarksSubMenu(targetting: self, tabCollectionViewModel: .init(tabCollection: .init(tabs: [tab1, tab2])), moreOptionsMenuIconsProvider: MockMoreOpationsMenuIconProvider())

        // WHEN
        let result = try XCTUnwrap(sut.item(withTitle: UserText.bookmarkAllTabs))

        // THEN
        XCTAssertTrue(result.isEnabled)
    }

    @MainActor
    func testWhenTabCollectionCannotBookmarkAllTabsThenBookmarkAllTabsMenuItemIsDisabled() throws {
        // GIVEN
        let sut = BookmarksSubMenu(targetting: self, tabCollectionViewModel: .init(tabCollection: .init(tabs: [])), moreOptionsMenuIconsProvider: MockMoreOpationsMenuIconProvider())

        // WHEN
        let result = try XCTUnwrap(sut.item(withTitle: UserText.bookmarkAllTabs))

        // THEN
        XCTAssertFalse(result.isEnabled)
    }

}

final class MockMoreOpationsMenuIconProvider: MoreOptionsMenuIconsProviding {
    var sendFeedbackIcon: NSImage = .logo
    var addToDockIcon: NSImage = .logo
    var setAsDefaultBrowserIcon: NSImage = .logo
    var newTabIcon: NSImage = .logo
    var newWindowIcon: NSImage = .logo
    var newFireWindowIcon: NSImage = .logo
    var newAIChatIcon: NSImage = .logo
    var zoomIcon: NSImage = .logo
    var zoomInIcon: NSImage = .logo
    var zoomOutIcon: NSImage = .logo
    var enterFullscreenIcon: NSImage = .logo
    var changeDefaultZoomIcon: NSImage = .logo
    var bookmarksIcon: NSImage = .logo
    var downloadsIcon: NSImage = .logo
    var historyIcon: NSImage = .logo
    var passwordsIcon: NSImage = .logo
    var syncIcon: NSImage = .logo
    var emailProtectionIcon: NSImage = .logo
    var privacyProIcon: NSImage = .logo
    var fireproofSiteIcon: NSImage = .logo
    var removeFireproofIcon: NSImage = .logo
    var findInPageIcon: NSImage = .logo
    var shareIcon: NSImage = .logo
    var printIcon: NSImage = .logo
    var helpIcon: NSImage = .logo
    var settingsIcon: NSImage = .logo
    var browserFeedbackIcon: NSImage = .logo
    var reportBrokenSiteIcon: NSImage = .logo
    var sendPrivacyProFeedbackIcon: NSImage = .logo
    var passwordsSubMenuIcon: NSImage = .logo
    var identitiesIcon: NSImage = .logo
    var creditCardsIcon: NSImage = .logo
    var vpnIcon: NSImage = .logo
    var personalInformationRemovalIcon: NSImage = .logo
    var identityTheftRestorationIcon: NSImage = .logo
    var emailGenerateAddressIcon: NSImage = .logo
    var emailManageAccount: NSImage = .logo
    var emailProtectionTurnOffIcon: NSImage = .logo
    var emailProtectionTurnOnIcon: NSImage = .logo
    var favoritesIcon: NSImage = .logo
}

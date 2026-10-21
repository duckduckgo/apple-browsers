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

import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class MoreOptionsMenu_BookmarksTests: XCTestCase {

    @MainActor
    func testWhenBookmarkSubmenuIsInitThenBookmarkAllTabsKeyIsCmdShiftD() throws {
        // GIVEN
        let sut = BookmarksSubMenu(targetting: self, tabCollectionViewModel: .init(isPopup: false), bookmarkManager: MockBookmarkManager(), moreOptionsMenuIconsProvider: MockMoreOpationsMenuIconProvider(), featureFlagger: MockFeatureFlagger())

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
        let sut = BookmarksSubMenu(targetting: self, tabCollectionViewModel: .init(tabCollection: .init(tabs: [tab1, tab2])), bookmarkManager: MockBookmarkManager(), moreOptionsMenuIconsProvider: MockMoreOpationsMenuIconProvider(), featureFlagger: MockFeatureFlagger())

        // WHEN
        let result = try XCTUnwrap(sut.item(withTitle: UserText.bookmarkAllTabs))

        // THEN
        XCTAssertTrue(result.isEnabled)
    }

    @MainActor
    func testWhenTabCollectionCannotBookmarkAllTabsThenBookmarkAllTabsMenuItemIsDisabled() throws {
        // GIVEN
        let sut = BookmarksSubMenu(targetting: self, tabCollectionViewModel: .init(tabCollection: .init()), bookmarkManager: MockBookmarkManager(), moreOptionsMenuIconsProvider: MockMoreOpationsMenuIconProvider(), featureFlagger: MockFeatureFlagger())

        // WHEN
        let result = try XCTUnwrap(sut.item(withTitle: UserText.bookmarkAllTabs))

        // THEN
        XCTAssertFalse(result.isEnabled)
    }

}

final class MockMoreOpationsMenuIconProvider: MoreOptionsMenuIconsProviding {
    var sendFeedbackIcon: NSImage = NSImage(resource: .logo)
    var addToDockIcon: NSImage = NSImage(resource: .logo)
    var setAsDefaultBrowserIcon: NSImage = NSImage(resource: .logo)
    var newTabIcon: NSImage = NSImage(resource: .logo)
    var newWindowIcon: NSImage = NSImage(resource: .logo)
    var newFireWindowIcon: NSImage = NSImage(resource: .logo)
    var newAIChatIcon: NSImage = NSImage(resource: .logo)
    var zoomIcon: NSImage = NSImage(resource: .logo)
    var zoomInIcon: NSImage = NSImage(resource: .logo)
    var zoomOutIcon: NSImage = NSImage(resource: .logo)
    var enterFullscreenIcon: NSImage = NSImage(resource: .logo)
    var changeDefaultZoomIcon: NSImage = NSImage(resource: .logo)
    var bookmarksIcon: NSImage = NSImage(resource: .logo)
    var downloadsIcon: NSImage = NSImage(resource: .logo)
    var historyIcon: NSImage = NSImage(resource: .logo)
    var passwordsIcon: NSImage = NSImage(resource: .logo)
    var deleteBrowsingDataIcon: NSImage = NSImage(resource: .logo)
    var syncIcon: NSImage = NSImage(resource: .logo)
    var emailProtectionIcon: NSImage = NSImage(resource: .logo)
    var subscriptionIcon: NSImage = NSImage(resource: .logo)
    var fireproofSiteIcon: NSImage = NSImage(resource: .logo)
    var removeFireproofIcon: NSImage = NSImage(resource: .logo)
    var findInPageIcon: NSImage = NSImage(resource: .logo)
    var shareIcon: NSImage = NSImage(resource: .logo)
    var printIcon: NSImage = NSImage(resource: .logo)
    var helpIcon: NSImage = NSImage(resource: .logo)
    var settingsIcon: NSImage = NSImage(resource: .logo)
    var browserFeedbackIcon: NSImage = NSImage(resource: .logo)
    var reportBrokenSiteIcon: NSImage = NSImage(resource: .logo)
    var paidAIChat: NSImage = NSImage(resource: .logo)
    var sendSubscriptionFeedbackIcon: NSImage = NSImage(resource: .logo)
    var passwordsSubMenuIcon: NSImage = NSImage(resource: .logo)
    var identitiesIcon: NSImage = NSImage(resource: .logo)
    var creditCardsIcon: NSImage = NSImage(resource: .logo)
    var vpnIcon: NSImage? = NSImage(resource: .logo)
    var personalInformationRemovalIcon: NSImage = NSImage(resource: .logo)
    var identityTheftRestorationIcon: NSImage = NSImage(resource: .logo)
    var emailGenerateAddressIcon: NSImage = NSImage(resource: .logo)
    var emailManageAccount: NSImage = NSImage(resource: .logo)
    var emailProtectionTurnOffIcon: NSImage = NSImage(resource: .logo)
    var emailProtectionTurnOnIcon: NSImage = NSImage(resource: .logo)
    var favoritesIcon: NSImage = NSImage(resource: .logo)
}

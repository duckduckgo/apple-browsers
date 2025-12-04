//
//  BrowsingMenuBuilding.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Foundation
import Bookmarks
import Core
import BrowserServicesKit
import PrivacyDashboard

enum BrowsingMenuContext {
    case newTabPage
    case aiChatTab
    case website
}

protocol BrowsingMenuEntryBuilding: AnyObject {
    func makeShortcutsMenu() -> [BrowsingMenuEntry]
    func makeAITabMenu() -> [BrowsingMenuEntry]
    func makeAITabMenuHeaderContent() -> [BrowsingMenuEntry]
    func makeBrowsingMenu(with bookmarksInterface: MenuBookmarksInteracting,
                          mobileCustomization: MobileCustomization,
                          clearTabsAndData: @escaping () -> Void) -> [BrowsingMenuEntry]
    func makeBrowsingMenuHeaderContent() -> [BrowsingMenuEntry]

    func makeNewTabEntry() -> BrowsingMenuEntry
    func makeChatEntry() -> BrowsingMenuEntry?
    func makeSettingsEntry() -> BrowsingMenuEntry
    func makeShareEntry() -> BrowsingMenuEntry
    func makePrintEntry() -> BrowsingMenuEntry
    func makeDownloadsEntry() -> BrowsingMenuEntry
    func makeAutoFillEntry() -> BrowsingMenuEntry?
    func makeVPNEntry() -> BrowsingMenuEntry?
    func makeOpenBookmarksEntry() -> BrowsingMenuEntry
    func makeBookmarkEntries(with bookmarksInterface: MenuBookmarksInteracting) -> (bookmark: BrowsingMenuEntry, favorite: BrowsingMenuEntry)?
    func makeFindInPageEntry() -> BrowsingMenuEntry?
    func makeZoomEntry() -> BrowsingMenuEntry?
    func makeDesktopSiteEntry() -> BrowsingMenuEntry?
    func makeReloadEntry() -> BrowsingMenuEntry?
    func makeToggleProtectionEntry() -> BrowsingMenuEntry?
    func makeReportBrokenSiteEntry() -> BrowsingMenuEntry?
    func makeClearDataEntry(mobileCustomization: MobileCustomization, clearTabsAndData: @escaping () -> Void) -> BrowsingMenuEntry?
    func makeUseNewDuckAddressEntry() -> BrowsingMenuEntry?
    func makeKeepSignInEntry() -> BrowsingMenuEntry?
}

protocol BrowsingMenuBuilding: AnyObject {
    var entryBuilder: BrowsingMenuEntryBuilding? { get }

    func buildMenu(
        context: BrowsingMenuContext,
        bookmarksInterface: MenuBookmarksInteracting,
        mobileCustomization: MobileCustomization,
        clearTabsAndData: @escaping () -> Void
    ) -> BrowsingMenuModel?
}

// MARK: - Default Implementation for AI Chat Menu

extension BrowsingMenuBuilding {
    func buildAIChatMenu() -> BrowsingMenuModel? {
        guard let entryBuilder = entryBuilder else { return nil }

        let header = entryBuilder.makeAITabMenuHeaderContent()
        let menu = entryBuilder.makeAITabMenu()

        let headerItems: [BrowsingMenuModel.Entry] = header.compactMap { .init($0) }
        let sections: [BrowsingMenuModel.Section] = menu.split(whereSeparator: \.isSeparator).map {
            BrowsingMenuModel.Section(items: $0.compactMap { .init($0) })
        }

        return BrowsingMenuModel(
            headerItems: headerItems,
            sections: sections,
            footerItems: []
        )
    }
}

//
//  BrowsingMenuVariantCBuilder.swift
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

/// Variant C Builder: Custom structure with share in header and settings in footer
final class BrowsingMenuVariantCBuilder: BrowsingMenuVariantBuilder {
    weak var entryBuilder: BrowsingMenuEntryBuilding?

    init(entryBuilder: BrowsingMenuEntryBuilding) {
        self.entryBuilder = entryBuilder
    }

    func buildMenu(
        context: BrowsingMenuContext,
        bookmarksInterface: MenuBookmarksInteracting,
        mobileCustomization: MobileCustomization,
        clearTabsAndData: @escaping () -> Void
    ) -> BrowsingMenuModel? {

        switch context {
        case .newTabPage:
            return buildNewTabPageMenu(mobileCustomization: mobileCustomization,
                                       clearTabsAndData: clearTabsAndData)

        case .aiChatTab:
            return buildAIChatMenu()

        case .website:
            return buildWebsiteMenu(
                bookmarksInterface: bookmarksInterface,
                mobileCustomization: mobileCustomization,
                clearTabsAndData: clearTabsAndData
            )
        }
    }

    private func buildNewTabPageMenu(mobileCustomization: MobileCustomization,
                                     clearTabsAndData: @escaping () -> Void) -> BrowsingMenuModel? {
        guard let entryBuilder = entryBuilder else { return nil }

        let headerItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeNewTabEntry()),
            .init(entryBuilder.makeChatEntry(withSmallIcon: false))
        ].compactMap { $0 }

        let shortcutsItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeOpenBookmarksEntry()),
            .init(entryBuilder.makeAutoFillEntry()),
            .init(entryBuilder.makeDownloadsEntry())
        ].compactMap { $0 }

        let privacyItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeVPNEntry()),
            .init(entryBuilder.makeClearDataEntry(mobileCustomization: mobileCustomization, clearTabsAndData: clearTabsAndData))
        ].compactMap { $0 }

        let sections = [
            BrowsingMenuModel.Section(items: shortcutsItems),
            BrowsingMenuModel.Section(items: privacyItems)
        ]

        let footerItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeSettingsEntry(useSmallIcon: false))
        ].compactMap { $0 }

        return BrowsingMenuModel(
            headerItems: headerItems,
            sections: sections,
            footerItems: footerItems
        )
    }

    private func buildWebsiteMenu(
        bookmarksInterface: MenuBookmarksInteracting,
        mobileCustomization: MobileCustomization,
        clearTabsAndData: @escaping () -> Void
    ) -> BrowsingMenuModel? {
        guard let entryBuilder = entryBuilder else { return nil }

        // Header: new tab, duck.ai (conditional), share
        let headerItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeNewTabEntry()),
            .init(entryBuilder.makeChatEntry(withSmallIcon: false)),
            .init(entryBuilder.makeShareEntry(useSmallIcon: false))
        ].compactMap { $0 }

        // Sections
        var sections = [BrowsingMenuModel.Section]()

        // Link section
        if let bookmarkEntries = entryBuilder.makeBookmarkEntries(with: bookmarksInterface) {
            let linkItems: [BrowsingMenuModel.Entry] = [
                .init(bookmarkEntries.bookmark),
                .init(bookmarkEntries.favorite, tag: .favorite)
            ].compactMap { $0 }
            sections.append(BrowsingMenuModel.Section(items: linkItems))
        }

        // Tab actions section
        let tabActionItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeFindInPageEntry()),
            .init(entryBuilder.makeZoomEntry()),
            .init(entryBuilder.makeDesktopSiteEntry())
        ].compactMap { $0 }

        if !tabActionItems.isEmpty {
            sections.append(BrowsingMenuModel.Section(items: tabActionItems))
        }

        // Privacy section
        let privacyItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeVPNEntry()),
            .init(entryBuilder.makeUseNewDuckAddressEntry()),
            .init(entryBuilder.makeToggleProtectionEntry()),
            .init(entryBuilder.makeKeepSignInEntry()),
            .init(entryBuilder.makeClearDataEntry(mobileCustomization: mobileCustomization, clearTabsAndData: clearTabsAndData))
        ].compactMap { $0 }

        if !privacyItems.isEmpty {
            sections.append(BrowsingMenuModel.Section(items: privacyItems))
        }

        // Shortcuts section
        let shortcutItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeOpenBookmarksEntry()),
            .init(entryBuilder.makeAutoFillEntry()),
            .init(entryBuilder.makeDownloadsEntry())
        ].compactMap { $0 }

        if !shortcutItems.isEmpty {
            sections.append(BrowsingMenuModel.Section(items: shortcutItems))
        }

        // Other section
        let otherItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeReloadEntry()),
            .init(entryBuilder.makeReportBrokenSiteEntry()),
            .init(entryBuilder.makePrintEntry(withSmallIcon: true))
        ].compactMap { $0 }

        if !otherItems.isEmpty {
            sections.append(BrowsingMenuModel.Section(items: otherItems))
        }

        // Footer: settings
        let footerItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeSettingsEntry(useSmallIcon: false))
        ].compactMap { $0 }

        return BrowsingMenuModel(
            headerItems: headerItems,
            sections: sections,
            footerItems: footerItems
        )
    }
}

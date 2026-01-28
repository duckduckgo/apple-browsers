//
//  BrowsingMenuBuilder.swift
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

final class BrowsingMenuBuilder: BrowsingMenuBuilding {

    struct Options {
        let mergeActionsAndBookmarks: Bool

        init(mergeActionsAndBookmarks: Bool = false) {
            self.mergeActionsAndBookmarks = mergeActionsAndBookmarks
        }

        init(capability: BrowsingMenuSheetCapable) {
            self.mergeActionsAndBookmarks = capability.mergeActionsAndBookmarks
        }
    }

    weak var entryBuilder: BrowsingMenuEntryBuilding?
    private let options: Options

    init(entryBuilder: BrowsingMenuEntryBuilding, options: Options = Options()) {
        self.entryBuilder = entryBuilder
        self.options = options
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

    // MARK: - New Tab Page

    private func buildNewTabPageMenu(mobileCustomization: MobileCustomization,
                                     clearTabsAndData: @escaping () -> Void) -> BrowsingMenuModel? {
        guard let entryBuilder = entryBuilder else { return nil }

        // MARK: Header
        let headerItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeNewTabEntry()),
            .init(entryBuilder.makeChatEntry()),
            .init(entryBuilder.makeSettingsEntry())
        ].compactMap { $0 }

        // MARK: Shortcuts group
        let shortcutsItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeOpenBookmarksEntry()),
            .init(entryBuilder.makeAutoFillEntry()),
            .init(entryBuilder.makeDownloadsEntry())
        ].compactMap { $0 }

        // MARK: Privacy group
        let privacyItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeVPNEntry()),
            .init(entryBuilder.makeClearDataEntry(mobileCustomization: mobileCustomization, clearTabsAndData: clearTabsAndData))
        ].compactMap { $0 }

        let sections = [
            BrowsingMenuModel.Section(items: shortcutsItems),
            BrowsingMenuModel.Section(items: privacyItems)
        ]

        return BrowsingMenuModel(
            headerItems: headerItems,
            sections: sections
        )
    }

    // MARK: - Website

    private func buildWebsiteMenu(
        bookmarksInterface: MenuBookmarksInteracting,
        mobileCustomization: MobileCustomization,
        clearTabsAndData: @escaping () -> Void
    ) -> BrowsingMenuModel? {
        guard let entryBuilder = entryBuilder else { return nil }

        // MARK: Header
        let headerItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeNewTabEntry()),
            .init(entryBuilder.makeChatEntry()),
            .init(entryBuilder.makeSettingsEntry())
        ].compactMap { $0 }

        var sections = [BrowsingMenuModel.Section]()

        if options.mergeActionsAndBookmarks {
            // MARK: Tab Actions
            if let bookmarkEntries = entryBuilder.makeBookmarkEntries(with: bookmarksInterface) {
                let bookmarkGroupItems: [BrowsingMenuModel.Entry] = [
                    .init(bookmarkEntries.bookmark),
                    .init(bookmarkEntries.favorite, tag: .favorite),
                    .init(entryBuilder.makeShareEntry()),
                    .init(entryBuilder.makeFindInPageEntry()),
                    .init(entryBuilder.makeZoomEntry()),
                    .init(entryBuilder.makeDesktopSiteEntry())
                ].compactMap { $0 }
                sections.append(BrowsingMenuModel.Section(items: bookmarkGroupItems))
            }
        } else {
            // MARK: Bookmark group
            if let bookmarkEntries = entryBuilder.makeBookmarkEntries(with: bookmarksInterface) {
                let bookmarkGroupItems: [BrowsingMenuModel.Entry] = [
                    .init(bookmarkEntries.bookmark),
                    .init(bookmarkEntries.favorite, tag: .favorite),
                    .init(entryBuilder.makeShareEntry())
                ].compactMap { $0 }
                sections.append(BrowsingMenuModel.Section(items: bookmarkGroupItems))
            }

            // MARK: Tab actions group
            let tabActionItems: [BrowsingMenuModel.Entry] = [
                .init(entryBuilder.makeFindInPageEntry()),
                .init(entryBuilder.makeZoomEntry()),
                .init(entryBuilder.makeDesktopSiteEntry())
            ].compactMap { $0 }

            if !tabActionItems.isEmpty {
                sections.append(BrowsingMenuModel.Section(items: tabActionItems))
            }
        }

        // MARK: Shortcuts group
        let shortcutItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeOpenBookmarksEntry()),
            .init(entryBuilder.makeAutoFillEntry()),
            .init(entryBuilder.makeDownloadsEntry())
        ].compactMap { $0 }

        if !shortcutItems.isEmpty {
            sections.append(BrowsingMenuModel.Section(items: shortcutItems))
        }

        // MARK: Privacy group
        let privacyItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeVPNEntry()),
            .init(entryBuilder.makeUseNewDuckAddressEntry()),
            .init(entryBuilder.makeKeepSignInEntry()),
            .init(entryBuilder.makeClearDataEntry(mobileCustomization: mobileCustomization, clearTabsAndData: clearTabsAndData))
        ].compactMap { $0 }

        if !privacyItems.isEmpty {
            sections.append(BrowsingMenuModel.Section(items: privacyItems))
        }

        // MARK: Actions group
        let otherItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeReloadEntry()),
            .init(entryBuilder.makeReportBrokenSiteEntry()),
            .init(entryBuilder.makeToggleProtectionEntry()),
            .init(entryBuilder.makePrintEntry())
        ].compactMap { $0 }

        if !otherItems.isEmpty {
            sections.append(BrowsingMenuModel.Section(items: otherItems))
        }

        return BrowsingMenuModel(
            headerItems: headerItems,
            sections: sections
        )
    }
}

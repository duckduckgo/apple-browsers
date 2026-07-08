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

    /// Appends a section for the given entries, skipping the section entirely when there are none.
    private func appendSection(_ items: [BrowsingMenuModel.Entry], to sections: inout [BrowsingMenuModel.Section]) {
        guard !items.isEmpty else { return }
        sections.append(BrowsingMenuModel.Section(items: items))
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
        // With Unified Toggle Input on, the Duck.ai "Chats" row moves into its own Duck.ai cluster below.
        let duckAIItems = entryBuilder.makeDuckAIMenuItems()
        let shortcutsItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeOpenBookmarksEntry()),
            .init(entryBuilder.makeAutoFillEntry()),
            .init(entryBuilder.makeDownloadsEntry()),
            .init(duckAIItems.isEmpty ? entryBuilder.makeDuckAiChatsEntry() : nil)
        ].compactMap { $0 }

        // MARK: Privacy group
        let privacyItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeVPNEntry()),
            .init(entryBuilder.makeUseNewDuckAddressEntry()),
            .init(entryBuilder.makeClearDataEntry(mobileCustomization: mobileCustomization, clearTabsAndData: clearTabsAndData))
        ].compactMap { $0 }

        var sections = [BrowsingMenuModel.Section]()

        sections.append(BrowsingMenuModel.Section(items: shortcutsItems))

        // MARK: Duck.ai group
        appendSection(duckAIItems.compactMap { .init($0) }, to: &sections)

        sections.append(BrowsingMenuModel.Section(items: privacyItems))

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

        // MARK: YouTube Ad Block toggle
        if let youTubeAdBlockEntry = BrowsingMenuModel.Entry(entryBuilder.makeYouTubeAdBlockToggleEntry()) {
            sections.append(BrowsingMenuModel.Section(items: [youTubeAdBlockEntry]))
        }

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
        // With Unified Toggle Input on, the Duck.ai "Chats" row moves into its own Duck.ai cluster below.
        let duckAIItems = entryBuilder.makeDuckAIMenuItems()
        let shortcutItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeOpenBookmarksEntry()),
            .init(entryBuilder.makeAutoFillEntry()),
            .init(entryBuilder.makeDownloadsEntry()),
            .init(duckAIItems.isEmpty ? entryBuilder.makeDuckAiChatsEntry() : nil)
        ].compactMap { $0 }

        appendSection(shortcutItems, to: &sections)

        // MARK: Duck.ai group
        appendSection(duckAIItems.compactMap { .init($0) }, to: &sections)

        // MARK: Privacy group
        let privacyItems: [BrowsingMenuModel.Entry] = [
            .init(entryBuilder.makeVPNEntry()),
            .init(entryBuilder.makeUseNewDuckAddressEntry()),
            .init(entryBuilder.makeKeepSignInEntry()),
            .init(entryBuilder.makeClearDataEntry(mobileCustomization: mobileCustomization, clearTabsAndData: clearTabsAndData), tag: .fire)
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

        // Show enough items to reveal "Open Bookmarks" (7th item in both layouts):
        // Non-merged: 3 (Bookmark, Favorite, Share) + 3 (Find in Page, Zoom, Desktop Site) + 1 (Open Bookmarks)
        // Merged: 6 (Bookmark, Favorite, Share, Find in Page, Zoom, Desktop Site) + 1 (Open Bookmarks)
        let preferredDetentItemCount = 7

        return BrowsingMenuModel(
            headerItems: headerItems,
            sections: sections,
            preferredDetentItemCount: preferredDetentItemCount
        )
    }
}

//
//  BrowsingMenuVariantABuilder.swift
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

/// Variant A Builder: Uses existing menu structure, splits by separators
final class BrowsingMenuVariantABuilder: BrowsingMenuVariantBuilder {
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
            return buildNewTabPageMenu()

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

    private func buildNewTabPageMenu() -> BrowsingMenuModel? {
        guard let entryBuilder = entryBuilder else { return nil }

        let shortcuts = entryBuilder.makeShortcutsMenu()

        let sections: [BrowsingMenuModel.Section] = shortcuts.split(whereSeparator: \.isSeparator).map {
            BrowsingMenuModel.Section(items: $0.compactMap { .init($0) })
        }

        return BrowsingMenuModel(
            headerItems: [],
            sections: sections,
            footerItems: []
        )
    }

    private func buildWebsiteMenu(
        bookmarksInterface: MenuBookmarksInteracting,
        mobileCustomization: MobileCustomization,
        clearTabsAndData: @escaping () -> Void
    ) -> BrowsingMenuModel? {
        guard let entryBuilder = entryBuilder else { return nil }

        let header = entryBuilder.makeBrowsingMenuHeaderContent()
        let headerItems: [BrowsingMenuModel.Entry] = header.compactMap { .init($0) }

        let sectionsItems = entryBuilder.makeBrowsingMenu(
            with: bookmarksInterface,
            mobileCustomization: mobileCustomization,
            clearTabsAndData: clearTabsAndData
        )

        // The favorite entry is at index 1 in the flat array
        let favoriteEntryIndex = 1

        // Tag entries before splitting into sections
        let taggedItems: [(entry: BrowsingMenuEntry, tag: BrowsingMenuModel.Entry.Tag?)] = sectionsItems.enumerated().map { index, entry in
            let tag: BrowsingMenuModel.Entry.Tag? = index == favoriteEntryIndex ? .favorite : nil
            return (entry, tag)
        }

        // Split by separators while preserving tags
        let sections: [BrowsingMenuModel.Section] = taggedItems.split(whereSeparator: { $0.entry.isSeparator }).map { subsection in
            let items = subsection.compactMap { BrowsingMenuModel.Entry($0.entry, tag: $0.tag) }
            return BrowsingMenuModel.Section(items: items)
        }

        return BrowsingMenuModel(
            headerItems: headerItems,
            sections: sections,
            footerItems: []
        )
    }
}

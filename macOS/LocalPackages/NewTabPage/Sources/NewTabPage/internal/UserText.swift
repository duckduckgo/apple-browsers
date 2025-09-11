//
//  UserText.swift
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

import Foundation

enum UserText {
    static let openInNewTab = NSLocalizedString("open.in.new.tab", value: "Open in New Tab", comment: "Menu item that opens the link in a new tab")
    static let openInNewWindow = NSLocalizedString("open.in.new.window", value: "Open in New Window", comment: "Menu item that opens the link in a new window")
    static let openInNewFireWindow = NSLocalizedString("open.in.new.fire.window", value: "Open in New Fire Window", comment: "Menu item that opens the link in a new Fire Window")
    static let edit = NSLocalizedString("edit", value: "Edit", comment: "Edit button")
    static let copyLink = NSLocalizedString("copy.link", value: "Copy Link", comment: "Menu item that copies the link from bookmark")
    static let deleteBookmark = NSLocalizedString("delete-bookmark", value: "Delete Bookmark", comment: "Delete Bookmark button")
    static let removeFavorite = NSLocalizedString("remove-favorite", value: "Remove Favorite", comment: "Remove Favorite button")

    static let newTabPageContextMenuSearch = NSLocalizedString("newtabpage.context.menu.search", value: "Search", comment: "Context menu item to manage Search section on the New Tab Page")
    static let newTabPageContextMenuFavorites = NSLocalizedString("newtabpage.context.menu.favorites", value: "Favorites", comment: "Context menu item to manage Favorites section on the New Tab Page")
    static let newTabPageContextMenuProtectionsReport = NSLocalizedString("newtabpage.context.menu.protections.report", value: "Protections Report", comment: "Context menu item to manage Protections Report section on the New Tab Page")
    static let newTabPageContextMenuShowDuckAI = NSLocalizedString("newtabpage.context.menu.show.duckai", value: "Show Duck.ai in Search Box", comment: "Context menu item to manage Duck.ai on the New Tab Page")
    static let newTabPageContextMenuOpenDuckAISettings = NSLocalizedString("newtabpage.context.menu.open.duckai.settings", value: "Open Duck.ai Settings", comment: "Context menu item to open Duck.ai Settings from the New Tab Page")
}

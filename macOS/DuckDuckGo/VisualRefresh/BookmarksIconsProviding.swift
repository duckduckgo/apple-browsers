//
//  BookmarksIconsProviding.swift
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

import AppKit
import DesignResourcesKitIcons

protocol BookmarksIconsProviding {
    var bookmarksManagerRootIcon: NSImage { get }
    var bookmarkFolderColorIcon: NSImage { get }
    var bookmarkFolderIcon: NSImage { get }
    var bookmarkIcon: NSImage { get }
    var bookmarkColorIcon: NSImage { get }
    var addBookmarkFolderIcon: NSImage { get }
    var addBookmarkIcon: NSImage { get }
    var deleteBookmarkIcon: NSImage { get }
    var sortBookmarkAscendingIcon: NSImage { get }
    var sortBookmarkDescendingIcon: NSImage { get }
    var sortBookmarkManuallyIcon: NSImage { get }
    var bookmarkFilledIcon: NSImage { get }
}

final class LegacyBookmarksIconsProvider: BookmarksIconsProviding {
    var bookmarksManagerRootIcon: NSImage = .bookmarksFolder
    var bookmarkFolderColorIcon: NSImage = .folder
    var bookmarkFolderIcon: NSImage = .folder16
    var bookmarkIcon: NSImage = .bookmark
    var bookmarkColorIcon: NSImage = .bookmarkDefaultFavicon
    var addBookmarkFolderIcon: NSImage = .addBookmark
    var addBookmarkIcon: NSImage = .addFolder
    var deleteBookmarkIcon: NSImage = .trash
    var sortBookmarkAscendingIcon: NSImage = .sortAscending
    var sortBookmarkDescendingIcon: NSImage = .sortDescending
    var sortBookmarkManuallyIcon: NSImage = .sortAscending
    var bookmarkFilledIcon: NSImage = .bookmarkFilled
}

final class CurrentBookmarksIconsProvider: BookmarksIconsProviding {
    var bookmarksManagerRootIcon: NSImage = DesignSystemImages.Color.Size16.bookmarksNew
    var bookmarkFolderColorIcon: NSImage = DesignSystemImages.Color.Size16.folder
    var bookmarkFolderIcon: NSImage = DesignSystemImages.Glyphs.Size16.folder
    var bookmarkIcon: NSImage = DesignSystemImages.Glyphs.Size16.bookmark
    var bookmarkColorIcon: NSImage = DesignSystemImages.Color.Size16.bookmark
    var addBookmarkFolderIcon: NSImage = DesignSystemImages.Glyphs.Size16.folderNew
    var addBookmarkIcon: NSImage = DesignSystemImages.Glyphs.Size16.bookmarkAdd
    var deleteBookmarkIcon: NSImage = DesignSystemImages.Glyphs.Size16.trash
    var sortBookmarkAscendingIcon: NSImage = DesignSystemImages.Glyphs.Size16.sortAscending
    var sortBookmarkDescendingIcon: NSImage = DesignSystemImages.Glyphs.Size16.sortDescending
    var sortBookmarkManuallyIcon: NSImage = DesignSystemImages.Glyphs.Size16.sortManually
    var bookmarkFilledIcon: NSImage = DesignSystemImages.Glyphs.Size16.bookmarkSolid
}

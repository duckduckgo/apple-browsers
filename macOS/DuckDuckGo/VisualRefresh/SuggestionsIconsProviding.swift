//
//  SuggestionsIconsProviding.swift
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
import DesignResourcesKitIcons

protocol SuggestionsIconsProviding {
    var phraseEntryIcon: NSImage { get }
    var websiteEntryIcon: NSImage { get }
    var bookmarkEntryIcon: NSImage { get }
    var favoriteEntryIcon: NSImage { get }
    var unknownEntryIcon: NSImage { get }
    var folderEntryIcon: NSImage { get }
    var settingsEntryIcon: NSImage { get }
    var historyEntryIcon: NSImage { get }
    var homeEntryIcon: NSImage { get }
    var openTabEntryIcon: NSImage { get }
}

final class LegacySuggestionsIconsProvider: SuggestionsIconsProviding {
    var phraseEntryIcon: NSImage = .web
    var websiteEntryIcon: NSImage = .historySuggestion
    var bookmarkEntryIcon: NSImage = .bookmarkSuggestion
    var favoriteEntryIcon: NSImage = .favoritedBookmarkSuggestion
    var unknownEntryIcon: NSImage = .web
    var folderEntryIcon: NSImage = .bookmarksFolder
    var settingsEntryIcon: NSImage = .settingsMulticolor16
    var historyEntryIcon: NSImage = .search
    var homeEntryIcon: NSImage = .home16
    var openTabEntryIcon: NSImage = .openTabSuggestion
}

final class CurrentSuggestionsIconsProvider: SuggestionsIconsProviding {
    var phraseEntryIcon: NSImage = DesignSystemImages.Glyphs.Size16.findSearch
    var websiteEntryIcon: NSImage = DesignSystemImages.Glyphs.Size16.globe
    var bookmarkEntryIcon: NSImage = DesignSystemImages.Glyphs.Size16.bookmark
    var favoriteEntryIcon: NSImage = DesignSystemImages.Glyphs.Size16.bookmarkFavorite
    var unknownEntryIcon: NSImage = DesignSystemImages.Glyphs.Size16.globe
    var folderEntryIcon: NSImage = DesignSystemImages.Color.Size16.bookmarksNew
    var settingsEntryIcon: NSImage = DesignSystemImages.Color.Size16.settings
    var historyEntryIcon: NSImage = DesignSystemImages.Glyphs.Size16.history
    var homeEntryIcon: NSImage = DesignSystemImages.Glyphs.Size16.home
    var openTabEntryIcon: NSImage = DesignSystemImages.Glyphs.Size16.tabDesktop
}

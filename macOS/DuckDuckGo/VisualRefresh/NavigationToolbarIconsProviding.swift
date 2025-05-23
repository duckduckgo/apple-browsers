//
//  NavigationToolbarIconsProviding.swift
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

protocol NavigationToolbarIconsProviding {
    var backButtonImage: NSImage { get }
    var forwardButtonImage: NSImage { get }
    var reloadButtonImage: NSImage { get }
    var homeButtonImage: NSImage { get }
    var downloadsButtonImage: NSImage { get }
    var passwordManagerButtonImage: NSImage { get }
    var bookmarksButtonImage: NSImage { get }
    var moreOptionsbuttonImage: NSImage { get }
    var overflowButtonImage: NSImage { get }
    var aiChatButtonImage: NSImage { get }
}

final class LegacyNavigationToolbarIconsProvider: NavigationToolbarIconsProviding {
    let backButtonImage: NSImage = .back
    let forwardButtonImage: NSImage = .forward
    let reloadButtonImage: NSImage = .refresh
    let homeButtonImage: NSImage = .home16
    let downloadsButtonImage: NSImage = .downloads
    let passwordManagerButtonImage: NSImage = .passwordManagement
    let bookmarksButtonImage: NSImage = .bookmarks
    let moreOptionsbuttonImage: NSImage = .settings
    let overflowButtonImage: NSImage = .chevronDoubleRight16
    let aiChatButtonImage: NSImage = .aiChat
}

final class CurrentNavigationToolbarIconsProvider: NavigationToolbarIconsProviding {
    let backButtonImage: NSImage = DesignSystemImages.Glyphs.Size16.arrowLeft
    let forwardButtonImage: NSImage = DesignSystemImages.Glyphs.Size16.arrowRight
    let reloadButtonImage: NSImage = DesignSystemImages.Glyphs.Size16.reload
    let homeButtonImage: NSImage = DesignSystemImages.Glyphs.Size16.home
    let downloadsButtonImage: NSImage = DesignSystemImages.Glyphs.Size16.downloads
    let passwordManagerButtonImage: NSImage = DesignSystemImages.Glyphs.Size16.keyLogin
    let bookmarksButtonImage: NSImage = DesignSystemImages.Glyphs.Size16.bookmarks
    let moreOptionsbuttonImage: NSImage = DesignSystemImages.Glyphs.Size16.menuLines
    let overflowButtonImage: NSImage = DesignSystemImages.Glyphs.Size16.chevronDoubleRight
    let aiChatButtonImage: NSImage = DesignSystemImages.Glyphs.Size16.aiChat
}

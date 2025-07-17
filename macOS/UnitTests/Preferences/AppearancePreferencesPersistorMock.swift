//
//  AppearancePreferencesPersistorMock.swift
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

import Bookmarks
import Foundation
@testable import DuckDuckGo_Privacy_Browser

struct AppearancePreferencesPersistorMock: AppearancePreferencesPersistor {

    var isFavoriteVisible: Bool
    var isContinueSetUpVisible: Bool
    var continueSetUpCardsLastDemonstrated: Date?
    var continueSetUpCardsNumberOfDaysDemonstrated: Int
    var continueSetUpCardsClosed: Bool
    var isOmnibarVisible: Bool
    var isProtectionsReportVisible: Bool
    var isSearchBarVisible: Bool
    var showFullURL: Bool
    var currentThemeName: String
    var favoritesDisplayMode: String?
    var showBookmarksBar: Bool
    var bookmarksBarAppearance: BookmarksBarAppearance
    var homeButtonPosition: HomeButtonPosition
    var homePageCustomBackground: String?
    var centerAlignedBookmarksBar: Bool
    var didDismissHomePagePromotion: Bool
    var showTabsAndBookmarksBarOnFullScreen: Bool

    init(
        showFullURL: Bool = false,
        currentThemeName: String = ThemeName.systemDefault.rawValue,
        favoritesDisplayMode: String? = FavoritesDisplayMode.displayNative(.desktop).description,
        isContinueSetUpVisible: Bool = true,
        continueSetUpCardsLastDemonstrated: Date? = nil,
        continueSetUpCardsNumberOfDaysDemonstrated: Int = 0,
        continueSetUpCardsClosed: Bool = false,
        isFavoriteVisible: Bool = true,
        isOmnibarVisible: Bool = true,
        isProtectionsReportVisible: Bool = true,
        isSearchBarVisible: Bool = true,
        showBookmarksBar: Bool = true,
        bookmarksBarAppearance: BookmarksBarAppearance = .alwaysOn,
        homeButtonPosition: HomeButtonPosition = .right,
        homePageCustomBackground: String? = nil,
        centerAlignedBookmarksBar: Bool = true,
        didDismissHomePagePromotion: Bool = true,
        showTabsAndBookmarksBarOnFullScreen: Bool = false
    ) {
        self.showFullURL = showFullURL
        self.currentThemeName = currentThemeName
        self.favoritesDisplayMode = favoritesDisplayMode
        self.isContinueSetUpVisible = isContinueSetUpVisible
        self.continueSetUpCardsLastDemonstrated = continueSetUpCardsLastDemonstrated
        self.continueSetUpCardsNumberOfDaysDemonstrated = continueSetUpCardsNumberOfDaysDemonstrated
        self.continueSetUpCardsClosed = continueSetUpCardsClosed
        self.isOmnibarVisible = isOmnibarVisible
        self.isFavoriteVisible = isFavoriteVisible
        self.isProtectionsReportVisible = isProtectionsReportVisible
        self.isSearchBarVisible = isSearchBarVisible
        self.showBookmarksBar = showBookmarksBar
        self.bookmarksBarAppearance = bookmarksBarAppearance
        self.homeButtonPosition = homeButtonPosition
        self.homePageCustomBackground = homePageCustomBackground
        self.centerAlignedBookmarksBar = centerAlignedBookmarksBar
        self.didDismissHomePagePromotion = didDismissHomePagePromotion
        self.showTabsAndBookmarksBarOnFullScreen = showTabsAndBookmarksBarOnFullScreen
    }
}

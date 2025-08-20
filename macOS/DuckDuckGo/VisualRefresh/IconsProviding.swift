//
//  IconsProviding.swift
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
import NetworkProtectionUI
import AppKit

protocol IconsProviding {
    var addressBarCookiesIconsProvider: AddressBarCookiesIconsProviding { get }
    var navigationToolbarIconsProvider: NavigationToolbarIconsProviding { get }
    var moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding { get }
    var fireButtonStyleProvider: FireButtonIconStyleProviding { get }
    var settingsIconProvider: SettingsIconsProviding { get }
    var bookmarksIconsProvider: BookmarksIconsProviding { get }
    var vpnNavigationIconsProvider: IconProvider { get }
    var suggestionsIconsProvider: SuggestionsIconsProviding { get }
    var addressBarButtonsIconsProvider: AddressBarPermissionButtonsIconsProviding { get }

    var fireInfoGraphic: NSImage { get }
}

final class LegacyIconsProvider: IconsProviding {
    var addressBarCookiesIconsProvider: AddressBarCookiesIconsProviding = LegacyAddressBarCookiesIconsProvider()
    var navigationToolbarIconsProvider: NavigationToolbarIconsProviding = LegacyNavigationToolbarIconsProvider()
    var moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding = LegacyMoreOptionsMenuIcons()
    var fireButtonStyleProvider: FireButtonIconStyleProviding = LegacyFireButtonIconStyleProvider()
    var settingsIconProvider: SettingsIconsProviding = LegacySettingsIconProvider()
    var bookmarksIconsProvider: BookmarksIconsProviding = LegacyBookmarksIconsProvider()
    var vpnNavigationIconsProvider: IconProvider = NavigationBarIconProvider()
    var suggestionsIconsProvider: SuggestionsIconsProviding = LegacySuggestionsIconsProvider()
    var addressBarButtonsIconsProvider: AddressBarPermissionButtonsIconsProviding = LegacyAddressBarPermissionButtonIconsProvider()
    var fireInfoGraphic: NSImage = .fireHeader
}

final class CurrentIconsProvider: IconsProviding {
    var addressBarCookiesIconsProvider: AddressBarCookiesIconsProviding = CurrentAddressBarCookiesIconsProvider()
    var navigationToolbarIconsProvider: NavigationToolbarIconsProviding = CurrentNavigationToolbarIconsProvider()
    var moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding = CurrentMoreOptionsMenuIcons()
    var fireButtonStyleProvider: FireButtonIconStyleProviding = CurrentFireButtonIconStyleProvider()
    var settingsIconProvider: SettingsIconsProviding = CurrentSettingsIconProvider()
    var bookmarksIconsProvider: BookmarksIconsProviding = CurrentBookmarksIconsProvider()
    var vpnNavigationIconsProvider: IconProvider = CurrentVPNNavigationBarIconProvider()
    var suggestionsIconsProvider: SuggestionsIconsProviding = CurrentSuggestionsIconsProvider()
    var addressBarButtonsIconsProvider: AddressBarPermissionButtonsIconsProviding = CurrentAddressBarPermissionButtonIconsProvider()
    var fireInfoGraphic: NSImage = .newFireHeader
}

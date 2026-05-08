//
//  UserText.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

struct UserText {

    static let favoritesWidgetGalleryDisplayName = NSLocalizedString("widget.gallery.search.and.favorites.display.name",
                                                                     value: "Search and Favorites",
                                                                     comment: "Display name for search and favorites widget in widget gallery")

    static let favoritesWidgetGalleryDescription = NSLocalizedString("widget.gallery.search.and.favorites.description",
                                                                     value: "Search or visit your favorite sites privately with just one tap.",
                                                                     comment: "Description of search and favorites widget in widget gallery")

    static let searchWidgetGalleryDisplayName = NSLocalizedString("widget.gallery.search.display.name",
                                                                  value: "Search",
                                                                  comment: "Display name for search only widget in widget gallery")

    static let searchWidgetGalleryDescription = NSLocalizedString("widget.gallery.search.description",
                                                                  value: "Quickly launch a private search in DuckDuckGo.",
                                                                  comment: "Description of search only widget in widget gallery")

    static let searchDuckDuckGo = NSLocalizedString("widget.search.duckduckgo",
                                                    value: "Search DuckDuckGo",
                                                    comment: "Placeholder text in search field on the search and favorites widget")

    static let quickActionsSearch = NSLocalizedString("widget.quickactions.search",
                                          value: "Search",
                                          comment: "Placeholder text in search field on the quick actions widget")

    static let noFavoritesMessage = NSLocalizedString("widget.no.favorites.message",
                                                      value: "Quickly visit your favorite sites.",
                                                      comment: "Message shown in the favorites widget empty state.")

    static let noFavoritesCTA = NSLocalizedString("widget.no.favorites.cta",
                                                  value: "Add Favorites",
                                                  comment: "CTA shown in the favorites widget empty state.")

    static let passwordsWidgetGalleryDisplayName = NSLocalizedString("widget.gallery.passwords.display.name",
                                                                  value: "Search Passwords",
                                                                  comment: "Display name for search passwords widget in widget gallery")


    static let passwordsWidgetGalleryDescription = NSLocalizedString("widget.gallery.passwords.description",
                                                                     value: "Quickly search your saved DuckDuckGo passwords.",
                                                                     comment: "Description of search passwords widget in widget gallery")
    static let passwords = NSLocalizedString("widget.passwords",
                                             value: "Search Passwords",
                                             comment: "Text in passwords widget")

    static let vpnWidgetGalleryDisplayName = NSLocalizedString("widget.gallery.vpn.display.name",
                                                               value: "VPN",
                                                               comment: "Display name for VPN widget in widget gallery")

    static let vpnWidgetGalleryDescription = NSLocalizedString("widget.gallery.vpn.description",
                                                               value: "View and manage your VPN connection. Requires a DuckDuckGo subscription.",
                                                               comment: "Description of VPN widget in widget gallery")

    static let vpnWidgetConnectedStatus = NSLocalizedString("widget.vpn.status.connected",
                                                            value: "VPN is On",
                                                            comment: "Message describing VPN connected status")

    static let vpnWidgetSnoozingStatus = NSLocalizedString("widget.vpn.status.snoozed",
                                                            value: "VPN is Snoozed",
                                                            comment: "Message describing VPN snoozing status")

    static let vpnWidgetDisconnectedStatus = NSLocalizedString("widget.vpn.status.disconnected",
                                                               value: "VPN is Off",
                                                               comment: "Message describing VPN disconnected status")

    static let vpnWidgetDisconnectedSubtitle = NSLocalizedString("widget.vpn.subtitle.disconnected",
                                                                 value: "Not connected",
                                                                 comment: "Subtitle describing VPN disconnected status")

    static let vpnWidgetConnectButton = NSLocalizedString("widget.vpn.button.connect",
                                                          value: "Connect",
                                                          comment: "VPN connect button text")

    static let vpnWidgetDisconnectButton = NSLocalizedString("widget.vpn.button.disconnect",
                                                             value: "Disconnect",
                                                             comment: "VPN disconnect button text")

    static let vpnWidgetLiveActivityVPNSnoozingStatusLabel = NSLocalizedString("widget.vpn.live-activity.label.snoozing",
                                                                     value: "VPN Snoozing",
                                                                     comment: "VPN Live Activity snoozing label text")

    static let vpnWidgetLiveActivityVPNActiveStatusLabel = NSLocalizedString("widget.vpn.live-activity.label.active",
                                                                     value: "VPN is On",
                                                                     comment: "VPN Live Activity active label text")

    static let vpnWidgetLiveActivityWakeUpButton = NSLocalizedString("widget.vpn.live-activity.button.wake-up",
                                                                     value: "Wake Up",
                                                                     comment: "VPN Live Activity wake up button text")

    static let vpnWidgetLiveActivityDismissButton = NSLocalizedString("widget.vpn.live-activity.button.dismiss",
                                                                      value: "Dismiss",
                                                                      comment: "VPN Live Activity dismiss button text")

    static func vpnWidgetSnoozingUntil(endDate: String) -> String {
        let localized = NSLocalizedString("widget.vpn.label.snoozing-until", value: "Until %@", comment: "Label for the snooze end date, e.g. 'Until 9:51 AM'")
        return localized.format(arguments: endDate)
    }

    // MARK: - Control Center Widget

    static let vpnControlWidgetOn = NSLocalizedString(
        "vpn.control.widget.on",
        value: "VPN is ON",
        comment: "Title for the control widget when enabled")

    static let vpnControlWidgetOff = NSLocalizedString(
        "vpn.control.widget.off",
        value: "VPN is OFF",
        comment: "Title for the control widget when disabled")

    static let vpnControlWidgetLocationUnknown = NSLocalizedString(
        "vpn.control.widget.location-unknown",
        value: "Unknown Location",
        comment: "Description for the control widget when the location is unknown")

    static let vpnControlWidgetConnecting = NSLocalizedString(
        "vpn.control.widget.connecting",
        value: "Connecting...",
        comment: "Description for the control widget when connecting")

    static let vpnControlWidgetDisconnecting = NSLocalizedString(
        "vpn.control.widget.disconnecting",
        value: "Disconnecting...",
        comment: "Description for the control widget when disconnecting")

    static let vpnControlWidgetNotConnected = NSLocalizedString(
        "vpn.control.widget.not-connected",
        value: "Not Connected",
        comment: "Description for the control widget when not connected")

    // MARK: - Misc...

    static let lockScreenSearchTitle = NSLocalizedString(
        "lock.screen.widget.search.title",
        value: "Private Search",
        comment: "Title shown to the user when adding the Search lock screen widget")

    static let lockScreenSearchDescription = NSLocalizedString(
        "lock.screen.widget.search.description",
        value: "Instantly start a private search in DuckDuckGo.",
        comment: "Description shown to the user when adding the Search lock screen widget")

    static let lockScreenFavoritesTitle = NSLocalizedString(
        "lock.screen.widget.favorites.title",
        value: "Favorites",
        comment: "Title shown to the user when adding the favorites lock screen widget")

    static let lockScreenFavoritesDescription = NSLocalizedString(
        "lock.screen.widget.favorites.description",
        value: "Quickly open your favorite websites with a tap.",
        comment: "Description shown to the user when adding the Search lock screen widget")

    static let lockScreenVoiceTitle = NSLocalizedString(
        "lock.screen.widget.voice.title",
        value: "Voice Search",
        comment: "Title shown to the user when adding the Voice Search lock screen widget")

    static let lockScreenVoiceDescription = NSLocalizedString(
        "lock.screen.widget.voice.description",
        value: "Instantly start a new private voice search in DuckDuckGo.",
        comment: "Description shown to the user when adding the Voice Search lock screen widget")

    static let lockScreenEmailTitle = NSLocalizedString(
        "lock.screen.widget.email.title",
        value: "Email Protection",
        comment: "Title shown to the user when adding the Email Protection lock screen widget")

    static let lockScreenEmailDescription = NSLocalizedString(
        "lock.screen.widget.email.description",
        value: "Instantly generate a new private Duck Address.",
        comment: "Description shown to the user when adding the Email Protection lock screen widget")

    static let lockScreenFireTitle = NSLocalizedString(
        "lock.screen.widget.fire.title",
        value: "Fire Button",
        comment: "Title shown to the user when adding the Fire Button lock screen widget")

    static let lockScreenFireDescription = NSLocalizedString(
        "lock.screen.widget.fire.description",
        value: "Instantly delete your browsing history and start a new private search in DuckDuckGo.",
        comment: "Description shown to the user when adding the Fire Button lock screen widget")

    static let lockScreenPasswordsTitle = NSLocalizedString(
        "lock.screen.widget.passwords.title",
        value: "Search Passwords",
        comment: "Title shown to the user when adding the Search Passwords lock screen widget")

    static let lockScreenPasswordsDescription = NSLocalizedString(
        "lock.screen.widget.passwords.description",
        value: "Quickly search your saved DuckDuckGo passwords.",
        comment: "Description shown to the user when adding the Search Passwords lock screen widget")

    static let lockScreenAIChatTitle = NSLocalizedString(
        "lock.screen.widget.aichat.title",
        value: "Duck.ai",
        comment: "Title shown to the user when adding the Duck.ai lock screen widget")

    static let lockScreenAIChatDescription = NSLocalizedString(
        "lock.screen.widget.aichat.description",
        value: "Quickly start a new AI chat in Duck.ai",
        comment: "Description shown to the user when adding the Duck.ai lock screen widget")

    static let lockScreenVoiceChatTitle = NSLocalizedString(
        "lock.screen.widget.voicechat.title",
        value: "Duck.ai Voice",
        comment: "Title shown to the user when adding the Duck.ai Voice lock screen widget")

    static let lockScreenVoiceChatDescription = NSLocalizedString(
        "lock.screen.widget.voicechat.description",
        value: "Quickly start a new voice chat in Duck.ai",
        comment: "Description shown to the user when adding the Duck.ai Voice lock screen widget")

    // MARK: - Quick Actions
    static let quickActionsWidgetGalleryDisplayName = NSLocalizedString("widget.gallery.customshortcuts.display.name",
                                                                  value: "Custom Shortcuts",
                                                                  comment: "Display name for quick actions widget in widget gallery")

    static let quickActionsWidgetGalleryDescription = NSLocalizedString("widget.gallery.customshortcuts.description",
                                                                  value: "Pick shortcuts to your favorite actions.",
                                                                  comment: "Description of quickActions widget in widget gallery")

    static let quickActionsWidgetEditLeftShortcutLabel = NSLocalizedString("widget.gallery.customshortcuts.edit.left",
                                                                  value: "Left Shortcut",
                                                                  comment: "Left label for editing custom shortcuts")

    static let quickActionsWidgetEditRightShortcutLabel = NSLocalizedString("widget.gallery.customshortcuts.edit.right",
                                                                  value: "Right Shortcut",
                                                                  comment: "Right label for editing custom shortcuts")

    static let quickActionsWidgetEditShortcutsTitle = NSLocalizedString("widget.gallery.customshortcuts.edit.title",
                                                                  value: "Configure Shortcuts",
                                                                  comment: "Title for editing custom shortcuts")

    static let quickActionsWidgetEditShortcutsDescription = NSLocalizedString("widget.gallery.customshortcuts.edit.description",
                                                                  value: "Choose your shortcuts",
                                                                  comment: "Description for editing custom shortcuts")

    // MARK: - Quick Actions Medium Configuration
    //
    // The four NSLocalizedString constants below are not consumed in Swift code.
    // The MediumConfigurationIntent references the same keys via
    // `LocalizedStringResource("...")`, which AppIntents requires inline at the
    // call site. These constants exist so the build phase's `extractLocStrings`
    // tool picks the keys up and writes them into Localizable.strings.

    static let quickActionsMediumWidgetEditShortcut1Label = NSLocalizedString("widget.gallery.medium.customshortcuts.edit.shortcut1",
                                                                  value: "Shortcut 1",
                                                                  comment: "Label for first shortcut slot in medium widget configuration")

    static let quickActionsMediumWidgetEditShortcut2Label = NSLocalizedString("widget.gallery.medium.customshortcuts.edit.shortcut2",
                                                                  value: "Shortcut 2",
                                                                  comment: "Label for second shortcut slot in medium widget configuration")

    static let quickActionsMediumWidgetEditShortcut3Label = NSLocalizedString("widget.gallery.medium.customshortcuts.edit.shortcut3",
                                                                  value: "Shortcut 3",
                                                                  comment: "Label for third shortcut slot in medium widget configuration")

    static let quickActionsMediumWidgetEditShortcut4Label = NSLocalizedString("widget.gallery.medium.customshortcuts.edit.shortcut4",
                                                                  value: "Shortcut 4",
                                                                  comment: "Label for fourth shortcut slot in medium widget configuration")

    // MARK: - Shortcut Option Display Representations
    //
    // Same pattern as above: ShortcutOption's `caseDisplayRepresentations` and
    // `typeDisplayRepresentation` reference these keys via `LocalizedStringResource`
    // inline. These NSLocalizedString constants feed `extractLocStrings`.

    static let shortcutOptionTypeName = NSLocalizedString("widget.shortcut.option.type-name",
                                                          value: "Shortcut Option",
                                                          comment: "Type name shown in the widget configuration picker for the shortcut option enum")

    static let shortcutOptionPasswords = NSLocalizedString("widget.shortcut.option.passwords",
                                                           value: "Passwords",
                                                           comment: "Display name shown in the widget configuration picker for the Passwords shortcut option")

    static let shortcutOptionDuckAI = NSLocalizedString("widget.shortcut.option.duck-ai",
                                                        value: "Duck.ai",
                                                        comment: "Display name shown in the widget configuration picker for the Duck.ai shortcut option")

    static let shortcutOptionDuckAIVoice = NSLocalizedString("widget.shortcut.option.duck-ai-voice",
                                                             value: "Duck.ai Voice",
                                                             comment: "Display name shown in the widget configuration picker for the Duck.ai Voice shortcut option")

    static let shortcutOptionVoiceSearch = NSLocalizedString("widget.shortcut.option.voice-search",
                                                             value: "Voice Search",
                                                             comment: "Display name shown in the widget configuration picker for the Voice Search shortcut option")

    static let shortcutOptionFavorites = NSLocalizedString("widget.shortcut.option.favorites",
                                                           value: "Favorites",
                                                           comment: "Display name shown in the widget configuration picker for the Favorites shortcut option")

    static let shortcutOptionDuckAddress = NSLocalizedString("widget.shortcut.option.duck-address",
                                                             value: "Duck Address",
                                                             comment: "Display name shown in the widget configuration picker for the Duck Address (email protection) shortcut option")

    static let shortcutOptionVPN = NSLocalizedString("widget.shortcut.option.vpn",
                                                     value: "VPN",
                                                     comment: "Display name shown in the widget configuration picker for the VPN shortcut option")

    static let shortcutOptionBookmarks = NSLocalizedString("widget.shortcut.option.bookmarks",
                                                           value: "Bookmarks",
                                                           comment: "Display name shown in the widget configuration picker for the Bookmarks shortcut option")

}

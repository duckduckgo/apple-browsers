//
//  UserText.swift
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


import Core
import Common

struct UserText {

    static let winBackCampaignMenuBadgeText = NSLocalizedString("win-back.campaign.menu.badge.text", value: "SAVE 25%", comment: "Text for the badge displayed on the Subscription menu item during the win-back campaign")

    static let settingsItemNewBadge = NSLocalizedString("settings.item.badge.new", value: "New", comment: "Copy for budge on settings item to show an item is new")
    
    public static let settingsTitle = NSLocalizedString("settings.title", value: "Settings", comment: "Title for the Settings View")
    public static let settingsOn = NSLocalizedString("settings.on", value: "On", comment: "Label describing a feature which is turned on")
    public static let settingsOff = NSLocalizedString("settings.off", value: "Off", comment: "Label describing a feature which is turned off")
    public static let settingsAlwaysOn = NSLocalizedString("settings.always.on", value: "Always On", comment: "Label describing a feature which is turned on always")
}

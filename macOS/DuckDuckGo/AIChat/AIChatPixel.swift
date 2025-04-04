//
//  AIChatPixel.swift
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
import PixelKit

/// This enum keeps pixels related to AI Chat (duck.ai)
/// > Related links:
/// [Original Pixel Triage](https://app.asana.com/0/69071770703008/1208619053222285/f)

enum AIChatPixel: PixelKitEventV2 {

    /// Event Trigger: AI Chat is opened via the ... Menu -> New AI Chat
    case aichatApplicationMenuAppClicked

    /// Event Trigger: AI Chat is opened via File -> New AI Chat
    case aichatApplicationMenuFileClicked

    /// Event Trigger: Can't find privacy config settings for AI Chat
    /// Anomaly Investigation:
    /// - Check if this is not a widespread issue. Sometimes users can change config data manually on macOS which could cause this
    case aichatNoRemoteSettingsFound(AIChatRemoteSettings.SettingsValue)

    /// Event Trigger: Address bar shortcut for AI Chat is turned on
    case aiChatSettingsAddressBarShortcutTurnedOn

    /// Event Trigger: Address bar shortcut for AI Chat is turned off
    case aiChatSettingsAddressBarShortcutTurnedOff

    /// Event Trigger: Application menu shortcut for AI Chat is turned off
    case aiChatSettingsApplicationMenuShortcutTurnedOff

    /// Event Trigger: Application menu shortcut for AI Chat is turned on
    case aiChatSettingsApplicationMenuShortcutTurnedOn

    /// Event Trigger: Duck.ai settings panel is displayed
    case aiChatSettingsDisplayed

    var name: String {
        switch self {
        case .aichatApplicationMenuAppClicked:
            return "m_mac_aichat_application-menu-app-clicked"
        case .aichatApplicationMenuFileClicked:
            return "m_mac_aichat_application-menu-file-clicked"
        case .aichatNoRemoteSettingsFound(let settings):
            return "m_mac_aichat_no_remote_settings_found-\(settings.rawValue.lowercased())"
        case .aiChatSettingsAddressBarShortcutTurnedOn:
            return "m_mac_aichat_settings_addressbar_on"
        case .aiChatSettingsAddressBarShortcutTurnedOff:
            return "m_mac_aichat_settings_addressbar_off"
        case .aiChatSettingsApplicationMenuShortcutTurnedOff:
            return "m_mac_aichat_settings_application_menu_off"
        case .aiChatSettingsApplicationMenuShortcutTurnedOn:
            return "m_mac_aichat_settings_application_menu_on"
        case .aiChatSettingsDisplayed:
            return "m_mac_aichat_settings_displayed"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var error: (any Error)? {
        nil
    }
}

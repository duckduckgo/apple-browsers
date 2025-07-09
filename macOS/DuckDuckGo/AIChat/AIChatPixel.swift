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
/// [Omnibar and Settings Pixel Triage](https://app.asana.com/0/1204167627774280/1209885580000745)
/// [Summarization Pixel Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210636012460969?focus=true)

enum AIChatPixel: PixelKitEventV2 {

    /// Event Trigger: AI Chat is opened via the ... Menu -> New Duck.ai Chat
    case aichatApplicationMenuAppClicked

    /// Event Trigger: AI Chat is opened via File -> New Duck.ai Chat
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
    ///
    /// - Note:
    /// This pixel is used in place of `SettingsPixel.settingsPaneOpened(.aiChat)`.
    /// Before removing it, verify that it's not needed for measuring settings interaction.
    case aiChatSettingsDisplayed

    /// Event Trigger: User clicks in the Omnibar duck.ai button
    case aiChatAddressBarButtonClicked

    // MARK: - Summarization

    /// Event Trigger: User triggers summarize action (either via keyboard shortcut or a context menu action)
    case aiChatSummarizeText(source: AIChatTextSummarizationRequest.Source)

    /// Event Trigger: User clicks "Show more" on a (collapsed by default) summarize prompt in Duck.ai tab or sidebar
    case aiChatSummarizePromptExpanded

    /// Event Trigger: User clicks the website link on a summarize prompt in Duck.ai tab or sidebar
    case aiChatSummarizeSourceLinkClicked

    // MARK: -

    var name: String {
        switch self {
        case .aichatApplicationMenuAppClicked:
            return "aichat_application-menu-app-clicked"
        case .aichatApplicationMenuFileClicked:
            return "aichat_application-menu-file-clicked"
        case .aichatNoRemoteSettingsFound(let settings):
            return "aichat_no_remote_settings_found-\(settings.rawValue.lowercased())"
        case .aiChatSettingsAddressBarShortcutTurnedOn:
            return "aichat_settings_addressbar_on"
        case .aiChatSettingsAddressBarShortcutTurnedOff:
            return "aichat_settings_addressbar_off"
        case .aiChatSettingsApplicationMenuShortcutTurnedOff:
            return "aichat_settings_application_menu_off"
        case .aiChatSettingsApplicationMenuShortcutTurnedOn:
            return "aichat_settings_application_menu_on"
        case .aiChatSettingsDisplayed:
            return "aichat_settings_displayed"
        case .aiChatAddressBarButtonClicked:
            return "aichat_addressbar_button_clicked"
        case .aiChatSummarizeText:
            return "aichat_summarize_text"
        case .aiChatSummarizePromptExpanded:
            return "aichat_summarize_prompt_expanded"
        case .aiChatSummarizeSourceLinkClicked:
            return "aichat_summarize_source_link_clicked"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .aichatApplicationMenuAppClicked,
                .aichatApplicationMenuFileClicked,
                .aichatNoRemoteSettingsFound,
                .aiChatSettingsAddressBarShortcutTurnedOn,
                .aiChatSettingsAddressBarShortcutTurnedOff,
                .aiChatSettingsApplicationMenuShortcutTurnedOff,
                .aiChatSettingsApplicationMenuShortcutTurnedOn,
                .aiChatSettingsDisplayed,
                .aiChatAddressBarButtonClicked,
                .aiChatSummarizePromptExpanded,
                .aiChatSummarizeSourceLinkClicked:
            return nil
        case .aiChatSummarizeText(let source):
            return ["source": source.rawValue]
        }
    }

    var error: (any Error)? {
        nil
    }
}

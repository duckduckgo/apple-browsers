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
/// [Sidebar Pixel Triage](https://app.asana.com/1/137249556945/project/1209671977594486/task/1210676151750614)
/// [Summarization Pixel Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210636012460969?focus=true)

enum AIChatPixel: PixelKitEvent {

    /// Event Trigger: AI Chat is opened via the ... Menu -> New Duck.ai Chat
    case aichatApplicationMenuAppClicked

    /// Event Trigger: AI Chat is opened via File -> New Duck.ai Chat
    case aichatApplicationMenuFileClicked

    /// Event Trigger: Can't find privacy config settings for AI Chat
    /// Anomaly Investigation:
    /// - Check if this is not a widespread issue. Sometimes users can change config data manually on macOS which could cause this
    case aichatNoRemoteSettingsFound(AIChatRemoteSettings.SettingsValue)

    /// Event Trigger: Global toggle for all AI Chat features is turned on
    case aiChatSettingsGlobalToggleTurnedOn

    /// Event Trigger: Global toggle for all AI Chat features is turned off
    case aiChatSettingsGlobalToggleTurnedOff

    /// Event Trigger: New Tab Page shortcut for AI Chat is turned on
    case aiChatSettingsNewTabPageShortcutTurnedOn

    /// Event Trigger: New Tab Page shortcut for AI Chat is turned off
    case aiChatSettingsNewTabPageShortcutTurnedOff

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
    case aiChatAddressBarButtonClicked(action: AIChatAddressBarAction)

    // MARK: - Sidebar

    /// Event Trigger: User opens a tab sidebar
    case aiChatSidebarOpened(source: AIChatSidebarOpenSource)

    /// Event Trigger: User closes a tab sidebar
    case aiChatSidebarClosed(source: AIChatSidebarCloseSource)

    /// Event Trigger: User expands the sidebar to a full-size tab
    case aiChatSidebarExpanded

    /// Event Trigger: User changes sidebar setting in AI Features settings
    /// This is a unique pixel (sent once per app installation)
    case aiChatSidebarSettingChanged

    // MARK: - Summarization

    /// Event Trigger: User triggers summarize action (either via keyboard shortcut or a context menu action)
    case aiChatSummarizeText(source: AIChatTextSummarizationRequest.Source)

    /// Event Trigger: User clicks the website link on a summarize prompt in Duck.ai tab or sidebar
    case aiChatSummarizeSourceLinkClicked

    /// Event Trigger: User triggers translate action
    case aiChatTranslateText

    /// Event Trigger: User clicks the website link on a translation prompt in Duck.ai tab or sidebar
    case aiChatTranslationSourceLinkClicked

    /// Event Trigger: User adds page context to the prompt using a button in the input field
    case aiChatPageContextAdded(automaticEnabled: Bool)

    /// Event Trigger: User removes page context from the prompt using a button in the input field
    case aiChatPageContextRemoved(automaticEnabled: Bool)

    // MARK: -

    var name: String {
        switch self {
        case .aichatApplicationMenuAppClicked:
            return "aichat_application-menu-app-clicked"
        case .aichatApplicationMenuFileClicked:
            return "aichat_application-menu-file-clicked"
        case .aichatNoRemoteSettingsFound(let settings):
            return "aichat_no_remote_settings_found-\(settings.rawValue.lowercased())"
        case .aiChatSettingsGlobalToggleTurnedOn:
            return "aichat_settings_global-toggle_on"
        case .aiChatSettingsGlobalToggleTurnedOff:
            return "aichat_settings_global-toggle_off"
        case .aiChatSettingsNewTabPageShortcutTurnedOn:
            return "aichat_settings_new-tab-page_on"
        case .aiChatSettingsNewTabPageShortcutTurnedOff:
            return "aichat_settings_new-tab-page_off"
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
        case .aiChatSidebarOpened:
            return "aichat_sidebar_opened"
        case .aiChatSidebarClosed:
            return "aichat_sidebar_closed"
        case .aiChatSidebarExpanded:
            return "aichat_sidebar_expanded"
        case .aiChatSidebarSettingChanged:
            return "aichat_sidebar_setting_changed_u"
        case .aiChatSummarizeText:
            return "aichat_summarize_text"
        case .aiChatSummarizeSourceLinkClicked:
            return "aichat_summarize_source_link_clicked"
        case .aiChatTranslateText:
            return "aichat_translate_text"
        case .aiChatTranslationSourceLinkClicked:
            return "aichat_translation_source_link_clicked"
        case .aiChatPageContextAdded:
            return "aichat_page_context_added"
        case .aiChatPageContextRemoved:
            return "aichat_page_context_removed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .aichatApplicationMenuAppClicked,
                .aichatApplicationMenuFileClicked,
                .aichatNoRemoteSettingsFound,
                .aiChatSettingsGlobalToggleTurnedOn,
                .aiChatSettingsGlobalToggleTurnedOff,
                .aiChatSettingsNewTabPageShortcutTurnedOn,
                .aiChatSettingsNewTabPageShortcutTurnedOff,
                .aiChatSettingsAddressBarShortcutTurnedOn,
                .aiChatSettingsAddressBarShortcutTurnedOff,
                .aiChatSettingsApplicationMenuShortcutTurnedOff,
                .aiChatSettingsApplicationMenuShortcutTurnedOn,
                .aiChatSettingsDisplayed,
                .aiChatSidebarExpanded,
                .aiChatSidebarSettingChanged,
                .aiChatSummarizeSourceLinkClicked,
                .aiChatTranslateText,
                .aiChatTranslationSourceLinkClicked:
            return nil
        case .aiChatAddressBarButtonClicked(let action):
            return ["action": action.rawValue]
        case .aiChatSidebarOpened(let source):
            return ["source": source.rawValue]
        case .aiChatSidebarClosed(let source):
            return ["source": source.rawValue]
        case .aiChatSummarizeText(let source):
            return ["source": source.rawValue]
        case .aiChatPageContextAdded(let automaticEnabled), .aiChatPageContextRemoved(let automaticEnabled):
            return ["automaticEnabled": String(automaticEnabled)]
        }
    }

}

// MARK: - Parameter values

/// Action performed when address bar button is clicked
enum AIChatAddressBarAction: String, CaseIterable {
    case sidebar = "sidebar"
    case tab = "tab"
    case tabWithPrompt = "tab-with-prompt"
}

/// Source of AI Chat sidebar open action
enum AIChatSidebarOpenSource: String, CaseIterable {
    case addressBarButton = "address-bar-button"
    case summarization = "summarization"
    case serp = "serp"
    case contextMenu = "context-menu"
    case translation = "translation"
}

/// Source of AI Chat sidebar close action
enum AIChatSidebarCloseSource: String, CaseIterable {
    case addressBarButton = "address-bar-button"
    case sidebarCloseButton = "sidebar-close-button"
    case contextMenu = "context-menu"
}

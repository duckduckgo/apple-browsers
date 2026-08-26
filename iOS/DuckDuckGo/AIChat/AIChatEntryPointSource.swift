//
//  AIChatEntryPointSource.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Core
import PixelKit

/// Fires as `m_aichat_entry_point`; the `m_` prefix plus the platform suffix are applied by PixelKit.
enum AIChatEntryPointPixel: PixelKit.Event, PixelKitEventWithCustomPrefix {

    case entryPoint

    var name: String { "aichat_entry_point" }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var namePrefix: String { "m_" }

    /// Shared so entry paths outside `MainViewController` can report too.
    static func fire(source: AIChatEntryPointSource,
                     duckAIEnabled: Bool,
                     toggleEnabled: Bool,
                     opensNewTab: Bool,
                     hasPrompt: Bool) {
        PixelKit.fire(AIChatEntryPointPixel.entryPoint, frequency: .dailyAndCount, withAdditionalParameters: [
            PixelParameters.source: source.rawValue,
            "duckai_enabled": String(duckAIEnabled),
            "toggle_enabled": String(toggleEnabled),
            "opens_new_tab": String(opensNewTab),
            "has_prompt": String(hasPrompt)
        ])
    }
}

public enum AIChatEntryPointSource: String {
    case addressBarPrompt = "address_bar_prompt"
    case addressBarIcon = "address_bar_icon"
    case addressBarShortcutChip = "address_bar_shortcut_chip"
    case addressBarEditingState = "address_bar_editing_state"
    case suggestionAskAI = "suggestion_ask_ai"
    case ipadTogglePrompt = "ipad_toggle_prompt"
    case browsingMenuNTP = "browsing_menu_ntp"
    case browsingMenuWebpage = "browsing_menu_webpage"
    case tabSwitcher = "tab_switcher"
    case tabsBarButton = "tabs_bar_button"
    case chatHistoryNewChat = "chat_history_new_chat"
    case chatHistoryOpenChat = "chat_history_open_chat"
    case voice
    case onboarding
    case directURL = "direct_url"
    case serp
    case iconShortcut = "icon_shortcut"
    case contextualChat = "contextual_chat"
    case widgetQuickActions = "widget_quick_actions"
    case widgetQuickActionsMedium = "widget_quick_actions_medium"
    case widgetFavorite = "widget_favorite"
    case widgetLockScreen = "widget_lock_screen"
    case widgetControlCenter = "widget_control_center"
    case siri
    case deepLinkOther = "deep_link_other"
}

extension AIChatEntryPointSource {

    /// Resolves the `source` parameter a Duck.ai deep link carries. Falls back to `.deepLinkOther`
    /// for links with no recognised source, e.g. the URL scheme invoked from outside the app.
    static func forDeepLink(_ url: URL) -> AIChatEntryPointSource {
        guard let rawValue = url.getParameter(named: WidgetSourceType.sourceKey) else { return .deepLinkOther }
        if let widgetSource = WidgetSourceType(rawValue: rawValue) {
            return widgetSource.aiChatEntryPointSource
        }
        // `AIVoiceChatIntent` writes this one, and it is not a `WidgetSourceType`.
        return rawValue == VoiceEntryPointSource.siri.rawValue ? .siri : .deepLinkOther
    }

    /// Names the page behind an `openAIChat` user-script request so it is not reported as a typed
    /// address. `nil` for duck.ai and debug hosts, which have no entry of their own.
    static func forFrontEndOpenRequest(messageHost: String?) -> AIChatEntryPointSource? {
        guard let messageHost, messageHost == URL.ddg.host else { return nil }
        return .serp
    }
}

extension WidgetSourceType {

    var aiChatEntryPointSource: AIChatEntryPointSource {
        switch self {
        case .quickActions: return .widgetQuickActions
        case .quickActionsMedium: return .widgetQuickActionsMedium
        case .favorite: return .widgetFavorite
        case .lockscreenComplication: return .widgetLockScreen
        case .controlCenter: return .widgetControlCenter
        }
    }
}

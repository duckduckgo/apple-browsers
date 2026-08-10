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
enum AIChatEntryPointPixel: PixelKitEvent, PixelKitEventWithCustomPrefix {

    case entryPoint

    var name: String { "aichat_entry_point" }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var namePrefix: String { "m_" }

    /// Shared so entry paths outside `MainViewController` can report too. Prefer
    /// `MainViewController.fireAIChatEntryPointPixel`, which also records the source for `origin`.
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

/// Where a Duck.ai entry began. Reported as `source` on `m_aichat_entry_point`;
/// the raw values are a dashboard contract — renaming one breaks its series.
enum AIChatEntryPointSource: String {
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
    case iconShortcut = "icon_shortcut"
    case restoredTab = "restored_tab"
    case contextualChat = "contextual_chat"
    case deepLinkOther = "deep_link_other"
}

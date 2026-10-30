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
import AIChat
import Core
import PixelKit

/// Fires as `m_aichat_entry_point`; the `m_` prefix plus the platform suffix are applied by PixelKit.
enum AIChatEntryPointPixel: PixelKit.Event {
    /// This pixel signature is non-standard and not aligned to the current PixelKit defaults. This policy freezes the signature to a legacy, and incorrect, suffix ordering.
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyBeforeFrequencySuffix }

    case entryPoint

    var name: String { "aichat_entry_point" }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var namePrefix: PixelKitNamePrefix { .custom("m_") }

    /// Fired only through `MainViewController.fireAIChatEntryPointPixel`, which also starts the Duck.ai entry wide event.
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

public enum AIChatEntryPointSource: String, CaseIterable {
    case addressBarPrompt = "address_bar_prompt"
    case addressBarIcon = "address_bar_icon"
    case addressBarShortcutChip = "address_bar_shortcut_chip"
    case addressBarEditingState = "address_bar_editing_state"
    case suggestionAskAI = "suggestion_ask_ai"
    case ipadTogglePrompt = "ipad_toggle_prompt"
    case browsingMenuNTP = "browsing_menu_ntp"
    case browsingMenuWebpage = "browsing_menu_webpage"
    case browsingMenuDuckAI = "browsing_menu_duckai"
    case duckAINewChat = "duck_ai_new_chat"
    case tabSwitcher = "tab_switcher"
    case tabSwitcherExistingChat = "tab_switcher_existing_chat"
    case tabsBarExistingChat = "tabs_bar_existing_chat"
    case tabsBarButton = "tabs_bar_button"
    case newTabLongPressMenu = "new_tab_long_press_menu"
    case chatHistoryNewChat = "chat_history_new_chat"
    case chatHistoryOpenChat = "chat_history_open_chat"
    case chatHistoryViewAll = "chat_history_view_all"
    case voice
    case onboarding
    case subscriptionOnboarding = "subscription_onboarding"
    case paidSettings = "paid_settings"
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
    case returnToChatCard = "return_to_chat_card"
    case ddgHomepage = "ddg_homepage"
}

extension AIChatEntryPointSource {

    /// Doors where the address bar hands a typed prompt to the Duck.ai page, which reports it as its own.
    var handsOverAddressBarPrompt: Bool {
        switch self {
        case .addressBarPrompt, .addressBarEditingState, .suggestionAskAI, .ipadTogglePrompt: return true
        default: return false
        }
    }

    /// Opens Duck.ai from Settings → Subscription and the subscription welcome page.
    static let paidSettingsDeepLink = AppDeepLinkSchemes.openAIChat.url
        .appendingParameter(name: WidgetSourceType.sourceKey, value: AIChatEntryPointSource.paidSettings.rawValue)

    /// Resolves the `source` parameter a Duck.ai deep link carries. Falls back to `.deepLinkOther`
    /// for links with no recognised source, e.g. the URL scheme invoked from outside the app.
    static func forDeepLink(_ url: URL) -> AIChatEntryPointSource {
        guard let rawValue = url.getParameter(named: WidgetSourceType.sourceKey) else { return .deepLinkOther }
        if let widgetSource = WidgetSourceType(rawValue: rawValue) {
            return widgetSource.aiChatEntryPointSource
        }
        // `AIVoiceChatIntent` and Settings → Subscription write these, and they are not a `WidgetSourceType`.
        switch rawValue {
        case VoiceEntryPointSource.siri.rawValue: return .siri
        case AIChatEntryPointSource.paidSettings.rawValue: return .paidSettings
        default: return .deepLinkOther
        }
    }

    /// Names the page behind an `openAIChat` user-script request so it is not reported as a typed
    /// address. `nil` for duck.ai and debug hosts, which have no entry of their own.
    static func forFrontEndOpenRequest(messageHost: String?, pageURL: URL?) -> AIChatEntryPointSource? {
        if pageURL?.isDuckDuckGoHomepageEntry == true { return .ddgHomepage }
        guard let messageHost, messageHost == URL.ddg.host else { return nil }
        return .serp
    }

    /// Attributes a navigation the page itself started into Duck.ai. The DuckDuckGo homepage is named
    /// whatever started it; elsewhere only a link the user activated counts, as `serp` from the search
    /// results page and `direct_url` from any other page.
    static func forInPageNavigation(from currentURL: URL?, to targetURL: URL, isLinkActivation: Bool) -> AIChatEntryPointSource? {
        guard targetURL.isDuckAIURL, currentURL?.isDuckAIURL != true else { return nil }
        if currentURL?.isDuckDuckGoHomepageEntry == true { return .ddgHomepage }
        guard isLinkActivation else { return nil }
        return currentURL?.isDuckDuckGoSearch == true ? .serp : .directURL
    }

    /// Doors that are a link the user followed, which also count as a direct navigation.
    var isFollowedLink: Bool {
        self == .serp || self == .directURL
    }
}

private extension URL {
    /// The homepage proper: `duckduckgo.com/?ia=chat` shares its shape but is a Duck.ai page.
    var isDuckDuckGoHomepageEntry: Bool { isDuckDuckGoHomepage && !isDuckAIURL }
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

//
//  AIChatEntryPointSourceTests.swift
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

import Testing
@testable import Core
@testable import DuckDuckGo

@Suite("AI Chat Entry Point Source")
struct AIChatEntryPointSourceTests {

    private func deepLink(source: String?) -> URL {
        let url = AppDeepLinkSchemes.openAIChat.url
        guard let source else { return url }
        return url.appendingParameter(name: WidgetSourceType.sourceKey, value: source)
    }

    @available(iOS 16, *)
    @Test("Every widget source resolves to its own entry point", .timeLimit(.minutes(1)))
    func widgetSourcesResolve() {
        let expected: [WidgetSourceType: AIChatEntryPointSource] = [
            .quickActions: .widgetQuickActions,
            .quickActionsMedium: .widgetQuickActionsMedium,
            .favorite: .widgetFavorite,
            .lockscreenComplication: .widgetLockScreen,
            .controlCenter: .widgetControlCenter
        ]

        for (widgetSource, entryPoint) in expected {
            #expect(AIChatEntryPointSource.forDeepLink(deepLink(source: widgetSource.rawValue)) == entryPoint)
        }
    }

    /// `AIVoiceChatIntent` writes this source and it is not a `WidgetSourceType`, so it needs
    /// its own branch or Siri chats fall into the unattributed bucket.
    @available(iOS 16, *)
    @Test("Siri shortcut resolves to siri", .timeLimit(.minutes(1)))
    func siriSourceResolves() {
        let url = AppDeepLinkSchemes.openAIVoiceChat.url
            .appendingParameter(name: WidgetSourceType.sourceKey, value: VoiceEntryPointSource.siri.rawValue)

        #expect(AIChatEntryPointSource.forDeepLink(url) == .siri)
    }

    @available(iOS 16, *)
    @Test("A deep link with no source falls back to deep_link_other", .timeLimit(.minutes(1)))
    func missingSourceFallsBack() {
        #expect(AIChatEntryPointSource.forDeepLink(deepLink(source: nil)) == .deepLinkOther)
    }

    @available(iOS 16, *)
    @Test("An unrecognised source falls back to deep_link_other", .timeLimit(.minutes(1)))
    func unknownSourceFallsBack() {
        #expect(AIChatEntryPointSource.forDeepLink(deepLink(source: "widget.something.new")) == .deepLinkOther)
    }

    @available(iOS 16, *)
    @Test("A front-end open request from the search results page resolves to serp", .timeLimit(.minutes(1)))
    func serpOpenRequestResolves() {
        let serp = URL(string: "https://duckduckgo.com/?q=test&ia=web")!
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: URL.ddg.host, pageURL: serp) == .serp)
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: URL.ddg.host, pageURL: nil) == .serp)
    }

    @available(iOS 16, *)
    @Test("A front-end open request from the homepage resolves to ddg_homepage", .timeLimit(.minutes(1)))
    func homepageOpenRequestResolves() {
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: URL.ddg.host, pageURL: homepage) == .ddgHomepage)
    }

    /// `duckduckgo.com/?ia=chat` has the homepage's shape but is a Duck.ai page, so it keeps the host mapping.
    @available(iOS 16, *)
    @Test("A front-end open request from a duckduckgo.com chat page is not a homepage entry", .timeLimit(.minutes(1)))
    func chatPageOpenRequestIsNotHomepage() {
        let chatOnDDG = URL(string: "https://duckduckgo.com/?ia=chat")!
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: URL.ddg.host, pageURL: chatOnDDG) == .serp)
    }

    /// Returning nil leaves the caller's own fallback in place rather than mislabelling the entry.
    @available(iOS 16, *)
    @Test("Other hosts have no front-end open request source", .timeLimit(.minutes(1)))
    func otherHostsResolveToNil() {
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: URL.duckAi.host, pageURL: URL.duckAi) == nil)
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: "localhost:8080", pageURL: nil) == nil)
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: nil, pageURL: nil) == nil)
    }

    /// The raw values are a dashboard contract: renaming one silently breaks its series.
    @available(iOS 16, *)
    @Test("Entry point raw values are stable", .timeLimit(.minutes(1)))
    func rawValues() {
        #expect(AIChatEntryPointSource.widgetQuickActions.rawValue == "widget_quick_actions")
        #expect(AIChatEntryPointSource.widgetQuickActionsMedium.rawValue == "widget_quick_actions_medium")
        #expect(AIChatEntryPointSource.widgetFavorite.rawValue == "widget_favorite")
        #expect(AIChatEntryPointSource.widgetLockScreen.rawValue == "widget_lock_screen")
        #expect(AIChatEntryPointSource.widgetControlCenter.rawValue == "widget_control_center")
        #expect(AIChatEntryPointSource.siri.rawValue == "siri")
        #expect(AIChatEntryPointSource.deepLinkOther.rawValue == "deep_link_other")
        #expect(AIChatEntryPointSource.serp.rawValue == "serp")
        #expect(AIChatEntryPointSource.directURL.rawValue == "direct_url")
        #expect(AIChatEntryPointSource.returnToChatCard.rawValue == "return_to_chat_card")
        #expect(AIChatEntryPointSource.tabSwitcherExistingChat.rawValue == "tab_switcher_existing_chat")
        #expect(AIChatEntryPointSource.ddgHomepage.rawValue == "ddg_homepage")
    }

    // MARK: - In-page navigations

    private let homepage = URL(string: "https://duckduckgo.com/")!
    private let duckAIChat = URL(string: "https://duck.ai/chat?ia=chat&origin=funnel_home_website&q=hello&prompt=1")!

    @available(iOS 16, *)
    @Test("A navigation the DuckDuckGo homepage starts into Duck.ai resolves to ddg_homepage", .timeLimit(.minutes(1)))
    func homepageNavigationResolves() {
        let homepageWithParams = URL(string: "https://duckduckgo.com/?atb=v550-1")!
        #expect(AIChatEntryPointSource.forInPageNavigation(from: homepage, to: duckAIChat) == .ddgHomepage)
        #expect(AIChatEntryPointSource.forInPageNavigation(from: homepageWithParams, to: duckAIChat) == .ddgHomepage)
    }

    /// Only the homepage is attributed; links into Duck.ai from other pages stay unattributed on purpose.
    @available(iOS 16, *)
    @Test("Navigations from other pages have no in-page source", .timeLimit(.minutes(1)))
    func otherPagesResolveToNil() {
        #expect(AIChatEntryPointSource.forInPageNavigation(from: URL(string: "https://duckduckgo.com/?q=test")!, to: duckAIChat) == nil)
        #expect(AIChatEntryPointSource.forInPageNavigation(from: URL(string: "https://example.com/")!, to: duckAIChat) == nil)
        #expect(AIChatEntryPointSource.forInPageNavigation(from: URL(string: "https://duckduckgo.com/?ia=chat")!, to: duckAIChat) == nil)
        #expect(AIChatEntryPointSource.forInPageNavigation(from: nil, to: duckAIChat) == nil)
    }

    @available(iOS 16, *)
    @Test("Homepage navigations that do not reach Duck.ai have no in-page source", .timeLimit(.minutes(1)))
    func homepageToWebResolvesToNil() {
        #expect(AIChatEntryPointSource.forInPageNavigation(from: homepage, to: URL(string: "https://example.com/")!) == nil)
        #expect(AIChatEntryPointSource.forInPageNavigation(from: homepage, to: URL(string: "https://duckduckgo.com/?q=test")!) == nil)
    }
}

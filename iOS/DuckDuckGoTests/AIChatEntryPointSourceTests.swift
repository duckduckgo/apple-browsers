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
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: URL.ddg.host) == .serp)
    }

    /// Returning nil leaves the caller's own fallback in place rather than mislabelling the entry.
    @available(iOS 16, *)
    @Test("Other hosts have no front-end open request source", .timeLimit(.minutes(1)))
    func otherHostsResolveToNil() {
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: URL.duckAi.host) == nil)
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: "localhost:8080") == nil)
        #expect(AIChatEntryPointSource.forFrontEndOpenRequest(messageHost: nil) == nil)
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
    }
}

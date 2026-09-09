//
//  AIChatBrowserToolsService.swift
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

import AIChat
import FeatureFlags_macOS
import Foundation
import PrivacyConfig

/// App-wide owner of the Duck.ai browser tools bridge: the MCP sessions, the tool catalog, and
/// the remote-config gating behind them.
///
/// One instance per app rather than per web view, because a session belongs to the Duck.ai *owner
/// tab* — a sidebar and the tab it is docked to share one — while each web view gets its own
/// `AIChatUserScript`.
@MainActor
final class AIChatBrowserToolsService {

    /// Identifies this browser in the MCP `initialize` result. The Windows browser reports
    /// `windows-browser`.
    static let serverName = "macos-browser"

    let sessions = AIChatMCPSessionStore()
    let catalog: BrowserToolCatalog

    private let configuration: AIChatBrowserToolsConfiguration

    /// Reported to the front end as `supportsBrowserTools`. The front end must not open a session
    /// when this is false, which also protects against version skew.
    var isEnabled: Bool { configuration.isEnabled }

    init(featureFlagger: FeatureFlagger, tools: [any BrowserTool] = []) {
        let configuration = AIChatBrowserToolsConfiguration(featureFlagger: featureFlagger)
        self.configuration = configuration
        self.catalog = BrowserToolCatalog(tools: tools, configuration: configuration)
    }
}

/// Maps the browser-tools remote-config sub-features onto macOS feature flags.
///
/// A tool's `name` is its sub-feature's raw value, so the two cannot drift apart: adding a
/// sub-feature is a compile error here until it is mapped.
@MainActor
final class AIChatBrowserToolsConfiguration: BrowserToolsConfiguration {

    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var isEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatBrowserTools)
    }

    func isToolEnabled(named name: String) -> Bool {
        guard isEnabled,
              let subfeature = AIChatBrowserToolsSubfeature(rawValue: name),
              let flag = Self.featureFlag(for: subfeature) else { return false }
        return featureFlagger.isFeatureOn(flag)
    }

    private static func featureFlag(for subfeature: AIChatBrowserToolsSubfeature) -> FeatureFlag? {
        switch subfeature {
        case .featureEnabled: nil // The parent gate, not a tool.
        case .listOpenTabs: .aiChatBrowserToolListOpenTabs
        case .searchHistory: .aiChatBrowserToolSearchHistory
        case .switchToTab: .aiChatBrowserToolSwitchToTab
        case .readTabContent: .aiChatBrowserToolReadTabContent
        case .findInPage: .aiChatBrowserToolFindInPage
        case .highlightInPage: .aiChatBrowserToolHighlightInPage
        }
    }
}

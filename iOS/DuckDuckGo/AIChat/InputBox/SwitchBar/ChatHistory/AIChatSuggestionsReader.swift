//
//  AIChatSuggestionsReader.swift
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

import AIChat
import BrowserServicesKit
import Common
import Foundation
import os.log
import PrivacyConfig

// MARK: - Protocol

protocol AIChatSuggestionsReading {
    /// Maximum number of chat history items to display, from privacy config settings.
    var maxHistoryCount: Int { get }

    /// Fetches AI chat suggestions from duck.ai.
    /// - Parameters:
    ///   - query: Optional search query to filter results
    ///   - maxChats: Maximum number of recent chats to return
    /// - Returns: Tuple of pinned and recent suggestions. Returns empty arrays on failure.
    @MainActor
    func fetchSuggestions(query: String?, maxChats: Int) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion])

    /// Tears down the WebView and releases resources.
    /// Should be called when the AI chat mode is deactivated.
    @MainActor
    func tearDown()
}

// MARK: - AIChatSuggestionsReader

@MainActor
final class AIChatSuggestionsReader: AIChatSuggestionsReading {

    enum SettingsKey: String {
        case maxHistoryCount

        var defaultValue: Int {
            switch self {
            case .maxHistoryCount: return 2
            }
        }
    }

    private let suggestionsReader: SuggestionsReading
    private let privacyConfig: PrivacyConfigurationManaging?

    var maxHistoryCount: Int {
        let settings = privacyConfig?.privacyConfig.settings(for: .duckAiChatHistory)
        return (settings?[SettingsKey.maxHistoryCount.rawValue] as? Int) ?? SettingsKey.maxHistoryCount.defaultValue
    }

    init(featureFlagger: FeatureFlagger, privacyConfig: PrivacyConfigurationManaging) {
        self.suggestionsReader = SuggestionsReader(featureFlagger: featureFlagger, privacyConfig: privacyConfig)
        self.privacyConfig = privacyConfig
    }

    /// For testing - allows injecting a mock reader
    init(suggestionsReader: SuggestionsReading) {
        self.suggestionsReader = suggestionsReader
        self.privacyConfig = nil
    }

    func fetchSuggestions(query: String?, maxChats: Int) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
        let result = await suggestionsReader.fetchSuggestions(query: query, maxChats: maxChats)

        switch result {
        case .success(let suggestions):
            return suggestions
        case .failure(let error):
            Logger.aiChat.error("Failed to fetch AI chat suggestions: \(error.localizedDescription)")
            return (pinned: [], recent: [])
        }
    }

    func tearDown() {
        suggestionsReader.tearDown()
    }
}

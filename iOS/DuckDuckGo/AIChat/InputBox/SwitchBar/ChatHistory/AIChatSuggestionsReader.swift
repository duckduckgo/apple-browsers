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
    /// Fetches AI chat suggestions from duck.ai.
    /// - Parameters:
    ///   - query: Optional search query to filter results
    ///   - maxChats: Maximum number of recent (non-pinned) chats to return
    /// - Returns: Tuple of pinned and recent suggestions. Returns empty arrays on failure.
    @MainActor
    func fetchSuggestions(query: String?, maxChats: Int) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion])

    /// Tears down the WebView and releases resources.
    /// Should be called when the AI chat mode is deactivated.
    @MainActor
    func tearDown()
}

// MARK: - AIChatSuggestionsReader

/// Wrapper around SuggestionsReader that provides a simpler API for iOS.
/// Feature flag checks should be done by the caller.
@MainActor
final class AIChatSuggestionsReader: AIChatSuggestionsReading {

    private let suggestionsReader: SuggestionsReading

    init(featureFlagger: FeatureFlagger, privacyConfig: PrivacyConfigurationManaging) {
        self.suggestionsReader = SuggestionsReader(featureFlagger: featureFlagger, privacyConfig: privacyConfig)
    }

    /// For testing - allows injecting a mock reader
    init(suggestionsReader: SuggestionsReading) {
        self.suggestionsReader = suggestionsReader
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

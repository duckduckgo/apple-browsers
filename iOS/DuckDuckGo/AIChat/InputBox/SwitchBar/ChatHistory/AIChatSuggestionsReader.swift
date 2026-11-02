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
import FoundationExtensions
import Foundation
import os.log
import PrivacyConfig

// MARK: - Protocol

@MainActor
protocol AIChatSuggestionsReading {
    /// Maximum number of chat history items to display, from privacy config settings.
    var maxHistoryCount: Int { get }

    /// Fetches AI chat suggestions from duck.ai.
    /// - Parameters:
    ///   - query: Optional search query to filter results
    ///   - maxChats: Maximum number of recent chats to return
    /// - Returns: Tuple of pinned and recent suggestions. Returns empty arrays on failure.
    func fetchSuggestions(query: String?, maxChats: Int) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion])

    /// Tears down the WebView and releases resources.
    /// Should be called when the AI chat mode is deactivated.
    func tearDown()
}

// MARK: - AIChatSuggestionsReader

@MainActor
final class AIChatSuggestionsReader: AIChatSuggestionsReading {
    private let suggestionsReader: SuggestionsReading
    private let historySettings: AIChatHistorySettings

    var maxHistoryCount: Int {
        historySettings.maxHistoryCount
    }

    init(suggestionsReader: SuggestionsReading, historySettings: AIChatHistorySettings) {
        self.suggestionsReader = suggestionsReader
        self.historySettings = historySettings
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

// MARK: - Recent chats

extension AIChatSuggestionsReader {

    /// Fire mode reads Fire storage only: the webview fallback would surface regular chats.
    static func makeRecentChatsReader(isFireMode: Bool,
                                      nativeStorageHandler: DuckAiNativeStorageHandling?,
                                      fireModeStorageHandler: DuckAiNativeStorageHandling?,
                                      featureFlagger: FeatureFlagger,
                                      privacyConfig: PrivacyConfigurationManaging) -> AIChatSuggestionsReading {
        let historySettings = AIChatHistorySettings(privacyConfig: privacyConfig)
        guard isFireMode else {
            let reader = SuggestionsReader(featureFlagger: featureFlagger,
                                           privacyConfig: privacyConfig,
                                           nativeStorageHandler: nativeStorageHandler,
                                           featureFlagProvider: AIChatFeatureFlagProvider(featureFlagger: featureFlagger))
            return AIChatSuggestionsReader(suggestionsReader: reader, historySettings: historySettings)
        }
        return makeFireModeReader(storageHandler: fireModeStorageHandler, historySettings: historySettings)
    }

    private static func makeFireModeReader(storageHandler: DuckAiNativeStorageHandling?,
                                           historySettings: AIChatHistorySettings) -> AIChatSuggestionsReading {
        guard let storageHandler else { return NilSuggestionsReader() }
        return AIChatSuggestionsReader(suggestionsReader: LocalSuggestionsReader(storageHandler: storageHandler),
                                       historySettings: historySettings)
    }
}

// MARK: - NilSuggestionsReader

@MainActor
final class NilSuggestionsReader: AIChatSuggestionsReading {
    var maxHistoryCount: Int = 0

    func fetchSuggestions(query: String?, maxChats: Int) async -> (pinned: [AIChat.AIChatSuggestion], recent: [AIChat.AIChatSuggestion]) {
        return ([], [])
    }

    func tearDown() {}
}

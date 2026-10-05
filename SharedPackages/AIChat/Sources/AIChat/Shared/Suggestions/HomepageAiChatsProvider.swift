//
//  HomepageAiChatsProvider.swift
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

// MARK: - Wire types

/// `getAIChats` params from the duckduckgo.com homepage.
public struct HomepageAiChatsRequest: Decodable, Equatable {
    public let query: String?
    public let maxChats: Int?

    public init(query: String? = nil, maxChats: Int? = nil) {
        self.query = query
        self.maxChats = maxChats
    }
}

/// `getAIChats` response. Pinned chats come first, then recent ones by last edit.
/// Carries no message content: the homepage only lists titles.
public struct HomepageAiChatsResponse: Encodable, Equatable {
    public struct Chat: Encodable, Equatable {
        public let chatId: String
        public let title: String
        public let pinned: Bool
        /// ISO 8601, e.g. `"2026-01-19T11:48:10.903Z"`.
        public let lastEdit: String?
        public let model: String?
    }

    public let chats: [Chat]

    public static let empty = HomepageAiChatsResponse(chats: [])

    public init(chats: [Chat]) {
        self.chats = chats
    }

    init(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
        self.chats = (pinned + recent).map {
            Chat(chatId: $0.chatId,
                 title: $0.title,
                 pinned: $0.isPinned,
                 lastEdit: AIChatSuggestion.formatISO8601Date($0.timestamp),
                 model: $0.model)
        }
    }
}

// MARK: - Provider

/// Answers the duckduckgo.com homepage's `getAIChats` request from native storage.
public final class HomepageAiChatsProvider {

    public static let defaultMaxChats = 5
    static let maxChatsLimit = 20

    private let featureFlagProvider: AIChatFeatureFlagProviding

    /// Chats are read through this script's store, which resolves to the fire-mode store in a
    /// fire tab or window, so those never list the normal chats.
    public weak var storageUserScript: DuckAiNativeStorageUserScript?

    public init(featureFlagProvider: AIChatFeatureFlagProviding) {
        self.featureFlagProvider = featureFlagProvider
    }

    public var isSupported: Bool {
        readyStorageHandler != nil
    }

    @MainActor
    public func chats(for request: HomepageAiChatsRequest) async -> HomepageAiChatsResponse {
        guard let storageHandler = readyStorageHandler else { return .empty }
        let maxChats = min(max(request.maxChats ?? Self.defaultMaxChats, 1), Self.maxChatsLimit)
        let query = request.query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await LocalSuggestionsReader(storageHandler: storageHandler)
            .fetchSuggestions(query: query?.isEmpty == false ? query : nil, maxChats: maxChats)
        switch result {
        case .success(let suggestions):
            return HomepageAiChatsResponse(pinned: suggestions.pinned, recent: suggestions.recent)
        case .failure:
            return .empty
        }
    }

    public static func isHomepageMessage(host: String) -> Bool {
        let host = host.lowercased()
        return host != "duck.ai" && !host.hasSuffix(".duck.ai")
    }

    private var readyStorageHandler: DuckAiNativeStorageHandling? {
        guard featureFlagProvider.isHomepageChatSuggestionsEnabled(),
              featureFlagProvider.isNativeDataAccessEnabled(),
              let storageHandler = storageUserScript?.handler,
              storageHandler.setupSucceeded != false,
              (try? storageHandler.isMigrationDone()) == true else {
            return nil
        }
        return storageHandler
    }
}

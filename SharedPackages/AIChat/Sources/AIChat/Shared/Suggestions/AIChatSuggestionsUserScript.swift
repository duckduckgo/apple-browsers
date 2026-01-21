//
//  AIChatSuggestionsUserScript.swift
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
import UserScript
import WebKit
import os.log
import Common

// MARK: - AIChatSuggestionsUserScript

/// UserScript that communicates with duck.ai to fetch chat history for suggestions.
/// Uses the duckAiChatHistory.js content script feature.
public final class AIChatSuggestionsUserScript: NSObject, Subfeature {

    // MARK: - Message Names

    public enum MessageName: String, CaseIterable {
        /// Request to fetch chats from duck.ai
        case getDuckAiChats
        /// Response containing chat data
        case duckAiChatsResult
    }

    // MARK: - Errors

    public enum SuggestionsError: Error, LocalizedError {
        case notReady
        case fetchFailed(String)
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .notReady:
                return "AIChatSuggestionsUserScript not ready"
            case .fetchFailed(let message):
                return "Failed to fetch chats: \(message)"
            case .invalidResponse:
                return "Invalid response from duck.ai"
            }
        }
    }

    // MARK: - Response Types

    /// Response structure from the JS getDuckAiChats call
    private struct ChatsResponse: Decodable {
        let success: Bool
        let pinnedChats: [ChatData]
        let chats: [ChatData]
        let error: String?
        let timestamp: Int64?
    }

    /// Individual chat data from JS
    private struct ChatData: Decodable {
        let chatId: String
        let title: String?
        let pinned: Bool?
        let lastEdit: String?  // ISO date string like "2026-01-19T11:48:10.903Z"

        func toAIChatSuggestion() -> AIChatSuggestion {
            AIChatSuggestion(
                id: chatId,
                title: title ?? "Untitled Chat",
                isPinned: pinned ?? false,
                chatId: chatId,
                timestamp: AIChatSuggestion.parseISO8601Date(lastEdit)
            )
        }
    }

    // MARK: - Request Types

    private struct FetchChatsParams: Encodable {
        let query: String?
        let maxChats: Int
        let since: Int64?

        enum CodingKeys: String, CodingKey {
            case query
            case maxChats = "max_chats"
            case since
        }
    }

    // MARK: - Properties

    public weak var broker: UserScriptMessageBroker?
    public private(set) var messageOriginPolicy: MessageOriginPolicy
    public var featureName = "duckAiChatHistory"
    public weak var webView: WKWebView?

    /// Callback for when chat results are received. Called on main actor.
    /// Multiple fetches can be in flight; each response triggers this callback.
    @MainActor public var onChatsReceived: ((Result<(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]), Error>) -> Void)?

    // MARK: - Constants

    public static let defaultMaxChats = 5

    // MARK: - Initialization

    public override init() {
        self.messageOriginPolicy = .only(rules: [
            .exact(hostname: "duck.ai"),
            .exact(hostname: "duckduckgo.com")
        ])
        super.init()
    }

    // MARK: - Subfeature Protocol

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {

        guard let message = MessageName(rawValue: methodName) else {
            Logger.aiChat.debug("Unhandled message: \(methodName) in AIChatSuggestionsUserScript")
            return nil
        }

        switch message {
        case .duckAiChatsResult:
            return handleChatsResult
        case .getDuckAiChats:
            return nil
        }
    }

    // MARK: - Public API

    /// Sends a request to fetch chat suggestions from duck.ai.
    /// Results are delivered via the `onChatsReceived` callback.
    /// Multiple requests can be in flight simultaneously.
    /// - Parameters:
    ///   - query: Optional search query to filter chats
    ///   - maxChats: Maximum number of recent (non-pinned) chats to return
    ///   - since: Optional timestamp in milliseconds - only return chats with lastEdit >= this value
    @MainActor
    public func fetchChats(query: String? = nil, maxChats: Int = defaultMaxChats, since: Int64? = nil) {
        guard let webView, broker != nil else {
            onChatsReceived?(.failure(SuggestionsError.notReady))
            return
        }

        let params = FetchChatsParams(
            query: query?.isEmpty == false ? query : nil,
            maxChats: maxChats,
            since: since
        )

        broker?.push(
            method: MessageName.getDuckAiChats.rawValue,
            params: params,
            for: self,
            into: webView
        )
    }

    // MARK: - Message Handlers

    @MainActor
    private func handleChatsResult(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let paramsDict = params as? [String: Any] else {
            onChatsReceived?(.failure(SuggestionsError.invalidResponse))
            return nil
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: paramsDict)
            let response = try JSONDecoder().decode(ChatsResponse.self, from: jsonData)

            if response.success {
                let pinnedSuggestions = response.pinnedChats.map { $0.toAIChatSuggestion() }
                let recentSuggestions = response.chats.map { $0.toAIChatSuggestion() }
                onChatsReceived?(.success((pinned: pinnedSuggestions, recent: recentSuggestions)))
            } else {
                let errorMessage = response.error ?? "Unknown error"
                Logger.aiChat.debug("Response indicated failure: \(errorMessage)")
                onChatsReceived?(.failure(SuggestionsError.fetchFailed(errorMessage)))
            }
        } catch {
            Logger.aiChat.error("Failed to decode chats response: \(error)")
            onChatsReceived?(.failure(SuggestionsError.invalidResponse))
        }

        return nil
    }
}

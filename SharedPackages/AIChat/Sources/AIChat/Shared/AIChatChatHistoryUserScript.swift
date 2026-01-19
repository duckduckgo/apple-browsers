//
//  AIChatChatHistoryUserScript.swift
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

import Foundation
import UserScript
import WebKit
import os.log
import Combine
import Common

// MARK: - AIChatChatHistoryUserScript Class

public final class AIChatChatHistoryUserScript: NSObject, Subfeature {

    public enum MessageName: String, CaseIterable {
        case getDuckAiChats
        case duckAiChatsResult
        case duckAiChatHistoryReady
    }

    // MARK: - Properties

    public weak var broker: UserScriptMessageBroker?
    public private(set) var messageOriginPolicy: MessageOriginPolicy
    public var featureName = "duckAiChatHistory"
    public weak var webView: WKWebView?

    private let chatsResultSubject = PassthroughSubject<[String: Any], Never>()
    public var chatsResultPublisher: AnyPublisher<[String: Any], Never> {
        chatsResultSubject.eraseToAnyPublisher()
    }

    /// Result containing the raw response dictionary from JavaScript
    public struct ChatsResult {
        public let rawResponse: [String: Any]
        public let chats: [[String: Any]]
        
        public var rawJSON: String {
            if let data = try? JSONSerialization.data(withJSONObject: rawResponse, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return String(describing: rawResponse)
        }
    }

    @MainActor private var continuation: CheckedContinuation<Result<ChatsResult, Error>, Never>?
    @MainActor private var timeoutTask: Task<Void, Never>?

    // MARK: - Errors

    public enum ChatHistoryError: Error, LocalizedError {
        case notReady
        case timeout
        case failedFromScript(String)

        public var errorDescription: String? {
            switch self {
            case .notReady: return "AIChatChatHistoryUserScript not ready"
            case .timeout: return "AIChatChatHistoryUserScript timed out waiting for response"
            case .failedFromScript(let message): return "Script error: \(message)"
            }
        }
    }

    // MARK: - Initialization

    public override init() {
        self.messageOriginPolicy = .only(rules: Self.buildMessageOriginRules(additionalHostnames: []))
        super.init()
    }

    public init(additionalHostnames: [String]) {
        self.messageOriginPolicy = .only(rules: Self.buildMessageOriginRules(additionalHostnames: additionalHostnames))
        super.init()
    }

    private static func buildMessageOriginRules(additionalHostnames: [String]) -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        // Allow duckduckgo.com and duck.ai
        rules.append(.exact(hostname: "duckduckgo.com"))
        rules.append(.exact(hostname: "duck.ai"))

        // Allow any additional custom hostnames (for debugging)
        for hostname in additionalHostnames {
            rules.append(.exact(hostname: hostname))
        }

        return rules
    }

    // MARK: - Subfeature

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = MessageName(rawValue: methodName) else {
            Logger.aiChat.debug("Unhandled message: \(methodName) in AIChatChatHistoryUserScript")
            return nil
        }

        switch message {
        case .duckAiChatsResult: return handleChatsResult
        case .duckAiChatHistoryReady: return handleReady
        default: return nil
        }
    }

    // MARK: - Public API

    /// Parameters for requesting chat history
    public struct GetChatsParams: Encodable {
        /// Search query to filter chats (optional)
        public let query: String?

        public init(query: String? = nil) {
            self.query = query
        }
    }

    /// Requests chat history from the frontend and awaits the result.
    /// - Parameters:
    ///   - query: Search query to filter chats (nil returns all chats)
    ///   - timeout: Maximum seconds to wait for a response before failing with `.timeout`.
    /// - Returns: Result containing ChatsResult with raw response and parsed chats, or an error.
    @MainActor
    public func getChatsAsync(query: String? = nil, timeout: TimeInterval = 5) async -> Result<ChatsResult, Error> {
        guard webView != nil, broker != nil else { return .failure(ChatHistoryError.notReady) }

        sendGetChatsMessage(query: query)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(result: .failure(ChatHistoryError.timeout))
            }
        }
    }

    /// Sends the getDuckAiChats message to request chat history
    /// - Parameter query: Search query to filter chats (nil returns all chats)
    public func sendGetChatsMessage(query: String? = nil) {
        guard let webView else {
            Logger.aiChat.error("sendGetChatsMessage: webView is nil")
            return
        }
        guard let broker else {
            Logger.aiChat.error("sendGetChatsMessage: broker is nil")
            return
        }
        let params = query.map { GetChatsParams(query: $0) }
        Logger.aiChat.debug("sendGetChatsMessage: Pushing getDuckAiChats to webView with query=\(String(describing: query))")
        broker.push(method: MessageName.getDuckAiChats.rawValue, params: params, for: self, into: webView)
    }

    // MARK: - Private Helpers

    @MainActor
    private func finish(result: Result<ChatsResult, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let cont = continuation
        continuation = nil
        cont?.resume(returning: result)
    }

    // MARK: - JS Callbacks

    @MainActor
    private func handleChatsResult(params: Any, message: UserScriptMessage) -> Encodable? {
        // Log raw params for debugging
        if let data = try? JSONSerialization.data(withJSONObject: params, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            Logger.aiChat.debug("Received duckAiChatsResult with params: \(jsonString)")
        } else {
            Logger.aiChat.debug("Received duckAiChatsResult with non-JSON params: \(String(describing: params))")
        }

        guard let dict = params as? [String: Any] else {
            Logger.aiChat.error("duckAiChatsResult: Invalid response format - params is not a dictionary")
            finish(result: .failure(ChatHistoryError.failedFromScript("Invalid response format: \(type(of: params))")))
            return nil
        }

        // Publish for subscribers
        chatsResultSubject.send(dict)

        // Parse chats from response
        let chats = dict["chats"] as? [[String: Any]] ?? []
        Logger.aiChat.debug("duckAiChatsResult: Found \(chats.count) chats")
        
        let result = ChatsResult(rawResponse: dict, chats: chats)
        finish(result: .success(result))

        return nil
    }

    @MainActor
    private func handleReady(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("duckAiChatHistory feature is ready")
        return nil
    }
}

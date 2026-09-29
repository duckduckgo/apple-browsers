//
//  AIChatDataClearingUserScript.swift
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
import DDGError
import UserScript
import WebKit
import os.log
import Combine
import Common
import FoundationExtensions

// MARK: - Delegate Protocol

protocol AIChatDataClearingUserScriptDelegate: AnyObject {

    @MainActor func dataClearingSucceeded()
    @MainActor func dataClearingFailed()

}

// MARK: - AIChatDataClearingUserScript Class

final class AIChatDataClearingUserScript: NSObject, Subfeature {

    public enum MessageName: String, CaseIterable {

        case duckAiClearData
        case duckAiClearDataCompleted
        case duckAiClearDataFailed
        case duckAiClearDataReady

    }

    // MARK: - Async Clear Support
    enum ClearError: Error, DDGError {
        case notReady
        case timeout
        case failedFromScript(ScriptFailure)
        case scriptNeverReady
        case navigationTimeout
        case webContentProcessTerminated

        static var errorDomain: String = "com.duckduckgo.aiChatDataClearing"

        var description: String {
            switch self {
            case .notReady: return "AIChatDataClearingUserScript not ready to clear data"
            case .timeout: return "AIChatDataClearingUserScript timed out waiting for response from script"
            case .failedFromScript: return "AIChatDataClearingUserScript reported failure from script"
            case .scriptNeverReady: return "AIChatDataClearingUserScript never reported that it is ready"
            case .navigationTimeout: return "AIChatDataClearingUserScript timed out waiting for the page to load"
            case .webContentProcessTerminated: return "AIChatDataClearingUserScript web content process terminated"
            }
        }

        var errorCode: Int {
            switch self {
            case .notReady: return 1
            case .timeout: return 2
            case .failedFromScript: return 3
            case .scriptNeverReady: return 4
            case .navigationTimeout: return 5
            case .webContentProcessTerminated: return 6
            }
        }

        /// Whether the page must be reloaded before the next clear: a late reply may still arrive, or the page is gone.
        var requiresPageReload: Bool {
            switch self {
            case .timeout, .webContentProcessTerminated: return true
            case .notReady, .failedFromScript, .scriptNeverReady, .navigationTimeout: return false
            }
        }

        var underlyingError: Error? {
            guard case .failedFromScript(let failure) = self else { return nil }
            return failure
        }
    }

    // MARK: - Properties

    weak var delegate: AIChatDataClearingUserScriptDelegate?
    weak var broker: UserScriptMessageBroker?
    private(set) var messageOriginPolicy: MessageOriginPolicy
    var featureName = "duckAiDataClearing"
    weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()

    @MainActor private var continuation: CheckedContinuation<Result<Void, Error>, Never>?
    @MainActor private var timeoutTask: Task<Void, Never>?
    @MainActor private let readyWaiter = CallbackWaiter()
    @MainActor private var isScriptReady = false

    // MARK: - Initialization

    override init() {
        self.messageOriginPolicy = .only(rules: Self.buildMessageOriginRules())
        super.init()
    }

    private static func buildMessageOriginRules() -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        URL.aiChatDomains.forEach { url in
            if let host = url.host {
                rules.append(.exact(hostname: host))
            }
        }

        return rules
    }

    // MARK: - Subfeature

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = AIChatDataClearingUserScript.MessageName(rawValue: methodName) else {
            Logger.aiChat.debug("Unhandled message: \(methodName) in AIChatDataClearingUserScript")
            return nil
        }

        switch message {
        case .duckAiClearDataCompleted: return aiChatDataClearingSucceeded
        case .duckAiClearDataFailed: return aiChatDataClearingFailed
        case .duckAiClearDataReady: return aiChatDataClearingReady
        default: return nil
        }
    }

    // MARK: - Public Async API

    /// Starts JS-based clearing and awaits a result. Safe to call only after navigation finished.
    /// - Parameter timeout: Maximum seconds to wait for a JS response before failing with `.timeout`.
    /// - Returns: Result signalling success or an error.
    @MainActor
    func clearAIChatDataAsync(chatID: String?, timeout: TimeInterval = 5) async -> Result<Void, Error> {
        guard webView != nil, broker != nil else { return .failure(ClearError.notReady) }

        sendClearDataMessage(chatID: chatID)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(result: .failure(ClearError.timeout))
            }
        }
    }

    /// Forgets the previous page's readiness. Call it before loading a page: the script can report ready before the load finishes.
    @MainActor
    func prepareForPageLoad() {
        isScriptReady = false
    }

    /// Waits until the script listens for the clear message, so the message isn't sent into the void.
    @MainActor
    func waitUntilReady(timeout: TimeInterval = 5) async -> Result<Void, Error> {
        guard !isScriptReady else { return .success(()) }
        return await readyWaiter.wait(timeout: timeout, timeoutError: ClearError.scriptNeverReady)
    }

    /// Fails whatever is still waiting on the script, e.g. because its page is gone.
    @MainActor
    func failPendingWaits(with error: ClearError) {
        readyWaiter.failPending(with: error)
        finish(result: .failure(error))
    }

    // MARK: - Private helpers

    private func sendClearDataMessage(chatID: String?) {
        guard let webView else { return }
        var params: [String: String]?
        if let chatID {
            params = ["chatId": chatID]
        }
        broker?.push(method: AIChatDataClearingUserScript.MessageName.duckAiClearData.rawValue, params: params, for: self, into: webView)
    }

    @MainActor
    private func finish(result: Result<Void, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let cont = continuation
        continuation = nil
        cont?.resume(returning: result)
    }

    // MARK: - JS Callbacks

    @MainActor
    private func aiChatDataClearingSucceeded(params: Any, message: UserScriptMessage) -> Encodable? {
        finish(result: .success(()))
        return nil
    }

    @MainActor
    private func aiChatDataClearingFailed(params: Any, message: UserScriptMessage) -> Encodable? {
        finish(result: .failure(ClearError.failedFromScript(ScriptFailure(payload: params))))
        return nil
    }

    @MainActor
    private func aiChatDataClearingReady(params: Any, message: UserScriptMessage) -> Encodable? {
        isScriptReady = true
        readyWaiter.complete(nil, with: .success(()))
        return nil
    }
}

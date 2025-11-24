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
import UserScript
import WebKit
import os.log
import Combine
import Common

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

    }

    // MARK: - Async Clear Support
    enum ClearError: Error, DDGError {
        case notReady
        case timeout
        case failedFromScript

        static var errorDomain: String = "com.duckduckgo.aiChatDataClearing"

        var description: String {
            switch self {
            case .notReady: return "AIChatDataClearingUserScript not ready to clear data"
            case .timeout: return "AIChatDataClearingUserScript timed out waiting for response from script"
            case .failedFromScript: return "AIChatDataClearingUserScript reported failure from script"
            }
        }

        var errorCode: Int {
            switch self {
            case .notReady: return 1
            case .timeout: return 2
            case .failedFromScript: return 3
            }
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
        default: return nil
        }
    }

    // MARK: - Public Async API

    /// Starts JS-based clearing and awaits a result. Safe to call only after navigation finished.
    /// - Parameter timeout: Maximum seconds to wait for a JS response before failing with `.timeout`.
    /// - Returns: Result signalling success or an error.
    @MainActor
    func clearAIChatDataAsync(timeout: TimeInterval = 5) async -> Result<Void, Error> {
        guard webView != nil, broker != nil else { return .failure(ClearError.notReady) }

        sendClearDataMessage()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(result: .failure(ClearError.timeout))
            }
        }
    }

    // MARK: - Private helpers

    private func sendClearDataMessage() {
        guard let webView else { return }
        broker?.push(method: AIChatDataClearingUserScript.MessageName.duckAiClearData.rawValue, params: nil, for: self, into: webView)
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
        finish(result: .failure(ClearError.failedFromScript))
        return nil
    }
}

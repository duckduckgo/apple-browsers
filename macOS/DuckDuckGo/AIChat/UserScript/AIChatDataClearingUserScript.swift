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

    // MARK: - Properties

    weak var delegate: AIChatDataClearingUserScriptDelegate?
    weak var broker: UserScriptMessageBroker?
    private(set) var messageOriginPolicy: MessageOriginPolicy
    var featureName = "duckAiDataClearing"
    weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    override init() {
        self.messageOriginPolicy = .only(rules: Self.buildMessageOriginRules())
        super.init()

        registerForNotifications()
    }

    private static func buildMessageOriginRules() -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        if let ddgDomain = URL.duckDuckGo.host {
            rules.append(.exact(hostname: ddgDomain))
        }

        return rules
    }

    private func registerForNotifications() {
        NotificationCenter.default.publisher(for: .aiChatHistoryClearDataRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearAIChatData()
            }
            .store(in: &cancellables)
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

    private func clearAIChatData() {
        guard let webView else { return }
        broker?.push(method: AIChatDataClearingUserScript.MessageName.duckAiClearData.rawValue, params: nil, for: self, into: webView)
    }

    @MainActor
    private func aiChatDataClearingSucceeded(params: Any, message: UserScriptMessage) -> Encodable? {
        delegate?.dataClearingSucceeded()
        return nil
    }

    @MainActor
    private func aiChatDataClearingFailed(params: Any, message: UserScriptMessage) -> Encodable? {
        delegate?.dataClearingFailed()
        return nil
    }
}

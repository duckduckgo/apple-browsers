//
//  AIChatUserScript.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Combine
import Common
import Foundation
import UserScript
import WebKit

final class AIChatUserScript: NSObject, Subfeature {
    public let handler: AIChatUserScriptHandling
    public let featureName: String = "aiChat"
    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?
    private(set) var messageOriginPolicy: MessageOriginPolicy

    private var cancellables: Set<AnyCancellable> = []

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    init(handler: AIChatUserScriptHandling, urlSettings: AIChatDebugURLSettingsRepresentable) {
        self.handler = handler
        var rules = [HostnameMatchingRule]()

        /// Default rule for DuckDuckGo AI Chat
        if let ddgDomain = URL.duckDuckGo.host {
            rules.append(.exact(hostname: ddgDomain))
        }

        /// Check if a custom hostname is provided in the URL settings
        /// Custom hostnames are used for debugging purposes
        if let customURLHostname = urlSettings.customURLHostname {
            rules.append(.exact(hostname: customURLHostname))
        }
        self.messageOriginPolicy = .only(rules: rules)
        super.init()

        handler.aiChatNativePromptPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prompt in
                self?.submitAIChatNativePrompt(prompt)
            }
            .store(in: &cancellables)

        handler.pageContextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pageContext in
                self?.submitPageContext(pageContext)
            }
            .store(in: &cancellables)
    }

    private func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        guard let webView else {
            return
        }
        broker?.push(method: AIChatUserScriptMessages.submitAIChatNativePrompt.rawValue, params: prompt, for: self, into: webView)
    }

    private func submitPageContext(_ pageContextData: AIChatPageContextData) {
        guard let webView else {
            return
        }
        let params = PageContextPayload(serializedPageData: pageContextData)
        broker?.push(method: AIChatUserScriptMessages.submitPageContext.rawValue, params: params, for: self, into: webView)
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch AIChatUserScriptMessages(rawValue: methodName) {
        case .openAIChatSettings:
            return handler.openAIChatSettings
        case .getAIChatNativeConfigValues:
            return handler.getAIChatNativeConfigValues
        case .closeAIChat:
            return handler.closeAIChat
        case .getAIChatNativePrompt:
            return handler.getAIChatNativePrompt
        case .openAIChat:
            return handler.openAIChat
        case .getAIChatNativeHandoffData:
            return handler.getAIChatNativeHandoffData
        case .recordChat:
            return handler.recordChat
        case .restoreChat:
            return handler.restoreChat
        case .removeChat:
            return handler.removeChat
        case .openSummarizationSourceLink:
            return handler.openSummarizationSourceLink
        case .getPageContext:
            return handler.getPageContext
        default:
            return nil
        }
    }
}

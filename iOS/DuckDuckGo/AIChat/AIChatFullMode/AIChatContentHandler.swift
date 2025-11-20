//
//  AIChatContentHandler.swift
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
import Foundation
import WebKit

/// Mockable interface to AIChatUserScript
protocol AIChatUserScriptProviding: AnyObject {
    var delegate: AIChatUserScriptDelegate? { get set }
    var webView: WKWebView? { get set }
    func setPayloadHandler(_ payloadHandler: any AIChatConsumableDataHandling)
}

extension AIChatUserScript: AIChatUserScriptProviding { }

/// Delegate for AIChatContentHandling navigation and UI actions.
protocol AIChatContentHandlingDelegate: AnyObject {
    /// Called when the content handler receives a request to open AIChat settings.
    func aiChatContentHandlerDidReceiveOpenSettingsRequest(_ handler: AIChatContentHandling)
    
    /// Called when the content handler receives a request to close the AIChat interface.
    func aiChatContentHandlerDidReceiveCloseChatRequest(_ handler: AIChatContentHandling)
}

/// Handles content initialization, payload management, and URL building for AIChat.
protocol AIChatContentHandling {

    var delegate: AIChatContentHandlingDelegate? { get set }

    /// Configures the user script and WebView for AIChat interaction.
    func setup(with userScript: AIChatUserScriptProviding, webView: WKWebView)

    /// Sets the initial payload data for the AIChat session.
    func setPayload(payload: Any?)

    /// Builds a query URL with optional prompt, auto-submit, and RAG tools.
    func buildQueryURL(query: String?, autoSend: Bool, tools: [AIChatRAGTool]?) -> URL
}

final class AIChatContentHandler: AIChatContentHandling {
    
    // MARK: - Dependencies
    private let aiChatSettings: AIChatSettingsProvider
    private var payloadHandler: AIChatPayloadHandler
    private let pixelMetricHandler: (any AIChatPixelMetricHandling)?
    
    // MARK: - Public API
    
    weak var delegate: AIChatContentHandlingDelegate?
    
    init(aiChatSettings: AIChatSettingsProvider,
         payloadHandler: AIChatPayloadHandler = AIChatPayloadHandler(),
         pixelMetricHandler: any AIChatPixelMetricHandling = AIChatPixelMetricHandler()) {
        self.aiChatSettings = aiChatSettings
        self.payloadHandler = payloadHandler
        self.pixelMetricHandler = pixelMetricHandler
    }
    
    /// Configures the user script and WebView for AIChat interaction.
    func setup(with userScript: AIChatUserScriptProviding, webView: WKWebView) {
        userScript.delegate = self
        userScript.setPayloadHandler(payloadHandler)
        userScript.webView = webView
    }
    
    /// Sets the initial payload data for the AIChat session.
    func setPayload(payload: Any?) {
        guard let payload = payload as? AIChatPayload else { return }
        payloadHandler.setData(payload)
    }
    
    /// Builds a query URL with optional prompt, auto-submit, and RAG tools.
    func buildQueryURL(query: String?, autoSend: Bool, tools: [AIChatRAGTool]?) -> URL {
        guard let query, var components = URLComponents(url: aiChatSettings.aiChatURL, resolvingAgainstBaseURL: false) else {
            return aiChatSettings.aiChatURL
        }

        var queryItems = components.queryItems ?? []

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.removeAll { $0.name == AIChatURLParameters.promptQueryName }
            queryItems.append(URLQueryItem(name: AIChatURLParameters.promptQueryName, value: query))
        }

        if autoSend {
            queryItems.removeAll { $0.name == AIChatURLParameters.autoSubmitPromptQueryName }
            queryItems.append(URLQueryItem(name: AIChatURLParameters.autoSubmitPromptQueryName, value: AIChatURLParameters.autoSubmitPromptQueryValue))
        }

        if let tools = tools, !tools.isEmpty {
            queryItems.removeAll { $0.name == AIChatURLParameters.toolChoiceName }
            for tool in tools {
                queryItems.append(URLQueryItem(name: AIChatURLParameters.toolChoiceName, value: tool.rawValue))
            }
        }

        components.queryItems = queryItems
        return components.url ?? aiChatSettings.aiChatURL
    }
}

// MARK: - AIChatUserScriptDelegate
extension AIChatContentHandler: AIChatUserScriptDelegate {
    
    func aiChatUserScript(_ userScript: AIChatUserScript, didReceiveMessage message: AIChatUserScriptMessages) {
        switch message {
        case .openAIChatSettings:
            delegate?.aiChatContentHandlerDidReceiveOpenSettingsRequest(self)
        case .closeAIChat:
            delegate?.aiChatContentHandlerDidReceiveCloseChatRequest(self)
        default:
            break
        }
    }

    func aiChatUserScript(_ userScript: AIChatUserScript, didReceiveMetric metric: AIChatMetric) {
        pixelMetricHandler?.firePixelWithMetric(metric)
    }
}

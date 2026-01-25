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
import BrowserServicesKit
import Common
import Core
import os.log
import PrivacyConfig
import Foundation
import WebKit

/// Mockable interface to AIChatUserScript
protocol AIChatUserScriptProviding: AnyObject {
    var delegate: AIChatUserScriptDelegate? { get set }
    var webView: WKWebView? { get set }
    func setPayloadHandler(_ payloadHandler: any AIChatConsumableDataHandling)
    func setPageContextProvider(_ provider: ((PageContextRequestReason) -> AIChatPageContextData?)?)
    func setDisplayMode(_ displayMode: AIChatDisplayMode)
    func submitPrompt(_ prompt: String, pageContext: AIChatPageContextData?)
    func submitStartChatAction()
    func submitOpenSettingsAction()
    func submitPageContext(_ context: AIChatPageContextData?)
    func submitToggleSidebarAction()
}

extension AIChatUserScriptProviding {
    func submitPrompt(_ prompt: String) {
        submitPrompt(prompt, pageContext: nil)
    }
}

extension AIChatUserScript: AIChatUserScriptProviding { }

/// Delegate for AIChatContentHandling navigation and UI actions.
protocol AIChatContentHandlingDelegate: AnyObject {
    /// Called when the content handler receives a request to open AIChat settings.
    func aiChatContentHandlerDidReceiveOpenSettingsRequest(_ handler: AIChatContentHandling)

    /// Called when the content handler receives a request to close the AIChat interface.
    func aiChatContentHandlerDidReceiveCloseChatRequest(_ handler: AIChatContentHandling)

    /// Called when the content handler receives a request to open Sync settings.
    func aiChatContentHandlerDidReceiveOpenSyncSettingsRequest(_ handler: AIChatContentHandling)

    /// Called when the user submits a prompt.
    func aiChatContentHandlerDidReceivePromptSubmission(_ handler: AIChatContentHandling)
}

/// Handles content initialization, payload management, and URL building for AIChat.
protocol AIChatContentHandling: AnyObject {

    var delegate: AIChatContentHandlingDelegate? { get set }

    /// Configures the user script, WebView and display mode for AIChat interaction.
    func setup(with userScript: AIChatUserScriptProviding, webView: WKWebView, displayMode: AIChatDisplayMode)

    /// Sets the initial payload data for the AIChat session.
    func setPayload(payload: Any?)

    /// Builds a query URL with optional prompt, auto-submit, and RAG tools.
    func buildQueryURL(query: String?, autoSend: Bool, tools: [AIChatRAGTool]?) -> URL
    
    /// Submits a prompt to the AI Chat with optional page context.
    func submitPrompt(_ prompt: String, pageContext: AIChatPageContextData?)


    /// Submits a start chat action to initiate a new AI Chat conversation.
    func submitStartChatAction()

    /// Submits an open settings action to open the AI Chat settings.
    func submitOpenSettingsAction()

    /// Submits a toggle sidebar action to open/close the sidebar.
    func submitToggleSidebarAction()

    /// Pushes page context to the frontend (for context updates during navigation).
    func submitPageContext(_ context: AIChatPageContextData?)

    /// Fires AI Chat telemetry: product surface telemetry, 'chat open' pixel, and sets the AI Chat feature as 'used before'
    func fireAIChatTelemetry()
}

extension AIChatContentHandling {
    func submitPrompt(_ prompt: String) {
        submitPrompt(prompt, pageContext: nil)
    }
}

final class AIChatContentHandler: AIChatContentHandling {
    
    // MARK: - Dependencies
    private let aiChatSettings: AIChatSettingsProvider
    private var payloadHandler: AIChatPayloadHandler
    private let pixelMetricHandler: (any AIChatPixelMetricHandling)?
    private let featureDiscovery: FeatureDiscovery
    private let featureFlagger: FeatureFlagger
    private let productSurfaceTelemetry: ProductSurfaceTelemetry
    private lazy var statisticsLoader: StatisticsLoader = .shared

    private var userScript: AIChatUserScriptProviding?

    /// Closure to get page context for contextual mode. Nil in full mode.
    /// Parameter is the request reason (e.g., `.userAction` for manual attach).
    private let getPageContext: ((PageContextRequestReason) -> AIChatPageContextData?)?

    weak var delegate: AIChatContentHandlingDelegate?

    init(aiChatSettings: AIChatSettingsProvider,
         payloadHandler: AIChatPayloadHandler = AIChatPayloadHandler(),
         pixelMetricHandler: any AIChatPixelMetricHandling = AIChatPixelMetricHandler(),
         featureDiscovery: FeatureDiscovery,
         featureFlagger: FeatureFlagger,
         productSurfaceTelemetry: ProductSurfaceTelemetry,
         getPageContext: ((PageContextRequestReason) -> AIChatPageContextData?)? = nil) {
        self.aiChatSettings = aiChatSettings
        self.payloadHandler = payloadHandler
        self.pixelMetricHandler = pixelMetricHandler
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
        self.productSurfaceTelemetry = productSurfaceTelemetry
        self.getPageContext = getPageContext
    }

    func setup(with userScript: AIChatUserScriptProviding, webView: WKWebView, displayMode: AIChatDisplayMode) {
        self.userScript = userScript
        self.userScript?.delegate = self
        self.userScript?.setDisplayMode(displayMode)
        self.userScript?.setPayloadHandler(payloadHandler)
        self.userScript?.webView = webView
        self.userScript?.setPageContextProvider(getPageContext)
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
    
    func submitPrompt(_ prompt: String, pageContext: AIChatPageContextData? = nil) {
        if let context = pageContext {
            Logger.aiChat.debug("[PageContext] Prompt submitted with context - title: \(context.title.prefix(50))")
        } else {
            Logger.aiChat.debug("[PageContext] Prompt submitted without context")
        }
        userScript?.submitPrompt(prompt, pageContext: pageContext)
    }

    /// Submits a start chat action to initiate a new AI Chat conversation.
    /// Only pushes page context if auto-attach is enabled; manual attach goes through explicit pushPageContext calls.
    func submitStartChatAction() {
        if aiChatSettings.isAutomaticContextAttachmentEnabled, let context = getPageContext?(.other) {
            userScript?.submitPageContext(context)
        }
        userScript?.submitStartChatAction()
    }

    /// Submits an open settings action to open the AI Chat settings.
    func submitOpenSettingsAction() {
        userScript?.submitOpenSettingsAction()
    }

    /// Submits a toggle sidebar action to open/close the sidebar.
    func submitToggleSidebarAction() {
        userScript?.submitToggleSidebarAction()
    }

    func submitPageContext(_ context: AIChatPageContextData?) {
        userScript?.submitPageContext(context)
    }

    /// Fires AI Chat telemetry: product surface telemetry, 'chat open' pixel, and sets the AI Chat feature as 'used before'
    func fireAIChatTelemetry() {
        productSurfaceTelemetry.duckAIUsed()
        pixelMetricHandler?.fireOpenAIChat()
        featureDiscovery.setWasUsedBefore(.aiChat)
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
        case .sendToSyncSettings, .sendToSetupSync:
            delegate?.aiChatContentHandlerDidReceiveOpenSyncSettingsRequest(self)
        default:
            break
        }
    }

    func aiChatUserScript(_ userScript: AIChatUserScript, didReceiveMetric metric: AIChatMetric) {
        if metric.metricName == .userDidSubmitPrompt
            || metric.metricName == .userDidSubmitFirstPrompt {
            NotificationCenter.default.post(name: .aiChatUserDidSubmitPrompt, object: nil)
            delegate?.aiChatContentHandlerDidReceivePromptSubmission(self)

            if featureFlagger.isFeatureOn(.aiChatAtb) {
                DispatchQueue.main.async {
                    let backgroundAssertion = QRunInBackgroundAssertion(name: "StatisticsLoader background assertion - duckai",
                                                                        application: UIApplication.shared)
                    self.statisticsLoader.refreshRetentionAtbOnDuckAIPromptSubmission {
                        DispatchQueue.main.async {
                            backgroundAssertion.release()
                        }
                    }
                }
            }
        }

        pixelMetricHandler?.firePixelWithMetric(metric)
    }
}

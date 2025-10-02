//
//  AIChatUserScriptHandling.swift
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
import UserScript
import Foundation
import BrowserServicesKit
import RemoteMessaging
import AIChat
import OSLog
import WebKit

// MARK: - Response Types

/// Response structure for openKeyboard request
struct OpenKeyboardResponse: Encodable {
    let success: Bool
    let error: String?

    init(success: Bool, error: String? = nil) {
        self.success = success
        self.error = error
    }
}

protocol AIChatMetricReportingHandling {
    func didReportMetric(_ metric: AIChatMetric)
}

protocol AIChatUserScriptHandling {
    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) -> Encodable?
    func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable?
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func setPayloadHandler(_ payloadHandler: (any AIChatConsumableDataHandling)?)
    func setAIChatInputBoxHandler(_ inputBoxHandler: (any AIChatInputBoxHandling)?)
    func setMetricReportingHandler(_ metricHandler: (any AIChatMetricReportingHandling)?)
    func getResponseState(params: Any, message: UserScriptMessage) async -> Encodable?
    func hideChatInput(params: Any, message: UserScriptMessage) async -> Encodable?
    func showChatInput(params: Any, message: UserScriptMessage) async -> Encodable?
    func reportMetric(params: Any, message: UserScriptMessage) async -> Encodable?
    func openKeyboard(params: Any, message: UserScriptMessage, webView: WKWebView?) async -> Encodable?
}

final class AIChatUserScriptHandler: AIChatUserScriptHandling {
    private var payloadHandler: (any AIChatConsumableDataHandling)?
    private var inputBoxHandler: (any AIChatInputBoxHandling)?
    private var metricReportingHandler: (any AIChatMetricReportingHandling)?
    private let experimentalAIChatManager: ExperimentalAIChatManager

    init(experimentalAIChatManager: ExperimentalAIChatManager) {
        self.experimentalAIChatManager = experimentalAIChatManager
    }

    enum AIChatKeys {
        static let aiChatPayload = "aiChatPayload"
    }

    /// Invoked by the front-end code when it intends to open the AI Chat interface.
    /// The front-end can provide a payload that will be used the next time the AI Chat view is displayed.
    /// This function stores the payload and triggers a notification to handle the AI Chat opening process.
    @MainActor
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        var payload: AIChatPayload?
        if let paramsDict = params as? AIChatPayload {
            payload = paramsDict[AIChatKeys.aiChatPayload] as? AIChatPayload
        }

        NotificationCenter.default.post(
            name: .urlInterceptAIChat,
            object: payload,
            userInfo: nil
        )

        return nil
    }

    func reportMetric(params: Any, message: UserScriptMessage) async -> Encodable? {
        if let paramsDict = params as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict, options: []) {

            let decoder = JSONDecoder()
            do {
                let metric = try decoder.decode(AIChatMetric.self, from: jsonData)
                metricReportingHandler?.didReportMetric(metric)
            } catch {
                Logger.aiChat.debug("Failed to decode metric JSON in AIChatUserScript: \(error)")
            }
        }
        return nil
    }

    public func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) -> Encodable? {
        AIChatNativeConfigValues.defaultValues
    }

    @MainActor
    public func getResponseState(params: Any, message: UserScriptMessage) async -> Encodable? {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: params, options: [])
            let decodedStatus = try JSONDecoder().decode(AIChatStatus.self, from: jsonData)
            inputBoxHandler?.aiChatStatus = decodedStatus.status
            return nil
        } catch {
            return nil
        }
    }

    @MainActor
    func hideChatInput(params: Any, message: UserScriptMessage) async -> Encodable? {
        inputBoxHandler?.aiChatInputBoxVisibility = .hidden
        return nil
    }

    @MainActor
    func showChatInput(params: Any, message: UserScriptMessage) async -> Encodable? {
        inputBoxHandler?.aiChatInputBoxVisibility = .visible
        return nil
    }

    public func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable? {
        AIChatNativeHandoffData.defaultValuesWithPayload(payloadHandler?.consumeData() as? AIChatPayload)
    }

    func setPayloadHandler(_ payloadHandler: (any AIChatConsumableDataHandling)?) {
        self.payloadHandler = payloadHandler
    }

    func setAIChatInputBoxHandler(_ inputBoxHandler: (any AIChatInputBoxHandling)?) {
        self.inputBoxHandler = inputBoxHandler
    }

    func setMetricReportingHandler(_ metricHandler: (any AIChatMetricReportingHandling)?) {
        self.metricReportingHandler = metricHandler
    }

    // Workaround for WKWebView: see https://app.asana.com/1/137249556945/task/1211361207345641/comment/1211365575147531?focus=true
    func openKeyboard(params: Any, message: UserScriptMessage, webView: WKWebView?) async -> Encodable? {
        guard let paramsDict = params as? [String: Any] else {
            Logger.aiChat.error("Invalid params format for openKeyboard")
            return OpenKeyboardResponse(success: false, error: "Invalid parameters format")
        }
        guard let cssSelector = paramsDict["selector"] as? String, !cssSelector.isEmpty else {
            Logger.aiChat.error("Missing or empty CSS selector for openKeyboard")
            return OpenKeyboardResponse(success: false, error: "Missing or empty CSS selector")
        }

        guard let webView = webView else {
            Logger.aiChat.error("WebView not available for openKeyboard")
            return OpenKeyboardResponse(success: false, error: "WebView not available")
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let javascript = """
                (function() {
                    try {
                        const element = document.querySelector('\(cssSelector)');
                        element?.focus?.();
                        return true;
                    } catch (error) {
                        console.error('Error focusing element:', error);
                        return false;
                    }
                })();
                """

                webView.evaluateJavaScript(javascript) { _, error in
                    if let error = error {
                        Logger.aiChat.error("Failed to execute openKeyboard JavaScript: \(error.localizedDescription)")
                        continuation.resume(returning: OpenKeyboardResponse(success: false, error: "JavaScript execution failed"))
                    } else {
                        continuation.resume(returning: OpenKeyboardResponse(success: true))
                    }
                }
            }
        }
    }
}

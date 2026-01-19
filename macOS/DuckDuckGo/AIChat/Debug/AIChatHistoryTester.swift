//
//  AIChatHistoryTester.swift
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

import AppKit
import AIChat
import BrowserServicesKit
import Combine
import os.log
import PrivacyConfig
import UserScript
import WebKit

/// A test helper class for fetching AI Chat history using a dedicated WebView.
/// Similar to HistoryCleaner, this creates a headless WebView to communicate with the frontend.
@MainActor
final class AIChatHistoryTester {

    private var webView: WKWebView?
    private var coordinator: Coordinator?
    private var contentScopeUserScript: ContentScopeUserScript?
    private var chatHistoryUserScript: AIChatChatHistoryUserScript?
    private var continuation: CheckedContinuation<Result<AIChatChatHistoryUserScript.ChatsResult, Error>, Never>?
    private var navigationContinuation: CheckedContinuation<Result<Void, Error>, Never>?

    private let featureFlagger: FeatureFlagger
    private let privacyConfig: PrivacyConfigurationManaging
    private let debugURLSettings: AIChatDebugURLSettingsRepresentable

    init(featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         privacyConfig: PrivacyConfigurationManaging = NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager,
         debugURLSettings: AIChatDebugURLSettingsRepresentable = AIChatDebugURLSettings()) {
        self.featureFlagger = featureFlagger
        self.privacyConfig = privacyConfig
        self.debugURLSettings = debugURLSettings
    }

    /// Returns the URL to use for fetching chat history
    private var chatHistoryURL: URL {
        if let customURLString = debugURLSettings.customURL,
           let customURL = URL(string: customURLString) {
            return customURL
        }
        // Default to duckduckgo.com AI Chat
        return URL(string: "https://duckduckgo.com/?ia=chat&duckai=1&q=1")!
    }

    /// Fetches chat history from Duck.ai
    /// - Parameter query: Search query to filter chats (nil returns all chats)
    func fetchChatHistory(query: String? = nil) async -> Result<AIChatChatHistoryUserScript.ChatsResult, Error> {
        guard webView == nil else {
            return .failure(TesterError.alreadyRunning)
        }

        self.requestedQuery = query

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor in
                await self.performFetch()
            }
        }
    }

    private var requestedQuery: String?

    private func performFetch() async {
        do {
            try setupWebView()

            // Navigate to AI Chat URL (custom URL if set, otherwise duckduckgo.com)
            Logger.aiChat.debug("AIChatHistoryTester: Using URL \(self.chatHistoryURL.absoluteString)")
            let navigationResult = await navigateToDuckAI()
            guard case .success = navigationResult else {
                Logger.aiChat.error("AIChatHistoryTester: Navigation failed")
                if case .failure(let error) = navigationResult {
                    finish(result: .failure(error))
                }
                return
            }
            Logger.aiChat.debug("AIChatHistoryTester: Navigation completed successfully")

            // Wait a moment for the script to initialize
            Logger.aiChat.debug("AIChatHistoryTester: Waiting for script initialization...")
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Request chat history
            guard let chatHistoryUserScript else {
                Logger.aiChat.error("AIChatHistoryTester: Script not initialized")
                finish(result: .failure(TesterError.scriptNotInitialized))
                return
            }

            Logger.aiChat.debug("AIChatHistoryTester: Requesting chat history with query=\(String(describing: self.requestedQuery))...")
            let historyResult = await chatHistoryUserScript.getChatsAsync(query: requestedQuery, timeout: 10)
            
            switch historyResult {
            case .success(let result):
                Logger.aiChat.debug("AIChatHistoryTester: Got \(result.chats.count) chats")
            case .failure(let error):
                Logger.aiChat.error("AIChatHistoryTester: Failed with error: \(error)")
            }
            
            finish(result: historyResult)

        } catch {
            finish(result: .failure(error))
        }
    }

    private func setupWebView() throws {
        // Include custom hostname if set
        var additionalHostnames: [String] = []
        if let customHostname = debugURLSettings.customURLHostname {
            additionalHostnames.append(customHostname)
        }

        let chatHistory = AIChatChatHistoryUserScript(additionalHostnames: additionalHostnames)

        let features = ContentScopeFeatureToggles(
            emailProtection: false,
            emailProtectionIncontextSignup: false,
            credentialsAutofill: false,
            identitiesAutofill: false,
            creditCardsAutofill: false,
            credentialsSaving: false,
            passwordGeneration: false,
            inlineIconCredentials: false,
            thirdPartyCredentialsProvider: false,
            unknownUsernameCategorization: false,
            partialFormSaves: false,
            passwordVariantCategorization: false,
            inputFocusApi: false,
            autocompleteAttributeSupport: false
        )

        let contentScopeProperties = ContentScopeProperties(
            gpcEnabled: false,
            sessionKey: UUID().uuidString,
            messageSecret: UUID().uuidString,
            isInternalUser: featureFlagger.internalUserDecider.isInternalUser,
            featureToggles: features
        )

        // Use a custom privacy config that enables duckAiChatHistory
        let customConfigGenerator = DuckAiChatHistoryPrivacyConfigGenerator(
            baseConfig: privacyConfig,
            customHostname: debugURLSettings.customURLHostname
        )

        let contentScope = try ContentScopeUserScript(
            privacyConfig,
            properties: contentScopeProperties,
            scriptContext: .aiChatHistory,
            allowedNonisolatedFeatures: [chatHistory.featureName],
            privacyConfigurationJSONGenerator: customConfigGenerator
        )
        contentScope.registerSubfeature(delegate: chatHistory)

        let userContentController = WKUserContentController()
        userContentController.addUserScript(contentScope.makeWKUserScriptSync())
        userContentController.addHandler(contentScope)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let coordinator = Coordinator(tester: self)
        webView.navigationDelegate = coordinator

        chatHistory.webView = webView
        self.webView = webView
        self.coordinator = coordinator
        self.contentScopeUserScript = contentScope
        self.chatHistoryUserScript = chatHistory
    }

    private func navigateToDuckAI() async -> Result<Void, Error> {
        guard let webView else {
            return .failure(TesterError.webViewNotInitialized)
        }

        return await withCheckedContinuation { continuation in
            self.navigationContinuation = continuation

            let url = chatHistoryURL
            Logger.aiChat.debug("AIChatHistoryTester: Loading simulated request for \(url.absoluteString)")
            
            // Use loadSimulatedRequest like HistoryCleaner - this sets the origin
            // without loading the actual page, giving us access to localStorage
            if #available(macOS 12.0, *) {
                webView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "")
            } else {
                webView.loadHTMLString("", baseURL: url)
            }
        }
    }

    func completeNavigation(with result: Result<Void, Error>) {
        navigationContinuation?.resume(returning: result)
        navigationContinuation = nil
    }

    private func finish(result: Result<AIChatChatHistoryUserScript.ChatsResult, Error>) {
        tearDown()
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func tearDown() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        coordinator = nil
        chatHistoryUserScript = nil
        contentScopeUserScript = nil
    }

    // MARK: - Errors

    enum TesterError: Error, LocalizedError {
        case alreadyRunning
        case webViewNotInitialized
        case scriptNotInitialized
        case navigationFailed

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "Test already in progress"
            case .webViewNotInitialized: return "WebView not initialized"
            case .scriptNotInitialized: return "Script not initialized"
            case .navigationFailed: return "Navigation to duck.ai failed"
            }
        }
    }

    // MARK: - Navigation Delegate

    private final class Coordinator: NSObject, WKNavigationDelegate {
        weak var tester: AIChatHistoryTester?

        init(tester: AIChatHistoryTester) {
            self.tester = tester
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            tester?.completeNavigation(with: .success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            tester?.completeNavigation(with: .failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            tester?.completeNavigation(with: .failure(error))
        }
    }
}

@MainActor
private extension WKUserContentController {

    func addHandler(_ userScript: UserScript) {
        for messageName in userScript.messageNames {
            let contentWorld: WKContentWorld = userScript.getContentWorld()
            if let handlerWithReply = userScript as? WKScriptMessageHandlerWithReply {
                addScriptMessageHandler(handlerWithReply, contentWorld: contentWorld, name: messageName)
            } else {
                add(userScript, contentWorld: contentWorld, name: messageName)
            }
        }
    }
}

// MARK: - Custom Privacy Config Generator

/// A custom privacy configuration generator that enables the duckAiChatHistory feature for testing
private struct DuckAiChatHistoryPrivacyConfigGenerator: CustomisedPrivacyConfigurationJSONGenerating {
    let baseConfig: PrivacyConfigurationManaging
    let customHostname: String?

    var privacyConfiguration: Data? {
        // Get the base config
        guard var configDict = try? JSONSerialization.jsonObject(with: baseConfig.currentConfig, options: []) as? [String: Any] else {
            return nil
        }

        // Ensure features dictionary exists
        var features = configDict["features"] as? [String: Any] ?? [:]

        // Build exceptions list - include custom hostname if set
        var exceptions: [[String: String]] = []
        if let hostname = customHostname {
            exceptions.append(["domain": hostname])
        }

        // Add duckAiChatHistory feature with enabled state
        features["duckAiChatHistory"] = [
            "state": "enabled",
            "exceptions": exceptions,
            "settings": [
                "chatsLocalStorageKeys": ["savedAIChats"]
            ] as [String: Any]
        ] as [String: Any]

        configDict["features"] = features

        return try? JSONSerialization.data(withJSONObject: configDict, options: [])
    }
}

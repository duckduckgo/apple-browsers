//
//  HistoryCleaner.swift
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

import BrowserServicesKit
import os.log
import PrivacyConfig
import UserScript
import WebKit

public protocol HistoryCleaning {
    @MainActor func cleanAIChatHistory() async -> Result<Void, Error>
    @MainActor func deleteAIChat(chatID: String) async -> Result<Void, Error>
}

public final class HistoryCleaner: HistoryCleaning {
    private var continuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var navigationContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var webView: WKWebView?
    private var coordinator: Coordinator?
    private let featureFlagger: FeatureFlagger
    private let privacyConfig: PrivacyConfigurationManaging
    private var contentScopeUserScript: ContentScopeUserScript?
    private var aiChatDataClearingUserScript: AIChatDataClearingUserScript?

    public init(featureFlagger: FeatureFlagger,
                privacyConfig: PrivacyConfigurationManaging) {
        self.featureFlagger = featureFlagger
        self.privacyConfig = privacyConfig
    }

    /// Launches a headless web view to clear Duck.ai chat history with a C-S-S feature.
    @MainActor
    public func cleanAIChatHistory() async -> Result<Void, Error> {
        await performDelete(chatID: nil)
    }

    /// Launches a headless web view to clear a single Duck.ai chat with a C-S-S feature.
    @MainActor
    public func deleteAIChat(chatID: String) async -> Result<Void, Error> {
        await performDelete(chatID: chatID)
    }

    private func performDelete(chatID: String?) async -> Result<Void, Error> {
        guard webView == nil else {
            return .failure(HistoryCleanerError.operationInProgress)
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor in
                await self.processAllDomains(chatID: chatID)
            }
        }
    }

    @MainActor
    private func processAllDomains(chatID: String?) async {
        do {
            try setupWebView()
            for domain in URL.aiChatDomains {
                let navigationResult = await launchHistoryCleaningWebView(requestURL: domain)

                guard case .success = navigationResult else {
                    finish(result: navigationResult)
                    return
                }

                let clearingResult = await executeClearingScript(chatID: chatID)

                guard case .success = clearingResult else {
                    finish(result: clearingResult)
                    return
                }
            }

            finish(result: .success(()))
        } catch {
            finish(result: .failure(error))
        }
    }

    // MARK: - WebView Setup

    @MainActor
    private func setupWebView() throws {
        let aiChatDataClearing = AIChatDataClearingUserScript()

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

        let contentScope = try ContentScopeUserScript(
            privacyConfig,
            properties: contentScopeProperties,
            scriptContext: .aiChatDataClearing,
            allowedNonisolatedFeatures: [aiChatDataClearing.featureName],
            privacyConfigurationJSONGenerator: nil
        )
        contentScope.registerSubfeature(delegate: aiChatDataClearing)

        let userContentController = WKUserContentController()
        userContentController.addUserScript(contentScope.makeWKUserScriptSync())
        userContentController.addHandler(contentScope)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let coordinator = Coordinator(cleaner: self)
        webView.navigationDelegate = coordinator

        aiChatDataClearing.webView = webView
        self.webView = webView
        self.coordinator = coordinator
        self.contentScopeUserScript = contentScope
        self.aiChatDataClearingUserScript = aiChatDataClearing
    }

    // MARK: - Domain Navigation

    @MainActor
    private func launchHistoryCleaningWebView(requestURL: URL) async -> Result<Void, Error> {
        guard let webView = webView else {
            return .failure(HistoryCleanerError.webViewNotInitialized)
        }

        return await withCheckedContinuation { continuation in
            self.navigationContinuation = continuation

            if #available(iOS 15.0, macOS 12.0, *) {
                webView.loadSimulatedRequest(URLRequest(url: requestURL), responseHTML: "")
            } else {
                webView.loadHTMLString("", baseURL: requestURL)
            }
        }
    }

    @MainActor
    private func completeNavigation(with result: Result<Void, Error>) {
        navigationContinuation?.resume(returning: result)
        navigationContinuation = nil
    }

    // MARK: - Script Execution

    @MainActor
    private func executeClearingScript(chatID: String?) async -> Result<Void, Error> {
        guard let script = aiChatDataClearingUserScript else {
            return .failure(HistoryCleanerError.scriptNotInitialized)
        }

        return await script.clearAIChatDataAsync(chatID: chatID, timeout: 5)
    }

    // MARK: - Cleanup

    @MainActor
    private func finish(result: Result<Void, Error>) {
        tearDownClearingWebView()
        continuation?.resume(returning: result)
        continuation = nil
    }

    @MainActor
    private func tearDownClearingWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        coordinator = nil
        aiChatDataClearingUserScript = nil
        contentScopeUserScript = nil
    }
}

// MARK: - Errors
extension HistoryCleaner {
    enum HistoryCleanerError: Error {
        case webViewNotInitialized
        case scriptNotInitialized
        case operationInProgress
    }
}

// MARK: - Navigation Delegate
extension HistoryCleaner {
    private final class Coordinator: NSObject, WKNavigationDelegate {
        weak var cleaner: HistoryCleaner?

        init(cleaner: HistoryCleaner) {
            self.cleaner = cleaner
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            cleaner?.completeNavigation(with: .success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            cleaner?.completeNavigation(with: .failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            cleaner?.completeNavigation(with: .failure(error))
        }
    }
}

@MainActor
extension WKUserContentController {

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

    func removeHandler(_ userScript: UserScript) {
        userScript.messageNames.forEach {
            let contentWorld: WKContentWorld = userScript.getContentWorld()
            removeScriptMessageHandler(forName: $0, contentWorld: contentWorld)
        }
    }
}

extension URL {
    static let aiChatDomains: [URL] = [
        URL(string: "https://duckduckgo.com")!,
        URL(string: "https://duck.ai")!
    ]
}

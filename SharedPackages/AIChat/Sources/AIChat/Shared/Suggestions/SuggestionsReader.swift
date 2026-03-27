//
//  SuggestionsReader.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

// MARK: - Protocol

public protocol SuggestionsReading {
    /// Fetches AI chat suggestions from duck.ai storage.
    /// - Parameters:
    ///   - query: Optional search query to filter results
    ///   - maxChats: Maximum number of recent (non-pinned) chats to return
    /// - Returns: Result containing pinned and recent suggestions, or an error
    @MainActor
    func fetchSuggestions(query: String?, maxChats: Int) async -> Result<(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]), Error>

    /// Tears down the WebView and releases resources.
    /// Should be called when the AI chat mode is deactivated.
    @MainActor
    func tearDown()
}

// MARK: - SuggestionsReader

@MainActor
public final class SuggestionsReader: SuggestionsReading {

    // MARK: - Errors

    public enum ReaderError: Error, LocalizedError {
        case webViewNotInitialized
        case scriptNotInitialized
        case operationSuperseded
        case navigationFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .webViewNotInitialized:
                return "WebView not initialized"
            case .scriptNotInitialized:
                return "UserScript not initialized"
            case .operationSuperseded:
                return "Operation superseded"
            case .navigationFailed(let error):
                return "Navigation failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    private var webView: WKWebView?
    private var coordinator: Coordinator?
    private var contentScopeUserScript: ContentScopeUserScript?
    private var suggestionsUserScript: AIChatSuggestionsUserScript?

    private var navigationContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var fetchContinuation: CheckedContinuation<Result<(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]), Error>, Never>?
    private var isWebViewReady = false
    private var isSettingUp = false

    private let featureFlagger: FeatureFlagger
    private let privacyConfig: PrivacyConfigurationManaging

    // MARK: - Initialization

    public init(featureFlagger: FeatureFlagger, privacyConfig: PrivacyConfigurationManaging) {
        self.featureFlagger = featureFlagger
        self.privacyConfig = privacyConfig
    }

    // MARK: - Public API

    @MainActor
    public func fetchSuggestions(query: String?, maxChats: Int) async -> Result<(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]), Error> {
        // Prevent re-entrant setup
        if isSettingUp {
            return .failure(ReaderError.webViewNotInitialized)
        }

        // Lazy initialization: set up WebView on first call
        if !isWebViewReady {
            isSettingUp = true
            defer { isSettingUp = false }

            do {
                try setupWebView()
                isWebViewReady = true
            } catch {
                Logger.aiChat.error("SuggestionsReader: Setup failed: \(error.localizedDescription)")
                return .failure(error)
            }
        }

        guard let script = suggestionsUserScript else {
            Logger.aiChat.error("SuggestionsReader: Script not initialized")
            return .failure(ReaderError.scriptNotInitialized)
        }

        // Fetch suggestions from duck.ai
        return await fetchSuggestionsFromDuckAi(query: query, maxChats: maxChats, script: script)
    }

    /// One week in seconds
    private static let oneWeekInterval: TimeInterval = 7 * 24 * 60 * 60

    @MainActor
    private func fetchSuggestionsFromDuckAi(
        query: String?,
        maxChats: Int,
        script: AIChatSuggestionsUserScript
    ) async -> Result<(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]), Error> {
        // When query is empty, only show chats from the last week
        let since: Int64?
        if query == nil || query?.isEmpty == true {
            let oneWeekAgo = Date().addingTimeInterval(-Self.oneWeekInterval)
            since = Int64(oneWeekAgo.timeIntervalSince1970 * 1000) // Convert to milliseconds
        } else {
            since = nil
        }

        // Only read suggestions from duck.ai — duckduckgo.com data was migrated
        let domain = URL.duckAi
        let navigationResult = await navigateToSite(domain)
        if case .failure(let error) = navigationResult {
            Logger.aiChat.debug("SuggestionsReader: Navigation to \(domain) failed: \(error.localizedDescription)")
            return .failure(error)
        }

        // Fetch suggestions
        let fetchResult = await withCheckedContinuation { continuation in
            // Resume any previous continuation to avoid leaking a suspended caller
            self.fetchContinuation?.resume(returning: .failure(ReaderError.operationSuperseded))
            self.fetchContinuation = continuation
            script.fetchChats(query: query, maxChats: maxChats, since: since)
        }

        switch fetchResult {
        case .success(let suggestions):
            return .success(suggestions)
        case .failure(let error):
            Logger.aiChat.debug("SuggestionsReader: Fetch from \(domain) failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    @MainActor
    public func tearDown() {
        if let webView {
            let userContentController = webView.configuration.userContentController

            if let contentScopeUserScript {
                userContentController.removeHandler(contentScopeUserScript)
            }

            userContentController.removeAllUserScripts()
            if #available(iOS 14.0, macOS 11.0, *) {
                userContentController.removeAllScriptMessageHandlers()
            }
        }

        suggestionsUserScript?.webView = nil
        suggestionsUserScript?.onChatsReceived = nil

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        coordinator = nil
        suggestionsUserScript = nil
        contentScopeUserScript = nil
        isWebViewReady = false
        isSettingUp = false

        // Resume any pending continuations to avoid hanging tasks
        navigationContinuation?.resume(returning: .failure(ReaderError.webViewNotInitialized))
        navigationContinuation = nil
        fetchContinuation?.resume(returning: .failure(ReaderError.webViewNotInitialized))
        fetchContinuation = nil
    }

    // MARK: - WebView Setup

    @MainActor
    private func setupWebView() throws {
        let suggestionsScript = AIChatSuggestionsUserScript()

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
            scriptContext: .aiChatHistory,
            allowedNonisolatedFeatures: [suggestionsScript.featureName],
            privacyConfigurationJSONGenerator: nil
        )
        contentScope.registerSubfeature(delegate: suggestionsScript)

        let userContentController = WKUserContentController()
        userContentController.addUserScript(contentScope.makeWKUserScriptSync())
        userContentController.addHandler(contentScope)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let coordinator = Coordinator(reader: self)
        webView.navigationDelegate = coordinator

        // Enable Web Inspector for debugging (macOS 13.3+)
        #if DEBUG
        if #available(macOS 13.3, iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        // Set up callback to resume continuation when results arrive
        suggestionsScript.onChatsReceived = { [weak self] result in
            self?.fetchContinuation?.resume(returning: result)
            self?.fetchContinuation = nil
        }

        suggestionsScript.webView = webView
        self.webView = webView
        self.coordinator = coordinator
        self.contentScopeUserScript = contentScope
        self.suggestionsUserScript = suggestionsScript
    }

    // MARK: - Navigation

    @MainActor
    private func navigateToSite(_ url: URL) async -> Result<Void, Error> {
        guard let webView else {
            return .failure(ReaderError.webViewNotInitialized)
        }

        return await withCheckedContinuation { continuation in
            // Resume any previous continuation to avoid leaking a suspended caller
            self.navigationContinuation?.resume(returning: .failure(ReaderError.operationSuperseded))
            self.navigationContinuation = continuation

            if #available(iOS 15.0, macOS 12.0, *) {
                webView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "")
            } else {
                webView.loadHTMLString("", baseURL: url)
            }
        }
    }

    @MainActor
    fileprivate func completeNavigation(with result: Result<Void, Error>) {
        navigationContinuation?.resume(returning: result)
        navigationContinuation = nil
    }
}

// MARK: - Navigation Delegate Coordinator

extension SuggestionsReader {

    fileprivate final class Coordinator: NSObject, WKNavigationDelegate {
        weak var reader: SuggestionsReader?

        init(reader: SuggestionsReader) {
            self.reader = reader
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            reader?.completeNavigation(with: .success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reader?.completeNavigation(with: .failure(ReaderError.navigationFailed(error)))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reader?.completeNavigation(with: .failure(ReaderError.navigationFailed(error)))
        }
    }
}

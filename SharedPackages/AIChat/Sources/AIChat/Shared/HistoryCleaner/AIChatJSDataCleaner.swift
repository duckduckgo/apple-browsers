//
//  AIChatJSDataCleaner.swift
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

/// Clears Duck.ai data held in the JS layer (localStorage, IndexedDB) by loading each
/// Duck.ai domain in a headless WebView and invoking the content-scope-scripts
/// `duck-ai-data-clearing` feature.
public protocol AIChatJSDataCleaning {
    @MainActor func clearJSData(chatID: String?) async -> Result<Void, Error>
    /// Clears a specific set of chats, reusing one web view session.
    @MainActor func clearJSData(chatIDs: [String]) async -> Result<Void, Error>
    /// What happened during the most recent clear, or `nil` before the first one.
    @MainActor var lastReport: AIChatClearingReport? { get }
}

public extension AIChatJSDataCleaning {
    @MainActor var lastReport: AIChatClearingReport? { nil }
}

public final class WebViewAIChatJSDataCleaner: AIChatJSDataCleaning {

    enum CleanerError: Error {
        case webViewNotInitialized
        case operationInProgress
    }

    private let featureFlagger: FeatureFlagger
    private let privacyConfig: PrivacyConfigurationManaging
    private let websiteDataStore: WKWebsiteDataStore

    public private(set) var lastReport: AIChatClearingReport?
    private var isClearing = false
    private static let retryDelay: TimeInterval = 1
    private let navigationWaiter = CallbackWaiter()
    /// Loading the local page normally takes under a second; this only catches loads that never end.
    private static let navigationTimeout: TimeInterval = 10
    private var webView: WKWebView?
    private var coordinator: Coordinator?
    private var contentScopeUserScript: ContentScopeUserScript?
    private var aiChatDataClearingUserScript: AIChatDataClearingUserScript?

    public init(featureFlagger: FeatureFlagger,
                privacyConfig: PrivacyConfigurationManaging,
                websiteDataStore: WKWebsiteDataStore) {
        self.featureFlagger = featureFlagger
        self.privacyConfig = privacyConfig
        self.websiteDataStore = websiteDataStore
    }

    @MainActor
    public func clearJSData(chatID: String?) async -> Result<Void, Error> {
        if let chatID {
            Logger.aiChat.debug("WebViewAIChatJSDataCleaner: deleting chat \(chatID) from webView")
        } else {
            Logger.aiChat.debug("WebViewAIChatJSDataCleaner: deleting all chats from webView")
        }
        // `nil` clears everything in one message; a single id clears just that chat.
        return await clear(chatIDs: chatID.map { [$0] })
    }

    @MainActor
    public func clearJSData(chatIDs: [String]) async -> Result<Void, Error> {
        guard !chatIDs.isEmpty else { return .success(()) }
        Logger.aiChat.debug("WebViewAIChatJSDataCleaner: deleting \(chatIDs.count) chats from webView")
        return await clear(chatIDs: chatIDs)
    }

    /// - Parameter chatIDs: `nil` clears all chats; otherwise the specific ids, cleared within a
    ///   single web view session.
    @MainActor
    private func clear(chatIDs: [String]?) async -> Result<Void, Error> {
        guard !isClearing else {
            return .failure(CleanerError.operationInProgress)
        }
        isClearing = true
        defer { isClearing = false }

        var firstAttemptTimings: AIChatClearingTimings?
        let attempts = AIChatClearingAttempts(retryDelay: Self.retryDelay, isTransient: Self.isTransient)
        let outcome = await attempts.run {
            let (result, timings) = await clearAllOrigins(chatIDs: chatIDs)
            firstAttemptTimings = firstAttemptTimings ?? timings
            return result
        }
        lastReport = AIChatClearingReport(attempts: outcome.attempts,
                                          firstAttemptError: outcome.firstAttemptError,
                                          firstAttemptTimings: firstAttemptTimings ?? AIChatClearingTimings())
        return outcome.result
    }

    /// Failures a fresh web view session can fix; internal misuse such as a missing script is not retried.
    static func isTransient(_ error: Error) -> Bool {
        if let clearError = error as? AIChatDataClearingUserScript.ClearError {
            return clearError.isTransient
        }
        return [WKErrorDomain, "WebKitErrorDomain", NSURLErrorDomain].contains((error as NSError).domain)
    }

    /// One attempt on a fresh web view, torn down afterwards.
    @MainActor
    private func clearAllOrigins(chatIDs: [String]?) async -> (Result<Void, Error>, AIChatClearingTimings) {
        let recorder = AIChatClearingTimingsRecorder()
        let script: AIChatDataClearingUserScript
        do {
            script = try setupWebView()
        } catch {
            return (.failure(error), recorder.timings)
        }
        defer { tearDown() }

        let sequence = AIChatClearingSequence(
            origins: URL.aiChatDomains,
            loadOrigin: { [weak self] origin in
                await self?.loadOriginWithListeningScript(origin, script: script, recorder: recorder) ?? .failure(CleanerError.webViewNotInitialized)
            },
            clear: { chatID in
                await recorder.measure(\.scriptReplyMilliseconds) { await script.clearAIChatDataAsync(chatID: chatID) }
            },
            requiresReload: { ($0 as? AIChatDataClearingUserScript.ClearError)?.requiresPageReload ?? false }
        )
        let result = await sequence.run(chatIDs: chatIDs)
        return (result, recorder.timings)
    }

    @MainActor
    private func setupWebView() throws -> AIChatDataClearingUserScript {
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
        configuration.websiteDataStore = websiteDataStore

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let coordinator = Coordinator(cleaner: self)
        webView.navigationDelegate = coordinator

        aiChatDataClearing.webView = webView
        self.webView = webView
        self.coordinator = coordinator
        self.contentScopeUserScript = contentScope
        self.aiChatDataClearingUserScript = aiChatDataClearing
        return aiChatDataClearing
    }

    /// Loads the origin and waits for the clearing script to listen, so the clear message isn't lost.
    @MainActor
    private func loadOriginWithListeningScript(_ origin: URL,
                                               script: AIChatDataClearingUserScript,
                                               recorder: AIChatClearingTimingsRecorder) async -> Result<Void, Error> {
        script.prepareForPageLoad()
        let loaded = await recorder.measure(\.pageLoadMilliseconds) { await launchClearingWebView(requestURL: origin) }
        guard case .success = loaded else { return loaded }
        return await recorder.measure(\.scriptReadyMilliseconds) { await script.waitUntilReady() }
    }

    @MainActor
    private func launchClearingWebView(requestURL: URL) async -> Result<Void, Error> {
        guard let webView = webView else {
            return .failure(CleanerError.webViewNotInitialized)
        }

        let result = await navigationWaiter.wait(timeout: Self.navigationTimeout,
                                                 timeoutError: AIChatDataClearingUserScript.ClearError.navigationTimeout) {
            webView.loadSimulatedRequest(URLRequest(url: requestURL), responseHTML: "")
        }
        if case .failure = result {
            webView.stopLoading()
        }
        return result
    }

    @MainActor
    private func completeNavigation(_ navigation: WKNavigation?, with result: Result<Void, Error>) {
        navigationWaiter.complete(navigation, with: result)
    }

    /// WebKit reports no navigation failure when the page's process dies, so fail whatever is waiting on it.
    @MainActor
    private func handleWebContentProcessTermination() {
        let error = AIChatDataClearingUserScript.ClearError.webContentProcessTerminated
        navigationWaiter.failPending(with: error)
        aiChatDataClearingUserScript?.failPendingWaits(with: error)
    }

    @MainActor
    private func tearDown() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        coordinator = nil
        aiChatDataClearingUserScript = nil
        contentScopeUserScript = nil
    }
}

// MARK: - Navigation Delegate
extension WebViewAIChatJSDataCleaner {
    private final class Coordinator: NSObject, WKNavigationDelegate {
        weak var cleaner: WebViewAIChatJSDataCleaner?

        init(cleaner: WebViewAIChatJSDataCleaner) {
            self.cleaner = cleaner
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            cleaner?.completeNavigation(navigation, with: .success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            cleaner?.completeNavigation(navigation, with: .failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            cleaner?.completeNavigation(navigation, with: .failure(error))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            cleaner?.handleWebContentProcessTermination()
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
    static let duckAi = URL(string: "https://duck.ai")!
    static let duckDuckGo = URL(string: "https://duckduckgo.com")!

    static let aiChatDomains: [URL] = [
        .duckDuckGo,
        .duckAi
    ]
}

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

import WebKit
import UserScript
import BrowserServicesKit
import os.log

public protocol HistoryCleaning {
    @MainActor func cleanAIChatHistory() async -> Result<Void, Error>
}

public final class HistoryCleaner: HistoryCleaning {
    private var continuation: CheckedContinuation<Result<Void, Error>, Never>?
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
        guard webView == nil else { return .success(()) }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.launchHistoryCleaningWebView()
        }
    }

    // MARK: - Headless WebView
    @MainActor
    private func launchHistoryCleaningWebView() {
        do {
            let aiChatDataClearing = AIChatDataClearingUserScript()

            let features = ContentScopeFeatureToggles(emailProtection: false,
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
                                                      autocompleteAttributeSupport: false)
            let contentScopeProperties = ContentScopeProperties(gpcEnabled: false,
                                                                sessionKey: UUID().uuidString,
                                                                messageSecret: UUID().uuidString,
                                                                isInternalUser: featureFlagger.internalUserDecider.isInternalUser,
                                                                featureToggles: features)
            let contentScope = try ContentScopeUserScript(privacyConfig,
                                                          properties: contentScopeProperties,
                                                          allowedNonisolatedFeatures: [aiChatDataClearing.featureName],
                                                          privacyConfigurationJSONGenerator: nil)
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

            if #available(iOS 15.0, macOS 12.0, *) {
                webView.loadSimulatedRequest(URLRequest(url: URL.duckDuckGo), responseHTML: "")
            } else {
                webView.loadHTMLString("", baseURL: URL.duckDuckGo)
            }
        } catch {
            finish(result: .failure(error))
        }
    }

    @MainActor
    private func finish(result: Result<Void, Error>) {
        tearDownClearingWebView()
        continuation?.resume(returning: result)
        continuation = nil
    }

    @MainActor
    private func startClearing() {
        Task { @MainActor [weak self] in
            guard let self, let script = aiChatDataClearingUserScript else { return }
            let result = await script.clearAIChatDataAsync(timeout: 5)
            self.finish(result: result)
        }
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

// MARK: - Navigation Delegate Wrapper
extension HistoryCleaner {
    private final class Coordinator: NSObject, WKNavigationDelegate {
        weak var cleaner: HistoryCleaner?
        init(cleaner: HistoryCleaner) { self.cleaner = cleaner }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            cleaner?.startClearing()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            cleaner?.finish(result: .failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            cleaner?.finish(result: .failure(error))
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
    static let duckDuckGo = URL(string: "https://duckduckgo.com")!

}

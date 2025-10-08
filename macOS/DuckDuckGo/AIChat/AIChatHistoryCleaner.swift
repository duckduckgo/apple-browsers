//
//  AIChatHistoryCleaner.swift
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
import Foundation
import Combine
import PixelKit
import WebKit
import UserScript

protocol AIChatHistoryCleaning {
    /// Whether the option to clear Duck.ai chat history should be displayed to the user.
    var shouldDisplayCleanAIChatHistoryOption: Bool { get }

    /// Publisher that emits updates to the `shouldDisplayCleanAIChatHistoryOption` property.
    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> { get }

    /// Deletes all Duck.ai chat history.
    @MainActor func cleanAIChatHistory()
}

final class AIChatHistoryCleaner: AIChatHistoryCleaning {

    private let featureFlagger: FeatureFlagger
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    let notificationCenter: NotificationCenter
    private var featureDiscoveryObserver: NSObjectProtocol?
    private let privacyConfig: PrivacyConfigurationManaging
    private let pixelKit: PixelKit?

    private var webView: WKWebView?
    private var coordinator: Coordinator?
    private var aiChatDataClearingUserScript: AIChatDataClearingUserScript?
    private var contentScopeUserScript: ContentScopeUserScript?

    @Published
    private var aiChatWasUsedBefore: Bool

    @Published
    var shouldDisplayCleanAIChatHistoryOption: Bool = false

    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> {
        $shouldDisplayCleanAIChatHistoryOption.eraseToAnyPublisher()
    }

    init(featureFlagger: FeatureFlagger,
         aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
         featureDiscovery: FeatureDiscovery,
         notificationCenter: NotificationCenter = .default,
         pixelKit: PixelKit? = PixelKit.shared,
         privacyConfig: PrivacyConfigurationManaging) {
        self.featureFlagger = featureFlagger
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.notificationCenter = notificationCenter
        self.privacyConfig = privacyConfig
        self.pixelKit = pixelKit
        aiChatWasUsedBefore = featureDiscovery.wasUsedBefore(.aiChat)

        subscribeToChanges()
    }

    deinit {
        if let token = featureDiscoveryObserver {
            notificationCenter.removeObserver(token)
        }
    }

    /// Launches a headless web view to clear Duck.ai chat history with a C-S-S feature.
    @MainActor
    func cleanAIChatHistory() {
        // Avoid launching multiple concurrent web views
        guard featureFlagger.isFeatureOn(.aiChatDataClearing), webView == nil else { return }

        launchHistoryCleaningWebView()
    }

    private func subscribeToChanges() {
        featureDiscoveryObserver = notificationCenter.addObserver(forName: .featureDiscoverySetWasUsedBefore, object: nil, queue: .main) { [weak self] notification in
            guard let featureRaw = notification.userInfo?["feature"] as? String,
                  featureRaw == WasUsedBeforeFeature.aiChat.rawValue else { return }
            self?.aiChatWasUsedBefore = true
        }

        $aiChatWasUsedBefore.combineLatest(aiChatMenuConfiguration.valuesChangedPublisher.prepend(()))
            .map { [weak self] wasUsed, _ in
                guard let self else { return false }
                return wasUsed && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatDataClearing)
            }
            .prepend(aiChatWasUsedBefore && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatDataClearing))
            .removeDuplicates()
            .assign(to: &$shouldDisplayCleanAIChatHistoryOption)
    }

    // MARK: - Headless WebView
    @MainActor
    private func launchHistoryCleaningWebView() {
        do {
            let aiChatDataClearing = AIChatDataClearingUserScript()
            aiChatDataClearing.delegate = self

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

            if #available(macOS 12.0, *) {
                webView.loadSimulatedRequest(URLRequest(url: URL.duckDuckGo), responseHTML: "")
            } else {
                webView.loadHTMLString("", baseURL: URL.duckDuckGo)
            }
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
                fatalError("Failed to initialize ContentScopeUserScript: \(error)")
            }
            tearDownClearingWebView()
        }
    }

    @MainActor
    private func tearDownClearingWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        coordinator = nil
        aiChatDataClearingUserScript?.delegate = nil
        aiChatDataClearingUserScript = nil
        contentScopeUserScript = nil
        notificationCenter.post(name: .aiChatHistoryClearDataCompleted, object: nil)
    }
}

// MARK: - AIChatDataClearingUserScriptDelegate Conformance
extension AIChatHistoryCleaner: AIChatDataClearingUserScriptDelegate {
    @MainActor
    func dataClearingSucceeded() {
        pixelKit?.fire(AIChatPixel.aiChatDeleteHistorySuccessful, frequency: .dailyAndCount)
        tearDownClearingWebView()
    }

    @MainActor
    func dataClearingFailed() {
        pixelKit?.fire(AIChatPixel.aiChatDeleteHistoryFailed, frequency: .dailyAndCount)
        tearDownClearingWebView()
    }
}

// MARK: - Navigation Delegate Wrapper
extension AIChatHistoryCleaner {
    private final class Coordinator: NSObject, WKNavigationDelegate {
        weak var cleaner: AIChatHistoryCleaner?
        init(cleaner: AIChatHistoryCleaner) {
            self.cleaner = cleaner
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            cleaner?.notificationCenter.post(name: .aiChatHistoryClearDataRequested, object: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            cleaner?.dataClearingFailed()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            cleaner?.dataClearingFailed()
        }
    }
}

// MARK: - Notifications
public extension NSNotification.Name {

    static let aiChatHistoryClearDataRequested = Notification.Name("aiChatHistoryClearDataRequested")
    static let aiChatHistoryClearDataCompleted = Notification.Name("aiChatHistoryClearDataCompleted")
}

//
//  AIChatContextualWebViewController.swift
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
import Combine
import Common
import Core
import PrivacyConfig
import UIKit
import UserScript
import WebKit

// MARK: - Delegate Protocol

protocol AIChatContextualWebViewControllerDelegate: AnyObject {
    func contextualWebViewController(_ viewController: AIChatContextualWebViewController, didRequestToLoad url: URL)
    func contextualWebViewController(_ viewController: AIChatContextualWebViewController, didUpdateContextualChatURL url: URL?)
}

final class AIChatContextualWebViewController: UIViewController {

    // MARK: - Properties

    weak var delegate: AIChatContextualWebViewControllerDelegate?

    private let aiChatSettings: AIChatSettingsProvider
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private let featureDiscovery: FeatureDiscovery
    private let featureFlagger: FeatureFlagger
    private let pageContextStore: AIChatPageContextStoring

    private(set) var aiChatContentHandler: AIChatContentHandling

    /// Passthrough delegate for the content handler. Set this to receive navigation callbacks.
    var aiChatContentHandlingDelegate: AIChatContentHandlingDelegate? {
        get { aiChatContentHandler.delegate }
        set { aiChatContentHandler.delegate = newValue }
    }

    /// Closure to provide page context for getAIChatPageContext requests from the frontend.
    var pageContextProvider: (() -> AIChatPageContextData?)? {
        get { aiChatContentHandler.pageContextProvider }
        set { aiChatContentHandler.pageContextProvider = newValue }
    }

    private var pendingPrompt: String?
    private var pendingPageContext: AIChatPageContextData?
    private var userContentController: UserContentController?
    private var isPageReady = false
    private var isContentHandlerReady = false
    private var urlObservation: NSKeyValueObservation?
    private var lastContextualChatURL: URL?

    /// URL to load on viewDidLoad instead of the default AI chat URL (for cold restore).
    var initialRestoreURL: URL?

    // MARK: - UI Components

    private lazy var webView: WKWebView = {
        let webView = WKWebView(frame: .zero, configuration: createWebViewConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()

    private lazy var loadingView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.color = .label
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hidesWhenStopped = true
        return view
    }()

    // MARK: - Initialization

    init(aiChatSettings: AIChatSettingsProvider,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         featureDiscovery: FeatureDiscovery,
         featureFlagger: FeatureFlagger,
         pageContextStore: AIChatPageContextStoring) {
        self.aiChatSettings = aiChatSettings
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
        self.pageContextStore = pageContextStore

        let productSurfaceTelemetry = PixelProductSurfaceTelemetry(featureFlagger: featureFlagger, dailyPixelFiring: DailyPixel.self)
        self.aiChatContentHandler = AIChatContentHandler(
            aiChatSettings: aiChatSettings,
            featureDiscovery: featureDiscovery,
            featureFlagger: featureFlagger,
            productSurfaceTelemetry: productSurfaceTelemetry,
            pageContextStore: pageContextStore
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupURLObservation()
        if let restoreURL = initialRestoreURL {
            loadChatURL(restoreURL)
        } else {
            loadAIChat()
        }
    }

    deinit {
        urlObservation?.invalidate()
    }

    // MARK: - Public Methods

    /// Queues prompt if web view not ready yet; otherwise submits immediately.
    func submitPrompt(_ prompt: String, pageContext: AIChatPageContextData? = nil) {
        if isPageReady && isContentHandlerReady {
            aiChatContentHandler.submitPrompt(prompt, pageContext: pageContext)
        } else {
            pendingPrompt = prompt
            pendingPageContext = pageContext
        }
    }

    func startNewChat() {
        aiChatContentHandler.submitStartChatAction()
    }

    func pushPageContext(_ context: AIChatPageContextData?) {
        aiChatContentHandler.submitPageContext(context)
    }

    func reload() {
        isPageReady = false
        isContentHandlerReady = false
        webView.reload()
    }

    /// Returns the current contextual chat URL if one exists, nil otherwise.
    var currentContextualChatURL: URL? {
        webView.url.flatMap { $0.duckAIChatID != nil ? $0 : nil }
    }

    /// Loads a specific chat URL (for cold restore after app restart).
    func loadChatURL(_ url: URL) {
        loadingView.startAnimating()
        webView.load(URLRequest(url: url))
    }

    // MARK: - Private Methods

    private func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(webView)
        view.addSubview(loadingView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration.persistent()
        let userContentController = UserContentController(
            assetsPublisher: contentBlockingAssetsPublisher,
            privacyConfigurationManager: privacyConfigurationManager
        )
        userContentController.delegate = self
        configuration.userContentController = userContentController
        self.userContentController = userContentController
        return configuration
    }

    private func loadAIChat() {
        loadingView.startAnimating()
        let contextualURL = aiChatSettings.aiChatURL.appendingParameter(name: "placement", value: "sidebar")
        let request = URLRequest(url: contextualURL)
        webView.load(request)
    }

    /// Handles edge case where user submits before preloaded web view is fully ready.
    private func submitPendingPromptIfReady() {
        guard let prompt = pendingPrompt,
              isPageReady,
              isContentHandlerReady else { return }

        let pageContext = pendingPageContext
        pendingPrompt = nil
        pendingPageContext = nil
        aiChatContentHandler.submitPrompt(prompt, pageContext: pageContext)
    }

    // MARK: - URL Observation

    private func setupURLObservation() {
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.handleURLChange()
            }
        }
    }

    private func handleURLChange() {
        let url = webView.url
        let contextualChatURL = url.flatMap { $0.duckAIChatID != nil ? $0 : nil }

        guard contextualChatURL != lastContextualChatURL else { return }

        if contextualChatURL != nil,
           aiChatSettings.isAutomaticContextAttachmentEnabled,
           let context = pageContextStore.latestContext {
            pushPageContext(context)
        }

        lastContextualChatURL = contextualChatURL
        delegate?.contextualWebViewController(self, didUpdateContextualChatURL: contextualChatURL)
    }
}

// MARK: - UserContentControllerDelegate

extension AIChatContextualWebViewController: UserContentControllerDelegate {
    func userContentController(_ userContentController: UserContentController,
                               didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
                               userScripts: UserScriptsProvider,
                               updateEvent: ContentBlockerRulesManager.UpdateEvent) {
        guard let userScripts = userScripts as? UserScripts else {
            assertionFailure("Unexpected UserScripts type")
            return
        }

        aiChatContentHandler.setup(with: userScripts.aiChatUserScript, webView: webView, displayMode: .contextual)

        isContentHandlerReady = true
        submitPendingPromptIfReady()
    }
}

// MARK: - WKNavigationDelegate

extension AIChatContextualWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        if url.isDuckAIURL || navigationAction.targetFrame?.isMainFrame == false {
            return .allow
        }

        delegate?.contextualWebViewController(self, didRequestToLoad: url)
        return .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingView.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingView.stopAnimating()
        isPageReady = true
        submitPendingPromptIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingView.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingView.stopAnimating()
    }
}

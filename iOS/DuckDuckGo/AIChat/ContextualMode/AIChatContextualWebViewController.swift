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
import os.log
import PrivacyConfig
import UIKit
import UserScript
import WebKit

// MARK: - Delegate Protocol

protocol AIChatContextualWebViewControllerDelegate: AnyObject {
    func contextualWebViewController(_ viewController: AIChatContextualWebViewController, didRequestToLoad url: URL)
    func contextualWebViewController(_ viewController: AIChatContextualWebViewController, didUpdateContextualChatURL url: URL?)
    func contextualWebViewController(_ viewController: AIChatContextualWebViewController, didRequestOpenDownloadWithFileName fileName: String)
}

final class AIChatContextualWebViewController: UIViewController {

    // MARK: - Properties

    weak var delegate: AIChatContextualWebViewControllerDelegate?

    private let aiChatSettings: AIChatSettingsProvider
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private let featureDiscovery: FeatureDiscovery
    private let featureFlagger: FeatureFlagger
    private var downloadHandler: DownloadHandling
    private let pixelHandler: AIChatContextualModePixelFiring
    private let debugSettings: AIChatDebugSettingsHandling
    private let userAgentManager: UserAgentManaging

    private(set) var aiChatContentHandler: AIChatContentHandling

    /// Passthrough delegate for the content handler. Set this to receive navigation callbacks.
    var aiChatContentHandlingDelegate: AIChatContentHandlingDelegate? {
        get { aiChatContentHandler.delegate }
        set { aiChatContentHandler.delegate = newValue }
    }

    private var pendingPrompt: String?
    /// Page context bundled with a pending prompt submission (consumed together in `submitPromptNow`).
    private var pendingPageContext: AIChatPageContextData?
    /// Standalone page context for the "Attach Page Content" chip, buffered when WebView isn't ready yet.
    private var pendingChipContext: AIChatPageContextData?
    private var hasPendingChipContext = false
    /// Set to true when WKWebView finishes loading HTML (`didFinish` navigation). Does not guarantee the frontend JS app is ready.
    private var isPageReady = false
    private var isContentHandlerReady = false
    /// Set to true when the Duck.ai web app has initialized and registered its JS message handlers (signaled by `getAIChatPageContext`).
    private var isFrontendReady = false
    private var urlObservation: NSKeyValueObservation?
    private var lastContextualChatURL: URL?

    /// URL to load on viewDidLoad instead of the default AI chat URL (for cold restore).
    var initialURL: URL?

    // MARK: - UI Components

    private lazy var webView: WKWebView = {
        let webView = WKWebView(frame: .zero, configuration: createWebViewConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.customUserAgent = userAgentManager.userAgent(isDesktop: false, url: aiChatSettings.aiChatURL)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.4, *) {
            #if DEBUG
            webView.isInspectable = true
            #else
            webView.isInspectable = AppUserDefaults().inspectableWebViewEnabled
            #endif
        }
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

    /// Initialize the web view controller.
    /// - Parameters:
    ///   - aiChatSettings: AI chat settings provider
    ///   - privacyConfigurationManager: Privacy configuration manager
    ///   - contentBlockingAssetsPublisher: Content blocking assets publisher
    ///   - featureDiscovery: Feature discovery
    ///   - featureFlagger: Feature flagger
    ///   - downloadHandler: Download handler for managing file downloads
    ///   - getPageContext: Closure to get page context (used by ContentHandler for JS getAIChatPageContext requests)
    ///   - pixelHandler: Pixel handler for contextual mode analytics
    init(aiChatSettings: AIChatSettingsProvider,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         featureDiscovery: FeatureDiscovery,
         featureFlagger: FeatureFlagger,
         downloadHandler: DownloadHandling,
         getPageContext: ((PageContextRequestReason) -> AIChatPageContextData?)?,
         pixelHandler: AIChatContextualModePixelFiring,
         debugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings(),
         userAgentManager: UserAgentManaging = DefaultUserAgentManager.shared) {
        self.aiChatSettings = aiChatSettings
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
        self.downloadHandler = downloadHandler
        self.pixelHandler = pixelHandler
        self.debugSettings = debugSettings
        self.userAgentManager = userAgentManager

        let productSurfaceTelemetry = PixelProductSurfaceTelemetry(featureFlagger: featureFlagger, dailyPixelFiring: DailyPixel.self)
        self.aiChatContentHandler = AIChatContentHandler(
            aiChatSettings: aiChatSettings,
            featureDiscovery: featureDiscovery,
            productSurfaceTelemetry: productSurfaceTelemetry,
            getPageContext: getPageContext
        )

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.aiChat.debug("[ContextualWebVC] viewDidLoad - initialURL: \(String(describing: self.initialURL?.absoluteString))")
        setupUI()
        aiChatContentHandler.fireAIChatTelemetry()
        setupURLObservation()
        setupDownloadHandler()
        if let url = initialURL {
            Logger.aiChat.debug("[ContextualWebVC] Loading initialURL: \(url.absoluteString)")
            loadChatURL(url)
        } else {
            Logger.aiChat.debug("[ContextualWebVC] No initialURL, loading default AI chat")
            loadAIChat()
        }
    }

    deinit {
        urlObservation?.invalidate()
    }

    // MARK: - Public Methods

    /// Queues prompt if web view not ready yet; otherwise submits immediately.
    func submitPrompt(_ prompt: String, pageContext: AIChatPageContextData? = nil) {
        Logger.aiChat.debug("[ContextualWebVC] submitPrompt called - isPageReady: \(self.isPageReady), isContentHandlerReady: \(self.isContentHandlerReady)")
        if isPageReady && isContentHandlerReady {
            Logger.aiChat.debug("[ContextualWebVC] Submitting prompt immediately")
            aiChatContentHandler.submitPrompt(prompt, pageContext: pageContext)
        } else {
            Logger.aiChat.debug("[ContextualWebVC] Queuing prompt as pending")
            pendingPrompt = prompt
            pendingPageContext = pageContext
        }
    }

    /// Called by the delegate chain when the Frontend requests content, indicating it has initialized.
    func markFrontendAsReady() {
        guard !isFrontendReady else { return }
        isFrontendReady = true
        submitPendingIfReady()
    }

    func startNewChat() {
        aiChatContentHandler.submitStartChatAction()
    }

    func pushPageContext(_ context: AIChatPageContextData?) {
        if isPageReady && isContentHandlerReady {
            hasPendingChipContext = false
            pendingChipContext = nil
            aiChatContentHandler.submitPageContext(context)
        } else {
            hasPendingChipContext = true
            pendingChipContext = context
        }
    }

    func reload() {
        isPageReady = false
        isContentHandlerReady = false
        isFrontendReady = false
        webView.reload()
    }

    func loadChatURL(_ url: URL) {
        Logger.aiChat.debug("[ContextualWebVC] loadChatURL - resetting page ready flag and loading: \(url.absoluteString)")
        isPageReady = false
        isFrontendReady = false
        pendingPrompt = nil
        pendingPageContext = nil
        hasPendingChipContext = false
        pendingChipContext = nil
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
        return configuration
    }

    private func loadAIChat() {
        loadingView.startAnimating()
        let contextualURL = aiChatSettings.aiChatURL.appendingParameter(name: "placement", value: "sidebar")
        Logger.aiChat.debug("[ContextualWebVC] loadAIChat - loading URL: \(contextualURL.absoluteString)")
        let request = URLRequest(url: contextualURL)
        webView.load(request)
    }

    private func setupDownloadHandler() {
        downloadHandler.onDownloadComplete = { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let filename):
                self.view.showDownloadCompletionToast(for: filename) { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.contextualWebViewController(self, didRequestOpenDownloadWithFileName: filename)
                }

            case .failure:
                self.view.showDownloadFailedToast()
            }
        }
    }

    /// Handles edge case where user submits or pushes context before preloaded web view is fully ready.
    private func submitPendingIfReady() {
        Logger.aiChat.debug("[ContextualWebVC] submitPendingIfReady - pendingPrompt: \(self.pendingPrompt != nil), hasPendingChipContext: \(self.hasPendingChipContext), isPageReady: \(self.isPageReady), isContentHandlerReady: \(self.isContentHandlerReady), isFrontendReady: \(self.isFrontendReady)")
        guard isPageReady, isContentHandlerReady else { return }

        if let prompt = pendingPrompt {
            let pageContext = pendingPageContext
            pendingPrompt = nil
            pendingPageContext = nil
            submitPromptNow(prompt, pageContext: pageContext)
        }

        if hasPendingChipContext, isFrontendReady {
            let context = pendingChipContext
            hasPendingChipContext = false
            pendingChipContext = nil
            aiChatContentHandler.submitPageContext(context)
        }
    }

    private func submitPromptNow(_ prompt: String, pageContext: AIChatPageContextData?) {
        Logger.aiChat.debug("[ContextualWebVC] Submitting pending prompt now")
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
        userScripts.aiChatUserScript.setContextualModePixelHandler(pixelHandler)

        isContentHandlerReady = true
        submitPendingIfReady()
    }
}

// MARK: - WKNavigationDelegate

extension AIChatContextualWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        if url.scheme == "blob" || url.isDuckAIURL || debugSettings.matchesCustomURL(url) || navigationAction.targetFrame?.isMainFrame == false {
            return .allow
        }

        delegate?.contextualWebViewController(self, didRequestToLoad: url)
        return .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard let url = navigationResponse.response.url else {
            return .allow
        }
        return url.scheme == "blob" ? .download : .allow
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = downloadHandler
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingView.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.aiChat.debug("[ContextualWebVC] didFinish navigation - URL: \(String(describing: webView.url?.absoluteString))")
        loadingView.stopAnimating()
        isPageReady = true
        submitPendingIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingView.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingView.stopAnimating()
    }
}

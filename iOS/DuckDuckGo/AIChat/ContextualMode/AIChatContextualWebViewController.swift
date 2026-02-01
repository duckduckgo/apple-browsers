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

    private(set) var aiChatContentHandler: AIChatContentHandling

    /// Callback for URL changes.
    var onContextualChatURLChange: ((URL?) -> Void)?

    /// Passthrough delegate for the content handler. Set this to receive navigation callbacks.
    var aiChatContentHandlingDelegate: AIChatContentHandlingDelegate? {
        get { aiChatContentHandler.delegate }
        set { aiChatContentHandler.delegate = newValue }
    }

    private var pendingPrompt: String?
    private var pendingPageContext: AIChatPageContextData?
    private var userContentController: UserContentController?
    private var isPageReady = false
    private var isContentHandlerReady = false
    private var urlObservation: NSKeyValueObservation?
    private var lastContextualChatURL: URL?

    /// Constraint for adjusting WebView bottom when keyboard appears
    private var webViewBottomConstraint: NSLayoutConstraint?
    private var isMediumDetent = true
    private var lastKnownKeyboardFrame: CGRect?

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
         pixelHandler: AIChatContextualModePixelFiring) {
        self.aiChatSettings = aiChatSettings
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
        self.downloadHandler = downloadHandler
        self.pixelHandler = pixelHandler

        let productSurfaceTelemetry = PixelProductSurfaceTelemetry(featureFlagger: featureFlagger, dailyPixelFiring: DailyPixel.self)
        self.aiChatContentHandler = AIChatContentHandler(
            aiChatSettings: aiChatSettings,
            featureDiscovery: featureDiscovery,
            featureFlagger: featureFlagger,
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
        setupUI()
        aiChatContentHandler.fireAIChatTelemetry()
        setupURLObservation()
        setupDownloadHandler()
        if let restoreURL = initialRestoreURL {
            loadChatURL(restoreURL)
        } else {
            loadAIChat()
        }
    }

    deinit {
        urlObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
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

    /// Updates the sheet detent. Keyboard fix only applies in medium detent.
    func setMediumDetent(_ isMediumDetent: Bool) {
        let wasInMediumDetent = self.isMediumDetent
        self.isMediumDetent = isMediumDetent

        if isMediumDetent && !wasInMediumDetent {
            // Transitioning TO medium: recalculate keyboard overlap if keyboard is visible
            recalculateKeyboardOverlapIfNeeded()
        } else if !isMediumDetent && webViewBottomConstraint?.constant != 0 {
            // Transitioning FROM medium: animate constraint reset
            UIView.animate(withDuration: 0.25) {
                self.webViewBottomConstraint?.constant = 0
                self.view.layoutIfNeeded()
            }
        }
    }

    private func recalculateKeyboardOverlapIfNeeded() {
        guard let keyboardFrame = lastKnownKeyboardFrame else { return }
        adjustForKeyboard(frame: keyboardFrame, duration: 0.25, options: .curveEaseInOut)
    }

    // MARK: - Private Methods

    private func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(webView)
        view.addSubview(loadingView)

        let bottomConstraint = webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        webViewBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,

            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        setupKeyboardObservers()
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }

        lastKnownKeyboardFrame = keyboardFrame

        guard isMediumDetent, view.window != nil else { return }

        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let animationCurveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRaw)

        adjustForKeyboard(frame: keyboardFrame, duration: duration, options: animationCurve)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        lastKnownKeyboardFrame = nil

        guard view.window != nil else { return }

        let userInfo = notification.userInfo
        let duration = (userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let animationCurveRaw = (userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRaw)

        webViewBottomConstraint?.constant = 0

        UIView.animate(withDuration: duration, delay: 0, options: animationCurve) {
            self.view.layoutIfNeeded()
        }
    }

    private func adjustForKeyboard(frame keyboardFrame: CGRect, duration: TimeInterval, options: UIView.AnimationOptions) {
        let keyboardFrameInView = view.convert(keyboardFrame, from: nil)
        let keyboardOverlap = max(0, view.bounds.height - keyboardFrameInView.origin.y)

        webViewBottomConstraint?.constant = -keyboardOverlap

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
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

        lastContextualChatURL = contextualChatURL

        delegate?.contextualWebViewController(self, didUpdateContextualChatURL: contextualChatURL)
        onContextualChatURLChange?(contextualChatURL)
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
        submitPendingPromptIfReady()
    }
}

// MARK: - WKNavigationDelegate

extension AIChatContextualWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        if url.scheme == "blob" || url.isDuckAIURL || navigationAction.targetFrame?.isMainFrame == false {
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

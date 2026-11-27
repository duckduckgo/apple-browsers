//
//  LinkedPageContextLoader.swift
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

import AIChat
import BrowserServicesKit
import Common
import ConcurrencyExtensions
import FeatureFlags_macOS
import Foundation
import MaliciousSiteProtection
import os.log
import PrivacyConfig
import UserScript
import WebKit

enum LinkedPageContextLoadResult: Equatable {
    case success(AIChatPageContextData)
    case failed(PageContextExtractionOutcome.FailureReason)
    case prevented(String)
}

@MainActor
protocol LinkedPageContextLoading: AnyObject {
    func load(_ url: URL) async -> LinkedPageContextLoadResult
    /// Hosts read with the user's session; Fire burns them with the tab.
    var sessionReadDomains: Set<String> { get set }
}

/// Not a hidden `Tab`: that would record history and run download, permission and autofill extensions.
@MainActor
final class LinkedPageContextLoader: LinkedPageContextLoading {

    static let timeout: TimeInterval = 30

    private let burnerMode: BurnerMode
    private let contentBlocking: AnyContentBlocking
    private let httpsUpgrade: HTTPSUpgrade
    private let maliciousSiteDetector: MaliciousSiteDetecting
    private let isGPCEnabled: () -> Bool
    private let featureFlagger: FeatureFlagger
    var sessionReadDomains = Set<String>()

    private lazy var linkProtection = LinkProtection(privacyManager: contentBlocking.privacyConfigurationManager,
                                                     contentBlockingManager: contentBlocking.contentBlockingManager,
                                                     errorReporting: NavigationProtectionTabExtension.debugEvents,
                                                     isFastTrackingParameterFilterEnabled: { [featureFlagger] in featureFlagger.isFeatureOn(.fastTrackingParameterFilter) })

    init(burnerMode: BurnerMode,
         contentBlocking: AnyContentBlocking,
         httpsUpgrade: HTTPSUpgrade,
         maliciousSiteDetector: MaliciousSiteDetecting,
         isGPCEnabled: @escaping () -> Bool,
         featureFlagger: FeatureFlagger) {
        self.burnerMode = burnerMode
        self.contentBlocking = contentBlocking
        self.httpsUpgrade = httpsUpgrade
        self.maliciousSiteDetector = maliciousSiteDetector
        self.isGPCEnabled = isGPCEnabled
        self.featureFlagger = featureFlagger
    }

    nonisolated static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host?.isEmpty == false else { return false }
        return url.user == nil && url.password == nil
    }

    func load(_ url: URL) async -> LinkedPageContextLoadResult {
        guard Self.isSupported(url) else { return .failed(.unsupportedURL) }
        do {
            return try await withTimeout(Self.timeout) { @MainActor [self] in
                await self.protectAndLoad(url)
            }
        } catch {
            return .failed(.timeout)
        }
    }

    private func protectAndLoad(_ url: URL) async -> LinkedPageContextLoadResult {
        guard let request = await protect(URLRequest(url: url)) else {
            return .failed(.unsupportedURL)
        }
        guard !Task.isCancelled else { return .failed(.timeout) }
        // The session read never leaves this host (see `LinkedPageLoad.isSameOrigin`).
        if let host = request.url?.host {
            sessionReadDomains.insert(host)
        }

        return await Self.read(with: { withSession in await self.read(request, withSession: withSession) })
    }

    /// Returns nil for a request that must not load: there's no warning page to show here.
    private func protect(_ request: URLRequest) async -> URLRequest? {
        guard var url = request.url, Self.isSupported(url) else { return nil }
        url = await linkProtection.getCleanURL(from: url, onStartExtracting: {}, onFinishExtracting: {})
        if url.isHttp, url.port == nil, case .success(let upgradedURL) = await httpsUpgrade.upgrade(url: url) {
            url = upgradedURL
        }
        if await maliciousSiteDetector.evaluate(url) != nil {
            return nil
        }
        var request = request
        request.url = url
        return GPCRequestFactory().requestForGPC(basedOn: request,
                                                 config: contentBlocking.privacyConfigurationManager.privacyConfig,
                                                 gpcEnabled: isGPCEnabled()) ?? request
    }

    /// A cross-origin redirect restarts the read without the session, so the session can't cause side effects there.
    static func read(with attempt: (_ withSession: Bool) async -> LinkedPageContextLoadResult) async -> LinkedPageContextLoadResult {
        let result = await attempt(true)
        guard result == .failed(.redirectBlocked), !Task.isCancelled else { return result }
        return await attempt(false)
    }

    private func read(_ request: URLRequest, withSession: Bool) async -> LinkedPageContextLoadResult {
        let configuration = WKWebViewConfiguration()
        configuration.applyStandardConfiguration(featureFlagger: featureFlagger, contentBlocking: contentBlocking, burnerMode: burnerMode)
        // The user didn't open this page, so it mustn't show as visited in their tabs.
        configuration.visitedLinkStore = WKWebViewConfiguration().visitedLinkStore
        if !withSession {
            // No cookies, storage or logins: nothing the redirect targets can act on as the user.
            configuration.websiteDataStore = .nonPersistent()
        }
        if #available(macOS 15.4, *) {
            // The user didn't open this page, so their browser extensions don't get to see it.
            configuration.webExtensionController = nil
        }
        guard let userContentController = configuration.userContentController as? UserContentController else {
            return .failed(.scriptError)
        }
        let userContentControllerDelegate = IgnoringUserContentControllerDelegate()
        userContentController.delegate = userContentControllerDelegate
        defer { userContentController.cleanUpBeforeClosing() }

        // The tab's tracker blocking only applies once the rule lists are installed.
        await userContentController.awaitContentBlockingAssetsInstalled()
        guard !Task.isCancelled else { return .failed(.timeout) }
        guard let pageContextUserScript = (userContentController.contentBlockingAssets?.userScripts as? UserScripts)?.pageContextUserScript else {
            return .failed(.scriptError)
        }

        let redirects: LinkedPageLoad.Redirects = withSession ? .sameOriginOnly : .anyOrigin(protect: { [weak self] request in
            await self?.protect(request)
        })
        return await LinkedPageLoad(configuration: configuration, redirects: redirects) { webView in
            pageContextUserScript.webView = webView
            return await pageContextUserScript.collectAndWait(timeout: 10)
        }.run(request)
    }
}

private final class IgnoringUserContentControllerDelegate: UserContentControllerDelegate {
    func userContentController(_ userContentController: UserContentController,
                               didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
                               userScripts: UserScriptsProvider,
                               updateEvent: ContentBlockerRulesManager.UpdateEvent) {}
}

@MainActor
final class LinkedPageLoad: NSObject {

    enum Redirects {
        case sameOriginOnly
        case anyOrigin(protect: @MainActor (URLRequest) async -> URLRequest?)
    }

    private let webView: WKWebView
    private let redirects: Redirects
    private let extract: @MainActor (WKWebView) async -> AIChatPageContextData?
    private var initialURL: URL?
    private var mimeType: String?
    /// Bumped by each main-frame navigation: an extraction of a page the frame has since left is dropped.
    private var navigationGeneration = 0
    /// A protected request loaded in place of a hop; it isn't protected again when it comes back.
    private var protectedRequestURL: URL?
    private var loadedProtectedURLs = Set<URL>()
    private var continuation: CheckedContinuation<LinkedPageContextLoadResult, Never>?

    init(configuration: WKWebViewConfiguration,
         redirects: Redirects = .sameOriginOnly,
         extract: @escaping @MainActor (WKWebView) async -> AIChatPageContextData?) {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: configuration)
        self.redirects = redirects
        self.extract = extract
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    nonisolated static func isSameOrigin(_ url: URL, as initialURL: URL) -> Bool {
        func origin(_ url: URL) -> (scheme: String?, host: String?, port: Int?) {
            let scheme = url.scheme?.lowercased()
            let defaultPort: Int? = switch scheme {
            case "http": 80
            case "https": 443
            default: nil
            }
            return (scheme, url.host?.lowercased(), url.port ?? defaultPort)
        }
        let (new, initial) = (origin(url), origin(initialURL))
        if new == initial { return true }
        return initial.scheme == "http" && initial.port == 80 && new.scheme == "https" && new.port == 443 && new.host == initial.host
    }

    enum HopDecision: Equatable {
        case allow
        case load(URLRequest)
        case block
    }

    nonisolated static func decision(for request: URLRequest, protected: URLRequest?) -> HopDecision {
        guard let protected else { return .block }
        let gpcHeader = GPCRequestFactory.Constants.secGPCHeader
        if protected.url != request.url || protected.value(forHTTPHeaderField: gpcHeader) != request.value(forHTTPHeaderField: gpcHeader) {
            return .load(protected)
        }
        return .allow
    }

    func run(_ request: URLRequest) async -> LinkedPageContextLoadResult {
        initialURL = request.url
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                webView.load(request)
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failed(.timeout)) }
        }
    }

    private func finish(_ result: LinkedPageContextLoadResult) {
        guard let continuation else { return }
        self.continuation = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        continuation.resume(returning: result)
    }

    private func extractPageContext() async {
        guard continuation != nil else { return }
        let generation = navigationGeneration
        let context = await extract(webView)
        // A redirector (meta refresh, script) moved the frame on: the next page's didFinish reads that one.
        guard generation == navigationGeneration else { return }
        guard let context, !context.content.isEmpty else {
            finish(.failed(.emptyContent))
            return
        }
        finish(.success(AIChatPageContextData(title: context.title,
                                              favicon: context.favicon,
                                              url: webView.url?.absoluteString ?? context.url,
                                              content: context.content,
                                              truncated: context.truncated,
                                              fullContentLength: context.fullContentLength,
                                              pageTypeSignals: context.pageTypeSignals,
                                              mimeType: mimeType ?? context.mimeType)))
    }

    /// Not the outcome: the next navigation's is, within the loader's timeout.
    nonisolated static func isInterruption(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && error.code == 102) // WebKitErrorFrameLoadInterruptedByPolicyChange
    }

    nonisolated static func failureReason(for error: Error) -> PageContextExtractionOutcome.FailureReason {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return .navigationFailed }
        switch error.code {
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .certificateError
        default:
            return .navigationFailed
        }
    }
}

extension LinkedPageLoad: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // A nil target frame is a new window: no popups.
        guard let targetFrame = navigationAction.targetFrame else {
            decisionHandler(.cancel)
            return
        }
        guard targetFrame.isMainFrame else {
            decisionHandler(navigationAction.shouldPerformDownload ? .cancel : .allow)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.cancel)
            finish(.failed(.navigationFailed))
            return
        }
        // Covers server redirects as well as script and meta-refresh navigations. WebKit asks before it sends
        // the redirected request, so a cancelled one never reaches the other origin.
        guard let url = navigationAction.request.url, let initialURL else {
            decisionHandler(.cancel)
            finish(.failed(.redirectBlocked))
            return
        }
        if Self.isSameOrigin(url, as: initialURL) {
            decisionHandler(.allow)
            return
        }
        switch redirects {
        case .sameOriginOnly:
            decisionHandler(.cancel)
            finish(.failed(.redirectBlocked))
        case .anyOrigin(let protect):
            if url == protectedRequestURL {
                protectedRequestURL = nil
                decisionHandler(.allow)
                return
            }
            let request = navigationAction.request
            Task { @MainActor in
                switch Self.decision(for: request, protected: await protect(request)) {
                case .allow:
                    decisionHandler(.allow)
                case .load(let protected):
                    guard let protectedURL = protected.url, !self.loadedProtectedURLs.contains(protectedURL) else {
                        // The page sent it back from the URL it was protected into (https redirecting to http): load it as asked, as a tab does.
                        decisionHandler(.allow)
                        return
                    }
                    decisionHandler(.cancel)
                    guard self.continuation != nil else { return }
                    self.protectedRequestURL = protectedURL
                    self.loadedProtectedURLs.insert(protectedURL)
                    webView.load(protected)
                case .block:
                    decisionHandler(.cancel)
                    self.finish(.failed(.redirectBlocked))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.isForMainFrame else {
            decisionHandler(.allow)
            return
        }
        if let statusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode, statusCode >= 400 {
            decisionHandler(.cancel)
            finish(.failed(.httpError))
            return
        }
        let mimeType = navigationResponse.response.mimeType
        if mimeType == AIChatPageContextData.pdfMIMEType {
            decisionHandler(.cancel)
            finish(.prevented("pdf"))
            return
        }
        // Anything WebKit can't display would become a download.
        guard navigationResponse.canShowMIMEType else {
            decisionHandler(.cancel)
            finish(.failed(.navigationFailed))
            return
        }
        self.mimeType = mimeType
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationGeneration += 1
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let generation = navigationGeneration
        Task { @MainActor in
            // Redirectors (meta refresh, script) navigate right after load, sometimes before a read would end:
            // let the frame settle first, and leave the read to the page it moves to.
            try? await Task.sleep(nanoseconds: Self.settleDelay)
            guard generation == self.navigationGeneration else { return }
            await self.extractPageContext()
        }
    }

    static let settleDelay: UInt64 = 500_000_000

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard Self.isInterruption(error) else {
            finish(.failed(Self.failureReason(for: error)))
            return
        }
        // The frame stayed on the page it had loaded: read that one, unless another load is underway.
        if !webView.isLoading, webView.url != nil {
            Task { await extractPageContext() }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !Self.isInterruption(error) else { return }
        finish(.failed(Self.failureReason(for: error)))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failed(.navigationFailed))
    }
}

extension LinkedPageLoad: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    // Geolocation and notification prompts go through private delegate methods this class doesn't
    // implement, and WebKit denies them when they're missing.
}

//
//  AMPCanonicalExtractor.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Foundation
import WebKit
import Common

public final class AMPCanonicalExtractor: NSObject {

    final class CompletionHandler {

        private var completion: ((URL?) -> Void)?

        func setCompletionHandler(completion: ((URL?) -> Void)?) {
            completeWithURL(nil)
            self.completion = completion
        }

        func completeWithURL(_ url: URL?) {
            // Make a copy of completion and set it to nil
            // This will prevent other callers before the completion has completed completing
            let compBlock = completion
            completion = nil
            compBlock?(url)
        }

    }

    struct Constants {
        static let sendCanonical = "sendCanonical"
        static let canonicalKey = "canonical"
        static let ruleListIdentifier = "blockImageRules"
    }

    private let completionHandler = CompletionHandler()

    private var webView: WKWebView?
    private var imageBlockingRules: WKContentRuleList?

    private let linkCleaner: LinkCleaner
    private let privacyManager: PrivacyConfigurationManaging
    private let contentBlockingManager: CompiledRuleListsSource
    private let errorReporting: EventMapping<AMPProtectionDebugEvents>?

    private var privacyConfig: PrivacyConfiguration { privacyManager.privacyConfig }

    private var currentUrl: URL?
    private var lastPositiveAMPUrl: URL?

    public init(linkCleaner: LinkCleaner,
                privacyManager: PrivacyConfigurationManaging,
                contentBlockingManager: CompiledRuleListsSource,
                errorReporting: EventMapping<AMPProtectionDebugEvents>? = nil) {
        self.linkCleaner = linkCleaner
        self.privacyManager = privacyManager
        self.contentBlockingManager = contentBlockingManager
        self.errorReporting = errorReporting

        super.init()

        loadImageBlockingRules()
    }

    private func loadImageBlockingRules() {
        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: Constants.ruleListIdentifier) { [weak self] ruleList, _ in
            if let ruleList = ruleList {
                self?.imageBlockingRules = ruleList
            } else {
                self?.compileImageRules()
            }
        }
    }

    private func compileImageRules() {
        let ruleSource = """
[
    {
        "trigger": {
            "url-filter": ".*",
            "resource-type": ["image", "style-sheet", "script"]
        },
        "action": {
            "type": "block"
        }
    }
]
"""

        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: Constants.ruleListIdentifier,
                                                                encodedContentRuleList: ruleSource) { [weak self] ruleList, error  in
            if let error = error {
                print("AMPCanonicalExtractor - Error compiling image blocking rules: \(error.localizedDescription)")
                self?.errorReporting?.fire(.ampBlockingRulesCompilationFailed)
                return
            }

            self?.imageBlockingRules = ruleList
        }
    }

    public func urlContainsAMPKeyword(_ url: URL?) -> Bool {
        guard url != lastPositiveAMPUrl else { return false }
        linkCleaner.lastAMPURLString = nil

        let settings = TrackingLinkSettings(fromConfig: privacyConfig)

        guard privacyConfig.isEnabled(featureKey: .ampLinks) else { return false }
        guard settings.deepExtractionEnabled else { return false }
        guard let url = url, !linkCleaner.isURLExcluded(url: url) else { return false }
        let urlStr = url.absoluteString

        let ampKeywords = settings.ampKeywords

        return ampKeywords.contains { keyword in
            return urlStr.contains(keyword)
        }
    }

    private func buildUserScript() -> WKUserScript {
        let source = """
(function() {
    document.addEventListener('DOMContentLoaded', (event) => {
        const canonicalLinks = document.querySelectorAll('[rel="canonical"]')

        let result = undefined
        if (canonicalLinks.length > 0) {
            result = canonicalLinks[0].href
        }

        // Loop prevention
        if (window.location.href === result) {
            result = undefined
        }

        if (!document.documentElement.hasAttribute('amp') && !document.documentElement.hasAttribute('⚡')) {
            result = undefined
        }

        window.webkit.messageHandlers.\(Constants.sendCanonical).postMessage({
            \(Constants.canonicalKey): result
        })
    })
})()
"""

        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    public func cancelOngoingExtraction() {
        webView?.stopLoading()
        webView = nil
        completionHandler.completeWithURL(nil)
    }

    public func getCanonicalURL(initiator: URL?,
                                url: URL?,
                                completion: @escaping ((URL?) -> Void)) {
        cancelOngoingExtraction()
        guard privacyConfig.isEnabled(featureKey: .ampLinks) else {
            completion(nil)
            return
        }
        guard TrackingLinkSettings(fromConfig: privacyConfig).deepExtractionEnabled else {
            completion(nil)
            return
        }
        guard let url = url, !linkCleaner.isURLExcluded(url: url) else {
            completion(nil)
            return
        }

        if let initiator = initiator, linkCleaner.isURLExcluded(url: initiator) {
            completion(nil)
            return
        }

        completionHandler.setCompletionHandler(completion: completion)

        currentUrl = url

        assert(Thread.isMainThread)
        webView = WKWebView(frame: .zero, configuration: makeConfiguration())
        webView?.navigationDelegate = self
        webView?.load(URLRequest(url: url))
    }

    public func getCanonicalUrl(initiator: URL?,
                                url: URL?) async -> URL? {
        await withCheckedContinuation { continuation in
            getCanonicalURL(initiator: initiator, url: url) { url in
                continuation.resume(returning: url)
            }
        }
    }

    private func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: Constants.sendCanonical)
        configuration.userContentController.addUserScript(buildUserScript())
        if let rulesList = contentBlockingManager.currentMainRules?.rulesList {
            configuration.userContentController.add(rulesList)
        }
        if let attributedRulesList = contentBlockingManager.currentAttributionRules?.rulesList {
            configuration.userContentController.add(attributedRulesList)
        }
        if let imageBlockingRules = imageBlockingRules {
            configuration.userContentController.add(imageBlockingRules)
        }

        return configuration
    }

    deinit {
        completionHandler.completeWithURL(nil)
    }

}

extension AMPCanonicalExtractor: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        defer {
            currentUrl = nil
        }

        guard message.name == Constants.sendCanonical else { return }

        webView = nil

        if let dict = message.body as? [String: AnyObject],
           let canonical = dict[Constants.canonicalKey] as? String {
            if let canonicalUrl = URL(string: canonical), !linkCleaner.isURLExcluded(url: canonicalUrl) {
                linkCleaner.lastAMPURLString = currentUrl?.absoluteString
                lastPositiveAMPUrl = currentUrl
                completionHandler.completeWithURL(canonicalUrl)
            } else {
                completionHandler.completeWithURL(nil)
            }
        } else {
            completionHandler.completeWithURL(nil)
        }
    }
}

extension AMPCanonicalExtractor: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completionHandler.completeWithURL(nil)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completionHandler.completeWithURL(nil)
    }
}

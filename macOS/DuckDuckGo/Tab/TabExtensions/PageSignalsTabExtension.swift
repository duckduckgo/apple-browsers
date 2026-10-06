//
//  PageSignalsTabExtension.swift
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

import Combine
import Common
import DDGNavigation
import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import WebKit

/// Bridges the tab's web view and navigation events into a `PageSignalsMonitor`
@MainActor
final class PageSignalsTabExtension: NSObject {
    static let contentRuleListActionSelectorName = "_webView:contentRuleListWithIdentifier:performedAction:forURL:"

    private let monitor: PageSignalsMonitor
    private var cancellables = Set<AnyCancellable>()

    var pageSignals: PageSignals? {
        monitor.pageSignals
    }

    init(webViewPublisher: some Publisher<WKWebView, Never>, featureFlagger: FeatureFlagger, tld: TLD) {
        self.monitor = PageSignalsMonitor(tld: tld,
                                          isEnabled: { featureFlagger.isFeatureOn(.pageSignals) })
        super.init()

        webViewPublisher
            .sink { [weak self] webView in
                self?.monitor.attach(to: webView)
            }
            .store(in: &cancellables)
    }
}

// MARK: - NavigationResponder

extension PageSignalsTabExtension: NavigationResponder {

    func didCommit(_ navigation: Navigation) {
        guard !navigation.isErrorPage else {
            return
        }

        monitor.didCommitNavigation(to: navigation.url)
    }

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard !navigation.isCommitted else {
            return
        }

        monitor.didFailProvisionalNavigation(to: error.failingUrl ?? navigation.url, with: error)
    }
}

// MARK: - Private WebKit Delegate

extension PageSignalsTabExtension {

    /// Forwarded by `DistributedNavigationDelegate` only when registered as a custom delegate method handler.
    @objc(_webView:contentRuleListWithIdentifier:performedAction:forURL:)
    func webView(_ webView: WKWebView, contentRuleListWithIdentifier identifier: String, performedAction action: NSObject, forURL url: URL) {
        monitor.didPerformContentRuleListAction(ContentRuleListAction(webKitAction: action), for: url)
    }
}

protocol PageSignalsTabExtensionProtocol: AnyObject, NavigationResponder {
    @MainActor var pageSignals: PageSignals? { get }
}

extension PageSignalsTabExtension: TabExtension, PageSignalsTabExtensionProtocol {
    typealias PublicProtocol = PageSignalsTabExtensionProtocol
    nonisolated func getPublicProtocol() -> PublicProtocol { self }
}

extension TabExtensions {
    var pageSignals: PageSignalsTabExtensionProtocol? {
        resolve(PageSignalsTabExtension.self, .nullable)

    }
}

private extension Navigation {

    /// Error pages are loaded right after a failure, and must not reset its signals.
    var isErrorPage: Bool {
        navigationAction.navigationType == .alternateHtmlLoad
    }
}

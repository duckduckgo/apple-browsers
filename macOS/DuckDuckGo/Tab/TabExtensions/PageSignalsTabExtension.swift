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

/// Observes Resource Load Errors and Content Rule Actions
@MainActor
final class PageSignalsTabExtension {
    private let signalsCollector: PageSignalsCollector
    private var resourceObserver: PageResourceLoadObserver
    private let featureFlagger: FeatureFlagger
    private var cancellables = Set<AnyCancellable>()
    private weak var webView: WKWebView?

    private var isEnabled: Bool {
        featureFlagger.isFeatureOn(.pageSignals)
    }

    var pageSignals: PageSignals {
        signalsCollector.signals
    }

    init(webViewPublisher: some Publisher<WKWebView, Never>, featureFlagger: FeatureFlagger, tld: TLD) {
        self.featureFlagger = featureFlagger
        self.signalsCollector = PageSignalsCollector(tld: tld)
        self.resourceObserver = PageResourceLoadObserver { [weak signalsCollector] url, error in
            signalsCollector?.recordResourceFailure(error, for: url)
        }

        startListeningToWebViewAvailability(webViewPublisher: webViewPublisher)
        starListeningToFeatureFlagUpdates(featureFlagger: featureFlagger)
    }
}

// MARK: - Observing Resource Load Events

private extension PageSignalsTabExtension {

    func startListeningToWebViewAvailability(webViewPublisher: some Publisher<WKWebView, Never>) {
        webViewPublisher
            .sink { [weak self] webView in
                self?.webView = webView
                self?.setupResourcesOberverIfNeeded()
            }
            .store(in: &cancellables)
    }

    func starListeningToFeatureFlagUpdates(featureFlagger: FeatureFlagger) {
        featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.pageSignals)
            }
            .prepend(featureFlagger.isFeatureOn(.pageSignals))
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupResourcesOberverIfNeeded()
            }
            .store(in: &cancellables)
    }

    func setupResourcesOberverIfNeeded() {
        guard let webView else {
            return
        }

        guard isEnabled else {
            resourceObserver.detach()
            return
        }

        signalsCollector.startObservingSignals(for: webView.url)
        resourceObserver.attach(to: webView)
    }
}

// MARK: - Observing Content Rule List Events

extension PageSignalsTabExtension: NavigationResponder {

    func didCommit(_ navigation: Navigation) {
        guard isEnabled, !navigation.isErrorPage else {
            return
        }

        signalsCollector.startObservingSignals(for: navigation.url)
    }

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard isEnabled, !navigation.isCommitted else {
            return
        }

        signalsCollector.didFailProvisionalNavigation(to: error.failingUrl ?? navigation.url, with: error)
    }

    func navigationDidPerformContentRuleListAction(_ action: ContentRuleListAction, forURL url: URL, ruleListIdentifier identifier: String) {
        guard isEnabled else {
            return
        }

        signalsCollector.recordContentRuleListAction(action, for: url)
    }
}

protocol PageSignalsTabExtensionProtocol: AnyObject, NavigationResponder {
    @MainActor var pageSignals: PageSignals { get }
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

//
//  PageSignalsController.swift
//  DuckDuckGo
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

import Common
import DDGNavigation
import FeatureFlags_iOS
import PrivacyConfig
import WebKit
import Combine

/// Owns page-signal collection for one iOS tab and its current web view.
@MainActor
final class PageSignalsController {
    private var signalsCollector: PageSignalsCollector
    private var resourceObserver: PageResourceLoadObserver
    private let featureFlagger: FeatureFlagger
    private var cancellables = [AnyCancellable]()
    private weak var targetWebView: WKWebView?

    var pageSignals: PageSignals? {
        signalsCollector.signals
    }

    init(featureFlagger: FeatureFlagger, tld: TLD) {
        self.featureFlagger = featureFlagger
        self.signalsCollector = PageSignalsCollector(tld: tld)
        self.resourceObserver = PageResourceLoadObserver { [weak signalsCollector] url, error in
            signalsCollector?.recordResourceFailure(error, for: url)
        }

        startObservingFeatureFlagUpdates()
    }

    func attach(to webView: WKWebView) {
        detach()
        targetWebView = webView

        guard featureFlagger.isFeatureOn(.pageSignals) else {
            return
        }

        startObserving(webView)
    }

    func detach() {
        stopObserving()
        targetWebView = nil
    }

    func didCommitNavigation(to url: URL?) {
        guard featureFlagger.isFeatureOn(.pageSignals) else {
            return
        }

        signalsCollector.startObservingSignals(for: url)
    }

    func didFailProvisionalNavigation(to url: URL?, with error: Error) {
        guard featureFlagger.isFeatureOn(.pageSignals), let url else {
            return
        }

        signalsCollector.didFailProvisionalNavigation(to: url, with: error)
    }

    func didPerformContentRuleListAction(_ action: NSObject, for url: URL, in webView: WKWebView) {
        guard featureFlagger.isFeatureOn(.pageSignals), targetWebView == webView else {
            return
        }

        signalsCollector.recordContentRuleListAction(ContentRuleListAction(webKitAction: action), for: url)
    }
}

private extension PageSignalsController {

    func startObservingFeatureFlagUpdates() {
        featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.pageSignals)
            }
            .prepend(featureFlagger.isFeatureOn(.pageSignals))
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshObservation()
            }
            .store(in: &cancellables)
    }

    func refreshObservation() {
        guard let targetWebView else {
            return
        }

        guard featureFlagger.isFeatureOn(.pageSignals) else {
            stopObserving()
            return
        }

        startObserving(targetWebView)
    }

    func startObserving(_ webView: WKWebView) {
        resourceObserver.attach(to: webView)
        signalsCollector.startObservingSignals(for: webView.url)
    }

    func stopObserving() {
        resourceObserver.detach()
    }
}

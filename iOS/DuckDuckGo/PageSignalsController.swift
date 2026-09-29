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

/// Owns page-signal collection for one iOS tab and its current web view.
@MainActor
final class PageSignalsController {
    var pageSignals: PageSignals? { collector?.signals }
    private var collector: PageSignalsCollector?
    private weak var webView: WKWebView?
    private var resourceObserver: PageResourceLoadObserver?
    private let featureFlagger: FeatureFlagger
    private let tld: TLD

    init(featureFlagger: FeatureFlagger, tld: TLD) {
        self.featureFlagger = featureFlagger
        self.tld = tld
    }

    func attach(to webView: WKWebView) {
        detach()
        guard featureFlagger.isFeatureOn(.pageSignals) else { return }

        self.webView = webView
        let collector = PageSignalsCollector(tld: tld)
        collector.reset(for: webView.url)
        self.collector = collector
        resourceObserver = PageResourceLoadObserver.attach(to: webView) { [weak collector] url, error in
            collector?.recordResourceFailure(error, for: url)
        }
    }

    func detach() {
        resourceObserver?.detach()
        resourceObserver = nil
        collector = nil
        webView = nil
    }

    func didCommitNavigation(url: URL?) {
        resourceObserver?.navigationDidCommit()
        collector?.reset(for: url)
    }

    func didFinishNavigation() {
        collector?.recordNavigationFinished()
    }

    func didPerformContentRuleListAction(_ action: NSObject, forURL url: URL, in webView: WKWebView) {
        guard self.webView === webView else { return }
        collector?.recordContentRuleListAction(ContentRuleListAction(webKitAction: action), forURL: url)
    }

    func renderingProgressDidChange(_ events: UInt, in webView: WKWebView) {
        guard self.webView === webView else { return }
        collector?.recordRenderingProgress(events)
    }
}

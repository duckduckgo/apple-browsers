//
//  PageSignalsMonitor.swift
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
import Foundation
import WebKit

#if PRIVATE_PAGE_SIGNALS_ENABLED
/// Collects page signals for one tab's web view, while `isEnabled` allows it.
@MainActor
public final class PageSignalsMonitor {
    private let signalsCollector: PageSignalsCollector
    private let resourceObserver: PageResourceLoadObserver
    private let isEnabled: () -> Bool

    public var pageSignals: PageSignals? {
        isEnabled() ? signalsCollector.signals : nil
    }

    /// - Parameters:
    ///   - isEnabled: Evaluated on attach and on every event.
    public init(tld: TLD, isEnabled: @escaping () -> Bool) {
        let signalsCollector = PageSignalsCollector(tld: tld)

        self.signalsCollector = signalsCollector
        self.isEnabled = isEnabled
        self.resourceObserver = PageResourceLoadObserver { [weak signalsCollector] url, error in
            guard isEnabled() else {
                return
            }

            signalsCollector?.recordResourceFailure(error, for: url)
        }
    }

    public func attach(to webView: WKWebView) {
        detach()

        guard isEnabled() else {
            return
        }

        signalsCollector.startCollectingSignals(for: webView.url)
        resourceObserver.attach(to: webView)
    }

    public func detach() {
        resourceObserver.detach()
    }

    public func didCommitNavigation(to url: URL?) {
        guard isEnabled() else {
            return
        }

        signalsCollector.startCollectingSignals(for: url)
    }

    public func didFailProvisionalNavigation(to url: URL?, with error: Error) {
        guard isEnabled(), let url else {
            return
        }

        signalsCollector.didFailProvisionalNavigation(to: url, with: error)
    }

    public func didPerformContentRuleListAction(_ action: ContentRuleListAction, for url: URL) {
        guard isEnabled() else {
            return
        }

        signalsCollector.recordContentRuleListAction(action, for: url)
    }
}
#endif

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
import Foundation
import WebKit

@MainActor
final class PageSignalsTabExtension {
    var pageSignals: PageSignals { collector.signals }
    private let collector: PageSignalsCollector
    private var resourceObserver: PageResourceLoadObserver?
    private var cancellables = Set<AnyCancellable>()

    init(webViewPublisher: some Publisher<WKWebView, Never>, tld: TLD) {
        collector = PageSignalsCollector(tld: tld)
        webViewPublisher.sink { [weak self] webView in
            guard let self else { return }
            resourceObserver?.detach()
            collector.reset(for: webView.url)
            resourceObserver = PageResourceLoadObserver.attach(to: webView) { [weak self] url, error in
                self?.collector.recordResourceFailure(error, for: url)
            }
        }.store(in: &cancellables)
    }
}

extension PageSignalsTabExtension: NavigationResponder {
    func didCommit(_ navigation: Navigation) {
        resourceObserver?.navigationDidCommit()
        collector.reset(for: navigation.url)
    }

    func navigationDidFinish(_ navigation: Navigation) {
        collector.recordNavigationFinished()
    }

    func navigationDidPerformContentRuleListAction(_ action: ContentRuleListAction, forURL url: URL, ruleListIdentifier identifier: String) {
        collector.recordContentRuleListAction(action, forURL: url)
    }

    func renderingProgressDidChange(progressEvents: UInt) {
        collector.recordRenderingProgress(progressEvents)
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
        resolve(PageSignalsTabExtension.self)
    }
}

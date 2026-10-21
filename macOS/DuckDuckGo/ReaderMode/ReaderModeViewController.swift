//
//  ReaderModeViewController.swift
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

import AppKit
import ReaderMode
import WebKit

/// Shows an extracted article in place of the tab's web view.
final class ReaderModeViewController: NSViewController {

    let article: ReaderArticle
    private let openLink: (URL) -> Void

    init(article: ReaderArticle, openLink: @escaping (URL) -> Void) {
        self.article = article
        self.openLink = openLink
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // The article is untrusted page content; it is rendered as a static document.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.loadHTMLString(ReaderDocument.html(for: article), baseURL: article.url)
        view = webView
    }
}

extension ReaderModeViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        switch navigationAction.navigationType {
        case .other where navigationAction.targetFrame?.isMainFrame == true && navigationAction.request.url == article.url:
            return .allow
        case .linkActivated:
            if let url = navigationAction.request.url {
                if url.absoluteString.hasPrefix(article.url.absoluteString + "#") {
                    return .allow
                }
                openLink(url)
            }
            return .cancel
        default:
            return .cancel
        }
    }
}

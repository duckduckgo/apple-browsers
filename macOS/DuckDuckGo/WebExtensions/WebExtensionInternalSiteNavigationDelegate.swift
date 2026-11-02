//
//  WebExtensionInternalSiteNavigationDelegate.swift
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

import WebKit

@available(macOS 15.4, *)
final class WebExtensionInternalSiteNavigationDelegate: NSObject, WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame == true else {
            return .allow
        }
        guard let url = navigationAction.request.url else {
            return .allow
        }
        if url.scheme?.caseInsensitiveCompare("webkit-extension") == .orderedSame {
            // Resolve the tab's owner, not the destination, so a foreign extension cannot supply the replacement origin.
            guard let ownerURL = (webView.uiDelegate as? Tab)?.content.urlForWebView,
                  let controller = webView.configuration.webExtensionController else { return .allow }
            let matchingContexts = controller.extensionContexts.filter { context in
                ownerURL.scheme?.caseInsensitiveCompare(context.baseURL.scheme ?? "") == .orderedSame
                    && ownerURL.host?.caseInsensitiveCompare(context.baseURL.host ?? "") == .orderedSame
                    && ownerURL.port == context.baseURL.port
            }
            guard let context = controller.extensionContext(for: ownerURL) ?? (matchingContexts.count == 1 ? matchingContexts.first : nil),
                  url.scheme?.caseInsensitiveCompare(context.baseURL.scheme ?? "") == .orderedSame,
                  url.host?.caseInsensitiveCompare(context.baseURL.host ?? "") == .orderedSame,
                  url.port == context.baseURL.port,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .allow }

            // WebKit requires the registered spelling even when an extension uppercases its origin.
            components.scheme = context.baseURL.scheme
            components.host = context.baseURL.host
            components.port = context.baseURL.port
            guard let canonicalURL = components.url, canonicalURL.absoluteString != url.absoluteString else { return .allow }
            var request = navigationAction.request
            request.url = canonicalURL
            webView.load(request)
            return .cancel
        }

        guard let tab = webView.uiDelegate as? Tab else {
            return .cancel
        }

        tab.setContent(.url(url, source: .ui), request: navigationAction.request)
        return .cancel
    }

}

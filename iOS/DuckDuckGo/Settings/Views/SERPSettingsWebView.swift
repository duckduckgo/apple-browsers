//
//  SERPSettingsWebView.swift
//  DuckDuckGo
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

import SwiftUI
import UIKit
import WebKit
import Combine
import Core
import BrowserServicesKit
import PrivacyConfig
import Persistence
import UserScript

struct SERPSettingsWebView: UIViewRepresentable {

    let url: URL
    let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    let keyValueStore: ThrowingKeyValueStoring

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, keyValueStore: keyValueStore)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = []
        let userContentController = UserContentController(assetsPublisher: contentBlockingAssetsPublisher,
                                                          privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager)
        configuration.userContentController = userContentController
        userContentController.delegate = context.coordinator

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.preventFlashOnLoad()
#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        (uiView.configuration.userContentController as? UserContentController)?.cleanUpBeforeClosing()
        coordinator.webView = nil
    }

    @MainActor
    final class Coordinator: NSObject, UserContentControllerDelegate, WKNavigationDelegate, WKUIDelegate {

        private let url: URL
        private let keyValueStore: ThrowingKeyValueStoring
        weak var webView: WKWebView?
        private var didLoad = false

        init(url: URL, keyValueStore: ThrowingKeyValueStoring) {
            self.url = url
            self.keyValueStore = keyValueStore
        }

        func userContentController(_ userContentController: UserContentController,
                                   didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
                                   userScripts: UserScriptsProvider,
                                   updateEvent: ContentBlockerRulesManager.UpdateEvent) {
            guard let userScripts = userScripts as? UserScripts else { return }
            userScripts.serpSettingsUserScript.setStore(keyValueStore)
            userScripts.serpSettingsUserScript.webView = webView

            guard !didLoad, let webView else { return }
            didLoad = true
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
                decisionHandler(.cancel)
                return
            }

            guard scheme == "http" || scheme == "https" else {
                openExternally(url)
                decisionHandler(.cancel)
                return
            }

            if url.isPart(ofDomain: "duckduckgo.com") {
                decisionHandler(.allow)
            } else {
                openExternally(url)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            webView.load(navigationAction.request)
            return nil
        }

        private func openExternally(_ url: URL) {
            guard UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)
        }
    }
}

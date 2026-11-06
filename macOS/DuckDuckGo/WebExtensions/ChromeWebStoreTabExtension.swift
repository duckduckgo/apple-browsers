//
//  ChromeWebStoreTabExtension.swift
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
import Foundation
import UserScript
import WebKit

protocol ChromeWebStoreUserScriptProvider {
    var chromeWebStoreUserScript: Subfeature? { get }
}
extension UserScripts: ChromeWebStoreUserScriptProvider {}

/// Gives the tab's web view to each new `ChromeWebStoreUserScript`, so the store page learns about
/// extension changes made outside the page, such as from the toolbar.
@available(macOS 15.4, *)
final class ChromeWebStoreTabExtension {
    private weak var webView: WKWebView?
    private weak var userScript: ChromeWebStoreUserScript?
    private var cancellables = Set<AnyCancellable>()

    init(scriptsPublisher: some Publisher<some ChromeWebStoreUserScriptProvider, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>) {

        webViewPublisher.sink { [weak self] webView in
            Task { @MainActor in
                self?.webView = webView
                self?.userScript?.webView = webView
            }
        }.store(in: &cancellables)

        scriptsPublisher.sink { [weak self] scripts in
            let userScript = scripts.chromeWebStoreUserScript as? ChromeWebStoreUserScript
            Task { @MainActor in
                self?.userScript = userScript
                userScript?.webView = self?.webView
            }
        }.store(in: &cancellables)
    }
}

protocol ChromeWebStoreTabExtensionProtocol: AnyObject {}

@available(macOS 15.4, *)
extension ChromeWebStoreTabExtension: TabExtension, ChromeWebStoreTabExtensionProtocol {
    func getPublicProtocol() -> ChromeWebStoreTabExtensionProtocol { self }
}

extension TabExtensions {
    @available(macOS 15.4, *)
    var chromeWebStore: ChromeWebStoreTabExtensionProtocol? {
        resolve(ChromeWebStoreTabExtension.self)
    }
}

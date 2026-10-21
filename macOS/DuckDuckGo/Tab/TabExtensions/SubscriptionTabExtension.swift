//
//  SubscriptionTabExtension.swift
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

import Foundation
import Subscription
import WebKit
import Combine

protocol SubscriptionUserScriptProvider {
    var subscriptionUserScript: SubscriptionUserScript? { get }
}
extension UserScripts: SubscriptionUserScriptProvider {}

final class SubscriptionTabExtension: NSObject {
    private weak var webView: WKWebView?
    private weak var subscriptionUserScript: SubscriptionUserScript?
    private var cancellables = Set<AnyCancellable>()

    init(scriptsPublisher: some Publisher<UserScripts, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>) {

        super.init()

        webViewPublisher.sink { [weak self] webView in
            Task { @MainActor in
                self?.webView = webView
                self?.subscriptionUserScript?.webView = webView
            }
        }.store(in: &cancellables)

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.subscriptionUserScript = scripts.subscriptionUserScript
                self?.subscriptionUserScript?.webView = self?.webView
            }
        }.store(in: &cancellables)
    }
}

protocol SubscriptionProtocol: AnyObject {
}
extension SubscriptionTabExtension: TabExtension, SubscriptionProtocol {
    func getPublicProtocol() -> SubscriptionProtocol { self }

}

extension TabExtensions {
    var subscriptionProtocol: SubscriptionProtocol? {
        resolve(SubscriptionTabExtension.self)
    }
}

//
//  WebNotificationsTabExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import Foundation
import WebKit

/// Manages web notification functionality for a tab.
///
/// This extension owns the `WebNotificationsHandler` and registers it with the
/// content scope user script when available. It provides a public interface for
/// dispatching notification click events from AppDelegate.
final class WebNotificationsTabExtension {

    let handler: WebNotificationsHandler
    private var cancellables = Set<AnyCancellable>()

    init(tabUUID: String,
         contentScopeUserScriptPublisher: some Publisher<ContentScopeUserScript, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>) {

        self.handler = WebNotificationsHandler(tabUUID: tabUUID)

        webViewPublisher.sink { [weak self] webView in
            self?.handler.webView = webView
        }.store(in: &cancellables)

        contentScopeUserScriptPublisher.sink { [weak self] contentScopeUserScript in
            guard let handler = self?.handler else { return }
            contentScopeUserScript.registerSubfeature(delegate: handler)
        }.store(in: &cancellables)
    }
}

// MARK: - Public Protocol

protocol WebNotificationsProtocol: AnyObject {
    /// Dispatches a click event to JavaScript for the given notification.
    /// - Parameter notificationId: The ID of the notification that was clicked.
    func sendClickEvent(notificationId: String)
}

// MARK: - TabExtension Conformance

extension WebNotificationsTabExtension: TabExtension, WebNotificationsProtocol {
    typealias PublicProtocol = WebNotificationsProtocol

    func getPublicProtocol() -> PublicProtocol { self }

    func sendClickEvent(notificationId: String) {
        handler.sendClickEvent(notificationId: notificationId)
    }
}

// MARK: - TabExtensions Accessor

extension TabExtensions {
    var webNotifications: WebNotificationsProtocol? {
        resolve(WebNotificationsTabExtension.self)
    }
}

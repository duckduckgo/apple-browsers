//
//  InternalFeedbackFormTabExtension.swift
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

import BrowserServicesKit
import Combine
import Common
import Navigation
import Foundation
import UserScript
import WebKit

/**
 * This is a wrapper class for a hardcoded script evaluated in on the Internal Feedback Form page.
 *
 * It's not really using any `UserScript` APIs and it isn't loaded permanently into the webView,
 * but it only subclasses `UserScript` to be able to use `loadJS` API and provide values for
 * placeholders.
 *
 * The `source` property is used by `InternalFeedbackFormTabExtension`.
 */
final class InternalFeedbackFormUserScript: NSObject, UserScript {
    let messageNames: [String] = []
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly: Bool = true
    let source: String

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}

    override init() {
#if APPSTORE
        let distributionType = "App Store"
#else
        let distributionType = "DMG"
#endif
        source = Self.loadJS("internal-feedback-autofiller", from: .main, withReplacements: [
            "%OS_VERSION%": ProcessInfo.processInfo.operatingSystemVersion.description,
            "%APP_VERSION%": "\(AppVersion().versionAndBuildNumber) (\(distributionType))"
        ])
        super.init()
    }
}

fileprivate extension URLComponents {
    /// This is the URL that users land on after going to `go.duckduckgo.com/feedback`.
    static let internalFeedbackForm = URLComponents(string: "https://form.asana.com/?k=auWnXd_NQejLUySD7egW_Q&d=137249556945")!
}

/// This tab extension auto-fills Internal Feedback Form with OS version and app version values.
///
/// It's only active for internal users and only performs an action on the Internal Feedback Form page.
///
final class InternalFeedbackFormTabExtension {

    private let internalUserDecider: InternalUserDecider
    private weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()
    private let scriptSource: String

    init(
        webViewPublisher: some Publisher<WKWebView, Never>,
        internalUserDecider: InternalUserDecider
    ) {
        self.internalUserDecider = internalUserDecider
        self.scriptSource = InternalFeedbackFormUserScript().source

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }
        .store(in: &cancellables)
    }
}

extension InternalFeedbackFormTabExtension: NavigationResponder {

    func navigationDidFinish(_ navigation: Navigation) {
        guard internalUserDecider.isInternalUser, let webView, navigation.navigationAction.isForMainFrame, isInternalFeedbackURL(navigation.url) else {
            return
        }
#if APPSTORE
        let distributionType = "App Store"
#else
        let distributionType = "DMG"
#endif
        webView.evaluateJavaScript(scriptSource)
    }

    /// The URL needs to be matched against the form URL, but there may be additional
    /// query items in the webView URL that shouldn't be affecting the logic.
    /// So we're comparing the host, path and that webView URL query items are superset
    /// of the reference URL query items.
    private func isInternalFeedbackURL(_ url: URL) -> Bool {
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return urlComponents.host == URLComponents.internalFeedbackForm.host &&
            urlComponents.path == URLComponents.internalFeedbackForm.path &&
            Set(urlComponents.queryItems ?? []).isSuperset(of: Set(URLComponents.internalFeedbackForm.queryItems ?? []))
    }
}

protocol InternalFeedbackFormTabExtensionProtocol: AnyObject, NavigationResponder {
}

extension InternalFeedbackFormTabExtension: InternalFeedbackFormTabExtensionProtocol, TabExtension {
    func getPublicProtocol() -> InternalFeedbackFormTabExtensionProtocol { self }
}

extension TabExtensions {
    var internalFeedbackForm: InternalFeedbackFormTabExtensionProtocol? {
        resolve(InternalFeedbackFormTabExtension.self)
    }
}

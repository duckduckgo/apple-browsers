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

import Combine
import Common
import FoundationExtensions
import Navigation
import Foundation
import UserScript
import WebKit
import PixelKit
import PrivacyConfig

/// When set on a tab, switches the autofiller into popup mode (quick mode + screenshot +
/// diagnostics) and forces a rebuild on each navigation so reopening picks up a fresh screenshot.
struct InternalFeedbackFormPopupContext {
    let quickMode: Bool
    let diagnostics: String
    let screenshotData: Data?
}

/**
 * This is a wrapper class for a hardcoded script evaluated on the Internal Feedback Form page.
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

    init(quickMode: Bool = false, diagnostics: String = "", screenshotBase64: String = "") {
        let appVersionModel = AppVersionModel()

        do {
            source = try Self.loadJS("internal-feedback-autofiller", from: .main, withReplacements: [
                "%OS_VERSION%": Self.jsStringLiteral(ProcessInfo.processInfo.operatingSystemVersion.description),
                "%APP_VERSION%": Self.jsStringLiteral("\(appVersionModel.versionLabelShort) (\(appVersionModel.distributionLabel))"),
                "%QUICK_MODE%": quickMode ? "true" : "false",
                "%DIAGNOSTICS%": Self.jsStringLiteral(diagnostics),
                "%SCREENSHOT_BASE64%": Self.jsStringLiteral(screenshotBase64),
            ])
            super.init()
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to load JS for InternalFeedbackFormUserScript: \(error)")
        }
    }

    /// Produces a JS string literal (including surrounding quotes) for safe inline substitution
    /// into the autofiller script. Diagnostics in particular contain newlines and may contain
    /// apostrophes, both of which would otherwise terminate a hand-quoted literal early.
    /// Mirrors `DuckAiNativeStorageBootstrapUserScript.jsStringLiteral`.
    static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        // Strip the surrounding `[` `]` to get the quoted-and-escaped string.
        return String(array.dropFirst().dropLast())
    }
}

fileprivate extension URLComponents {
    /// This is the URL that users land on after going to `go.duckduckgo.com/feedback`.
    static let internalFeedbackForm = URLComponents(string: "https://form.asana.com/?k=auWnXd_NQejLUySD7egW_Q&d=137249556945")!
}

/// This tab extension auto-fills Internal Feedback Form with OS version and app version values.
///
/// It's only active for internal users and only performs an action on the Internal Feedback Form page.
final class InternalFeedbackFormTabExtension {

    /// Injected so tests don't need `internal-feedback-autofiller.js` in the test bundle.
    typealias ScriptSourceBuilder = (_ quickMode: Bool, _ diagnostics: String, _ screenshotBase64: String) -> String

    static let defaultScriptSourceBuilder: ScriptSourceBuilder = { quickMode, diagnostics, screenshotBase64 in
        InternalFeedbackFormUserScript(
            quickMode: quickMode,
            diagnostics: diagnostics,
            screenshotBase64: screenshotBase64
        ).source
    }

    private let internalUserDecider: InternalUserDecider
    private let scriptSourceBuilder: ScriptSourceBuilder
    private weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()
    /// Non-internal users don't need this script, hence lazy load only for them.
    private lazy var defaultScriptSource: String = scriptSourceBuilder(false, "", "")

    var popupContext: InternalFeedbackFormPopupContext?

    init(
        webViewPublisher: some Publisher<WKWebView, Never>,
        internalUserDecider: InternalUserDecider,
        scriptSourceBuilder: @escaping ScriptSourceBuilder = defaultScriptSourceBuilder
    ) {
        self.internalUserDecider = internalUserDecider
        self.scriptSourceBuilder = scriptSourceBuilder

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }
        .store(in: &cancellables)
    }

    func scriptSourceForCurrentNavigation() -> String {
        guard let popupContext else { return defaultScriptSource }
        let base64 = popupContext.screenshotData?.base64EncodedString() ?? ""
        return scriptSourceBuilder(popupContext.quickMode, popupContext.diagnostics, base64)
    }
}

extension InternalFeedbackFormTabExtension: NavigationResponder {

    func navigationDidFinish(_ navigation: Navigation) {
        guard internalUserDecider.isInternalUser, let webView, navigation.navigationAction.isForMainFrame, Self.isInternalFeedbackURL(navigation.url) else {
            return
        }
        webView.evaluateJavaScript(scriptSourceForCurrentNavigation())
    }

    /// The URL needs to be matched against the form URL, but there may be additional
    /// query items in the webView URL that shouldn't be affecting the logic.
    /// So we're comparing the host, path and that webView URL query items are superset
    /// of the reference URL query items.
    static func isInternalFeedbackURL(_ url: URL) -> Bool {
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return urlComponents.host == URLComponents.internalFeedbackForm.host &&
            urlComponents.path == URLComponents.internalFeedbackForm.path &&
            Set(urlComponents.queryItems ?? []).isSuperset(of: Set(URLComponents.internalFeedbackForm.queryItems ?? []))
    }
}

protocol InternalFeedbackFormTabExtensionProtocol: AnyObject, NavigationResponder {
    var popupContext: InternalFeedbackFormPopupContext? { get set }
}

extension InternalFeedbackFormTabExtension: InternalFeedbackFormTabExtensionProtocol, TabExtension {
    func getPublicProtocol() -> InternalFeedbackFormTabExtensionProtocol { self }
}

extension TabExtensions {
    var internalFeedbackForm: InternalFeedbackFormTabExtensionProtocol? {
        resolve(InternalFeedbackFormTabExtension.self)
    }
}

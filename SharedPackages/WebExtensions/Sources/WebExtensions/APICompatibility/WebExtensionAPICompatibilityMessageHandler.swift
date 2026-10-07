//
//  WebExtensionAPICompatibilityMessageHandler.swift
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

import Foundation
import WebKit

/// Receives the reports extension pages post and writes them to the compatibility log.
///
/// The script sends `{kind: "stubbed" | "missing", api}` for what it can name itself and
/// `{kind: "error", message}` for errors it observed. The message is only classified, never kept.
/// Only extension pages that belong to a loaded extension are heard.
@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionAPICompatibilityMessageHandler: NSObject, WKScriptMessageHandler {

    private static let extensionScheme = "webkit-extension"
    private static let errorKind = "error"

    /// Name and version of the loaded extension that owns the given extension page URL.
    var resolveExtension: (URL) -> (name: String, version: String)? = { _ in nil }

    private let reporter: WebExtensionAPICompatibilityReporter

    init(reporter: WebExtensionAPICompatibilityReporter = WebExtensionAPICompatibilityReporter()) {
        self.reporter = reporter
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        handle(message)
    }

    func handle(_ message: WKScriptMessage) {
        guard message.name == WebExtensionAPICompatibilityScript.messageHandlerName else { return }
        let origin = message.frameInfo.securityOrigin
        handle(body: message.body, originProtocol: origin.protocol, originHost: origin.host)
    }

    func handle(body: Any, originProtocol: String, originHost: String) {
        guard originProtocol == Self.extensionScheme,
              !originHost.isEmpty,
              let url = URL(string: "\(Self.extensionScheme)://\(originHost)/"),
              let owner = resolveExtension(url),
              let payload = body as? [String: Any],
              let kind = payload["kind"] as? String else {
            return
        }

        let issue: WebExtensionAPICompatibilityClassifier.Issue?
        if kind == Self.errorKind {
            issue = (payload["message"] as? String).flatMap(WebExtensionAPICompatibilityClassifier.classify(errorMessage:))
        } else if let kind = WebExtensionAPICompatibilityKind(rawValue: kind),
                  kind != .invalidArgs,
                  let api = payload["api"] as? String {
            issue = WebExtensionAPICompatibilityClassifier.issue(kind: kind, reportedAPI: api)
        } else {
            issue = nil
        }

        guard let issue else { return }
        reporter.report(kind: issue.kind, api: issue.api, extensionName: owner.name, version: owner.version)
    }
}

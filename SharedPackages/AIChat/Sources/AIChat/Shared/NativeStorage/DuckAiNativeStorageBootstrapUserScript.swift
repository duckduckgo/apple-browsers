//
//  DuckAiNativeStorageBootstrapUserScript.swift
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
import UserScript
import WebKit

/// Injects a snapshot of allowed list native-storage entries on the `window` object
/// before any page script runs. Exists to eliminate the first-render theme flash
/// on Duck.ai by exposing `setting_kae` and `duckaiSidebarCollapsed` synchronously,
/// bypassing the async messaging bridge for these two keys only.
public final class DuckAiNativeStorageBootstrapUserScript: NSObject, UserScript {

    /// Entries allowed to leave native storage via this early-injection path.
    /// Keep this set minimal — any key here is visible to the page content world before Duck.ai scripts run.
    public static let exposedKeys: Set<String> = ["setting_kae", "duckaiSidebarCollapsed"]

    public let source: String
    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly: Bool = true
    public var requiresRunInPageContentWorld: Bool { true }
    public let messageNames: [String] = []

    public init(handler: DuckAiNativeStorageHandling, allowedOrigins: [HostnameMatchingRule]) {
        self.source = Self.buildSource(handler: handler, allowedOrigins: allowedOrigins)
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Intentionally empty — this script has no message handlers.
    }

    // MARK: - Source construction

    private static func buildSource(handler: DuckAiNativeStorageHandling, allowedOrigins: [HostnameMatchingRule]) -> String {
        let entries = allowedEntries(from: handler)
        let json = jsonString(for: entries)
        let guardExpression = originGuardExpression(for: allowedOrigins)
        return """
        (function() {
          if (!(\(guardExpression))) return;
          window.__nativeStorageEntries = \(json);
        })();
        """
    }

    private static func allowedEntries(from handler: DuckAiNativeStorageHandling) -> [String: Any] {
        guard let all = try? handler.getAllEntries() else { return [:] }
        return all.filter { exposedKeys.contains($0.key) }
    }

    private static func jsonString(for entries: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(entries),
              let data = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func originGuardExpression(for rules: [HostnameMatchingRule]) -> String {
        guard !rules.isEmpty else { return "false" }
        return rules.map(hostnameCheck(for:)).joined(separator: " || ")
    }

    private static func hostnameCheck(for rule: HostnameMatchingRule) -> String {
        switch rule {
        case .exact(let hostname):
            return "location.hostname === \(jsStringLiteral(hostname))"
        case .exactOrSubdomain(let hostname), .etldPlus1(let hostname):
            let exact = "location.hostname === \(jsStringLiteral(hostname))"
            let suffix = "location.hostname.endsWith(\(jsStringLiteral("." + hostname)))"
            return "(\(exact) || \(suffix))"
        }
    }

    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        // Strip the surrounding [ ] to get the quoted-and-escaped string.
        return String(array.dropFirst().dropLast())
    }
}

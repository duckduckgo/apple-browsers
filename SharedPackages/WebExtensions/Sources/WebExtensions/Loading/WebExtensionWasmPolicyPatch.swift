//
//  WebExtensionWasmPolicyPatch.swift
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

/// Rewrites a Manifest V3 `extension_pages` policy so WebKit before macOS 26 lets extension pages use WebAssembly.
///
/// That WebKit ignores `'wasm-unsafe-eval'` in Manifest V3 (https://bugs.webkit.org/show_bug.cgi?id=290153), and
/// allows WebAssembly only when `script-src`, or `default-src` without it, is absent or allows it. So the rewrite
/// removes both, and gives each directive that fell back to them the sources WebKit honored there for Manifest V3:
/// `'self'` and `'none'`. String `eval` becomes allowed too, since WebKit decides it from the same directive.
enum WebExtensionWasmPolicyPatch {

    /// Directives that can fall back to `script-src` or `default-src`, with the order they fall back in.
    private static let fallbacks: KeyValuePairs<String, [String]> = [
        "script-src-elem": ["script-src", "default-src"],
        "script-src-attr": ["script-src", "default-src"],
        "worker-src": ["child-src", "script-src", "default-src"],
        "frame-src": ["child-src", "default-src"],
        "child-src": ["default-src"],
        "connect-src": ["default-src"],
        "font-src": ["default-src"],
        "img-src": ["default-src"],
        "manifest-src": ["default-src"],
        "media-src": ["default-src"],
        "object-src": ["default-src"],
        "style-src": ["default-src"]
    ]

    /// The rewritten policy, or `nil` when `policy` doesn't ask for WebAssembly.
    static func patchedPolicy(_ policy: String) -> String? {
        var sources: [String: [String]] = [:]
        var keptDirectives: [String] = []
        for directive in policy.split(separator: ";") {
            let tokens = directive.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
            // CSP ignores a repeated directive.
            guard let name = tokens.first, sources[name] == nil else { continue }
            sources[name] = Array(tokens.dropFirst())
            if name != "script-src" && name != "default-src" {
                keptDirectives.append(directive.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        guard let scriptSources = sources["script-src"] ?? sources["default-src"],
              scriptSources.contains("'wasm-unsafe-eval'") else { return nil }

        let addedDirectives = fallbacks.compactMap { name, fallbackNames -> String? in
            // A fallback to `child-src` needs no copy: `child-src` stays in the policy.
            guard sources[name] == nil,
                  let fallback = fallbackNames.first(where: { sources[$0] != nil }),
                  fallback != "child-src",
                  let inherited = sources[fallback] else { return nil }
            return ([name] + inherited.filter { $0 == "'self'" || $0 == "'none'" }).joined(separator: " ")
        }

        return (keptDirectives + addedDirectives).joined(separator: "; ")
    }
}

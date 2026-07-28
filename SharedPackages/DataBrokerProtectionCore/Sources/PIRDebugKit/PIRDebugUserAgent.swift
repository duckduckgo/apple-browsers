//
//  PIRDebugUserAgent.swift
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

/// `WKWebViewConfiguration.applicationNameForUserAgent` values for the debug engine.
///
/// This is not cosmetic: the value is appended to the web view's User-Agent, and brokers behind bot
/// management serve an interstitial instead of the real page when it doesn't look like a browser. A
/// tool-shaped name like `pir-debug` is enough to be challenged, so ``safariLike`` mirrors the macOS
/// app's `WebViewUserAgentProvider` — `Version/<safari> Safari/<webkit>` — and is the default.
public enum PIRDebugUserAgent {

    /// Same fallbacks `WebViewUserAgentProvider` uses when a version can't be read.
    private static let fallbackSafariVersion = "14.1.2"
    private static let fallbackWebKitVersion = "605.1.15"

    private static let safariInfoPlistPath = "/Applications/Safari.app/Contents/Info.plist"

    /// Identifies the CLI in the User-Agent. Honest, and fine against your own fixtures, but expect
    /// bot-managed brokers to challenge it.
    public static let toolLike = "pir-debug"

    @MainActor private static var cachedSafariLike: String?

    /// The Safari-shaped application name the app's web views use. `@MainActor` because reading the
    /// WebKit version instantiates a `WKWebView`.
    @MainActor
    public static func safariLike() -> String {
        if let cachedSafariLike { return cachedSafariLike }
        let value = "Version/\(safariVersion() ?? fallbackSafariVersion) Safari/\(webKitVersion() ?? fallbackWebKitVersion)"
        cachedSafariLike = value
        return value
    }

    private static func safariVersion() -> String? {
        NSDictionary(contentsOfFile: safariInfoPlistPath)?["CFBundleShortVersionString"] as? String
    }

    @MainActor
    private static func webKitVersion() -> String? {
        let prefix = "AppleWebKit/"
        guard let userAgent = WKWebView().value(forKey: "userAgent") as? String,
              let match = userAgent.range(of: prefix + #"[\d.]+"#, options: .regularExpression) else {
            return nil
        }
        return String(userAgent[match].dropFirst(prefix.count))
    }
}

//
//  ScriptRequestValidator.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

/// Protocol for validating script requests from web pages to ensure secure access to subscription tokens.
///
/// Implementations of this protocol are responsible for determining whether a script message
/// from a web page is authorized to request subscription tokens. This is a critical security
/// boundary that prevents unauthorized access to sensitive subscription data.
public protocol ScriptRequestValidator {
    /// Validates whether a script message is authorized to request a subscription token.
    ///
    /// - Parameter message: The script message to validate
    /// - Returns: `true` if the message is authorized to request a token, `false` otherwise
    @MainActor
    func canPageRequestToken(_ message: WKScriptMessage) async -> Bool
}

/// Default implementation of `ScriptRequestValidator` that validates token requests based on URL path and host verification.
///
/// This validator implements a multi-layer security check to ensure that only authorized subscription pages
/// can request tokens. The validation process includes:
/// - Main frame verification (prevents iframe attacks)
/// - URL path validation against known subscription paths
/// - Host matching against expected subscription domain
/// - Security origin verification to prevent XSS attacks
///
/// Related: https://app.asana.com/1/137249556945/project/1205842942115003/task/1212924237876347?focus=true
public struct DefaultScriptRequestValidator: ScriptRequestValidator {

    private let subscriptionManager: any SubscriptionManager

    /// Set of all valid subscription URL paths that are authorized to request tokens.
    /// Paths are dynamically retrieved from `SubscriptionURL.allSubscriptionPaths()`.
    private var allValidPaths: Set<String> { SubscriptionURL.allSubscriptionPaths() }

    /// Creates a new validator with the specified subscription manager.
    ///
    /// - Parameter subscriptionManager: The subscription manager used to determine expected hosts and URLs
    public init(subscriptionManager: any SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
    }

    /// Validates whether a script message is authorized to request a subscription token.
    ///
    /// This method performs the following security checks in order:
    /// 1. Verifies the request comes from the main frame (not an iframe)
    /// 2. Extracts and validates the requesting page's URL and host
    /// 3. Verifies the URL uses HTTPS scheme (rejects HTTP and other protocols)
    /// 4. Normalizes the URL path by filtering out empty and "/" components
    /// 5. Checks if the path matches a known valid subscription path
    /// 6. Verifies the host matches the expected subscription domain
    /// 7. Confirms the security origin matches the host (prevents XSS)
    ///
    /// - Parameter message: The script message containing the token request
    /// - Returns: `true` if all security checks pass and the request is authorized, `false` otherwise
    ///
    /// - Note: All checks must pass for the method to return `true`. Any single failing check
    ///         results in immediate rejection of the request.
    @MainActor
    public func canPageRequestToken(_ message: WKScriptMessage) async -> Bool {
        // Only allow requests from the main frame to prevent iframe-based attacks
        guard message.frameInfo.isMainFrame else { return false }

        // Extract URL and host from the web view
        guard let webViewURL = message.webView?.url,
              let host = webViewURL.host else { return false }

        // Verify the URL uses HTTPS to prevent token exposure over insecure connections
        guard webViewURL.scheme == "https" else { return false }

        // Normalise the path by filtering out empty and "/" components, then joining
        var path = webViewURL.pathComponents.filter { !$0.isEmpty && $0 != "/" }.joined(separator: "/")
        path = path.hasPrefix("/") ? String(path.dropFirst()) : path

        // Verify the path is a known valid subscription path
        guard allValidPaths.contains(path) else { return false }

        // Verify the host matches the expected subscription domain
        let expectedHost = subscriptionManager.url(for: .baseURL).host
        guard host == expectedHost else { return false }

        // Verify the security origin matches the host to prevent XSS attacks
        guard message.frameInfo.securityOrigin.host == host else { return false }

        return true
    }
}

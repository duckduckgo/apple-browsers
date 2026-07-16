//
//  SafariRedirectHandler.swift
//  DuckDuckGo
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

import Core
import Common
import FoundationExtensions
import PrivacyConfig

protocol SafariRedirectHandling: AnyObject {
    /// Whether the given URL was loaded after a suppressed x-safari redirect (for breakage reports).
    func isAfterSuppressedXSafariRedirect(for url: URL) -> Bool

    /// Called from decidePolicyFor when an x-safari URL is encountered.
    /// Returns true if the handler consumed the navigation (caller should .cancel).
    @discardableResult
    func handleRedirect(to url: URL) -> Bool

    /// Full reset including converted load attempts. Called on new top-level navigation.
    func reset()
}

protocol SafariRedirectHandlerDelegate: AnyObject {
    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestLoadURL url: URL)
    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestShowSafariRedirectLoopErrorForURL url: URL)
}

final class SafariRedirectHandler: SafariRedirectHandling {

    private enum Constants {
        static let safariHTTPSRedirectScheme = "x-safari-https"
        static let maximumConvertedLoadAttempts = 3
    }

    private struct HostState {
        var convertedLoadAttemptCount: Int = 0

        var isSafariRedirectSuppressed: Bool {
            convertedLoadAttemptCount > 0
        }
    }

    private let tld: TLD
    private var hostStates: [String: HostState] = [:]

    weak var delegate: SafariRedirectHandlerDelegate?

    init(tld: TLD) {
        self.tld = tld
    }

    func isAfterSuppressedXSafariRedirect(for url: URL) -> Bool {
        guard let domain = domain(for: url) else { return false }
        return hostStates[domain]?.isSafariRedirectSuppressed == true
    }

    func handleRedirect(to url: URL) -> Bool {
        guard isSafariRedirectScheme(url.scheme) else { return false }

        guard let host = domain(for: url) else { return false }
        var state = hostStates[host, default: HostState()]

        if state.convertedLoadAttemptCount >= Constants.maximumConvertedLoadAttempts {
            delegate?.safariRedirectHandler(self, didRequestShowSafariRedirectLoopErrorForURL: url)
        } else {
            state.convertedLoadAttemptCount += 1
            hostStates[host] = state

            convertAndLoad(url: url)
        }
        
        return true
    }

    func reset() {
        hostStates.removeAll()
    }

    // MARK: - Private

    private func domain(for url: URL) -> String? {
        guard let host = url.host else { return nil }
        return tld.eTLDplus1(host) ?? host
    }

    private func convertAndLoad(url: URL) {
        if let convertedURL = convertToHTTPOrHTTPSURL(url: url) {
            delegate?.safariRedirectHandler(self, didRequestLoadURL: convertedURL)
        }
    }

    private func convertToHTTPOrHTTPSURL(url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch url.scheme {
        case Constants.safariHTTPSRedirectScheme:
            components.scheme = "https"
        default:
            return nil
        }

        return components.url
    }

    private func isSafariRedirectScheme(_ scheme: String?) -> Bool {
        scheme == Constants.safariHTTPSRedirectScheme
    }
}

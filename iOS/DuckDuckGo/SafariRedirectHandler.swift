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

import UIKit
import Core
import Common
import PrivacyConfig

protocol SafariRedirectHandling: AnyObject {
    /// Whether the given URL was loaded after a suppressed x-safari-https redirect (for breakage reports).
    func isAfterSuppressedXSafariRedirect(for url: URL) -> Bool

    /// Called from decidePolicyFor when an x-safari-https URL is encountered.
    /// Returns true if the handler consumed the navigation (caller should .cancel).
    @discardableResult
    func handleRedirect(to url: URL) -> Bool

    /// Full reset including the redirect-detected flag. Called on new top-level navigation.
    func reset()
}

protocol SafariRedirectHandlerDelegate: AnyObject {
    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestLoadURL url: URL)
    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestOpenExternallyURL url: URL)
    func safariRedirectHandlerDidRequestGoBack(_ handler: SafariRedirectHandling)
    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestPresentAlert alert: UIAlertController)
}

final class SafariRedirectHandler: SafariRedirectHandling {

    private enum Constants {
        static let safariRedirectScheme = "x-safari-https"
    }

    private struct HostState {
        var redirectCount: Int = 0
        var isSafariRedirectSuppressed: Bool = false
        var alertShown: Bool = false
        var loopAlertShown: Bool = false

        var isAwaitingInitialChoice: Bool { !isSafariRedirectSuppressed && !alertShown }

    }

    private let tld: TLD
    private let featureFlagger: FeatureFlagger
    private var hostStates: [String: HostState] = [:]

    weak var delegate: SafariRedirectHandlerDelegate?

    init(tld: TLD, featureFlagger: FeatureFlagger) {
        self.tld = tld
        self.featureFlagger = featureFlagger
    }

    func isAfterSuppressedXSafariRedirect(for url: URL) -> Bool {
        guard let domain = domain(for: url) else { return false }
        return hostStates[domain]?.isSafariRedirectSuppressed == true
    }

    func handleRedirect(to url: URL) -> Bool {
        guard url.scheme == Constants.safariRedirectScheme,
              featureFlagger.isFeatureOn(.customXSafariRedirectHandling) else { return false }

        guard let host = domain(for: url) else { return false }
        var state = hostStates[host, default: HostState()]

        if state.isAwaitingInitialChoice {
            state.alertShown = true
            hostStates[host] = state
            showTryOpenAlert(url: url, host: host)
            return true
        } else if state.isSafariRedirectSuppressed {
            return handleSubsequentRedirect(url: url, host: host)
        } else {
            // Alert is shown but user hasn't responded yet — consume the redirect silently
            return true
        }
    }

    func reset() {
        hostStates.removeAll()
    }

    // MARK: - Private

    private func domain(for url: URL) -> String? {
        guard let host = url.host else { return nil }
        return tld.eTLDplus1(host) ?? host
    }

    private func handleSubsequentRedirect(url: URL, host: String) -> Bool {
        var state = hostStates[host, default: HostState()]
        state.redirectCount += 1
        hostStates[host] = state
        if state.redirectCount > 2 && !state.loopAlertShown {
            state.loopAlertShown = true
            hostStates[host] = state
            DailyPixel.fireDailyAndCount(pixel: .webViewExternalSchemeNavigationXSafariHTTPSLoopDetected, error: nil, withAdditionalParameters: [:])
            showLoopAlert(url: url, host: host)
        } else if state.redirectCount <= 2 {
            convertAndLoad(url: url)
        }
        return true
    }

    private func convertAndLoad(url: URL) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        if let httpsURL = components?.url {
            delegate?.safariRedirectHandler(self, didRequestLoadURL: httpsURL)
        }
    }

    private func showTryOpenAlert(url: URL, host: String) {
        let alert = UIAlertController(
            title: UserText.xSafariHTTPSTryOpenTitle,
            message: UserText.xSafariHTTPSTryOpenMessage,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: UserText.xSafariHTTPSStayInDDG, style: .cancel, handler: { [weak self] _ in
            guard let self else { return }
            DailyPixel.fireDaily(.webViewExternalSchemeNavigationXSafariHTTPSStay)
            self.hostStates[host] = HostState(isSafariRedirectSuppressed: true, alertShown: true)
            self.convertAndLoad(url: url)
        }))

        alert.addAction(UIAlertAction(title: UserText.xSafariHTTPSOpenInSafari, style: .default, handler: { [weak self] _ in
            guard let self else { return }
            DailyPixel.fireDaily(.webViewExternalSchemeNavigationXSafariHTTPSOpenInSafari)
            self.hostStates[host]?.alertShown = false
            self.delegate?.safariRedirectHandler(self, didRequestOpenExternallyURL: url)
        }))

        delegate?.safariRedirectHandler(self, didRequestPresentAlert: alert)
    }

    private func showLoopAlert(url: URL, host: String) {
        let alert = UIAlertController(
            title: UserText.xSafariHTTPSLoopTitle,
            message: UserText.xSafariHTTPSLoopMessage,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: UserText.xSafariHTTPSGoBack, style: .cancel, handler: { [weak self] _ in
            guard let self else { return }
            self.hostStates[host] = HostState()
            self.delegate?.safariRedirectHandlerDidRequestGoBack(self)
        }))

        alert.addAction(UIAlertAction(title: UserText.xSafariHTTPSOpenInSafari, style: .default, handler: { [weak self] _ in
            guard let self else { return }
            DailyPixel.fireDaily(.webViewExternalSchemeNavigationXSafariHTTPSLoopOpenInSafari)
            self.hostStates[host] = HostState()
            self.delegate?.safariRedirectHandler(self, didRequestOpenExternallyURL: url)
        }))

        delegate?.safariRedirectHandler(self, didRequestPresentAlert: alert)
    }
}

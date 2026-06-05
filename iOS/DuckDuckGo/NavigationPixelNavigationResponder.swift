//
//  NavigationPixelNavigationResponder.swift
//  DuckDuckGo
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

import Foundation
import Navigation
import PixelKit
import PrivacyDashboard
import WebKit

/// iOS counterpart of macOS's `NavigationPixelNavigationResponder`. The host `WKNavigationDelegate`
/// (e.g. `TabViewController`) just forwards its callbacks via `willStart`, `didStart`, `didFinish`, `didFail`;
/// this class owns the pending-navigation-type, the per-`WKNavigation` start time, the gating logic
/// (`SiteLoadingPixel.shouldFireSiteLoadingPixel`), and the firing of
/// `SiteLoadingPixel.siteLoadingSuccess` / `.siteLoadingFailure`.
///
/// Error-page state is provided via closures so this class stays decoupled from
/// `SpecialErrorPageNavigationHandler`.
final class NavigationPixelNavigationResponder {

    private var pendingNavigationType: String?
    private let isOnErrorPage: () -> Bool
    private let isLoadingErrorPage: () -> Bool

    init(isOnErrorPage: @escaping () -> Bool, isLoadingErrorPage: @escaping () -> Bool) {
        self.isOnErrorPage = isOnErrorPage
        self.isLoadingErrorPage = isLoadingErrorPage
    }

    /// Forwarded from `webView(_:decidePolicyFor:decisionHandler:)`. Captures the safe-string
    /// `navigation_type` so the next `didStart` can attach it to the produced `WKNavigation`. Mirrors
    /// macOS's `shouldFireNavigationPixel` gating (JS redirects, alternate-HTML loads, error-page reloads)
    /// and additionally short-circuits the iOS-only "loading the special error page itself" case.
    func willStart(_ navigationAction: WKNavigationAction) {
        guard navigationAction.isTargetingMainFrame() else { return }

        guard !isLoadingErrorPage() else {
            pendingNavigationType = nil
            return
        }

        let navigationType = NavigationType(navigationAction, currentHistoryItemIdentity: nil)
        let shouldFire = SiteLoadingPixel.shouldFireSiteLoadingPixel(
            for: navigationType,
            isStartingFromErrorPage: isOnErrorPage()
        )
        guard shouldFire else {
            pendingNavigationType = nil
            return
        }

        pendingNavigationType = SiteLoadingPixel.safeNavigationType(for: navigationType)
    }

    /// Forwarded from `webView(_:didStartProvisionalNavigation:)`. Stamps start time + navigation type onto
    /// the navigation handle so success/failure can compute duration later.
    func didStart(_ navigation: WKNavigation?) {
        guard let navigation, let type = pendingNavigationType else { return }
        navigation.siteLoadingStartTime = Date()
        navigation.siteLoadingNavigationType = type
        pendingNavigationType = nil
    }

    /// Forwarded from `webView(_:didFinish:)`. Fires `.siteLoadingSuccess` for navigations that passed the `willStart` gate.
    func didFinish(_ navigation: WKNavigation?) {
        guard let navigation,
              let startTime = navigation.siteLoadingStartTime,
              let navigationType = navigation.siteLoadingNavigationType else { return }
        let duration = Date().timeIntervalSince(startTime)
        PixelKit.fire(SiteLoadingPixel.siteLoadingSuccess(duration: duration, navigationType: navigationType))
        clearState(on: navigation)
    }

    /// Forwarded from both `webView(_:didFail:withError:)` and
    /// `webView(_:didFailProvisionalNavigation:withError:)`. Fires `.siteLoadingFailure` for navigations
    /// that passed the `willStart` gate.
    func didFail(_ navigation: WKNavigation?, error: Error) {
        guard let navigation,
              let startTime = navigation.siteLoadingStartTime,
              let navigationType = navigation.siteLoadingNavigationType else { return }
        let duration = Date().timeIntervalSince(startTime)
        PixelKit.fire(SiteLoadingPixel.siteLoadingFailure(duration: duration, error: error, navigationType: navigationType))
        clearState(on: navigation)
    }

    private func clearState(on navigation: WKNavigation) {
        navigation.siteLoadingStartTime = nil
        navigation.siteLoadingNavigationType = nil
    }
}

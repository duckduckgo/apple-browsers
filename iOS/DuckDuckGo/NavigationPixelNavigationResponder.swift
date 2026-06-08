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

/// Measures the duration of main-frame navigations and fires `SiteLoadingPixel.siteLoadingSuccess`
/// or `.siteLoadingFailure` (sampled per `SiteLoadingPixel.samplePercentage`) when each navigation
/// completes. 
///
/// The lifecycle is exposed as four entry points — `willStart`, `didStart`, `didFinish`, `didFail` —
/// to be invoked from the corresponding `WKNavigationDelegate` callbacks by the host. Error-page
/// state ("currently on the error page", "this action is loading the error page") is supplied via
/// injected closures, so the responder doesn't depend on a specific error-page implementation.
final class NavigationPixelNavigationResponder {

    private var pendingNavigationType: String?
    private let isOnErrorPage: () -> Bool
    private let isLoadingErrorPage: (WKNavigationAction) -> Bool

    /// - Parameters:
    ///   - isOnErrorPage: Closure returning whether the currently-displayed page is a special error page.
    ///   - isLoadingErrorPage: Closure returning whether the supplied `WKNavigationAction` is loading the
    ///     special error page itself. Must be navigation-specific (URL-matched), not a stateful flag —
    ///     otherwise an unrelated main-frame navigation initiated during the brief error-page-load window
    ///     would also be dropped.
    init(isOnErrorPage: @escaping () -> Bool,
         isLoadingErrorPage: @escaping (WKNavigationAction) -> Bool) {
        self.isOnErrorPage = isOnErrorPage
        self.isLoadingErrorPage = isLoadingErrorPage
    }

    /// Forwarded from `webView(_:decidePolicyFor:decisionHandler:)`. Captures the safe-string
    /// `navigation_type` so the next `didStart` can attach it to the produced `WKNavigation`. Mirrors
    /// macOS's `shouldFireNavigationPixel` gating (JS redirects, alternate-HTML loads, error-page reloads)
    /// and additionally short-circuits the iOS-only "loading the special error page itself" case.
    func willStart(_ navigationAction: WKNavigationAction) {
        guard navigationAction.isTargetingMainFrame() else { return }

        guard !isLoadingErrorPage(navigationAction) else {
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
        PixelKit.fire(SiteLoadingPixel.siteLoadingSuccess(duration: duration,
                                                          navigationType: navigationType),
                      frequency: .sample(percentage: SiteLoadingPixel.samplePercentage))
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
        PixelKit.fire(SiteLoadingPixel.siteLoadingFailure(duration: duration,
                                                          error: error, navigationType: navigationType),
                      frequency: .sample(percentage: SiteLoadingPixel.samplePercentage))
        clearState(on: navigation)
    }

    private func clearState(on navigation: WKNavigation) {
        navigation.siteLoadingStartTime = nil
        navigation.siteLoadingNavigationType = nil
    }
}

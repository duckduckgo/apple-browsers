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

/// Navigation handle that can carry the start time and safe-string navigation type used to compute
/// site-loading pixel duration. `WKNavigation` conforms in app code (storage via associated objects);
/// tests use a lightweight class double — both to express the contract on the navigation handle and
/// to avoid `WKNavigation()`, whose direct-init deinit crashes (see `WebViewNavigationHandling.swift`).
protocol SiteLoadingNavigation: AnyObject {
    var siteLoadingStartTime: Date? { get set }
    var siteLoadingNavigationType: String? { get set }
}

extension WKNavigation: SiteLoadingNavigation {
    private static var startTimeKey: UInt8 = 0
    private static var navigationTypeKey: UInt8 = 0

    var siteLoadingStartTime: Date? {
        get { objc_getAssociatedObject(self, UnsafeRawPointer(&Self.startTimeKey)) as? Date }
        set { objc_setAssociatedObject(self, UnsafeRawPointer(&Self.startTimeKey), newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    var siteLoadingNavigationType: String? {
        get { objc_getAssociatedObject(self, UnsafeRawPointer(&Self.navigationTypeKey)) as? String }
        set { objc_setAssociatedObject(self, UnsafeRawPointer(&Self.navigationTypeKey), newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

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
    private let samplePercentage: Int
    private let isErrorPageReload: (WKNavigationAction) -> Bool
    private let isLoadingErrorPage: (WKNavigationAction) -> Bool

    /// - Parameters:
    ///   - samplePercentage: Pixel sampling rate (1–100). Defaults to `SiteLoadingPixel.samplePercentage`
    ///   - isErrorPageReload: Closure returning whether the supplied action looks like an error-page
    ///     reload (i.e. the error page is showing AND the action targets the failed URL). Used to skip
    ///     `.other` reload-like navigations the error page issues internally, while letting unrelated
    ///     main-frame navigations initiated from the error page (e.g. a user-typed URL) fire the pixel.
    ///   - isLoadingErrorPage: Closure returning whether the supplied `WKNavigationAction` is loading the
    ///     special error page itself. Must be navigation-specific (URL-matched), not a stateful flag —
    ///     otherwise an unrelated main-frame navigation initiated during the brief error-page-load window
    ///     would also be dropped.
    init(samplePercentage: Int = SiteLoadingPixel.samplePercentage,
         isErrorPageReload: @escaping (WKNavigationAction) -> Bool,
         isLoadingErrorPage: @escaping (WKNavigationAction) -> Bool) {
        self.samplePercentage = samplePercentage
        self.isErrorPageReload = isErrorPageReload
        self.isLoadingErrorPage = isLoadingErrorPage
    }

    /// Records the safe-string navigation type for this main-frame action when its navigation should be
    /// measured. The captured type is consumed by the next `didStart` call; navigations that fail the
    /// gating clear any pending value instead.
    func willStart(_ navigationAction: WKNavigationAction) {
        guard navigationAction.isTargetingMainFrame() else { return }

        guard !isLoadingErrorPage(navigationAction) else {
            pendingNavigationType = nil
            return
        }

        let navigationType = NavigationType(navigationAction, currentHistoryItemIdentity: nil)
        let shouldFire = SiteLoadingPixel.shouldFireSiteLoadingPixel(
            for: navigationType,
            isStartingFromErrorPage: isErrorPageReload(navigationAction)
        )
        guard shouldFire else {
            pendingNavigationType = nil
            return
        }

        pendingNavigationType = SiteLoadingPixel.safeNavigationType(for: navigationType)
    }

    /// Stamps the start timestamp + pending navigation type onto the supplied navigation. The
    /// stamped state is consumed by `didFinish` / `didFail` to compute duration. No-op when no
    /// `willStart` recorded a pending type.
    func didStart(_ navigation: SiteLoadingNavigation?) {
        guard let navigation, let type = pendingNavigationType else { return }
        navigation.siteLoadingStartTime = Date()
        navigation.siteLoadingNavigationType = type
        pendingNavigationType = nil
    }

    /// Fires `.siteLoadingSuccess` for navigations that `didStart` previously stamped.
    func didFinish(_ navigation: SiteLoadingNavigation?) {
        guard let navigation,
              let startTime = navigation.siteLoadingStartTime,
              let navigationType = navigation.siteLoadingNavigationType else { return }
        let duration = Date().timeIntervalSince(startTime)
        PixelKit.fire(SiteLoadingPixel.siteLoadingSuccess(duration: duration,
                                                          navigationType: navigationType),
                      frequency: .sample(percentage: samplePercentage))
        clearState(on: navigation)
    }

    /// Fires `.siteLoadingFailure` for navigations that `didStart` previously stamped.
    func didFail(_ navigation: SiteLoadingNavigation?, error: Error) {
        guard let navigation,
              let startTime = navigation.siteLoadingStartTime,
              let navigationType = navigation.siteLoadingNavigationType else { return }
        let duration = Date().timeIntervalSince(startTime)
        PixelKit.fire(SiteLoadingPixel.siteLoadingFailure(duration: duration,
                                                          error: error,
                                                          navigationType: navigationType),
                      frequency: .sample(percentage: samplePercentage))
        clearState(on: navigation)
    }

    private func clearState(on navigation: SiteLoadingNavigation) {
        navigation.siteLoadingStartTime = nil
        navigation.siteLoadingNavigationType = nil
    }
}

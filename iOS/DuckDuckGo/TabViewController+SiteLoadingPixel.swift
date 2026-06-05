//
//  TabViewController+SiteLoadingPixel.swift
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

extension TabViewController {

    /// Stash the navigation type from `decidePolicyFor` so the next `didStartProvisionalNavigation`
    /// can attach it (and a start timestamp) to the produced `WKNavigation`.
    func captureSiteLoadingNavigationType(_ navigationAction: WKNavigationAction) {
        guard navigationAction.isTargetingMainFrame() else { return }
        let navigationType = NavigationType(navigationAction, currentHistoryItemIdentity: nil)
        pendingSiteLoadingNavigationType = SiteLoadingPixel.safeNavigationType(for: navigationType)
    }

    /// Attach the pending navigation type and a start timestamp to the navigation handle.
    func recordSiteLoadingStart(for navigation: WKNavigation?) {
        guard let navigation, let type = pendingSiteLoadingNavigationType else { return }
        navigation.siteLoadingStartTime = Date()
        navigation.siteLoadingNavigationType = type
        pendingSiteLoadingNavigationType = nil
    }

    func fireSiteLoadingSuccessPixel(for navigation: WKNavigation?) {
        guard let navigation,
              let startTime = navigation.siteLoadingStartTime,
              let navigationType = navigation.siteLoadingNavigationType else { return }
        let duration = Date().timeIntervalSince(startTime)
        PixelKit.fire(SiteLoadingPixel.siteLoadingSuccess(duration: duration, navigationType: navigationType))
        clearSiteLoadingState(on: navigation)
    }

    func fireSiteLoadingFailurePixel(for navigation: WKNavigation?, error: Error) {
        guard let navigation,
              let startTime = navigation.siteLoadingStartTime,
              let navigationType = navigation.siteLoadingNavigationType else { return }
        let duration = Date().timeIntervalSince(startTime)
        PixelKit.fire(SiteLoadingPixel.siteLoadingFailure(duration: duration, error: error, navigationType: navigationType))
        clearSiteLoadingState(on: navigation)
    }

    private func clearSiteLoadingState(on navigation: WKNavigation) {
        navigation.siteLoadingStartTime = nil
        navigation.siteLoadingNavigationType = nil
    }
}

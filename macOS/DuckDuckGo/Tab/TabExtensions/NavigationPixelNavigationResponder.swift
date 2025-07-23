//
//  NavigationPixelNavigationResponder.swift
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
import WebKit

/**
 * This responder is responsible for firing navigation pixel on regular and same-tab navigations.
 */
struct NavigationPixelNavigationResponder {

    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }
}

extension NavigationPixelNavigationResponder: NavigationResponder {

    func didStart(_ navigation: Navigation) {
        let shouldFireNavigationPixel: Bool = {
            /// Fire navigation pixel on all navigations except for loading error pages
            if navigation.navigationAction.navigationType == .alternateHtmlLoad {
                return false
            }
            /// Sometimes navigation type for an error page is reported as `.other`, so checking also target frame URL
            /// This has a side effect of filtering out also some navigations starting on an error page (e.g. using a reload button,
            /// that is also reported as `.other`).
            if navigation.navigationAction.navigationType == .other && navigation.navigationAction.targetFrame?.url == .error {
                return false
            }
            return true
        }()

        if shouldFireNavigationPixel {
            pixelFiring?.fire(GeneralPixel.navigation)
        }
    }

    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {
        if navigationType != .sessionStateReplace {
            PixelKit.fire(GeneralPixel.navigation)
        }
    }
}

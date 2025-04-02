//
//  DuckPlayerHosting.swift
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

import WebKit
import BrowserServicesKit
import Core
import UIKit

/// A protocol that defines the requirements for view controllers that can host DuckPlayer UI
protocol DuckPlayerHosting: UIViewController {

    /// The web view that is hosting the DuckPlayer
    var webView: WKWebView! { get }

    /// The constraint that controls the bottom spacing of the main content
    var contentBottomConstraint: NSLayoutConstraint? { get }

    /// Returns the height of any persistent UI bars at the bottom of the screen (e.g. toolbars, tab bars)
    var persistentBottomBarHeight: CGFloat { get }

    /// The URL of the current page
    var url: URL? { get }

    /// The delegate of the tab
    var delegate: TabDelegate? { get }

    func showChrome()
    func hideChrome()
    func setupWebViewForPortraitVideo()
    func setupWebViewForLandscapeVideo()
    func isTabCurrentlyPresented() -> Bool
}

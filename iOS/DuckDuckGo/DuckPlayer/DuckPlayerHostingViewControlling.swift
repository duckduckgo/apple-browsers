//
//  DuckPlayerHostingViewControlling.swift
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

// First, create a protocol that TabViewController already conforms to
protocol DuckPlayerHostingViewControlling: AnyObject {
    var isLinkPreview: Bool { get }
    var tabModel: Tab { get }
    var webView: WKWebView! { get }
    var view: UIView! { get }
    var duckPlayerChromeDelegate: DuckPlayerBrowserChromeDelegate? { get }
    var duckPlayerTabDelegate: DuckPlayerTabDelegate? { get }
    var url: URL? { get }
    var webViewBottomAnchorConstraint: NSLayoutConstraint? { get }
    
    // UIViewController presentation methods
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
    
    // Portrait + Landscape video
    func setupWebViewForLandscapeVideo()
    func setupWebViewForPortraitVideo()
}

/// A simplified protocol for managing browser chrome visibility specifically for DuckPlayer functionality.
protocol DuckPlayerBrowserChromeDelegate: AnyObject {
    func setBarsHidden(_ hidden: Bool, animated: Bool, customAnimationDuration: CGFloat?)
    func setBarsVisibility(_ percent: CGFloat, animated: Bool, animationDuration: CGFloat?)
    var omniBar: any OmniBar { get }
    var barsMaxHeight: CGFloat { get }
}

/// A simplified protocol for managing tab-related functionality specifically for DuckPlayer.
/// This protocol provides the essential tab delegate methods needed for video playback and navigation.
protocol DuckPlayerTabDelegate: AnyObject {
    func tabCheckIfItsBeingCurrentlyPresented(_ tab: DuckPlayerHostingViewControlling) -> Bool
    func tabDidRequestClose(_ tab: DuckPlayerHostingViewControlling, shouldCreateEmptyTabAtSamePosition: Bool)
    func tab(_ tab: DuckPlayerHostingViewControlling,
             didRequestNewTabForUrl url: URL,
             openedByPage: Bool,
             inheritingAttribution: AdClickAttributionLogic.State?)
}

// TabViewController conformance / Mapping
extension TabViewController: DuckPlayerHostingViewControlling {
    var duckPlayerChromeDelegate: DuckPlayerBrowserChromeDelegate? {
        self.chromeDelegate as? DuckPlayerBrowserChromeDelegate
    }
    
    var duckPlayerTabDelegate: DuckPlayerTabDelegate? {
        self.delegate as? DuckPlayerTabDelegate
    }
}

// BrowserChromeManager conformance / Mapping
extension BrowserChromeManager: DuckPlayerBrowserChromeDelegate {
    func setBarsHidden(_ hidden: Bool, animated: Bool, customAnimationDuration: CGFloat?) {
        delegate?.setBarsHidden(hidden, animated: animated, customAnimationDuration: customAnimationDuration)
    }
    
    func setBarsVisibility(_ percent: CGFloat, animated: Bool, animationDuration: CGFloat?) {
        delegate?.setBarsVisibility(percent, animated: animated, animationDuration: animationDuration)
    }
    
    var omniBar: any OmniBar {
        guard let delegate = delegate else {
            fatalError("BrowserChromeManager delegate is required for DuckPlayer functionality")
        }
        return delegate.omniBar
    }
    
    var barsMaxHeight: CGFloat {
        guard let delegate = delegate else {
            fatalError("BrowserChromeManager delegate is required for DuckPlayer functionality")
        }
        return delegate.barsMaxHeight
    }
}

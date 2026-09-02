//
//  BrowserAutomationProvider.swift
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
import WebKit

/// Metadata describing a single tab, as returned by the `/getTabs` route.
public struct AutomationTabInfo: Codable, Equatable, Sendable {
    /// Stable identifier for the tab; matches the handles returned by `getAllTabHandles()`.
    public var handle: String
    public var url: String?
    public var title: String?
    public var isActive: Bool

    public init(handle: String, url: String? = nil, title: String? = nil, isActive: Bool) {
        self.handle = handle
        self.url = url
        self.title = title
        self.isActive = isActive
    }
}

/// Protocol that platform-specific code implements to provide browser automation capabilities.
/// This abstraction allows the AutomationServerCore to work with both iOS and macOS browser implementations.
@MainActor
public protocol BrowserAutomationProvider: AnyObject {
    /// The unique handle/identifier for the current tab
    var currentTabHandle: String? { get }

    /// Whether the current tab is still loading
    var isLoading: Bool { get }

    /// Whether the content blocker rules have been compiled and are ready
    /// WebDriver should wait for this before considering the browser ready for testing
    var isContentBlockerReady: Bool { get }

    /// The current URL of the active tab
    var currentURL: URL? { get }

    /// The title of the active tab
    var currentTitle: String? { get }

    /// The WKWebView of the current tab (for script execution)
    var currentWebView: WKWebView? { get }

    /// Navigate to a URL in the current tab
    /// - Returns: true if navigation was initiated, false if no current tab exists
    func navigate(to url: URL) -> Bool

    /// Navigate back in the current tab's history
    /// - Returns: true if navigation was initiated, false if there is no current tab or no history
    func goBack() -> Bool

    /// Navigate forward in the current tab's history
    /// - Returns: true if navigation was initiated, false if there is no current tab or no history
    func goForward() -> Bool

    /// Scroll the current tab's viewport by the given deltas, in CSS pixels
    /// - Returns: true if the scroll was performed
    func scroll(deltaX: Double, deltaY: Double) async -> Bool

    /// Get all tab handles across all windows
    func getAllTabHandles() -> [String]

    /// Get metadata for all tabs across all windows.
    /// Handles must match those returned by `getAllTabHandles()`.
    func getAllTabs() -> [AutomationTabInfo]

    /// Close the current tab
    func closeCurrentTab()

    /// Switch to a tab with the given handle
    /// - Returns: true if the tab was found and switched to
    func switchToTab(handle: String) -> Bool

    /// Create a new tab
    /// - Returns: The handle of the new tab, or nil if creation failed
    func newTab() -> String?

    /// Execute a script in the current tab's webview
    func executeScript(_ script: String, args: [String: Any]) async -> Result<Any?, Error>

    /// Clear all website data from the store used by the current web view.
    func clearWebsiteData() async -> Bool

    /// Take a screenshot of the current webview
    /// - Parameter rect: Optional rect to crop the screenshot (for element screenshots)
    /// - Returns: PNG image data, or nil if screenshot failed
    func takeScreenshot(rect: CGRect?) async -> Data?
}

public extension BrowserAutomationProvider {
    func clearWebsiteData() async -> Bool {
        false
    }

    var currentTitle: String? {
        currentWebView?.title
    }

    func goBack() -> Bool {
        guard let webView = currentWebView, webView.canGoBack else { return false }
        webView.goBack()
        return true
    }

    func goForward() -> Bool {
        guard let webView = currentWebView, webView.canGoForward else { return false }
        webView.goForward()
        return true
    }

    func scroll(deltaX: Double, deltaY: Double) async -> Bool {
        let result = await executeScript("window.scrollBy(deltaX, deltaY);", args: ["deltaX": deltaX, "deltaY": deltaY])
        if case .success = result {
            return true
        }
        return false
    }

    /// Default implementation built from `getAllTabHandles()`. Only the active tab carries a URL and title;
    /// platforms override this to report metadata for every tab.
    func getAllTabs() -> [AutomationTabInfo] {
        let activeHandle = currentTabHandle
        return getAllTabHandles().map { handle in
            let isActive = handle == activeHandle
            return AutomationTabInfo(
                handle: handle,
                url: isActive ? currentURL?.absoluteString : nil,
                title: isActive ? currentTitle : nil,
                isActive: isActive
            )
        }
    }
}

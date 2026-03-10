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

    /// The WKWebView of the current tab (for script execution)
    var currentWebView: WKWebView? { get }

    /// Navigate to a URL in the current tab
    /// - Returns: true if navigation was initiated, false if no current tab exists
    func navigate(to url: URL) -> Bool

    /// Get all tab handles across all windows
    func getAllTabHandles() -> [String]

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

    /// Take a screenshot of the current webview
    /// - Parameter rect: Optional rect to crop the screenshot (for element screenshots)
    /// - Returns: PNG image data, or nil if screenshot failed
    func takeScreenshot(rect: CGRect?) async -> Data?
}

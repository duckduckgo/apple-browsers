//
//  MockBrowserAutomationProvider.swift
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
@testable import AutomationServer

/// Mock implementation of BrowserAutomationProvider for testing
@MainActor
final class MockBrowserAutomationProvider: BrowserAutomationProvider {

    // MARK: - Configurable State

    var currentTabHandle: String? = "mock-tab-1"
    var isLoading: Bool = false
    var isContentBlockerReady: Bool = true
    var currentURL: URL? = URL(string: "https://example.com")
    var currentWebView: WKWebView?

    var tabHandles: [String] = ["mock-tab-1"]

    // MARK: - Call Tracking

    var navigateCalled: URL?
    var closeCurrentTabCalled = false
    var switchToTabCalled: String?
    var newTabCalled = false
    var executeScriptCalled: (script: String, args: [String: Any])?

    // MARK: - Configurable Responses

    var navigateResult: Bool = true
    var switchToTabResult: Bool = true
    var newTabResult: String? = "mock-new-tab"
    var executeScriptResult: Result<Any?, Error> = .success(nil)
    var screenshotResult: Data?

    // MARK: - BrowserAutomationProvider

    func navigate(to url: URL) -> Bool {
        navigateCalled = url
        return navigateResult
    }

    func getAllTabHandles() -> [String] {
        return tabHandles
    }

    func closeCurrentTab() {
        closeCurrentTabCalled = true
    }

    func switchToTab(handle: String) -> Bool {
        switchToTabCalled = handle
        return switchToTabResult
    }

    func newTab() -> String? {
        newTabCalled = true
        return newTabResult
    }

    func executeScript(_ script: String, args: [String: Any]) async -> Result<Any?, Error> {
        executeScriptCalled = (script, args)
        return executeScriptResult
    }

    func takeScreenshot(rect: CGRect?) async -> Data? {
        return screenshotResult
    }

    // MARK: - Reset

    func reset() {
        navigateCalled = nil
        closeCurrentTabCalled = false
        switchToTabCalled = nil
        newTabCalled = false
        executeScriptCalled = nil
    }
}

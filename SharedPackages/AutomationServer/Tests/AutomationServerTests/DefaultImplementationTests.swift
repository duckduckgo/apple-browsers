//
//  DefaultImplementationTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import XCTest
@testable import AutomationServer

/// A provider that only implements the members without default implementations,
/// so these tests exercise the protocol extension defaults.
@MainActor
private final class MinimalProvider: BrowserAutomationProvider {
    var currentTabHandle: String? = "tab-1"
    var isLoading = false
    var isContentBlockerReady = true
    var currentURL: URL? = URL(string: "https://duckduckgo.com")
    var currentWebView: WKWebView?
    var tabHandles = ["tab-1", "tab-2"]
    var executeScriptCalled: (script: String, args: [String: Any])?
    var executeScriptResult: Result<Any?, Error> = .success(nil)

    func navigate(to url: URL) -> Bool { true }
    func getAllTabHandles() -> [String] { tabHandles }
    func closeCurrentTab() {}
    func switchToTab(handle: String) -> Bool { true }
    func newTab() -> String? { nil }
    func executeScript(_ script: String, args: [String: Any]) async -> Result<Any?, Error> {
        executeScriptCalled = (script, args)
        return executeScriptResult
    }
    func takeScreenshot(rect: CGRect?) async -> Data? { nil }
}

@MainActor
final class DefaultImplementationTests: XCTestCase {

    func testGoBack_ReturnsFalseWithoutWebView() {
        let provider = MinimalProvider()
        provider.currentWebView = nil

        XCTAssertFalse(provider.goBack())
        XCTAssertFalse(provider.goForward())
    }

    func testGoBack_ReturnsFalseWhenWebViewHasNoHistory() {
        let provider = MinimalProvider()
        provider.currentWebView = WKWebView(frame: .zero)

        XCTAssertFalse(provider.goBack())
        XCTAssertFalse(provider.goForward())
    }

    func testCurrentTitle_IsNilWithoutWebView() {
        let provider = MinimalProvider()
        provider.currentWebView = nil

        XCTAssertNil(provider.currentTitle)
    }

    func testGetAllTabs_MarksOnlyActiveTabWithMetadata() {
        let provider = MinimalProvider()

        let tabs = provider.getAllTabs()

        XCTAssertEqual(tabs, [
            AutomationTabInfo(handle: "tab-1", url: "https://duckduckgo.com", title: nil, isActive: true),
            AutomationTabInfo(handle: "tab-2", url: nil, title: nil, isActive: false)
        ])
    }

    func testScroll_ExecutesScrollByScriptWithDeltas() async {
        let provider = MinimalProvider()

        let didScroll = await provider.scroll(deltaX: 10, deltaY: -20)

        XCTAssertTrue(didScroll)
        XCTAssertEqual(provider.executeScriptCalled?.script, "window.scrollBy(deltaX, deltaY);")
        XCTAssertEqual(provider.executeScriptCalled?.args["deltaX"] as? Double, 10)
        XCTAssertEqual(provider.executeScriptCalled?.args["deltaY"] as? Double, -20)
    }

    func testScroll_ReturnsFalseWhenScriptFails() async {
        let provider = MinimalProvider()
        provider.executeScriptResult = .failure(AutomationServerError.scriptExecutionFailed)

        let didScroll = await provider.scroll(deltaX: 0, deltaY: 100)

        XCTAssertFalse(didScroll)
    }
}

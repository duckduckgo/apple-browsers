//
//  WebExtensionNavigationGateTests.swift
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
import WebExtensions
import XCTest

@testable import DDGNavigation
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WebExtensionNavigationGateTests: XCTestCase {

    func testMainFrameHTTPNavigationWaitsForInitialExtensionLoad() async {
        var didWait = false
        let gate = WebExtensionNavigationGate()

        let navigationAction = makeNavigationAction(url: URL(string: "https://example.com")!, isForMainFrame: true)
        await gate.waitIfNeeded(isMainFrame: navigationAction.isForMainFrame,
                                url: navigationAction.url,
                                initialLoadWaiter: { didWait = true })

        XCTAssertTrue(didWait)
        XCTAssertEqual(WebExtensionNavigationGate.defaultInitialLoadTimeout, 10)
    }

    func testSubframeHTTPNavigationDoesNotWaitForInitialExtensionLoad() async {
        let gate = WebExtensionNavigationGate()

        let navigationAction = makeNavigationAction(url: URL(string: "https://example.com/frame")!, isForMainFrame: false)
        await gate.waitIfNeeded(isMainFrame: navigationAction.isForMainFrame,
                                url: navigationAction.url,
                                initialLoadWaiter: { XCTFail("Subframe navigation must not wait") })
    }

    func testMainFrameNonHTTPNavigationDoesNotWaitForInitialExtensionLoad() async {
        let gate = WebExtensionNavigationGate()

        let navigationAction = makeNavigationAction(url: .newtab, isForMainFrame: true)
        await gate.waitIfNeeded(isMainFrame: navigationAction.isForMainFrame,
                                url: navigationAction.url,
                                initialLoadWaiter: { XCTFail("Non-HTTP navigation must not wait") })
    }

    func testMainFrameHTTPNavigationFailsOpenWhenInitialExtensionLoadHangs() async {
        let gate = WebExtensionNavigationGate(initialLoadTimeout: 0.01)
        let start = Date()

        let navigationAction = makeNavigationAction(url: URL(string: "https://example.com")!, isForMainFrame: true)
        await gate.waitIfNeeded(isMainFrame: navigationAction.isForMainFrame,
                                url: navigationAction.url,
                                initialLoadWaiter: {
            while !Task.isCancelled {
                await Task.yield()
            }
        })

        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    private func makeNavigationAction(url: URL, isForMainFrame: Bool) -> NavigationAction {
        let webView = WKWebView()
        let sourceFrame = FrameInfo(webView: webView,
                                    handle: FrameHandle(rawValue: 1),
                                    isMainFrame: true,
                                    url: url,
                                    securityOrigin: url.securityOrigin)
        let targetFrame = FrameInfo(webView: webView,
                                    handle: FrameHandle(rawValue: 2),
                                    isMainFrame: isForMainFrame,
                                    url: url,
                                    securityOrigin: url.securityOrigin)
        return NavigationAction(request: URLRequest(url: url),
                                navigationType: .sessionRestoration,
                                currentHistoryItemIdentity: nil,
                                redirectHistory: nil,
                                isUserInitiated: false,
                                sourceFrame: sourceFrame,
                                targetFrame: targetFrame,
                                shouldDownload: false,
                                mainFrameNavigation: nil)
    }
}

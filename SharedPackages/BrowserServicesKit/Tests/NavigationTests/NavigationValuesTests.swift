//
//  NavigationValuesTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

#if os(macOS)

import Combine
import Common
import Swifter
import WebKit
import XCTest
@testable import Navigation

@available(macOS 12.0, iOS 15.0, *)
class NavigationValuesTests: DistributedNavigationDelegateTestsBase {

    @MainActor
    func testNavigationActionPreferences() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let webView = withWebView { $0 }
        let navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView, isMain: false), targetFrame: nil, navigationType: .other, request: req(urls.local)).navigationAction

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = "1"
            prefs.contentMode = .mobile
            prefs.javaScriptEnabled = false
            return .cancel
        }
        var e = expectation(description: "decisionHandler1 called")
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "")
            XCTAssertTrue(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .recommended)
            e.fulfill()
        }
        waitForExpectations(timeout: 5)

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = "allow_ua"
            prefs.contentMode = .mobile
            prefs.javaScriptEnabled = false
            return .allow
        }
        e = expectation(description: "decisionHandler2 called")
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "allow_ua")
            XCTAssertFalse(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .mobile)
            e.fulfill()
        }
        waitForExpectations(timeout: 5)

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = nil
            return .allow
        }
        e = expectation(description: "decisionHandler3 called")
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        prefs.preferredContentMode = .desktop
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: prefs) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "allow_ua")
            XCTAssertFalse(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .desktop)
            e.fulfill()
        }
        waitForExpectations(timeout: 5)

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = "download_ua"
            prefs.contentMode = .mobile
            prefs.javaScriptEnabled = false
            return .download
        }
        e = expectation(description: "decisionHandler4 called")
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "allow_ua")
            XCTAssertTrue(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .recommended)
            e.fulfill()
        }
        waitForExpectations(timeout: 5)

        responder(at: 0).onNavigationAction = { _, prefs in
            prefs.userAgent = "next_ua"
            prefs.contentMode = .mobile
            prefs.javaScriptEnabled = false
            return .next
        }
        e = expectation(description: "decisionHandler5 called")
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { [unowned webView] _, prefs in
            XCTAssertEqual(webView.customUserAgent, "next_ua")
            XCTAssertFalse(prefs.allowsContentJavaScript)
            XCTAssertEqual(prefs.preferredContentMode, .mobile)
            e.fulfill()
        }
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testNavigationTypes() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let webView = withWebView { $0 }
        var navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView, isMain: false), targetFrame: nil, navigationType: .formSubmitted, request: req(urls.local)).navigationAction
        var e = expectation(description: "decisionHandler 1 called")
        responder(at: 0).onNavigationAction = { action, _ in
            XCTAssertEqual(action.navigationType, .formSubmitted)
            e.fulfill()
            return .cancel
        }
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { _, _ in }
        waitForExpectations(timeout: 1)

        navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView, isMain: false), targetFrame: nil, navigationType: .formResubmitted, request: req(urls.local)).navigationAction
        e = expectation(description: "decisionHandler 2 called")
        responder(at: 0).onNavigationAction = { action, _ in
            XCTAssertEqual(action.navigationType, .formResubmitted)
            e.fulfill()
            return .cancel
        }
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { _, _ in }
        waitForExpectations(timeout: 1)

        navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView, isMain: false), targetFrame: nil, navigationType: .linkActivated, request: req(urls.local)).navigationAction
        e = expectation(description: "decisionHandler 2 called")
        responder(at: 0).onNavigationAction = { action, _ in
#if os(macOS)
            XCTAssertEqual(action.navigationType, .linkActivated(isMiddleClick: false))
#else
            XCTAssertEqual(action.navigationType, .linkActivated)
#endif
            e.fulfill()
            return .cancel
        }
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { _, _ in }
        waitForExpectations(timeout: 1)

#if os(macOS)
        navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView, isMain: false), targetFrame: nil, navigationType: .linkActivated, request: req(urls.local), buttonNumber: 4).navigationAction
        e = expectation(description: "decisionHandler 2 called")
        responder(at: 0).onNavigationAction = { action, _ in
            XCTAssertEqual(action.navigationType, .link(.middleClick))
            XCTAssertFalse(action.isUserInitiated)
            e.fulfill()
            return .cancel
        }
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { _, _ in }
        waitForExpectations(timeout: 1)
#endif

        navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView, isMain: false), targetFrame: nil, navigationType: .reload, request: req(urls.local)).navigationAction
        e = expectation(description: "decisionHandler 2 called")
        responder(at: 0).onNavigationAction = { action, _ in
            XCTAssertEqual(action.navigationType, .reload)
            e.fulfill()
            return .cancel
        }
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { _, _ in }
        waitForExpectations(timeout: 1)

#if _IS_USER_INITIATED_ENABLED
        navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView, isMain: false), targetFrame: nil, navigationType: .other, request: req(urls.local), isUserInitiated: true).navigationAction
        e = expectation(description: "decisionHandler 2 called")
        responder(at: 0).onNavigationAction = { action, _ in
            XCTAssertTrue(action.isUserInitiated)
            e.fulfill()
            return .cancel
        }
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { _, _ in }
        waitForExpectations(timeout: 1)
#endif
    }

#if os(macOS)
    @MainActor
    func testNavigationHotkeys() {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let webView = withWebView { $0 }
        var navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView, isMain: false), targetFrame: nil, navigationType: .linkActivated, request: req(urls.local), isUserInitiated: true, modifierFlags: [.capsLock, .command, .function]).navigationAction
        var e = expectation(description: "decisionHandler 1 called")
        responder(at: 0).onNavigationAction = { action, _ in
            XCTAssertEqual(action.navigationType, .link)
            XCTAssertEqual(action.modifierFlags, [.capsLock, .command, .function])
            e.fulfill()
            return .cancel
        }
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { _, _ in }
        waitForExpectations(timeout: 1)

        navAction = WKNavigationActionMock(sourceFrame: .mock(for: webView, isMain: false), targetFrame: nil, navigationType: .other, request: req(urls.local), isUserInitiated: false, modifierFlags: [.option, .shift]).navigationAction
        e = expectation(description: "decisionHandler 2 called")
        responder(at: 0).onNavigationAction = { action, _ in
            XCTAssertEqual(action.navigationType, .other)
            XCTAssertEqual(action.modifierFlags, [.option, .shift])
            e.fulfill()
            return .cancel
        }
        navigationDelegate.webView(webView, decidePolicyFor: navAction, preferences: WKWebpagePreferences()) { _, _ in }
        waitForExpectations(timeout: 1)
    }
#endif

}

#endif

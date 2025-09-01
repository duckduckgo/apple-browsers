//
//  WebKitPrivateMethodsAvailabilityTests.swift
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

#if _SESSION_STATE_WITH_FILTER_ENABLED

import Combine
import Foundation
import WebKit
import XCTest

@testable import Navigation

@available(macOS 12.0, iOS 15.0, *)
class WebKitPrivateMethodsAvailabilityTests: DistributedNavigationDelegateTestsBase {

    func testSessionStateDataAvailability() throws {
        XCTAssertTrue(WKWebView.instancesRespond(to: WKWebView.Selector.sessionStateData))
    }

    func testRestoreFromSessionStateDataAvailability() throws {
        XCTAssertTrue(WKWebView.instancesRespond(to: WKWebView.Selector.restoreFromSessionStateData))
    }

    func testSessionStateWithFilterAvailability() throws {
        XCTAssertTrue(WKWebView.instancesRespond(to: WKWebView.Selector.sessionStateWithFilter))
    }

    func testRestoreSessionStateAndNavigateAvailability() throws {
        XCTAssertTrue(WKWebView.instancesRespond(to: WKWebView.Selector.restoreSessionStateAndNavigate))
    }

    // MARK: - Functional Tests

    func testSessionStateDataFunctionality() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))
        let eDidFinish = expectation(description: "onDidFinish")
        responder(at: 0).onDidFinish = { _ in eDidFinish.fulfill() }

        let dataURL = URL(string: "data:text/html,no%20error%20A")!
        withWebView { webView in
            webView.load(URLRequest(url: dataURL))
        }
        waitForExpectations()

        withWebView { webView in
            XCTAssertNotNil(webView.backForwardList.currentItem, "Should have current item after loading")

            let sessionData = webView.sessionStateData()
            XCTAssertNotNil(sessionData, "sessionStateData() should return valid data")
            XCTAssertFalse(sessionData!.isEmpty, "sessionStateData() should return non-empty data")
        }
    }

    func testRestoreFromSessionStateDataFunctionality() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        withWebView { webView in
            webView.restoreSessionState(from: data.interactionStateData)
        }

        withWebView { webView in
            let backURLs = webView.backForwardList.backList.map(\.url)
            let forwardURLs = webView.backForwardList.forwardList.map(\.url)
            let currentURL = webView.backForwardList.currentItem?.url

            XCTAssertNotNil(currentURL)
            XCTAssertEqual(backURLs, [urls.local1])
            XCTAssertEqual(forwardURLs, [])
            XCTAssertEqual(currentURL?.separatedString, urls.local.separatedString)
        }
    }

    func testSessionStateWithFilterFunctionality() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let dataURL1 = URL(string: "data:text/html,page%20one")!
        let dataURL2 = URL(string: "data:text/html,page%20two")!
        let dataURL3 = URL(string: "data:text/html,page%20three")!

        // Load multiple pages to create back/forward list items
        let eDidFinish1 = expectation(description: "onDidFinish1")
        responder(at: 0).onDidFinish = { _ in eDidFinish1.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: dataURL1))
        }
        waitForExpectations()

        let eDidFinish2 = expectation(description: "onDidFinish2")
        responder(at: 0).onDidFinish = { _ in eDidFinish2.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: dataURL2))
        }
        waitForExpectations()

        let eDidFinish3 = expectation(description: "onDidFinish3")
        responder(at: 0).onDidFinish = { _ in eDidFinish3.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: dataURL3))
        }
        waitForExpectations()

        withWebView { webView in
            // Verify we have the expected navigation history
            let backURLs = webView.backForwardList.backList.map(\.url)
            let forwardURLs = webView.backForwardList.forwardList.map(\.url)
            let currentURL = webView.backForwardList.currentItem?.url

            XCTAssertEqual(backURLs, [dataURL1, dataURL2])
            XCTAssertEqual(forwardURLs, [])
            XCTAssertEqual(currentURL, dataURL3)

            // Test with a filter that excludes page two (dataURL2)
            let sessionStateFiltered = webView.sessionState(withFilter: { item in
                return item.url != dataURL2
            })
            XCTAssertNotNil(sessionStateFiltered)

            // Create a fresh WebView to test restore into clean state
            let cleanWebView = makeWebView()
            cleanWebView.navigationDelegate = navigationDelegateProxy

            cleanWebView.restoreSessionState(from: sessionStateFiltered!, andNavigate: false)

            // Verify the filter worked - should only have dataURL1 and dataURL3
            let restoredBackURLs = cleanWebView.backForwardList.backList.map(\.url)
            let restoredForwardURLs = cleanWebView.backForwardList.forwardList.map(\.url)
            let restoredCurrentURL = cleanWebView.backForwardList.currentItem?.url

            XCTAssertEqual(restoredBackURLs, [dataURL1])
            XCTAssertEqual(restoredForwardURLs, [])
            XCTAssertEqual(restoredCurrentURL, dataURL3)
        }
    }

    func testRestoreSessionStateAndNavigateFunctionality() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let dataURL1 = URL(string: "data:text/html,page%20one")!
        let dataURL2 = URL(string: "data:text/html,page%20two")!
        let dataURL3 = URL(string: "data:text/html,page%20three")!

        // Create a multi-page session state by navigating to multiple pages
        let eDidFinish1 = expectation(description: "onDidFinish1")
        responder(at: 0).onDidFinish = { _ in eDidFinish1.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: dataURL1))
        }
        waitForExpectations()

        let eDidFinish2 = expectation(description: "onDidFinish2")
        responder(at: 0).onDidFinish = { _ in eDidFinish2.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: dataURL2))
        }
        waitForExpectations()

        let eDidFinish3 = expectation(description: "onDidFinish3")
        responder(at: 0).onDidFinish = { _ in eDidFinish3.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: dataURL3))
        }
        waitForExpectations()

        // Capture session state when we're on page 3 with back history
        var sessionState: Any?
        withWebView { webView in
            sessionState = webView.sessionState(withFilter: { _ in true })
        }

        // Load a completely different page to change the state
        let differentURL = URL(string: "data:text/html,different%20page")!
        let eDidFinish4 = expectation(description: "onDidFinish4")
        responder(at: 0).onDidFinish = { _ in eDidFinish4.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: differentURL))
        }
        waitForExpectations()

        let eDidFinish5 = expectation(description: "onDidFinish5")
        responder(at: 0).onDidFinish = { _ in eDidFinish5.fulfill() }

        withWebView { webView in
            // Test restoreSessionState(from:andNavigate:) with navigation enabled
            let navigation = webView.restoreSessionState(from: sessionState!, andNavigate: true)
            XCTAssertNotNil(navigation)
        }
        waitForExpectations()

        withWebView { webView in
            // Verify we restored to the original multi-page session state
            let backURLs = webView.backForwardList.backList.map(\.url)
            let forwardURLs = webView.backForwardList.forwardList.map(\.url)
            let currentURL = webView.backForwardList.currentItem?.url

            XCTAssertEqual(currentURL, dataURL3)
            XCTAssertEqual(backURLs, [dataURL1, dataURL2])
            XCTAssertEqual(forwardURLs, [])
        }
    }

    func testRestoreSessionStateWithoutNavigation() throws {
        navigationDelegate.setResponders(.strong(NavigationResponderMock(defaultHandler: { _ in })))

        let dataURL1 = URL(string: "data:text/html,no%20error%20D")!
        let dataURL2 = URL(string: "data:text/html,different%20page")!
        let dataURL3 = URL(string: "data:text/html,different%20page%20again")!

        // First load a page to create session state
        let eDidFinish1 = expectation(description: "onDidFinish1")
        responder(at: 0).onDidFinish = { _ in eDidFinish1.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: dataURL1))
        }
        waitForExpectations()

        let eDidFinish2 = expectation(description: "onDidFinish2")
        responder(at: 0).onDidFinish = { _ in eDidFinish2.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: dataURL2))
        }
        waitForExpectations()

        var sessionState: Any?
        withWebView { webView in
            sessionState = webView.sessionState(withFilter: { _ in true })
        }

        let eDidFinish3 = expectation(description: "onDidFinish3")
        responder(at: 0).onDidFinish = { _ in eDidFinish3.fulfill() }
        withWebView { webView in
            webView.load(URLRequest(url: dataURL3))
        }
        waitForExpectations()

        responder(at: 0).defaultHandler = {
            XCTFail("Unexpected navigation event: \($0))")
        }
        withWebView { webView in
            XCTAssertFalse(webView.isLoading)

            // Test restoreSessionState(from:andNavigate:) without navigation
            let navigation = webView.restoreSessionState(from: sessionState!, andNavigate: false)
            XCTAssertNil(navigation)
            XCTAssertFalse(webView.isLoading)

            // Check URLs after restore
            let backURLs = webView.backForwardList.backList.map(\.url)
            let forwardURLs = webView.backForwardList.forwardList.map(\.url)
            let currentURL = webView.backForwardList.currentItem?.url

            XCTAssertEqual(webView.url, dataURL3)
            XCTAssertEqual(currentURL, dataURL2)
            XCTAssertEqual(backURLs, [dataURL1])
            XCTAssertEqual(forwardURLs, [])
        }
    }

}

#endif

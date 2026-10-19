//
//  TabViewControllerFindInPageTests.swift
//  DuckDuckGo
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
@_spi(Testing) import PixelKit

@testable import DuckDuckGo

@available(iOS 16.0, *)
final class TabViewControllerFindInPageTests: XCTestCase {

    func testWhenFindInPageIsRequestedThenFiresDailyUsagePixelWithoutSearchData() {
        let pixelFiring = PixelKitMock()
        let tab = TabViewController.fake(pixelFiring: pixelFiring)
        (tab.webView as? WebView)?.lastFindInPageQuery = "private search"

        tab.requestFindInPage()

        let calls = pixelFiring.actualFireCalls.filter { $0.pixel is FindInPagePixel }
        XCTAssertEqual(calls, [ExpectedFireCall(pixel: FindInPagePixel.opened, frequency: .daily)])
        XCTAssertNil(calls.first?.pixel.parameters)
        XCTAssertNil(calls.first?.pixel.standardParameters)
        XCTAssertNil(calls.first?.additionalParameters)
    }

    func testWhenNavigatorIsStuckVisibleThenRequestPresentsFreshNavigatorWithCurrentQuery() throws {
        let pixelFiring = PixelKitMock()
        let webView = FindWebViewSpy(frame: .zero, configuration: WKWebViewConfiguration())
        let tab = TabViewController.fake(customWebView: { _ in webView }, pixelFiring: pixelFiring)
        webView.isFindInteractionEnabled = true
        let previousInteraction = try XCTUnwrap(webView.findInteraction as? FindInteractionSpy)
        previousInteraction.navigatorVisible = true
        previousInteraction.searchText = "in progress"

        tab.requestFindInPage()

        let interaction = try XCTUnwrap(webView.findInteraction as? FindInteractionSpy)
        XCTAssertTrue(previousInteraction.wasDismissed)
        XCTAssertFalse(interaction === previousInteraction)
        XCTAssertTrue(interaction.wasPresented)
        XCTAssertEqual(interaction.searchText, "in progress")
        XCTAssertTrue(pixelFiring.actualFireCalls.contains(ExpectedFireCall(pixel: FindInPagePixel.opened, frequency: .daily)))
    }

    func testWhenCurrentQueryWasClearedThenRequestKeepsItEmpty() throws {
        let webView = FindWebViewSpy(frame: .zero, configuration: WKWebViewConfiguration())
        let tab = TabViewController.fake(customWebView: { _ in webView })
        webView.isFindInteractionEnabled = true
        let previousInteraction = try XCTUnwrap(webView.findInteraction as? FindInteractionSpy)
        previousInteraction.navigatorVisible = true
        previousInteraction.searchText = nil

        tab.requestFindInPage()

        XCTAssertEqual(webView.findInteraction?.searchText, "")
        XCTAssertTrue((webView.findInteraction as? FindInteractionSpy)?.wasPresented == true)
    }

    func testWhenPreviousNavigatorIsClosedThenRequestUsesRememberedTabQuery() throws {
        let tab = TabViewController.fake()
        let webView = try XCTUnwrap(tab.webView as? WebView)
        webView.lastFindInPageQuery = "remembered"
        webView.isFindInteractionEnabled = true
        let previousInteraction = try XCTUnwrap(webView.findInteraction)
        previousInteraction.searchText = "another tab"

        tab.requestFindInPage()

        XCTAssertFalse(webView.findInteraction === previousInteraction)
        XCTAssertEqual(webView.findInteraction?.searchText, "remembered")
    }

    func testWhenTabHasNoRememberedQueryThenRequestStartsEmpty() throws {
        let tab = TabViewController.fake()
        tab.webView.isFindInteractionEnabled = true
        tab.webView.findInteraction?.searchText = "another tab"

        tab.requestFindInPage()

        XCTAssertEqual(tab.webView.findInteraction?.searchText, "")
    }
}

@available(iOS 16.0, *)
private final class FindWebViewSpy: WKWebView {
    private let findDelegate = FindInteractionDelegateStub()
    private var interaction: FindInteractionSpy?

    override var isFindInteractionEnabled: Bool {
        get { interaction != nil }
        set {
            if newValue && interaction == nil {
                interaction = FindInteractionSpy(sessionDelegate: findDelegate)
            } else if !newValue {
                interaction = nil
            }
        }
    }

    override var findInteraction: UIFindInteraction? { interaction }
}

@available(iOS 16.0, *)
private final class FindInteractionSpy: UIFindInteraction {
    var navigatorVisible = false
    var wasDismissed = false
    var wasPresented = false

    override var isFindNavigatorVisible: Bool { navigatorVisible }

    override func dismissFindNavigator() {
        wasDismissed = true
        navigatorVisible = false
    }

    override func presentFindNavigator(showingReplace: Bool) {
        wasPresented = true
        navigatorVisible = true
    }
}

@available(iOS 16.0, *)
private final class FindInteractionDelegateStub: NSObject, UIFindInteractionDelegate {
    func findInteraction(_ interaction: UIFindInteraction, sessionFor view: UIView) -> UIFindSession? { nil }
}

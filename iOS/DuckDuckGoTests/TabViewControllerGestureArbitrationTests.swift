//
//  TabViewControllerGestureArbitrationTests.swift
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

import UIKit
import WebKit
import XCTest
@testable import DuckDuckGo

final class TabViewControllerGestureArbitrationTests: XCTestCase {

    /// Stands in for the touch location, which is otherwise only settable by a real `UITouch`.
    private final class StubLocationTapGestureRecognizer: UITapGestureRecognizer {
        var stubbedLocation: CGPoint = .zero
        override func location(in view: UIView?) -> CGPoint { stubbedLocation }
    }

    private var sut: TabViewController!
    private var chromeDelegate: DuckPlayerBrowserChromeDelegateMock!
    private var featureFlagger: MockFeatureFlagger!
    private var showBarsTap: StubLocationTapGestureRecognizer!
    private var webContentDoubleTap: UITapGestureRecognizer!

    override func setUpWithError() throws {
        try super.setUpWithError()

        featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.suppressShowBarsGestureRecogniserDelay])
        sut = .fake(featureFlagger: featureFlagger)
        sut.loadViewIfNeeded()
        sut.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        sut.view.layoutIfNeeded()

        chromeDelegate = DuckPlayerBrowserChromeDelegateMock()
        sut.chromeDelegate = chromeDelegate

        // With the bars hidden the web view stays full height and the toolbar's height becomes the
        // scroll view's bottom content inset. That inset is what creates the strip `isBottom` matches.
        sut.webView.scrollView.contentInset.bottom = 48

        showBarsTap = StubLocationTapGestureRecognizer()
        sut.view.addGestureRecognizer(showBarsTap)
        sut.showBarsTapGestureRecogniser = showBarsTap

        // Stands in for WKWebView's multi-tap recognizers, which live on the web view itself.
        webContentDoubleTap = UITapGestureRecognizer()
        webContentDoubleTap.numberOfTapsRequired = 2
        sut.webView.addGestureRecognizer(webContentDoubleTap)
    }

    override func tearDownWithError() throws {
        webContentDoubleTap = nil
        showBarsTap = nil
        featureFlagger = nil
        chromeDelegate = nil
        sut = nil
        try super.tearDownWithError()
    }

    // MARK: - Geometry, derived from the live hierarchy rather than hard-coded

    private var webViewFrameInRootView: CGRect {
        sut.webView.convert(sut.webView.bounds, to: sut.view)
    }

    /// Inside the page — where a keyboard key or link would be tapped.
    private var locationInPageContent: CGPoint {
        CGPoint(x: webViewFrameInRootView.midX, y: webViewFrameInRootView.midY)
    }

    /// Below the web view's uncovered content, i.e. the strip the hidden toolbar occupies.
    private var locationBelowPageContent: CGPoint {
        CGPoint(x: webViewFrameInRootView.midX,
                y: webViewFrameInRootView.maxY - sut.webView.scrollView.contentInset.bottom + 1)
    }

    // MARK: - Web content must arbitrate taps unencumbered

    func testWhenChromeIsVisibleThenWebContentTapIsNotHeldBehindShowBarsTap() {
        chromeDelegate.isToolbarHidden = false
        showBarsTap.stubbedLocation = locationBelowPageContent

        XCTAssertFalse(sut.gestureRecognizer(showBarsTap, shouldBeRequiredToFailBy: webContentDoubleTap))
    }

    /// The reported failure: chrome hidden, tapping page content, second tap of a quick pair dropped.
    func testWhenChromeIsHiddenAndTapIsInPageContentThenWebContentTapIsNotHeldBehindShowBarsTap() {
        chromeDelegate.isToolbarHidden = true
        showBarsTap.stubbedLocation = locationInPageContent

        XCTAssertFalse(sut.gestureRecognizer(showBarsTap, shouldBeRequiredToFailBy: webContentDoubleTap))
    }

    /// Priority is only ever worth claiming where the tap can fire, so the two must agree.
    func testWhenShowBarsTapWouldNotBeginThenItClaimsNoPriorityOverWebContent() {
        chromeDelegate.isToolbarHidden = true
        showBarsTap.stubbedLocation = locationInPageContent

        XCTAssertFalse(sut.gestureRecognizerShouldBegin(showBarsTap))
        XCTAssertFalse(sut.gestureRecognizer(showBarsTap, shouldBeRequiredToFailBy: webContentDoubleTap))
    }

    func testWhenDelaySuppressionIsDisabledThenShowBarsTapRetainsLegacyPriorityOverWebContent() {
        featureFlagger.enabledFeatureFlags = []
        chromeDelegate.isToolbarHidden = false
        showBarsTap.stubbedLocation = locationInPageContent

        XCTAssertTrue(sut.gestureRecognizer(showBarsTap, shouldBeRequiredToFailBy: webContentDoubleTap))
    }

    func testWhenDelaySuppressionIsEnabledThenShowBarsTapDoesNotDelayTouchEndDelivery() {
        let sut = TabViewController.fake(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.suppressShowBarsGestureRecogniserDelay]))

        sut.loadViewIfNeeded()

        XCTAssertFalse(sut.showBarsTapGestureRecogniser.delaysTouchesEnded)
    }

    func testWhenDelaySuppressionIsDisabledThenShowBarsTapUsesDefaultTouchEndDelay() {
        let sut = TabViewController.fake(featureFlagger: MockFeatureFlagger())

        sut.loadViewIfNeeded()

        XCTAssertTrue(sut.showBarsTapGestureRecogniser.delaysTouchesEnded)
    }

    // MARK: - Revealing hidden chrome from the bottom strip still takes precedence

    func testWhenChromeIsHiddenAndTapIsBelowPageContentThenWebContentTapWaitsForShowBarsTap() {
        chromeDelegate.isToolbarHidden = true
        showBarsTap.stubbedLocation = locationBelowPageContent

        XCTAssertTrue(sut.gestureRecognizerShouldBegin(showBarsTap))
        XCTAssertTrue(sut.gestureRecognizer(showBarsTap, shouldBeRequiredToFailBy: webContentDoubleTap))
    }

    // MARK: - Unrelated recognizers

    func testWhenOtherRecognizerIsNotATapThenItIsNotHeldBehindShowBarsTap() {
        chromeDelegate.isToolbarHidden = true
        showBarsTap.stubbedLocation = locationBelowPageContent
        let pan = UIPanGestureRecognizer()
        sut.webView.addGestureRecognizer(pan)

        XCTAssertFalse(sut.gestureRecognizer(showBarsTap, shouldBeRequiredToFailBy: pan))
    }

    func testWhenGestureRecognizerIsNotShowBarsTapThenNoPriorityIsClaimed() {
        chromeDelegate.isToolbarHidden = true
        showBarsTap.stubbedLocation = locationBelowPageContent
        let unrelated = UITapGestureRecognizer()
        sut.view.addGestureRecognizer(unrelated)

        XCTAssertFalse(sut.gestureRecognizer(unrelated, shouldBeRequiredToFailBy: webContentDoubleTap))
    }
}

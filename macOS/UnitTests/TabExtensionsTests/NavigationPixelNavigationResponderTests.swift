//
//  NavigationPixelNavigationResponderTests.swift
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

import DDGNavigation
@_spi(Testing) import PixelKit
import PrivacyConfig
@_spi(Testing) import SharedTestUtilities
import WebExtensions
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class NavigationPixelNavigationResponderTests: XCTestCase {

    /// Regression test for APPLE-MACOS-BDE.
    ///
    /// A navigation that fails provisionally before it ever starts has an empty `navigationActions`
    /// array. `Navigation.navigationAction` force-unwraps `navigationActions.last`, so reading it in
    /// `navigation(_:didFailWith:)` used to trap (EXC_BREAKPOINT). Since `siteLoadingStartTime` is only
    /// set in `didStart` (after a navigation action exists), the responder must short-circuit on it
    /// *before* touching `navigationAction`.
    @MainActor
    func testWhenNavigationFailsWithNoNavigationActions_thenItDoesNotCrashAndNoPixelIsFired() {
        let pixelMock = PixelKitMock(expecting: [])
        let responder = NavigationPixelNavigationResponder(pixelFiring: pixelMock, featureFlagger: MockFeatureFlagger())

        // A navigation that never received a navigation action (empty `navigationActions`),
        // e.g. a provisional load that failed before `didStart`.
        let navigation = Navigation(identity: NavigationIdentity(nil),
                                    responders: ResponderChain(responderRefs: []),
                                    state: .expected(nil),
                                    redirectHistory: nil,
                                    isCurrent: false)

        // Previously trapped on `navigationActions.last!` while evaluating the guard.
        responder.navigation(navigation, didFailWith: WKError(.webContentProcessTerminated))

        // No pixel should be fired for a navigation that never started loading.
        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    /// A redirect replaces `navigationAction`, but CPM attribution must continue to describe the
    /// logical navigation's initiating action.
    @MainActor
    func testCPMNavigationKindUsesInitialSessionRestorationActionAfterRedirect() {
        let webView = WKWebView()
        let frame = FrameInfo.mainFrame(for: webView)
        let initialAction = NavigationAction(
            request: URLRequest(url: URL(string: "https://example.com/restored")!),
            navigationType: .sessionRestoration,
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: false,
            sourceFrame: frame,
            targetFrame: frame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )
        let redirectAction = NavigationAction(
            request: URLRequest(url: URL(string: "https://example.com/redirected")!),
            navigationType: .redirect(.server),
            currentHistoryItemIdentity: nil,
            redirectHistory: [initialAction],
            isUserInitiated: false,
            sourceFrame: frame,
            targetFrame: frame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )
        let navigation = Navigation(
            identity: NavigationIdentity(nil),
            responders: ResponderChain(responderRefs: []),
            state: .started,
            redirectHistory: [initialAction, redirectAction],
            isCurrent: true
        )

        XCTAssertEqual(navigation.cpmMessagingNavigationKind, .sessionRestoration)
    }

    @MainActor
    func testCPMNavigationKindOfErrorPageIsErrorPage() {
        let navigation = makeNavigation(types: [.alternateHtmlLoad])

        XCTAssertEqual(navigation.cpmMessagingNavigationKind, .errorPage)
    }

    @MainActor
    func testCPMNavigationKindUsesInitialBackForwardActionAfterRedirect() {
        let navigation = makeNavigation(types: [.backForward(distance: -1), .redirect(.server)])

        XCTAssertEqual(navigation.cpmMessagingNavigationKind, .backForward)
    }

    @MainActor
    func testCPMNavigationKindOfAnOrdinaryNavigationWithoutAResponseIsOther() {
        XCTAssertEqual(makeNavigation(types: [.other]).cpmMessagingNavigationKind, .other)
        XCTAssertEqual(makeNavigation(types: [.linkActivated(isMiddleClick: false)]).cpmMessagingNavigationKind, .other)
        XCTAssertEqual(makeNavigation(types: [.redirect(.client(delay: 0)), .redirect(.server)]).cpmMessagingNavigationKind, .other)
    }

    @MainActor
    func testCPMNavigationKindOfADuckPlayerVideoIsDuckPlayerVideo() {
        let embed = URL(string: "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ")!
        let otherPage = URL(string: "https://www.youtube-nocookie.com/other")!

        XCTAssertEqual(makeNavigation(types: [.other], url: embed).cpmMessagingNavigationKind, .duckPlayerVideo)
        XCTAssertEqual(makeNavigation(types: [.other], url: otherPage).cpmMessagingNavigationKind, .other)
        XCTAssertEqual(makeNavigation(types: [.backForward(distance: -1)], url: embed).cpmMessagingNavigationKind, .backForward)
        XCTAssertEqual(makeNavigation(types: [.alternateHtmlLoad], url: embed).cpmMessagingNavigationKind, .errorPage)
    }

    @MainActor
    func testCPMNavigationKindOfADocumentThatIsNotHTMLIsNonHTMLDocument() {
        for mimeType in ["application/pdf", "image/png", "video/mp4", "text/plain", "application/json"] {
            XCTAssertEqual(Navigation.cpmMessagingNavigationKind(isErrorPage: false, initialNavigationType: .other, responseMimeType: mimeType),
                           .nonHTMLDocument,
                           mimeType)
        }
    }

    @MainActor
    func testCPMNavigationKindOfAnHTMLOrUnknownResponseIsOther() {
        for mimeType in ["text/html", "TEXT/HTML", "application/xhtml+xml", "", nil] {
            XCTAssertEqual(Navigation.cpmMessagingNavigationKind(isErrorPage: false, initialNavigationType: .other, responseMimeType: mimeType),
                           .other,
                           mimeType ?? "nil")
        }
    }

    @MainActor
    func testCPMNavigationKindOfRestorationHistoryAndErrorPageIgnoresTheResponse() {
        let pdf = "application/pdf"
        XCTAssertEqual(Navigation.cpmMessagingNavigationKind(isErrorPage: false, initialNavigationType: .sessionRestoration, responseMimeType: pdf), .sessionRestoration)
        XCTAssertEqual(Navigation.cpmMessagingNavigationKind(isErrorPage: false, initialNavigationType: .backForward(distance: -1), responseMimeType: pdf), .backForward)
        XCTAssertEqual(Navigation.cpmMessagingNavigationKind(isErrorPage: true, initialNavigationType: .other, responseMimeType: pdf), .errorPage)
    }

    /// A navigation whose actions have the given types, the last one being the current action.
    @MainActor
    private func makeNavigation(types: [NavigationType], url: URL = URL(string: "https://example.com/page")!) -> Navigation {
        let webView = WKWebView()
        let frame = FrameInfo.mainFrame(for: webView)
        let actions = types.map { type in
            NavigationAction(
                request: URLRequest(url: url),
                navigationType: type,
                currentHistoryItemIdentity: nil,
                redirectHistory: nil,
                isUserInitiated: false,
                sourceFrame: frame,
                targetFrame: frame,
                shouldDownload: false,
                mainFrameNavigation: nil
            )
        }
        return Navigation(
            identity: NavigationIdentity(nil),
            responders: ResponderChain(responderRefs: []),
            state: .started,
            redirectHistory: actions,
            isCurrent: true
        )
    }
}

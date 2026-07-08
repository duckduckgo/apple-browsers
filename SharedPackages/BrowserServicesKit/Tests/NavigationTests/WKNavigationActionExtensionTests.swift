//
//  WKNavigationActionExtensionTests.swift
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

#if os(macOS)

import WebKit
import XCTest
@testable import Navigation

/// Unit tests for `WKNavigationAction.isSameDocumentNavigation`.
///
/// BSK adds this heuristic property to `WKNavigationAction`; WebKit itself does not expose it.
/// WebKit's own fragment-navigation policy delegate checks `request.URL.fragment` (see
/// `Tools/TestWebKitAPI/Tests/WebKit/WKWebView/mac/FragmentNavigation.mm`), which is the
/// same O(1) approach used here instead of scanning `absoluteString`.
@available(macOS 12.0, *)
class WKNavigationActionExtensionTests: XCTestCase {

    // MARK: - Helpers

    private func makeAction(
        currentURL: URL,
        newURL: URL,
        navigationType: WKNavigationType
    ) -> WKNavigationAction {
        let targetFrame = WKFrameInfoMock(
            isMainFrame: false,
            request: URLRequest(url: currentURL),
            securityOrigin: WKSecurityOriginMock.new(url: currentURL),
            webView: nil
        ).frameInfo

        let sourceFrame = WKFrameInfoMock(
            isMainFrame: false,
            request: URLRequest(url: currentURL),
            securityOrigin: WKSecurityOriginMock.new(url: currentURL),
            webView: nil
        ).frameInfo

        return WKNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            navigationType: navigationType,
            request: URLRequest(url: newURL)
        ).navigationAction
    }

    // MARK: - .linkActivated

    // Adding a fragment to the current URL (the common anchor-click case).
    func testWhenLinkActivatedAndNewURLHasFragmentAndSameDocumentThenIsSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL(string: "http://example.com/page#section")!,
            navigationType: .linkActivated
        )
        XCTAssertTrue(action.isSameDocumentNavigation)
    }

    // Changing from one fragment to another on the same page.
    func testWhenLinkActivatedAndBothURLsHaveFragmentAndSameDocumentThenIsSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page#top")!,
            newURL: URL(string: "http://example.com/page#bottom")!,
            navigationType: .linkActivated
        )
        XCTAssertTrue(action.isSameDocumentNavigation)
    }

    // New URL has no fragment — must be a full navigation.
    func testWhenLinkActivatedAndNewURLHasNoFragmentThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page#section")!,
            newURL: URL(string: "http://example.com/page")!,
            navigationType: .linkActivated
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // Fragment present but different host — different document.
    func testWhenLinkActivatedAndDifferentHostThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL(string: "http://other.com/page#section")!,
            navigationType: .linkActivated
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // Fragment present but different path — different document.
    func testWhenLinkActivatedAndDifferentPathThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page1")!,
            newURL: URL(string: "http://example.com/page2#section")!,
            navigationType: .linkActivated
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // MARK: - .other

    // .other behaves identically to .linkActivated for same-document detection.
    func testWhenOtherNavigationTypeAndNewURLHasFragmentAndSameDocumentThenIsSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL(string: "http://example.com/page#anchor")!,
            navigationType: .other
        )
        XCTAssertTrue(action.isSameDocumentNavigation)
    }

    func testWhenOtherNavigationTypeAndNewURLHasNoFragmentThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL(string: "http://example.com/page")!,
            navigationType: .other
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // MARK: - .backForward

    // WebKit process-swap tests confirm back/forward to a fragment URL is same-document.
    func testWhenBackForwardAndNewURLHasFragmentAndSameDocumentThenIsSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL(string: "http://example.com/page#section")!,
            navigationType: .backForward
        )
        XCTAssertTrue(action.isSameDocumentNavigation)
    }

    // Going back from a fragment URL to the unfragmented URL is still same-document.
    func testWhenBackForwardAndCurrentURLHasFragmentAndNewURLDoesNotThenIsSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page#section")!,
            newURL: URL(string: "http://example.com/page")!,
            navigationType: .backForward
        )
        XCTAssertTrue(action.isSameDocumentNavigation)
    }

    // Neither URL has a fragment — cannot be a same-document fragment navigation.
    func testWhenBackForwardAndNeitherURLHasFragmentThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL(string: "http://example.com/page")!,
            navigationType: .backForward
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // Fragment present but on a different document.
    func testWhenBackForwardAndDifferentDocumentThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page1")!,
            newURL: URL(string: "http://example.com/page2#section")!,
            navigationType: .backForward
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // MARK: - Non-fragment navigation types

    func testWhenReloadThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page#section")!,
            newURL: URL(string: "http://example.com/page#section")!,
            navigationType: .reload
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    func testWhenFormSubmittedThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL(string: "http://example.com/page#section")!,
            navigationType: .formSubmitted
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    func testWhenFormResubmittedThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL(string: "http://example.com/page#section")!,
            navigationType: .formResubmitted
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // MARK: - Guard conditions

    // No targetFrame → currentURL is nil → guard fails.
    func testWhenNoTargetFrameThenIsNotSameDocument() {
        let sourceFrame = WKFrameInfoMock(
            isMainFrame: false,
            request: URLRequest(url: URL(string: "http://example.com/page")!),
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "http://example.com/page")!),
            webView: nil
        ).frameInfo

        let action = WKNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: nil,
            navigationType: .linkActivated,
            request: URLRequest(url: URL(string: "http://example.com/page#section")!)
        ).navigationAction

        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // Empty currentURL → guard fails (`!currentURL.isEmpty`).
    func testWhenCurrentURLIsEmptyThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL.empty,
            newURL: URL(string: "http://example.com/page#section")!,
            navigationType: .linkActivated
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // Empty newURL → guard fails (`!newURL.isEmpty`).
    func testWhenNewURLIsEmptyThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL.empty,
            navigationType: .linkActivated
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // MARK: - file:// URLs (from WebKit's equalIgnoringFragmentIdentifier test matrix)

    func testWhenFileURLHasFragmentAndSamePathThenIsSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "file:///path/to/file.html")!,
            newURL: URL(string: "file:///path/to/file.html#hash")!,
            navigationType: .linkActivated
        )
        XCTAssertTrue(action.isSameDocumentNavigation)
    }

    func testWhenFileURLHasDifferentPathThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "file:///path/to/file.html")!,
            newURL: URL(string: "file:///path/to/other.html#hash")!,
            navigationType: .linkActivated
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    // MARK: - about: URLs

#if _ORIGINAL_DATA_AS_STRING_ENABLED
    // Foundation's URL parser will wrongly percent-encode '#' to '%23' in opaque about: URLs
    // (e.g. when constructed via URL(trimmedAddressBarString:)). URL.hasFragment and
    // URL.equals(_:by:) recover the literal '#' via URLComponents(webKitUrl:), which reads
    // the WebKit-internal _web_originalDataAsString to parse the URL as WebKit intended.
    func testWhenAboutURLWithPercentEncodedHashAndSameDocumentThenIsSameDocument() {
        let action = makeAction(
            currentURL: NSURL(string: "about:blank")! as URL,
            newURL: NSURL(string: "about:blank#section")! as URL,
            navigationType: .other
        )
        XCTAssertEqual(action.request.url?.absoluteString, "about:blank%23section")
        XCTAssertTrue(action.isSameDocumentNavigation)
    }
#endif

    func testWhenAboutURLWithRealHashAndSameDocumentThenIsSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "about:blank")!,
            newURL: URL(string: "about:blank#section")!,
            navigationType: .other
        )
        XCTAssertTrue(action.isSameDocumentNavigation)
    }

    // MARK: - Crash regression (data: URLs)

    // A data: URL has no fragment → not same-document, and must not trigger
    // an O(n) string scan of a multi-megabyte absoluteString (SIGKILL regression).
    func testWhenDataURLWithNoFragmentThenIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "http://example.com/page")!,
            newURL: URL(string: "data:text/html,<h1>hello</h1>")!,
            navigationType: .linkActivated
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

    func testWhenCurrentURLIsDataURLThenBackForwardIsNotSameDocument() {
        let action = makeAction(
            currentURL: URL(string: "data:text/html;base64,PHNjcmlwdD4=")!,
            newURL: URL(string: "http://example.com/page")!,
            navigationType: .backForward
        )
        XCTAssertFalse(action.isSameDocumentNavigation)
    }

}

// MARK: - Foundation URL.fragment performance on large data: URLs

/// Verifies that Foundation's URL.fragment is O(1) (or at worst very fast) even for
/// multi-megabyte data: URI strings, i.e. it does NOT decode grapheme clusters across
/// the full absoluteString the way String.firstIndex(of:) does.
///
/// This is a companion to the SIGKILL regression: if URL.fragment turns out to be slow
/// for data: URIs, URL.hasFragment cannot safely be used as an O(1) fragment-presence check.
final class URLFragmentDataURIPerformanceTests: XCTestCase {

    /// A data: URI whose payload is ~1 MB of repeated ASCII — mirrors the content-scope
    /// JSON blobs that triggered the original main-thread stall / SIGKILL.
    private static let largeMegabyteDataURL: URL = {
        let payload = String(repeating: "A", count: 1_024 * 1_024)
        return URL(string: "data:text/html," + payload)!
    }()

    func testURLFragmentIsFastForLargeDataURLWithoutFragment() {
        let url = Self.largeMegabyteDataURL
        let start = Date()
        let fragment = url.fragment
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNil(fragment, "data: URI without '#' must have no fragment")
        XCTAssertLessThan(elapsed, 0.01, "URL.fragment took \(elapsed)s on a 1 MB data: URI — must be near-instant")
    }

    func testURLFragmentIsFastForLargeDataURLWithFragment() {
        let payload = String(repeating: "A", count: 1_024 * 1_024)
        // The '#' is at the very end — worst case for a lazy left-to-right scanner.
        guard let url = URL(string: "data:text/html," + payload + "#anchor") else {
            XCTFail("Failed to construct large data: URL with fragment")
            return
        }
        let start = Date()
        let fragment = url.fragment
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(fragment, "anchor")
        XCTAssertLessThan(elapsed, 0.01, "URL.fragment took \(elapsed)s on a 1 MB data: URI with '#' at end — if this fails Foundation is scanning lazily and URL.hasFragment is unsafe as an O(1) check")
    }

}

#endif

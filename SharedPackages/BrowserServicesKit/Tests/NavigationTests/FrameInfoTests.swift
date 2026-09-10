//
//  FrameInfoTests.swift
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

import Common
import WebKit
import XCTest
@testable import Navigation

@available(iOS 15.0, *)
final class FrameInfoTests: XCTestCase {

    @MainActor
    func testWhenUrlIsEmptyThenFrameInfoUrlIsAboutBlank() {
        let webView = WKWebView(frame: .zero)
        let frame = FrameInfo(webView: webView,
                              handle: webView.mainFrameHandle,
                              isMainFrame: true,
                              url: .empty,
                              securityOrigin: .empty)

        XCTAssertEqual(frame.url, .blankPage)
    }

    /// `WKFrameInfo.request` may be `null` for a newly created frame, see `WKFrameInfo.safeRequest`.
    @MainActor
    func testWhenFrameHasNoRequestThenFrameInfoUrlIsAboutBlank() {
        let webView = WKWebView(frame: .zero)
        let frame = FrameInfo(frame: .mock(for: webView))

        XCTAssertEqual(frame.url, .blankPage)
    }

    @MainActor
    func testWhenUrlIsNotEmptyThenFrameInfoUrlIsPreserved() {
        let webView = WKWebView(frame: .zero)
        let url = URL(string: "https://duckduckgo.com/")!
        let frame = FrameInfo(webView: webView,
                              handle: webView.mainFrameHandle,
                              isMainFrame: true,
                              url: url,
                              securityOrigin: url.securityOrigin)

        XCTAssertEqual(frame.url, url)
    }

    @MainActor
    func testWhenWebViewHasNoUrlThenMainFrameUrlIsAboutBlank() {
        let webView = WKWebView(frame: .zero)
        XCTAssertNil(webView.url)

        XCTAssertEqual(FrameInfo.mainFrame(for: webView).url, .blankPage)
    }
}

#endif

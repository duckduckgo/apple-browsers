//
//  WebViewInputAccessoryTests.swift
//  DuckDuckGo
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

import XCTest
import WebKit

@testable import DuckDuckGo

final class WebViewInputAccessoryTests: XCTestCase {

    func testDefaultInputAccessoryViewHiddenIsFalse() {
        let webView = WebView(frame: .zero, configuration: WKWebViewConfiguration())
        XCTAssertFalse(webView.inputAccessoryViewHidden)
    }

    func testWhenInputAccessoryViewHiddenThenReturnsNil() {
        let webView = WebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setInputAccessoryViewHidden(true)
        XCTAssertNil(webView.inputAccessoryView)
    }

    func testWhenCustomAccessorySetAndHiddenThenReturnsNil() {
        let webView = WebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setAccessoryContentView(UIView())
        webView.setInputAccessoryViewHidden(true)
        XCTAssertNil(webView.inputAccessoryView)
    }

    func testWhenCustomAccessorySetAndNotHiddenThenReturnsCustomView() {
        let webView = WebView(frame: .zero, configuration: WKWebViewConfiguration())
        let customView = UIView()
        webView.setAccessoryContentView(customView)
        XCTAssertEqual(webView.inputAccessoryView, customView)
    }

    func testWhenHiddenToggledBackToFalseThenCustomAccessoryRestores() {
        let webView = WebView(frame: .zero, configuration: WKWebViewConfiguration())
        let customView = UIView()
        webView.setAccessoryContentView(customView)

        webView.setInputAccessoryViewHidden(true)
        XCTAssertNil(webView.inputAccessoryView)

        webView.setInputAccessoryViewHidden(false)
        XCTAssertEqual(webView.inputAccessoryView, customView)
    }

    func testSetInputAccessoryViewHiddenIsIdempotent() {
        let webView = WebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setInputAccessoryViewHidden(true)
        webView.setInputAccessoryViewHidden(true)
        XCTAssertTrue(webView.inputAccessoryViewHidden)
        XCTAssertNil(webView.inputAccessoryView)
    }
}

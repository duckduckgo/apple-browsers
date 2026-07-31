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

final class WebViewAskAIChatMenuTests: XCTestCase {

    private func makeWebView() -> WebView {
        WebView(frame: .zero, configuration: WKWebViewConfiguration())
    }

    func testWhenAvailabilityUnsetThenMenuIsNotInserted() {
        let webView = makeWebView()
        XCTAssertFalse(webView.shouldInsertAskAIChatMenu(forSystem: .context))
    }

    func testWhenAvailabilityReturnsFalseThenMenuIsNotInserted() {
        let webView = makeWebView()
        webView.isAskAIChatMenuAvailable = { false }
        XCTAssertFalse(webView.shouldInsertAskAIChatMenu(forSystem: .context))
    }

    func testWhenAvailabilityReturnsTrueThenMenuIsInserted() {
        let webView = makeWebView()
        webView.isAskAIChatMenuAvailable = { true }
        XCTAssertTrue(webView.shouldInsertAskAIChatMenu(forSystem: .context))
    }

    func testWhenSystemIsMainThenMenuIsNotInsertedEvenWhenAvailable() {
        let webView = makeWebView()
        webView.isAskAIChatMenuAvailable = { true }
        XCTAssertFalse(webView.shouldInsertAskAIChatMenu(forSystem: .main))
    }

    func testAvailabilityIsReevaluatedOnEveryMenuBuild() {
        let webView = makeWebView()
        var available = false
        webView.isAskAIChatMenuAvailable = { available }

        XCTAssertFalse(webView.shouldInsertAskAIChatMenu(forSystem: .context))
        available = true
        XCTAssertTrue(webView.shouldInsertAskAIChatMenu(forSystem: .context))
        available = false
        XCTAssertFalse(webView.shouldInsertAskAIChatMenu(forSystem: .context))
    }

    func testSelectionIsTrimmedOfSurroundingWhitespaceAndNewlines() {
        XCTAssertEqual(WebView.normalizedAskAIChatSelection("  \n hello world \n\t "), "hello world")
    }

    func testSelectionKeepsInteriorWhitespace() {
        XCTAssertEqual(WebView.normalizedAskAIChatSelection("first line\nsecond line"), "first line\nsecond line")
    }

    func testEmptySelectionIsRejected() {
        XCTAssertNil(WebView.normalizedAskAIChatSelection(""))
    }

    func testWhitespaceOnlySelectionIsRejected() {
        XCTAssertNil(WebView.normalizedAskAIChatSelection("   \n\t  "))
    }

    func testLongSelectionIsCappedAtMaximumLength() {
        let selection = String(repeating: "a", count: WebView.maxAskAIChatSelectionLength + 500)
        let normalized = WebView.normalizedAskAIChatSelection(selection)
        XCTAssertEqual(normalized?.count, WebView.maxAskAIChatSelectionLength)
    }

    func testSelectionAtMaximumLengthIsUnchanged() {
        let selection = String(repeating: "a", count: WebView.maxAskAIChatSelectionLength)
        XCTAssertEqual(WebView.normalizedAskAIChatSelection(selection), selection)
    }

    func testSelectionIsTrimmedBeforeBeingCapped() {
        let padding = String(repeating: " ", count: 100)
        let selection = padding + String(repeating: "a", count: WebView.maxAskAIChatSelectionLength) + padding
        let normalized = WebView.normalizedAskAIChatSelection(selection)
        XCTAssertEqual(normalized?.count, WebView.maxAskAIChatSelectionLength)
        XCTAssertEqual(normalized?.first, "a")
    }
}

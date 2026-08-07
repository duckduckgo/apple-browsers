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

final class WebViewSelectionMenuTests: XCTestCase {

    private func makeWebView() -> WebView {
        WebView(frame: .zero, configuration: WKWebViewConfiguration())
    }

    private func makeWebView(askAvailable: Bool, searchAvailable: Bool) -> WebView {
        let webView = makeWebView()
        webView.isAskAIChatItemAvailable = { askAvailable }
        webView.isSearchWithDuckDuckGoItemAvailable = { searchAvailable }
        return webView
    }

    func testWhenAvailabilityUnsetThenNoItemsAreOffered() {
        XCTAssertEqual(makeWebView().selectionMenuItems(forSystem: .context), [])
    }

    func testWhenBothAreAvailableThenAskIsOfferedFirst() {
        let webView = makeWebView(askAvailable: true, searchAvailable: true)
        XCTAssertEqual(webView.selectionMenuItems(forSystem: .context), [.askAIChat, .searchWithDuckDuckGo])
    }

    func testWhenNeitherIsAvailableThenNoItemsAreOffered() {
        let webView = makeWebView(askAvailable: false, searchAvailable: false)
        XCTAssertEqual(webView.selectionMenuItems(forSystem: .context), [])
    }

    /// Duck.ai switched off must leave Search in place.
    func testWhenOnlySearchIsAvailableThenOnlySearchIsOffered() {
        let webView = makeWebView(askAvailable: false, searchAvailable: true)
        XCTAssertEqual(webView.selectionMenuItems(forSystem: .context), [.searchWithDuckDuckGo])
    }

    func testWhenOnlyAskIsAvailableThenOnlyAskIsOffered() {
        let webView = makeWebView(askAvailable: true, searchAvailable: false)
        XCTAssertEqual(webView.selectionMenuItems(forSystem: .context), [.askAIChat])
    }

    func testWhenSystemIsMainThenNoItemsAreOfferedEvenWhenAvailable() {
        let webView = makeWebView(askAvailable: true, searchAvailable: true)
        XCTAssertEqual(webView.selectionMenuItems(forSystem: .main), [])
    }

    func testAvailabilityIsReevaluatedOnEveryMenuBuild() {
        let webView = makeWebView()
        var available = false
        webView.isAskAIChatItemAvailable = { available }

        XCTAssertEqual(webView.selectionMenuItems(forSystem: .context), [])
        available = true
        XCTAssertEqual(webView.selectionMenuItems(forSystem: .context), [.askAIChat])
        available = false
        XCTAssertEqual(webView.selectionMenuItems(forSystem: .context), [])
    }

    func testSelectionIsTrimmedOfSurroundingWhitespaceAndNewlines() {
        XCTAssertEqual(WebView.normalizedSelection("  \n hello world \n\t "), "hello world")
    }

    func testSelectionKeepsInteriorWhitespace() {
        XCTAssertEqual(WebView.normalizedSelection("first line\nsecond line"), "first line\nsecond line")
    }

    func testEmptySelectionIsRejected() {
        XCTAssertNil(WebView.normalizedSelection(""))
    }

    func testWhitespaceOnlySelectionIsRejected() {
        XCTAssertNil(WebView.normalizedSelection("   \n\t  "))
    }

    /// Length is deliberately not capped here — truncation is the payload builder's job, and it needs
    /// the selection's real length.
    func testLongSelectionIsPassedThroughAtFullLength() {
        let selection = String(repeating: "a", count: 250_000)
        XCTAssertEqual(WebView.normalizedSelection(selection)?.count, 250_000)
    }
}

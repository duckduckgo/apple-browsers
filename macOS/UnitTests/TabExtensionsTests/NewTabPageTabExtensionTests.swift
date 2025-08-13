//
//  NewTabPageTabExtensionTests.swift
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
import Combine
import WebKit
@testable import DuckDuckGo_Privacy_Browser
@testable import NewTabPage

private struct MockScriptProvider: NewTabPageUserScriptProvider {
    let script: NewTabPageUserScript
    var newTabPageUserScript: NewTabPageUserScript? { script }
}

@MainActor
class NewTabPageTabExtensionTests: XCTestCase {
    private var scriptsSubject: CurrentValueSubject<MockScriptProvider, Never>!
    var webViewSubject: PassthroughSubject<WKWebView, Never>!
    var extensionUnderTest: NewTabPageTabExtension!

    override func setUp() {
        super.setUp()
        scriptsSubject = .init(MockScriptProvider(script: NewTabPageUserScript()))
        webViewSubject = .init()
        extensionUnderTest = NewTabPageTabExtension(
            scriptsPublisher: scriptsSubject.eraseToAnyPublisher(),
            webViewPublisher: webViewSubject.eraseToAnyPublisher(),
            pixelSender: NSApp.delegateTyped.newTabPageCoordinator.newTabPageShownPixelSender
        )
    }

    override func tearDown() {
        extensionUnderTest = nil
        scriptsSubject = nil
        webViewSubject = nil
        super.tearDown()
    }

    func test_webViewForwardedAfterBothPublished() async {
        let script = NewTabPageUserScript()
        scriptsSubject.send(MockScriptProvider(script: script))
        await Task.yield()
        let sentWebView = WKWebView()
        webViewSubject.send(sentWebView)
        await Task.yield()
        XCTAssertTrue(script.webView === sentWebView)
    }

    func test_webViewAppliedWhenScriptArrivesAfterWebView() async {
        let sentWebView = WKWebView()
        webViewSubject.send(sentWebView)
        await Task.yield()
        let script = NewTabPageUserScript()
        scriptsSubject.send(MockScriptProvider(script: script))
        await Task.yield()
        XCTAssertTrue(script.webView === sentWebView)
    }

    func test_scriptReplacedRetainsWebViewBinding() async {
        let sentWebView = WKWebView()
        webViewSubject.send(sentWebView)
        await Task.yield()
        let first = NewTabPageUserScript()
        scriptsSubject.send(MockScriptProvider(script: first))
        await Task.yield()
        XCTAssertTrue(first.webView === sentWebView)
        let second = NewTabPageUserScript()
        scriptsSubject.send(MockScriptProvider(script: second))
        await Task.yield()
        XCTAssertTrue(second.webView === sentWebView)
    }
}

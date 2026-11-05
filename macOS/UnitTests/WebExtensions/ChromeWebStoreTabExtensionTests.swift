//
//  ChromeWebStoreTabExtensionTests.swift
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

import Combine
import UserScript
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class ChromeWebStoreTabExtensionTests: XCTestCase {

    private struct ScriptsProvider: ChromeWebStoreUserScriptProvider {
        let chromeWebStoreUserScript: Subfeature?
    }

    func testRebuiltUserScriptsGetTheTabWebView() async {
        let scripts = PassthroughSubject<ScriptsProvider, Never>()
        let webViews = PassthroughSubject<WKWebView, Never>()
        let tabExtension = ChromeWebStoreTabExtension(scriptsPublisher: scripts, webViewPublisher: webViews)
        let webView = WKWebView()
        let first = ChromeWebStoreUserScript(serviceProvider: { nil })
        let rebuilt = ChromeWebStoreUserScript(serviceProvider: { nil })

        scripts.send(ScriptsProvider(chromeWebStoreUserScript: first))
        webViews.send(webView)
        await Task.yield()
        XCTAssertIdentical(first.webView, webView)

        // Rebuilt user scripts, as after an extension takes autofill over, must still reach the page.
        scripts.send(ScriptsProvider(chromeWebStoreUserScript: rebuilt))
        await Task.yield()
        XCTAssertIdentical(rebuilt.webView, webView)

        withExtendedLifetime(tabExtension) {}
    }
}

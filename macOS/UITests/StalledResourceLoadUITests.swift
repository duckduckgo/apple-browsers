//
//  StalledResourceLoadUITests.swift
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

import XCTest

class StalledResourceLoadUITests: UITestCase {

    private var webView: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        webView = app.webViews.firstMatch
    }

    override func tearDown() {
        webView = nil
        app = nil
    }

    /// Verifies that a page with a stalled deferred script still renders and dismisses the NTP.
    ///
    /// This reproduces the issue where a `<script defer>` pointing to a non-routable IP
    /// (simulating a DNS sinkhole) causes WebKit to never fire `didFinishNavigation`,
    /// keeping the NTP visible indefinitely.
    func testPageRendersAndNTPDismissedWithStalledDeferredScript() {
        // Serve a page with a deferred script pointing to a non-routable IP that will hang
        let html = """
        <html>
        <head><title>Stalled Load Test</title></head>
        <body><p>Page loaded despite stalled script</p></body>
        <script defer src="https://10.255.255.1/hang.js"></script>
        </html>
        """
        let url = URL.testsServer.appendingTestParameters(data: html.data(using: .utf8)!)

        // Navigate from NTP
        app.activateAddressBar()
        app.pasteURL(url, pressingEnter: true)

        // Wait for page content to be visible (proves NTP was dismissed and page rendered)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "Page loaded despite stalled script").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Page content should be visible despite the stalled deferred script"
        )

        // Verify NTP is dismissed (address bar shows test URL, not newtab)
        let addressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            addressBarValue?.contains("localhost") == true,
            "Address bar should show the test URL, not the NTP. Got: \(addressBarValue ?? "nil")"
        )
    }
}

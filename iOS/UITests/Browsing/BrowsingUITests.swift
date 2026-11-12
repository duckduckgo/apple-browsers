//
//  BrowsingUITests.swift
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

import Swifter
import XCTest
import UITestingSupport

final class BrowsingUITests: UITestCase {

    private let server = HttpServer()
    private let page = LocalPage()

    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_DISABLE_ANIMATIONS": "1"]
    }

    private var pageURL: String {
        get throws { "http://127.0.0.1:\(try server.port())/browsing-test" }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        page.setHeading(LocalPage.initialHeading)
        server["/browsing-test"] = { [page] _ in page.response() }
        server.listenAddressIPv4 = "127.0.0.1"
        try server.start(0, forceIPv4: true, priority: .userInitiated)
    }

    override func tearDownWithError() throws {
        defer { server.stop() }
        try super.tearDownWithError()
    }

    func testWhenURLIsEnteredThenPageLoads() throws {
        app.openURL(try pageURL, expecting: LocalPage.initialHeading)
    }

    func testWhenPageLoadsThenRefreshBecomesAvailable() throws {
        let refreshButton = app.buttons["Browser.OmniBar.Button.Refresh"]
        let url = try pageURL

        XCTContext.runActivity(named: "Verify refresh is unavailable on the new-tab page") { _ in
            XCTAssertTrue(
                app.searchEntry.waitForExistence(timeout: UITestTimeouts.navigation),
                "Browser UI did not appear after launch.")
            XCTAssertFalse(refreshButton.isHittable, "Refresh should not be available on the new tab page.")
        }

        XCTContext.runActivity(named: "Load and refresh the test page") { _ in
            app.openURL(url, expecting: LocalPage.initialHeading)
            page.setHeading(LocalPage.refreshedHeading)
            refreshButton.tapWhenHittable(in: app)
            app.assertPageContains(LocalPage.refreshedHeading)
        }
    }

    private final class LocalPage {
        static let initialHeading = "Browsing test page"
        static let refreshedHeading = "Refreshed browsing test page"

        private let lock = NSLock()
        private var heading = initialHeading

        func setHeading(_ heading: String) {
            lock.withLock { self.heading = heading }
        }

        func response() -> HttpResponse {
            let title = lock.withLock { heading }
            let body = Array("<!doctype html><title>Browsing test</title><h1>\(title)</h1>".utf8)
            let headers = [
                "Cache-Control": "no-store",
                "Content-Type": "text/html; charset=utf-8",
                "Content-Length": String(body.count),
            ]
            return .raw(200, "OK", headers) { writer in
                try writer.write(body)
            }
        }
    }
}

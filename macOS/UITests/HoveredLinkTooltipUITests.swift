//
//  HoveredLinkTooltipUITests.swift
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

final class HoveredLinkTooltipUITests: UITestCase {

    private let pageTitle = "Hovered Link Page"
    private let linkTitle = "Hovered link"

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try super.tearDownWithError()
    }

    func testWhenHoveringLinkThenTooltipAppears() {
        let link = openPageWithLink()
        link.hover()
        XCTAssertTrue(tooltipLabel.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testWhenPointerMovesFromInspectorToLinkThenTooltipAppears() {
        let link = openPageWithLink()
        showInspector()
        deactivateApp()

        // Activate the window by clicking into the inspector, then move to the link across the page.
        inspector.click()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITests.Timeouts.elementExistence))
        let page = app.windows.firstMatch.webViews[pageTitle]
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.1)).hover()
        link.hover()

        XCTAssertTrue(tooltipLabel.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "The tooltip should appear after the pointer moves from the inspector to a link")
    }

    // MARK: - Helpers

    private var tooltipLabel: XCUIElement {
        app.staticTexts["HoveredLinkTooltip.label"]
    }

    private func openPageWithLink() -> XCUIElement {
        let body = "<a href=\"https://example.com/hovered\" style=\"position:absolute;left:20px;top:20px;font-size:24px\">\(linkTitle)</a>"
        let url = UITests.simpleServedPage(titled: pageTitle, body: body)
        let addressBar = app.addressBar
        XCTAssertTrue(addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        addressBar.pasteURL(url, pressingEnter: true)

        let webView = app.windows.firstMatch.webViews[pageTitle]
        XCTAssertTrue(webView.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        let link = webView.links[linkTitle]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        return link
    }

    private var inspector: XCUIElement {
        app.windows.firstMatch.webViews.matching(NSPredicate(format: "title != %@", pageTitle)).firstMatch
    }

    private func showInspector() {
        app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertTrue(inspector.waitForExistence(timeout: UITests.Timeouts.elementExistence), "The web inspector should be shown")
    }

    private func deactivateApp() {
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITests.Timeouts.elementExistence))
    }
}

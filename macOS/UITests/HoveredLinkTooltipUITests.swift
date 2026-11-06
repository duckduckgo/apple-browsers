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
    private let destinationTitle = "Destination Page"

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
        assertTooltipAppears()
    }

    func testWhenAppIsReactivatedWithPointerStillOnLinkThenTooltipReappears() {
        let link = openPageWithLink()
        link.hover()
        assertTooltipAppears()

        deactivateApp()
        assertTooltipDisappears("The tooltip must hide when the window is deactivated")

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITests.Timeouts.elementExistence))

        assertTooltipAppears("The tooltip must come back for the link under the unmoved pointer")
    }

    func testWhenSwitchingTabsWithCtrlTabThenTooltipIsDismissedAndComesBack() {
        let link = openPageWithLink()
        openSecondTab()
        app.typeKey("\t", modifierFlags: .control) // back to the first tab (wraps around)
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        link.hover()
        assertTooltipAppears()

        app.typeKey("\t", modifierFlags: .control)
        assertTooltipDisappears("The tooltip must not stay when another tab is selected")

        app.typeKey("\t", modifierFlags: .control)
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        assertTooltipAppears("The tooltip must come back for the link under the unmoved pointer in the re-selected tab")
    }

    func testWhenClickingLinkWithPointerStayingPutThenTooltipDisappearsOnTheNewPage() {
        let link = openPageWithLink()
        link.hover()
        assertTooltipAppears()

        link.click()

        XCTAssertTrue(app.windows.firstMatch.webViews[destinationTitle].waitForExistence(timeout: UITests.Timeouts.localTestServer))
        assertTooltipDisappears("The destination page has no link under the pointer")
    }

    func testWhenSwitchingWindowsWithCmdBacktickThenTooltipIsDismissedAndComesBack() {
        let link = openPageWithLink()
        link.hover()
        assertTooltipAppears()

        app.openNewWindow()
        XCTAssertEqual(app.windows.count, 2)
        assertTooltipDisappears("The tooltip must not stay when another window becomes key")

        app.typeKey("`", modifierFlags: .command)
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        assertTooltipAppears("The tooltip must come back for the link under the unmoved pointer after the first window becomes key again")
    }

    // MARK: - Helpers

    private var tooltipLabel: XCUIElement {
        app.staticTexts["HoveredLinkTooltip.label"]
    }

    private func assertTooltipAppears(_ message: String = "The tooltip should appear",
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tooltipLabel.waitForExistence(timeout: UITests.Timeouts.elementExistence), message, file: file, line: line)
    }

    private func assertTooltipDisappears(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tooltipLabel.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), message, file: file, line: line)
    }

    private func openPageWithLink() -> XCUIElement {
        let destination = UITests.simpleServedPage(titled: destinationTitle)
        let linkStyle = "position:absolute;left:20px;top:20px;font-size:24px"
        let body = "<a href=\"\(destination.absoluteString)\" style=\"\(linkStyle)\">\(linkTitle)</a>"
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

    private func openSecondTab() {
        app.openNewTab()
        let addressBar = app.addressBar
        XCTAssertTrue(addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        addressBar.pasteURL(UITests.simpleServedPage(titled: "Second Tab Page"), pressingEnter: true)
        XCTAssertTrue(app.windows.firstMatch.webViews["Second Tab Page"].waitForExistence(timeout: UITests.Timeouts.localTestServer))
    }

    private func deactivateApp() {
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITests.Timeouts.elementExistence))
    }
}

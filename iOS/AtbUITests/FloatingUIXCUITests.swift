//
//  FloatingUIXCUITests.swift
//  AtbUITests
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

private extension XCUIElement {

    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForNotHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false OR isHittable == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

enum FloatingUIBarPosition: String {
    case top
    case bottom

    var opposite: FloatingUIBarPosition {
        switch self {
        case .top:
            return .bottom
        case .bottom:
            return .top
        }
    }

    var moveAction: String {
        switch self {
        case .top:
            return "Move Address Bar to Top"
        case .bottom:
            return "Move Address Bar to Bottom"
        }
    }

    var oppositeMoveAction: String {
        opposite.moveAction
    }
}

class FloatingUIXCUITestCase: XCTestCase {

    private enum AccessibilityID {
        static let searchEntry = "searchEntry"
        static let utiDismiss = "UnifiedToggleInput.Button.Dismiss"
        static let tabSwitcher = "Browser.Toolbar.Button.TabSwitcher"
        static let tabSwitcherDone = "TabSwitcher.Button.Done"
        static let toolbarBack = "Browser.Toolbar.Button.Back"
        static let toolbarForward = "Browser.Toolbar.Button.Forward"
        static let toolbarFire = "Browser.Toolbar.Button.Fire"
        static let toolbarMenu = "Browser.Toolbar.Button.Menu"
        static let domainCapsule = "Browser.FloatingDomainCapsule"
    }

    private enum Page {
        static let oneHeading = "Floating UI Test Page One"
        static let twoHeading = "Floating UI Test Page Two"
        static let longHeading = "Floating UI Long Page"
        static let edgeHeading = "Floating UI Edge Controls"
        static let slowHeading = "Floating UI Slow Page"
        static let swipeOneHeading = "Floating UI Swipe Page One"
        static let swipeTwoHeading = "Floating UI Swipe Page Two"
    }

    let app = XCUIApplication()
    let server = HttpServer()
    var barPosition: FloatingUIBarPosition { fatalError("Override barPosition") }

    private let timeout: TimeInterval = 20
    private var serverBaseURL = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try startServer()
        launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        server.stop()
        XCUIDevice.shared.orientation = .portrait
        try super.tearDownWithError()
    }

    func verifyUnifiedToggleInputTransitions() {
        let collapsedFrame = searchField.frame
        searchField.tap()

        XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForHittable(timeout: timeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        XCTAssertNotEqual(searchField.frame, collapsedFrame)

        element(withIdentifier: AccessibilityID.utiDismiss).tap()

        XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForNotHittable(timeout: timeout))
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        assertConfiguredBarPosition()
    }

    func verifyTabSwitcherTransitions() {
        tabSwitcherButton.tap()

        let doneButton = element(withIdentifier: AccessibilityID.tabSwitcherDone)
        XCTAssertTrue(doneButton.waitForHittable(timeout: timeout))

        doneButton.tap()

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        assertConfiguredBarPosition()
    }

    func verifyBrowserChromeLongPressMenus() {
        searchField.press(forDuration: 0.8)

        XCTAssertTrue(app.buttons[barPosition.oppositeMoveAction].waitForExistence(timeout: timeout))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))

        tabSwitcherButton.press(forDuration: 0.8)

        XCTAssertTrue(app.buttons["New Tab"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["New Fire Tab"].exists)
    }

    func verifyBrowserChromeInLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.width > self.app.frame.height })

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        XCTAssertGreaterThan(searchField.frame.width, 100)
        XCTAssertTrue(searchField.frame.intersects(app.frame))

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.height > self.app.frame.width })
        assertConfiguredBarPosition()
    }

    func verifyDomainCapsuleAppears() {
        openPage(path: "/long-page", heading: Page.longHeading)

        collapseChrome()

        let domainCapsule = self.domainCapsule
        XCTAssertEqual(domainCapsule.label, "127.0.0.1")

        webView.swipeDown(velocity: .fast)
        webView.swipeDown(velocity: .fast)
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        XCTAssertTrue(domainCapsule.waitForNonExistence(timeout: timeout))
        assertConfiguredBarPosition()

        collapseChrome()
        domainCapsule.tap()
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        XCTAssertTrue(domainCapsule.waitForNonExistence(timeout: timeout))
        assertConfiguredBarPosition()
    }

    func verifyRuntimeAddressBarRelocation() {
        openPage(path: "/long-page", heading: Page.longHeading)

        let destination = barPosition.opposite
        moveAddressBar(to: destination)

        collapseChrome()
        domainCapsule.tap()
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))

        searchField.tap()
        let dismissButton = element(withIdentifier: AccessibilityID.utiDismiss)
        XCTAssertTrue(dismissButton.waitForHittable(timeout: timeout))
        dismissButton.tap()
        XCTAssertTrue(dismissButton.waitForNotHittable(timeout: timeout))
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))

        XCTAssertTrue(tabSwitcherButton.waitForHittable(timeout: timeout))
        tabSwitcherButton.tap()
        let doneButton = element(withIdentifier: AccessibilityID.tabSwitcherDone)
        XCTAssertTrue(doneButton.waitForHittable(timeout: timeout))
        doneButton.tap()
        XCTAssertTrue(doneButton.waitForNotHittable(timeout: timeout))
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))

        moveAddressBar(to: barPosition)
        assertChromeButtonsAreUsable()
        // Relocating after a focus/dismiss cycle: the focus transition hides the omnibar's
        // collection view, and only re-hosting restores it.
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))

        let menuButton = element(withIdentifier: AccessibilityID.toolbarMenu)
        XCTAssertTrue(menuButton.waitForHittable(timeout: timeout))
        menuButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Settings"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.descendants(matching: .any)["New Tab"].exists)
    }

    func verifyConsecutiveAddressBarRelocation() {
        openPage(path: "/long-page", heading: Page.longHeading)

        moveAddressBar(to: barPosition.opposite)
        moveAddressBar(to: barPosition)

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        assertConfiguredBarPosition()
    }

    func verifyFloatingContentInsets() {
        openPage(path: "/edge-controls", heading: Page.edgeHeading)

        let topControl = app.buttons["Top edge control"]
        let bottomControl = app.buttons["Bottom edge control"]
        XCTAssertTrue(topControl.waitForHittable(timeout: timeout))
        XCTAssertTrue(bottomControl.waitForHittable(timeout: timeout))

        topControl.tap()
        XCTAssertTrue(app.staticTexts["Top edge activated"].waitForExistence(timeout: timeout))
        bottomControl.tap()
        XCTAssertTrue(app.staticTexts["Bottom edge activated"].waitForExistence(timeout: timeout))

        collapseChrome()
        XCTAssertTrue(topControl.waitForHittable(timeout: timeout))
        XCTAssertTrue(bottomControl.waitForHittable(timeout: timeout))

        topControl.tap()
        XCTAssertTrue(app.staticTexts["Top edge activated again"].waitForExistence(timeout: timeout))
        bottomControl.tap()
        XCTAssertTrue(app.staticTexts["Bottom edge activated again"].waitForExistence(timeout: timeout))
    }

    func verifyUnifiedToggleInputKeyboardGeometry() {
        searchField.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForHittable(timeout: timeout))
        XCTAssertLessThanOrEqual(searchField.frame.maxY, keyboard.frame.minY + 1)

        element(withIdentifier: AccessibilityID.utiDismiss).tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout))

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        assertConfiguredBarPosition()
        assertChromeButtonsAreUsable()
    }

    func verifyCollapsedChromeTransitions() {
        openPage(path: "/long-page", heading: Page.longHeading)
        collapseChrome()

        domainCapsule.tap()
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        searchField.tap()
        let dismissButton = element(withIdentifier: AccessibilityID.utiDismiss)
        XCTAssertTrue(dismissButton.waitForHittable(timeout: timeout))
        dismissButton.tap()
        XCTAssertTrue(dismissButton.waitForNotHittable(timeout: timeout))
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))

        collapseChrome()
        domainCapsule.tap()
        XCTAssertTrue(tabSwitcherButton.waitForHittable(timeout: timeout))
        tabSwitcherButton.tap()
        let doneButton = element(withIdentifier: AccessibilityID.tabSwitcherDone)
        XCTAssertTrue(doneButton.waitForHittable(timeout: timeout))
        doneButton.tap()

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.searchEntry).count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.tabSwitcher).count, 1)
        assertConfiguredBarPosition()
    }

    func verifyUnifiedToggleInputRotation() {
        searchField.tap()
        let dismissButton = element(withIdentifier: AccessibilityID.utiDismiss)
        XCTAssertTrue(dismissButton.waitForHittable(timeout: timeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.width > self.app.frame.height })
        XCTAssertTrue(dismissButton.waitForHittable(timeout: timeout))
        XCTAssertTrue(searchField.frame.intersects(app.frame))

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.height > self.app.frame.width })
        XCTAssertTrue(dismissButton.waitForHittable(timeout: timeout))
        dismissButton.tap()

        XCTAssertTrue(dismissButton.waitForNotHittable(timeout: timeout))
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        assertConfiguredBarPosition()
    }

    func verifyTabSwitcherRotation() {
        tabSwitcherButton.tap()
        let doneButton = element(withIdentifier: AccessibilityID.tabSwitcherDone)
        XCTAssertTrue(doneButton.waitForHittable(timeout: timeout))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.width > self.app.frame.height })
        XCTAssertTrue(doneButton.waitForHittable(timeout: timeout))

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.height > self.app.frame.width })
        XCTAssertTrue(doneButton.waitForHittable(timeout: timeout))
        doneButton.tap()

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        assertConfiguredBarPosition()
    }

    func verifyChromeDuringSlowLoading() {
        openPage(path: "/long-page", heading: Page.longHeading)
        collapseChrome()

        let slowLink = app.links["Load slow page"]
        XCTAssertTrue(slowLink.waitForHittable(timeout: timeout))
        slowLink.tap()

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        XCTAssertTrue(domainCapsule.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts[Page.slowHeading].waitForExistence(timeout: timeout))
        assertConfiguredBarPosition()
        assertChromeButtonsAreUsable()
    }

    func verifyChromeOnErrorPage() {
        openPage(path: "/long-page", heading: Page.longHeading)
        collapseChrome()

        let errorLink = app.links["Load error page"]
        XCTAssertTrue(errorLink.waitForHittable(timeout: timeout))
        errorLink.tap()

        XCTAssertTrue(app.staticTexts["DuckDuckGo can’t load this page."].waitForExistence(timeout: timeout))
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        XCTAssertTrue(domainCapsule.waitForNonExistence(timeout: timeout))
        assertConfiguredBarPosition()
        assertChromeButtonsAreUsable()
    }

    func verifyFloatingSwipeTabs() {
        openPage(path: "/swipe-one", heading: Page.swipeOneHeading)
        tabSwitcherButton.press(forDuration: 0.8)
        let newTabButton = app.buttons["New Tab"]
        XCTAssertTrue(newTabButton.waitForHittable(timeout: timeout))
        newTabButton.tap()
        openPage(path: "/swipe-two", heading: Page.swipeTwoHeading)
        collapseChrome()
        domainCapsule.tap()
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))

        swipeBetweenTabs(toward: .right)
        XCTAssertTrue(app.staticTexts[Page.swipeOneHeading].waitForExistence(timeout: timeout))
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))

        collapseChrome()
        domainCapsule.tap()
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        swipeBetweenTabs(toward: .left)
        XCTAssertTrue(app.staticTexts[Page.swipeTwoHeading].waitForExistence(timeout: timeout))
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        assertConfiguredBarPosition()
    }

    func verifyBrowsingMenuOpens() {
        element(withIdentifier: AccessibilityID.toolbarMenu).tap()

        XCTAssertTrue(app.descendants(matching: .any)["Settings"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.descendants(matching: .any)["New Tab"].exists)
    }

    func verifyDefaultCustomizableFireButton() {
        let fireButton = element(withIdentifier: AccessibilityID.toolbarFire)
        XCTAssertTrue(fireButton.waitForHittable(timeout: timeout))
        fireButton.tap()

        let confirmation = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ OR identifier == %@",
                "alert.forget-data.confirm",
                "Fire.Confirmation.Button.Delete"
            )
        ).firstMatch
        XCTAssertTrue(confirmation.waitForHittable(timeout: timeout))

        let cancelButton = element(withIdentifier: "Fire.Confirmation.Button.Cancel")
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.tap()
        }
    }

    func verifyNewTabPageScenarios() {
        openPage(path: "/page-one", heading: Page.oneHeading)
        tabSwitcherButton.press(forDuration: 0.8)

        let newTabButton = app.buttons["New Tab"]
        XCTAssertTrue(newTabButton.waitForHittable(timeout: timeout))
        newTabButton.tap()

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        XCTAssertFalse(app.staticTexts[Page.oneHeading].exists)
        assertConfiguredBarPosition()
    }

    func verifyBrowsingScenarios() {
        openPage(path: "/page-one", heading: Page.oneHeading)

        let nextPageLink = app.links["Next page"]
        XCTAssertTrue(nextPageLink.waitForHittable(timeout: timeout))
        nextPageLink.tap()
        XCTAssertTrue(app.staticTexts[Page.twoHeading].waitForExistence(timeout: timeout))

        let backButton = element(withIdentifier: AccessibilityID.toolbarBack)
        XCTAssertTrue(backButton.waitForHittable(timeout: timeout))
        backButton.tap()
        XCTAssertTrue(app.staticTexts[Page.oneHeading].waitForExistence(timeout: timeout))

        let forwardButton = element(withIdentifier: AccessibilityID.toolbarForward)
        XCTAssertTrue(forwardButton.waitForHittable(timeout: timeout))
        forwardButton.tap()
        XCTAssertTrue(app.staticTexts[Page.twoHeading].waitForExistence(timeout: timeout))
        assertConfiguredBarPosition()
    }

    private var searchField: XCUIElement {
        let fields = app.descendants(matching: .any).matching(identifier: AccessibilityID.searchEntry)
        return fields.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? fields.firstMatch
    }

    private var tabSwitcherButton: XCUIElement {
        element(withIdentifier: AccessibilityID.tabSwitcher)
    }

    private var domainCapsule: XCUIElement {
        element(withIdentifier: AccessibilityID.domainCapsule)
    }

    private var webView: XCUIElement {
        app.webViews.firstMatch
    }

    private func launchApp() {
        app.launchArguments = [
            "-clearAllDefaults",
            "isRunningUITests",
            "-isOnboardingCompleted", "true",
            "-ff.floatingUIAugust2026", "true",
            "-ff.omniBarLongPressMenu", "true",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_GB",
        ]
        app.launchEnvironment = [
            "UITEST_MODE": "1",
            "BASE_URL": serverBaseURL,
            "PIXEL_BASE_URL": serverBaseURL,
        ]
        app.launch()

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout), "Browser chrome did not become ready.")
        XCTAssertTrue(element(withIdentifier: AccessibilityID.toolbarFire).exists)
        XCTAssertTrue(tabSwitcherButton.exists)
        XCTAssertTrue(element(withIdentifier: AccessibilityID.toolbarMenu).exists)
        if barPosition == .bottom {
            moveAddressBar(to: .bottom)
        }
        assertConfiguredBarPosition()
    }

    private func assertConfiguredBarPosition(file: StaticString = #filePath, line: UInt = #line) {
        assertBarPosition(barPosition, file: file, line: line)
    }

    private func assertBarPosition(_ position: FloatingUIBarPosition, file: StaticString = #filePath, line: UInt = #line) {
        let searchMidY = searchField.frame.midY
        let screenMidY = app.frame.midY
        switch position {
        case .top:
            XCTAssertLessThan(searchMidY, screenMidY, "Address bar is not at the top.", file: file, line: line)
        case .bottom:
            XCTAssertGreaterThan(searchMidY, screenMidY, "Address bar is not at the bottom.", file: file, line: line)
        }
    }

    private func assertChromeButtonsAreUsable(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element(withIdentifier: AccessibilityID.toolbarFire).waitForHittable(timeout: timeout), file: file, line: line)
        XCTAssertTrue(tabSwitcherButton.waitForHittable(timeout: timeout), file: file, line: line)
        XCTAssertTrue(element(withIdentifier: AccessibilityID.toolbarMenu).waitForHittable(timeout: timeout), file: file, line: line)
    }

    private func moveAddressBar(to position: FloatingUIBarPosition, file: StaticString = #filePath, line: UInt = #line) {
        searchField.press(forDuration: 0.8)
        let moveAction = app.buttons[position.moveAction]
        XCTAssertTrue(moveAction.waitForHittable(timeout: timeout), file: file, line: line)
        moveAction.tap()
        XCTAssertTrue(waitUntil(timeout: timeout) {
            switch position {
            case .top:
                return self.searchField.frame.midY < self.app.frame.midY
            case .bottom:
                return self.searchField.frame.midY > self.app.frame.midY
            }
        }, file: file, line: line)
        assertBarPosition(position, file: file, line: line)
    }

    private func collapseChrome(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(webView.waitForExistence(timeout: timeout), file: file, line: line)
        webView.swipeUp(velocity: .fast)
        webView.swipeUp(velocity: .fast)
        XCTAssertTrue(domainCapsule.waitForHittable(timeout: timeout), file: file, line: line)
    }

    private enum SwipeDirection: Equatable {
        case left
        case right
    }

    private func swipeBetweenTabs(toward direction: SwipeDirection) {
        if direction == .left {
            searchField.swipeLeft(velocity: .slow)
            return
        }

        let yOffset = barPosition == .top ? 0.1 : 0.9
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: yOffset))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: yOffset))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func openPage(path: String, heading: String, file: StaticString = #filePath, line: UInt = #line) {
        searchField.tap()
        XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForHittable(timeout: timeout), file: file, line: line)
        let activeSearchField = searchField
        XCTAssertTrue(activeSearchField.waitForHittable(timeout: timeout), file: file, line: line)
        activeSearchField.typeText("\(serverBaseURL)\(path)\r")
        XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: timeout), "Did not load \(path).", file: file, line: line)
    }

    private func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    private func startServer() throws {
        server["/page-one"] = { _ in
            .ok(.html(Self.pageOneHTML))
        }
        server["/page-two"] = { _ in
            .ok(.html(Self.pageTwoHTML))
        }
        server["/long-page"] = { _ in
            .ok(.html(Self.longPageHTML))
        }
        server["/edge-controls"] = { _ in
            .ok(.html(Self.edgeControlsHTML))
        }
        server["/slow-page"] = { _ in
            Thread.sleep(forTimeInterval: 2)
            return .ok(.html(Self.slowPageHTML))
        }
        server["/swipe-one"] = { _ in
            .ok(.html(Self.swipeOneHTML))
        }
        server["/swipe-two"] = { _ in
            .ok(.html(Self.swipeTwoHTML))
        }
        server["/atb.js"] = { _ in
            .ok(.json(["version": "v1-1", "majorVersion": 1, "minorVersion": 1]))
        }
        server["/exti/"] = { _ in .accepted }
        server["/t/:pixelName"] = { _ in .accepted }
        server["/"] = { _ in .ok(.html(Self.pageOneHTML)) }

        try server.start(0, forceIPv4: true, priority: .userInitiated)
        serverBaseURL = "http://127.0.0.1:\(try server.port())"
    }

    private static let pageOneHTML = """
    <!doctype html>
    <html lang="en">
      <head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Page One</title></head>
      <body><h1>\(Page.oneHeading)</h1><a href="/page-two">Next page</a></body>
    </html>
    """

    private static let pageTwoHTML = """
    <!doctype html>
    <html lang="en">
      <head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Page Two</title></head>
      <body><h1>\(Page.twoHeading)</h1><a href="/page-one">Previous page</a></body>
    </html>
    """

    private static let longPageHTML = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Long Page</title>
        <style>
          body { min-height: 5000px; }
          .bottom { margin-top: 4500px; }
          .test-links { position: fixed; top: 48%; right: 16px; display: grid; gap: 16px; }
        </style>
      </head>
      <body>
        <h1>\(Page.longHeading)</h1>
        <nav class="test-links">
          <a href="/slow-page">Load slow page</a>
          <a href="http://127.0.0.1:65534/floating-ui-error">Load error page</a>
        </nav>
        <p class="bottom">End of page</p>
      </body>
    </html>
    """

    private static let edgeControlsHTML = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Edge Controls</title>
        <style>
          body { min-height: 5000px; margin: 0; }
          button { position: fixed; z-index: 2; min-height: 44px; padding: 8px 16px; }
          #top { top: 0; left: 16px; }
          #bottom { bottom: 0; right: 16px; }
          #status { position: fixed; top: 45%; left: 16px; }
        </style>
      </head>
      <body>
        <h1>\(Page.edgeHeading)</h1>
        <button id="top" aria-label="Top edge control" onclick="activate('Top')">Top</button>
        <button id="bottom" aria-label="Bottom edge control" onclick="activate('Bottom')">Bottom</button>
        <p id="status" aria-live="polite">No edge activated</p>
        <script>
          const counts = { Top: 0, Bottom: 0 };
          function activate(edge) {
            counts[edge] += 1;
            document.getElementById('status').textContent = edge + ' edge activated' + (counts[edge] > 1 ? ' again' : '');
          }
        </script>
      </body>
    </html>
    """

    private static let slowPageHTML = """
    <!doctype html>
    <html lang="en">
      <head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Slow Page</title></head>
      <body><h1>\(Page.slowHeading)</h1></body>
    </html>
    """

    private static let swipeOneHTML = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Swipe One</title>
        <style>body { min-height: 5000px; }</style>
      </head>
      <body><h1>\(Page.swipeOneHeading)</h1></body>
    </html>
    """

    private static let swipeTwoHTML = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Swipe Two</title>
        <style>body { min-height: 5000px; }</style>
      </head>
      <body><h1>\(Page.swipeTwoHeading)</h1></body>
    </html>
    """
}

final class FloatingUITopBarTests: FloatingUIXCUITestCase {

    override var barPosition: FloatingUIBarPosition { .top }

    func testUnifiedToggleInputTransitions() { verifyUnifiedToggleInputTransitions() }
    func testTabSwitcherTransitions() { verifyTabSwitcherTransitions() }
    func testBrowserChromeLongPressMenus() { verifyBrowserChromeLongPressMenus() }
    func testBrowserChromeInLandscape() { verifyBrowserChromeInLandscape() }
    func testDomainCapsuleAppears() { verifyDomainCapsuleAppears() }
    func testBrowsingMenuOpens() { verifyBrowsingMenuOpens() }
    func testDefaultCustomizableFireButton() { verifyDefaultCustomizableFireButton() }
    func testNewTabPageScenarios() { verifyNewTabPageScenarios() }
    func testBrowsingScenarios() { verifyBrowsingScenarios() }
    func testRuntimeAddressBarRelocation() { verifyRuntimeAddressBarRelocation() }
    func testConsecutiveAddressBarRelocation() { verifyConsecutiveAddressBarRelocation() }
    func testFloatingContentInsets() { verifyFloatingContentInsets() }
    func testUnifiedToggleInputKeyboardGeometry() { verifyUnifiedToggleInputKeyboardGeometry() }
    func testCollapsedChromeTransitions() { verifyCollapsedChromeTransitions() }
    func testUnifiedToggleInputRotation() { verifyUnifiedToggleInputRotation() }
    func testTabSwitcherRotation() { verifyTabSwitcherRotation() }
    func testChromeDuringSlowLoading() { verifyChromeDuringSlowLoading() }
    func testChromeOnErrorPage() { verifyChromeOnErrorPage() }
    func testFloatingSwipeTabs() { verifyFloatingSwipeTabs() }
}

final class FloatingUIBottomBarTests: FloatingUIXCUITestCase {

    override var barPosition: FloatingUIBarPosition { .bottom }

    func testUnifiedToggleInputTransitions() { verifyUnifiedToggleInputTransitions() }
    func testTabSwitcherTransitions() { verifyTabSwitcherTransitions() }
    func testBrowserChromeLongPressMenus() { verifyBrowserChromeLongPressMenus() }
    func testBrowserChromeInLandscape() { verifyBrowserChromeInLandscape() }
    func testDomainCapsuleAppears() { verifyDomainCapsuleAppears() }
    func testBrowsingMenuOpens() { verifyBrowsingMenuOpens() }
    func testDefaultCustomizableFireButton() { verifyDefaultCustomizableFireButton() }
    func testNewTabPageScenarios() { verifyNewTabPageScenarios() }
    func testBrowsingScenarios() { verifyBrowsingScenarios() }
    func testRuntimeAddressBarRelocation() { verifyRuntimeAddressBarRelocation() }
    func testConsecutiveAddressBarRelocation() { verifyConsecutiveAddressBarRelocation() }
    func testFloatingContentInsets() { verifyFloatingContentInsets() }
    func testUnifiedToggleInputKeyboardGeometry() { verifyUnifiedToggleInputKeyboardGeometry() }
    func testCollapsedChromeTransitions() { verifyCollapsedChromeTransitions() }
    func testUnifiedToggleInputRotation() { verifyUnifiedToggleInputRotation() }
    func testTabSwitcherRotation() { verifyTabSwitcherRotation() }
    func testChromeDuringSlowLoading() { verifyChromeDuringSlowLoading() }
    func testChromeOnErrorPage() { verifyChromeOnErrorPage() }
    func testFloatingSwipeTabs() { verifyFloatingSwipeTabs() }
}

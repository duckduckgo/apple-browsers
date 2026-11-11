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

extension XCUIElement {

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
        static let aiChat = "Browser.OmniBar.Button.AIChat"
        static let customizable = "Browser.OmniBar.Button.Customizable"
    }

    private enum Page {
        static let oneHeading = "Floating UI Test Page One"
        static let twoHeading = "Floating UI Test Page Two"
        static let longHeading = "Floating UI Long Page"
        static let findKeyboardHeading = "Find Keyboard Test Page"
        static let scrollEdgeHeading = "Floating UI Scroll Edge"
        static let edgeHeading = "Floating UI Edge Controls"
        static let slowHeading = "Floating UI Slow Page"
        static let swipeOneHeading = "Floating UI Swipe Page One"
        static let swipeTwoHeading = "Floating UI Swipe Page Two"
        static let favoriteCount = 21

        static func favoriteHeading(_ index: Int) -> String {
            "Floating UI Favorite \(index)"
        }
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

    func verifyCustomAIChatPageScrolling() {
        for usesLiquidGlass in [false, true] {
            app.terminate()
            launchApp(additionalArguments: [
                "-ff.duckAIAndInputLiquidGlass", String(usesLiquidGlass),
                "-aichat.debug.customURL", "\(serverBaseURL)/long-page",
            ])
            openPage(path: "/long-page", heading: Page.longHeading)
            XCTAssertTrue(app.buttons["Recent chats"].waitForHittable(timeout: timeout))
            let heading = app.staticTexts[Page.longHeading]
            XCTAssertTrue(heading.waitForHittable(timeout: timeout))
            heading.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNotHittable(timeout: timeout))

            webView.swipeUp()

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Custom chat after scrolling — Liquid Glass \(usesLiquidGlass)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(heading.waitForNotHittable(timeout: timeout), "Custom chat page did not scroll.")
            webView.swipeDown()
            XCTAssertTrue(heading.waitForHittable(timeout: timeout), "Custom chat page could not return to the top.")
        }
    }

    func verifyExistingSearchReplacement(toggleEnabled: Bool) {
        app.terminate()
        launchApp(toggleEnabled: toggleEnabled)
        searchField.tap()
        XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForHittable(timeout: timeout))
        XCTAssertEqual(element(withIdentifier: "AddressBar.Button.DuckAI").isHittable, toggleEnabled)
        searchField.typeText("original query\r")
        XCTAssertTrue(app.staticTexts[Page.oneHeading].waitForExistence(timeout: timeout))
        XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForNotHittable(timeout: timeout))

        for returnsFromBackground in [false, true] {
            if returnsFromBackground {
                XCUIDevice.shared.press(.home)
                XCTAssertTrue(app.wait(for: .runningBackground, timeout: timeout))
                app.activate()
            }

            XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
            searchField.tap()
            XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForHittable(timeout: timeout))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
            XCTAssertEqual(searchField.value as? String, "original query")

            searchField.typeText("replacement query")
            XCTAssertEqual(searchField.value as? String, "replacement query")

            element(withIdentifier: AccessibilityID.utiDismiss).tap()
            XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForNotHittable(timeout: timeout))
        }
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

    func verifyAddressBarButtonMenus() {
        app.terminate()
        launchApp(additionalArguments: [
            "-ff.contextualDuckAIMode", "true",
            "-ff.pageContextFeature", "true",
            "-ff.aiChatContextualFloatingInput", "true",
            "-ff.aiChatNativeChatHistory", "true",
            "-ff.aiChatAddressBarRecentChats", "true",
            "-ff.customizeNTPIcons", "true",
        ])

        let aiChatButton = element(withIdentifier: AccessibilityID.aiChat)
        XCTAssertTrue(aiChatButton.waitForHittable(timeout: timeout))
        aiChatButton.tap()
        XCTAssertTrue(app.buttons["New Chat"].waitForHittable(timeout: timeout))
        XCTAssertTrue(app.buttons["Chats"].waitForHittable(timeout: timeout))
        XCTAssertFalse(app.buttons["Ask About Page"].exists)
        dismissMenu(containing: "New Chat")

        openPage(path: "/page-one", heading: Page.oneHeading)

        XCTAssertTrue(aiChatButton.waitForHittable(timeout: timeout))
        aiChatButton.tap()
        XCTAssertTrue(app.buttons["Ask About Page"].waitForHittable(timeout: timeout))
        dismissMenu(containing: "Ask About Page")

        aiChatButton.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Ask About Page"].waitForHittable(timeout: timeout))
        dismissMenu(containing: "Ask About Page")

        let customizableButton = element(withIdentifier: AccessibilityID.customizable)
        XCTAssertTrue(customizableButton.waitForHittable(timeout: timeout))
        customizableButton.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Customize"].waitForHittable(timeout: timeout))
    }

    func verifyBrowserChromeInLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.width > self.app.frame.height })

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        XCTAssertGreaterThan(searchField.frame.width, 100)
        XCTAssertTrue(searchField.frame.intersects(app.frame))

        searchField.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons[barPosition.oppositeMoveAction].waitForExistence(timeout: timeout))
        dismissMenu(containing: barPosition.oppositeMoveAction)
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        assertConfiguredBarPosition()

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.height > self.app.frame.width })
        assertConfiguredBarPosition()
    }

    func verifyAddressBarButtonSpacingAfterRotation() {
        launchApp(additionalArguments: ["-ff.duckAIAndInputLiquidGlass", "true"])
        openPage(path: "/page-one", heading: Page.oneHeading)
        openNewTab()
        openPage(path: "/page-two", heading: Page.twoHeading)

        for (index, orientation) in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight, .portrait].enumerated() {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(waitUntil(timeout: timeout) {
                (self.app.frame.width > self.app.frame.height) == orientation.isLandscape
            })
            tabSwitcherButton.tap()
            let title = index.isMultiple(of: 2) ? "Page One" : "Page Two"
            let tab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open \"\(title)\"")).firstMatch
            XCTAssertTrue(tab.waitForHittable(timeout: timeout))
            tab.tap()
            let share = element(withIdentifier: AccessibilityID.customizable)
            XCTAssertTrue(share.waitForHittable(timeout: timeout))
            let refresh = ["Browser.OmniBar.Button.Refresh", "Browser.OmniBar.Button.RefreshExternal"]
                .map { element(withIdentifier: $0) }.first { $0.isHittable }
            guard let refresh else { return XCTFail("Refresh button missing after rotation") }
            XCTAssertGreaterThanOrEqual(refresh.frame.width, 40)
            XCTAssertGreaterThanOrEqual(share.frame.width, 40)
            XCTAssertFalse(refresh.frame.intersects(share.frame))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(barPosition.rawValue) address bar, rotation \(index + 1)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
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
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
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

    func verifyNewTabPageAddressBarRelocation() {
        moveAddressBar(to: barPosition.opposite)
        assertChromeButtonsAreUsable()
        moveAddressBar(to: barPosition)
        assertChromeButtonsAreUsable()
    }

    func verifyStatusBarScrollEdgeInBothBarPositions() {
        for position in [FloatingUIBarPosition.top, .bottom] {
            openPage(path: "/scroll-edge", heading: Page.scrollEdgeHeading)
            if position == .bottom {
                moveAddressBar(to: position)
            }
            collapseChrome()
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "scroll-edge-\(position.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            domainCapsule.tap()
            XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
            assertBarPosition(position)
        }
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

    func verifyBottomPinnedInputSurvivesKeyboardDismissal() {
        openPage(path: "/bottom-pinned-chat", heading: "Bottom pinned chat")

        let input = app.webViews.textViews["Message"]
        let keyboard = app.keyboards.firstMatch
        for cycle in 1...5 {
            XCTAssertTrue(input.waitForHittable(timeout: timeout))
            input.tap()
            XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
            XCTAssertTrue(waitUntil(timeout: timeout) {
                keyboard.frame.intersects(self.app.frame) && input.frame.maxY <= keyboard.frame.minY + 1
            }, "Message hidden by keyboard on cycle \(cycle)")
            input.typeText("Message \(cycle)\nAnother line ")
            app.webViews.buttons["Dismiss keyboard"].tap()
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout))
            XCTAssertTrue(input.waitForHittable(timeout: timeout))
            assertClearsBottomChrome(input)
        }
        verifyUnifiedToggleInputKeyboardGeometry()
    }

    func verifyWebInputChromeAfterAddressBarRelocation() {
        openPage(path: "/bottom-pinned-chat", heading: "Bottom pinned chat")
        let input = app.webViews.textViews["Message"]
        var currentPosition = barPosition

        for position in [barPosition, barPosition.opposite, barPosition] {
            if currentPosition != position {
                moveAddressBar(to: position)
                currentPosition = position
            }
            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
                XCUIDevice.shared.orientation = orientation
                XCTAssertTrue(waitUntil(timeout: timeout) {
                    (self.app.frame.width > self.app.frame.height) == (orientation == .landscapeLeft)
                })
                XCTAssertTrue(input.waitForHittable(timeout: timeout))
                input.tap()
                input.typeText("Editing ")
                XCTAssertTrue(input.frame.intersects(app.frame))

                XCTAssertTrue(element(withIdentifier: AccessibilityID.toolbarFire).waitForNonExistence(timeout: timeout))
                if position == .bottom {
                    XCTAssertTrue(searchField.waitForNonExistence(timeout: timeout))
                    XCTAssertFalse(domainCapsule.exists)
                }

                let keyboardControls = app.toolbars["Toolbar"]
                XCTAssertTrue(keyboardControls.waitForExistence(timeout: timeout))
                let typedText = input.staticTexts.firstMatch
                XCTAssertTrue(typedText.waitForExistence(timeout: timeout))
                XCTAssertTrue(typedText.label.contains("Editing"))

                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Web input \(position.rawValue) \(orientation.rawValue)"
                screenshot.lifetime = .keepAlways
                add(screenshot)

                let pageDismissButton = app.webViews.buttons["Dismiss keyboard"]
                if pageDismissButton.isHittable {
                    pageDismissButton.tap()
                } else {
                    keyboardControls.buttons.element(boundBy: 2).tap()
                }
                XCTAssertTrue(keyboardControls.waitForNonExistence(timeout: timeout))
                XCTAssertTrue(input.waitForHittable(timeout: timeout))
                XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
                assertBarPosition(position)
            }
        }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.height > self.app.frame.width })
        assertChromeButtonsAreUsable()
        verifyUnifiedToggleInputTransitions()
    }

    func verifyScrollingPerformance() {
        let environment = ProcessInfo.processInfo.environment
        if let url = environment["FLOATING_UI_PERFORMANCE_URL"],
           let heading = environment["FLOATING_UI_PERFORMANCE_HEADING"] {
            searchField.tap()
            XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForHittable(timeout: timeout))
            searchField.typeText("\(url)\r")
            let pageHeading = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", heading)).firstMatch
            XCTAssertTrue(pageHeading.waitForExistence(timeout: timeout))
        } else {
            openPage(path: "/long-page", heading: Page.longHeading)
        }
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: timeout))
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            webView.swipeUp(velocity: .fast)
            webView.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        assertConfiguredBarPosition()
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

    func verifyFindInPageGlass() {
        app.terminate()
        launchApp(additionalArguments: ["-ff.legacyFindInPage", "true"])
        openPage(path: "/page-one", heading: Page.oneHeading)

        element(withIdentifier: AccessibilityID.toolbarMenu).tap()
        let findAction = app.buttons["Find in Page"]
        XCTAssertTrue(findAction.waitForHittable(timeout: timeout))
        findAction.tap()

        let findField = app.searchFields["Find in Page"]
        XCTAssertTrue(findField.waitForHittable(timeout: timeout))
        findField.typeText("Floating")
        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: timeout))
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForHittable(timeout: timeout))
        XCTAssertLessThan(doneButton.frame.maxX, findField.frame.minX)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Find in Page - Floating UI"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        doneButton.tap()
        XCTAssertTrue(findField.waitForNonExistence(timeout: timeout))
    }

    func verifyDelegateSessionLifecycle() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Experiment targets iOS 27") }
        app.terminate()
        launchApp(additionalArguments: ["-ff.legacyFindInPage", "true", "-ff.legacyFindInPageUIWithSystemFindEngine", "true"])
        openPage(path: "/delegate-find", heading: "Delegate Find Fixture")
        webView.buttons["Expand all sections"].tap()
        XCTAssertTrue(webView.staticTexts["Expanded content stays open"].waitForExistence(timeout: timeout))
        openFindFromMenu()
        let field = app.searchFields["FindInPage.Query"]
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        expectDelegateCount(nil)
        field.typeText("needle")
        expectDelegateCount("1 of 3")
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        }
        captureFind("Delegate session - engine highlights including iframe")

        if UIDevice.current.userInterfaceIdiom == .phone {
            app.typeKey("g", modifierFlags: .command)
        } else {
            app.buttons["Find Next"].tap()
        }
        expectDelegateCount("2 of 3")
        app.buttons["Find Next"].tap()
        expectDelegateCount("3 of 3")
        captureFind("Delegate session - iframe result")
        app.buttons["Find Next"].tap()
        expectDelegateCount("1 of 3")
        if UIDevice.current.userInterfaceIdiom == .phone {
            app.typeKey("g", modifierFlags: [.command, .shift])
        } else {
            app.buttons["Find Previous"].tap()
        }
        expectDelegateCount("3 of 3")

        app.buttons["FindInPage.Clear"].tap()
        field.typeText("absent-result")
        expectDelegateCount("0 of 0")
        app.buttons["FindInPage.Clear"].tap()
        field.typeText("needlezz" + String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        expectDelegateCount("1 of 3")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(field.exists)
        XCTAssertFalse(element(withIdentifier: AccessibilityID.toolbarMenu).isHittable)
        XCUIDevice.shared.press(.home)
        app.activate()
        expectDelegateCount("1 of 3")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.width > self.app.frame.height })
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        XCTAssertLessThanOrEqual(field.frame.maxX, app.frame.maxX)
        app.buttons["Find Next"].tap()
        expectDelegateCount("2 of 3")
        let secondMatch = webView.staticTexts["needle second match"]
        XCTAssertTrue(waitUntil(timeout: timeout) { secondMatch.exists && secondMatch.frame.maxY < field.frame.minY - 24 })
        captureFind("Delegate session - compact landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: timeout) { self.app.frame.height > self.app.frame.width })
        app.buttons["Done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: timeout))
        captureFind("Delegate session - ended without overlay")

        openFindFromMenu()
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        XCTAssertEqual(field.value as? String, "needle")
        expectDelegateCount("1 of 3")
        app.buttons["FindInPage.Clear"].tap()
        expectDelegateCount(nil)
        app.buttons["Done"].tap()
        openFindFromMenu()
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        XCTAssertEqual(field.value as? String, "")
        expectDelegateCount(nil)
        if UIDevice.current.userInterfaceIdiom == .phone {
            app.typeKey("f", modifierFlags: .command)
            expectDelegateCount(nil)
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: timeout))
        captureFind("Delegate session - cleared and ended")
        XCTAssertTrue(webView.staticTexts["Expanded content stays open"].exists)
    }

    func verifyDelegateSessionTabAndNavigation() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Experiment targets iOS 27") }
        app.terminate()
        launchApp(additionalArguments: ["-ff.legacyFindInPage", "true", "-ff.legacyFindInPageUIWithSystemFindEngine", "true"])
        openPage(path: "/delegate-find", heading: "Delegate Find Fixture")
        webView.buttons["Expand all sections"].tap()
        openFindFromMenu()
        let field = app.searchFields["FindInPage.Query"]
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        field.typeText("needle")
        expectDelegateCount("1 of 3")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: timeout))
        openPage(path: "/page-one", heading: Page.oneHeading)
        openFindFromMenu()
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        XCTAssertEqual(field.value as? String, "")
        field.typeText("Floating")
        expectDelegateCount("1 of 1")
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: timeout))
        openFindFromMenu()
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        XCTAssertEqual(field.value as? String, "needle")
        expectDelegateCount("1 of 3")
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(webView.staticTexts["Delegate Find Fixture"].waitForExistence(timeout: timeout))
        captureFind("Delegate session - reloaded without overlay")
        webView.buttons["Expand all sections"].tap()
        openFindFromMenu()
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        XCTAssertEqual(field.value as? String, "needle")
        expectDelegateCount("1 of 3")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        webView.links["Navigate away"].tap()
        XCTAssertTrue(webView.staticTexts[Page.twoHeading].waitForExistence(timeout: timeout))
        XCTAssertFalse(field.exists)
    }

    func verifyNativeFindWithoutExperiment() {
        app.terminate()
        launchApp(additionalArguments: ["-ff.legacyFindInPage", "false", "-ff.legacyFindInPageUIWithSystemFindEngine", "true"])
        openPage(path: "/delegate-find", heading: "Delegate Find Fixture")
        webView.buttons["Expand all sections"].tap()
        openFindFromMenu()
        let nativeField = app.searchFields["find.searchField"].firstMatch
        XCTAssertTrue(nativeField.waitForHittable(timeout: timeout))
        nativeField.typeText("needle")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'of 3'")).firstMatch.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.searchFields["FindInPage.Query"].exists)
        captureFind("Native Find - experiment disabled")
        app.buttons["find.doneButton"].tap()
        XCTAssertTrue(nativeField.waitForNonExistence(timeout: timeout))
    }

    func verifyLiveFindInvestigation(delegateSession: Bool) throws {
        guard ProcessInfo.processInfo.environment["FIND_ENGINE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Opt-in live device investigation")
        }
        guard #available(iOS 27.0, *) else { throw XCTSkip("Experiment targets iOS 27") }
        app.terminate()
        let arguments = [
            "-ff.legacyFindInPage", String(delegateSession),
            "-ff.legacyFindInPageUIWithSystemFindEngine", String(delegateSession)
        ]
        launchApp(additionalArguments: arguments)
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        searchField.tap()
        searchField.typeText("https://duckduckgo.com/whatsnew\r")
        let quarter = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Q3 2026'")).firstMatch
        XCTAssertTrue(quarter.waitForExistence(timeout: 60))

        searchField.tap()
        let url = searchField.value as? String ?? "unknown"
        let evidence = XCTAttachment(string: "Requested: https://duckduckgo.com/whatsnew\nAddress field after load: \(url)\nOS: \(UIDevice.current.systemVersion)")
        evidence.name = "Live Find - URL and runtime"
        evidence.lifetime = .keepAlways
        add(evidence)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        for section in ["Q2 2026", "Q1 2026", "Q4 2025", "Q3 2025", "Q2 2025", "Q1 2025"] {
            let button = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", section)).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: timeout), section)
            button.tap()
        }
        for year in ["2024", "2023", "2022"] {
            let yearButton = webView.buttons.matching(NSPredicate(format: "label == %@", year)).firstMatch
            XCTAssertTrue(yearButton.waitForExistence(timeout: timeout))
            yearButton.tap()
            let firstQuarter = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Q4 \(year)")).firstMatch
            XCTAssertTrue(firstQuarter.waitForExistence(timeout: timeout))
            for quarter in [3, 2, 1] {
                let button = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Q\(quarter) \(year)")).firstMatch
                if button.exists { button.tap() }
            }
        }
        let expanded = XCTAttachment(string: webView.debugDescription)
        expanded.name = "Live Find - expansion accessibility state"
        expanded.lifetime = .keepAlways
        add(expanded)
        captureFind("Live Find - all quarterly sections expanded")

        openFindFromMenu()
        let identifier = delegateSession ? "FindInPage.Query" : "find.searchField"
        let field = app.searchFields[identifier].firstMatch
        let doneButton = app.buttons[delegateSession ? "Done" : "find.doneButton"].firstMatch
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        field.typeText("privacy")
        if delegateSession {
            let count = app.staticTexts["FindInPage.ResultCount"]
            XCTAssertTrue(waitUntil(timeout: 30) { count.label.hasPrefix("1 of ") })
            XCTAssertFalse(app.searchFields["find.searchField"].firstMatch.exists)
        } else {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'of '")).firstMatch.waitForExistence(timeout: 30))
        }
        captureFind(delegateSession ? "Live delegate session - highlights" : "Live native Find - highlights")
        doneButton.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: timeout))
        captureFind(delegateSession ? "Live delegate session - ended" : "Live native Find - ended")
        openFindFromMenu()
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        XCTAssertEqual(field.value as? String, "privacy")
        let clear = delegateSession ? app.buttons["FindInPage.Clear"] : field.buttons["Clear text"]
        XCTAssertTrue(clear.waitForHittable(timeout: timeout))
        clear.tap()
        captureFind(delegateSession ? "Live delegate session - cleared" : "Live native Find - cleared")
        doneButton.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: timeout))
        openFindFromMenu()
        XCTAssertTrue(field.waitForHittable(timeout: timeout))
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == field.placeholderValue)
        captureFind(delegateSession ? "Live delegate session - reopened empty" : "Live native Find - reopened empty")
        doneButton.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: timeout))
    }

    private func openFindFromMenu() {
        let menuID = UIDevice.current.userInterfaceIdiom == .pad ? "Browser.OmniBar.Button.BrowsingMenu" : AccessibilityID.toolbarMenu
        let menu = element(withIdentifier: menuID)
        if !menu.isHittable { webView.swipeDown() }
        XCTAssertTrue(menu.waitForHittable(timeout: timeout))
        menu.tap()
        let action = app.buttons["Find in Page"]
        XCTAssertTrue(action.waitForHittable(timeout: timeout))
        action.tap()
    }

    private func expectDelegateCount(_ count: String?, file: StaticString = #filePath, line: UInt = #line) {
        let counter = app.staticTexts["FindInPage.ResultCount"]
        if let count {
            XCTAssertTrue(waitUntil(timeout: timeout) { counter.exists && counter.label == count }, counter.label, file: file, line: line)
        } else {
            XCTAssertTrue(counter.waitForNonExistence(timeout: timeout), file: file, line: line)
        }
        XCTAssertFalse(app.searchFields["find.searchField"].firstMatch.exists, file: file, line: line)
        XCTAssertTrue(app.staticTexts["FindInPage.ExperimentStatus"].label.contains("nativeUI=false"), file: file, line: line)
    }

    private func captureFind(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func verifyFindResultClearsKeyboard(floatingUIEnabled: Bool) {
        app.terminate()
        launchApp(additionalArguments: [
            "-ff.floatingUIiOS26", String(floatingUIEnabled),
            "-ff.floatingUIiOS27", String(floatingUIEnabled),
            "-ff.legacyFindInPage", "true",
        ])
        openPage(path: "/find-keyboard", heading: Page.findKeyboardHeading)

        element(withIdentifier: AccessibilityID.toolbarMenu).tap()
        let findAction = app.buttons["Find in Page"]
        XCTAssertTrue(findAction.waitForHittable(timeout: timeout))
        findAction.tap()

        let findField = app.searchFields["Find in Page"]
        XCTAssertTrue(findField.waitForHittable(timeout: timeout))
        let browserMenu = element(withIdentifier: AccessibilityID.toolbarMenu)
        XCTAssertTrue(browserMenu.waitForNotHittable(timeout: timeout))
        findField.typeText("hackers")
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: timeout))
        let nextButton = app.buttons["Find Next"]
        XCTAssertTrue(nextButton.waitForHittable(timeout: timeout))
        nextButton.tap()
        nextButton.tap()
        let resultCount = app.staticTexts["3 of 3"]
        XCTAssertTrue(resultCount.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))

        if floatingUIEnabled {
            let clearButton = app.buttons["FindInPage.Clear"]
            XCTAssertTrue(clearButton.waitForHittable(timeout: timeout))
            XCTAssertLessThan(resultCount.frame.maxX, clearButton.frame.minX)
        }

        let matches = webView.staticTexts.matching(identifier: "hackers")
        XCTAssertEqual(matches.count, 3)
        let selectedMatch = matches.element(boundBy: 2)
        XCTAssertTrue(waitUntil(timeout: timeout) { selectedMatch.frame.maxY < findField.frame.minY - 8 })

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Find in Page - Keyboard Clearance"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let initialMatchY = selectedMatch.frame.minY
        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.3))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(findField.exists)
        XCTAssertTrue(waitUntil(timeout: timeout) { selectedMatch.frame.minY < initialMatchY - 10 })
        XCTAssertTrue(browserMenu.waitForNotHittable(timeout: timeout))
        if floatingUIEnabled {
            XCTAssertTrue(element(withIdentifier: AccessibilityID.domainCapsule).waitForNotHittable(timeout: timeout))
        }

        let dismissedScreenshot = XCTAttachment(screenshot: app.screenshot())
        dismissedScreenshot.name = "Find in Page - Keyboard Dismissed"
        dismissedScreenshot.lifetime = .keepAlways
        add(dismissedScreenshot)

        if floatingUIEnabled {
            app.buttons["FindInPage.Clear"].tap()
            XCTAssertEqual(findField.value as? String, "")
            XCTAssertFalse(resultCount.exists)
        }

        app.buttons["Done"].tap()
        XCTAssertTrue(browserMenu.waitForHittable(timeout: timeout))
    }

    func verifyIPadFindInPageUsesGlassWithFloatingFlagOff() {
        app.terminate()
        launchApp(additionalArguments: [
            "-ff.floatingUIiOS26", "false",
            "-ff.floatingUIiOS27", "false",
            "-ff.legacyFindInPage", "true",
        ])
        openPage(path: "/page-one", heading: Page.oneHeading)

        element(withIdentifier: "Browser.OmniBar.Button.BrowsingMenu").tap()
        let findAction = app.buttons["Find in Page"]
        XCTAssertTrue(findAction.waitForHittable(timeout: timeout))
        findAction.tap()

        let findField = app.searchFields["Find in Page"]
        XCTAssertTrue(findField.waitForHittable(timeout: timeout))
        findField.typeText("Floating")
        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: timeout))
        let clearButton = app.buttons["FindInPage.Clear"]
        XCTAssertTrue(clearButton.waitForHittable(timeout: timeout))
        XCTAssertLessThan(app.staticTexts["1 of 1"].frame.maxX, clearButton.frame.minX)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Find in Page - iPad Glass With Floating Flag Off"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

    func verifyNewTabPageFavoritesClearFloatingChromeInBothBarPositions() {
        addFavorites(count: Page.favoriteCount)
        openNewTab()

        scrollNewTabPageToBottom()
        assertBottomFavoriteClearsFloatingChrome()

        moveAddressBar(to: .bottom)
        scrollNewTabPageToBottom()
        assertBottomFavoriteClearsFloatingChrome()
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

    private func launchApp(toggleEnabled: Bool? = nil, additionalArguments: [String] = []) {
        app.launchArguments = [
            "-clearAllDefaults",
            "isRunningUITests",
            "-isOnboardingCompleted", "true",
            "-isInternalUser", "true",
            "-ff.floatingUIiOS26", "true",
            "-ff.floatingUIiOS27", "true",
            "-ff.omniBarLongPressMenu", "true",
            "-ff.alwaysShowKeyboardOnNewTabPage", "false",
            "-ff.newTabPageRedesign", "false",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_GB",
        ]
        if let toggleEnabled {
            app.launchArguments += [
                "-aichat.settings.isEnabled", "true",
                "-aichat.settings.showAIChatExperimentalSearchInput", String(toggleEnabled),
            ]
        }
        for flag in ["-ff.legacyFindInPage", "-ff.legacyFindInPageUIWithSystemFindEngine"] where !additionalArguments.contains(flag) {
            app.launchArguments += [flag, "false"]
        }
        app.launchArguments += additionalArguments
        app.launchEnvironment = [
            "UITEST_MODE": "1",
            "BASE_URL": serverBaseURL,
            "PIXEL_BASE_URL": serverBaseURL,
        ]
        app.launch()

        XCTAssertTrue(searchField.waitForHittable(timeout: timeout), "Browser chrome did not become ready.")
        if UIDevice.current.userInterfaceIdiom != .pad {
            XCTAssertTrue(element(withIdentifier: AccessibilityID.toolbarFire).exists)
            XCTAssertTrue(tabSwitcherButton.exists)
            XCTAssertTrue(element(withIdentifier: AccessibilityID.toolbarMenu).exists)
        }
        let dismissButton = element(withIdentifier: AccessibilityID.utiDismiss)
        if dismissButton.exists, dismissButton.isHittable {
            dismissButton.tap()
            XCTAssertTrue(dismissButton.waitForNotHittable(timeout: timeout))
        }
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
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout), file: file, line: line)
        searchField.press(forDuration: 0.8)
        let moveAction = app.buttons[position.moveAction]
        XCTAssertTrue(moveAction.waitForHittable(timeout: timeout), file: file, line: line)
        moveAction.tap()
        var didMove = waitUntil(timeout: 5) {
            guard self.searchField.exists, self.searchField.isHittable else { return false }
            switch position {
            case .top:
                return self.searchField.frame.midY < self.app.frame.midY
            case .bottom:
                return self.searchField.frame.midY > self.app.frame.midY
            }
        }
        if !didMove, position == .top {
            // Reparenting can leave XCTest's accessibility snapshot stale.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
            let dismissButton = element(withIdentifier: AccessibilityID.utiDismiss)
            if dismissButton.waitForHittable(timeout: timeout) {
                dismissButton.tap()
                _ = dismissButton.waitForNotHittable(timeout: timeout)
                didMove = searchField.waitForHittable(timeout: timeout)
                    && searchField.frame.midY < app.frame.midY
            }
        }
        if !didMove {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTFail("Address bar did not move to \(position.rawValue). Search field: \(searchField.debugDescription)", file: file, line: line)
        }
        assertBarPosition(position, file: file, line: line)
    }

    private func dismissMenu(containing actionTitle: String) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons[actionTitle].waitForNonExistence(timeout: timeout))
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

    private func addFavorites(count: Int, file: StaticString = #filePath, line: UInt = #line) {
        openPage(path: "/favorite-1", heading: Page.favoriteHeading(1), file: file, line: line)

        for index in 1...count {
            element(withIdentifier: AccessibilityID.toolbarMenu).tap()

            let addFavoriteButton = app.buttons["Add Favorite"]
            XCTAssertTrue(
                addFavoriteButton.waitForHittable(timeout: timeout),
                app.debugDescription,
                file: file,
                line: line
            )
            addFavoriteButton.tap()
            XCTAssertTrue(addFavoriteButton.waitForNotHittable(timeout: timeout), file: file, line: line)

            if index < count {
                let nextFavoriteLink = app.links["Next favorite"]
                XCTAssertTrue(nextFavoriteLink.waitForHittable(timeout: timeout), file: file, line: line)
                nextFavoriteLink.tap()
                let nextFavoriteHeading = app.staticTexts[Page.favoriteHeading(index + 1)]
                XCTAssertTrue(nextFavoriteHeading.waitForExistence(timeout: timeout), file: file, line: line)
            }
        }
    }

    private func scrollNewTabPageToBottom(file: StaticString = #filePath, line: UInt = #line) {
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: timeout), file: file, line: line)
        for _ in 0..<4 {
            scrollView.swipeUp(velocity: .fast)
        }
    }

    private func assertBottomFavoriteClearsFloatingChrome(file: StaticString = #filePath, line: UInt = #line) {
        let favoritePredicate = NSPredicate(format: "label ENDSWITH %@", ". Favorite")
        let favorites = app.buttons.matching(favoritePredicate).allElementsBoundByIndex
        let visibleFavorites = favorites.filter { $0.frame.intersects(app.frame) }
        guard let bottomFavorite = visibleFavorites.max(by: { $0.frame.maxY < $1.frame.maxY }) else {
            XCTFail("Could not find favorites on the new tab page.", file: file, line: line)
            return
        }
        XCTAssertTrue(bottomFavorite.isHittable, app.debugDescription, file: file, line: line)
        assertClearsBottomChrome(bottomFavorite, file: file, line: line)
    }

    private func openNewTab(file: StaticString = #filePath, line: UInt = #line) {
        tabSwitcherButton.press(forDuration: 0.8)
        let newTabButton = app.buttons["New Tab"]
        XCTAssertTrue(newTabButton.waitForHittable(timeout: timeout), file: file, line: line)
        newTabButton.tap()
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout), file: file, line: line)

        let dismissButton = element(withIdentifier: AccessibilityID.utiDismiss)
        if dismissButton.waitForHittable(timeout: timeout) {
            dismissButton.tap()
            XCTAssertTrue(dismissButton.waitForNotHittable(timeout: timeout), file: file, line: line)
        }
    }

    private func assertClearsBottomChrome(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let bottomChromeElements = [
            searchField,
            self.element(withIdentifier: AccessibilityID.toolbarBack),
            self.element(withIdentifier: AccessibilityID.toolbarForward),
            self.element(withIdentifier: AccessibilityID.toolbarFire),
            tabSwitcherButton,
            self.element(withIdentifier: AccessibilityID.toolbarMenu),
        ].filter { $0.exists && $0.frame.midY > app.frame.midY }

        guard let chromeTop = bottomChromeElements.map(\.frame.minY).min() else {
            XCTFail("Could not find the bottom browser chrome.", file: file, line: line)
            return
        }

        XCTAssertLessThanOrEqual(element.frame.maxY, chromeTop, file: file, line: line)
    }

    private func openPage(path: String, heading: String, file: StaticString = #filePath, line: UInt = #line) {
        searchField.tap()
        if UIDevice.current.userInterfaceIdiom != .pad {
            XCTAssertTrue(element(withIdentifier: AccessibilityID.utiDismiss).waitForHittable(timeout: timeout), file: file, line: line)
        }
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
        server["/find-keyboard"] = { _ in
            .ok(.html(Self.findKeyboardHTML))
        }
        server["/delegate-find"] = { _ in
            .ok(.html("""
                <meta name="viewport" content="width=device-width,initial-scale=1">
                <style>body { font: 22px/1.5 -apple-system; padding: 12px; } iframe { height: 130px; width: 95%; }</style>
                <h1>Delegate Find Fixture</h1>
                <button onclick="document.querySelectorAll('details').forEach(section => section.open = true)">Expand all sections</button>
                <details><summary>Article section</summary><p>Expanded content stays open</p>
                <p>needle first match</p><p>needle second match</p>
                <iframe title="Same-origin frame" src="/delegate-find-frame"></iframe></details>
                <p><a href="/page-two">Navigate away</a></p><div style="height:1200px"></div>
                """))
        }
        server["/delegate-find-frame"] = { _ in
            .ok(.html("<style>body { font: 22px -apple-system; }</style><p>needle third match inside iframe</p>"))
        }
        server["/scroll-edge"] = { _ in
            .ok(.html(Self.scrollEdgeHTML))
        }
        server["/edge-controls"] = { _ in
            .ok(.html(Self.edgeControlsHTML))
        }
        server["/bottom-pinned-chat"] = { _ in
            .ok(.html(Self.bottomPinnedChatHTML))
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
        for index in 1...Page.favoriteCount {
            let favoriteIndex = index
            server["/favorite-\(favoriteIndex)"] = { _ in
                .ok(.html(Self.favoriteHTML(index: favoriteIndex)))
            }
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

    private static let findKeyboardHTML = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Find Keyboard Test</title>
        <style>body { font: 24px/1.5 -apple-system; } p { margin: 320px 0; }</style>
      </head>
      <body>
        <h1>\(Page.findKeyboardHeading)</h1>
        <p>hackers</p><p>hackers</p><p>hackers</p>
        <div style="height: 1200px"></div>
      </body>
    </html>
    """

    private static let scrollEdgeHTML = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <title>Scroll Edge</title>
        <style>
          body { margin: 0; color: #111; background: white; font: 24px/1.3 -apple-system; }
          h1 { font-size: 28px; padding: 16px; }
          p { margin: 0; padding: 12px 6px; border-bottom: 1px solid #aaa; }
          p:nth-child(even) { background: #ffe282; }
        </style>
      </head>
      <body>
        <h1>\(Page.scrollEdgeHeading)</h1>
        \((1...80).map { "<p>Line \($0): Content scrolling behind the status bar.</p>" }.joined())
      </body>
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

    private static let bottomPinnedChatHTML = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <title>Bottom pinned chat</title>
        <style>
          body { margin: 0; font: 16px system-ui; background: #eef4ff; }
          h1 { font-size: 24px; }
          main { padding: 16px; }
          footer { position: fixed; bottom: 0; left: 0; right: 0; padding: 12px 12px calc(12px + env(safe-area-inset-bottom, 0px)); background: white; }
          textarea { box-sizing: border-box; width: 100%; min-height: 44px; font-size: 16px; }
          button { min-height: 44px; font-size: 16px; }
        </style>
      </head>
      <body>
        <main>
          <h1>Bottom pinned chat</h1>
          <button onclick="document.activeElement.blur()">Dismiss keyboard</button>
        </main>
        <footer><textarea aria-label="Message" rows="2" placeholder="Type a message"></textarea></footer>
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

    private static func favoriteHTML(index: Int) -> String {
        let nextLink = index < Page.favoriteCount ? #"<a href="/favorite-\#(index + 1)">Next favorite</a>"# : ""
        return """
        <!doctype html>
        <html lang="en">
          <head><meta name="viewport" content="width=device-width, initial-scale=1"><title>\(Page.favoriteHeading(index))</title></head>
          <body><h1>\(Page.favoriteHeading(index))</h1>\(nextLink)</body>
        </html>
        """
    }

}

final class FloatingUITopBarTests: FloatingUIXCUITestCase {

    override var barPosition: FloatingUIBarPosition { .top }

    func testExistingSearchReplacementWithToggleEnabled() { verifyExistingSearchReplacement(toggleEnabled: true) }
    func testExistingSearchReplacementWithToggleDisabled() { verifyExistingSearchReplacement(toggleEnabled: false) }

    func testUnifiedToggleInputTransitions() { verifyUnifiedToggleInputTransitions() }
    func testTabSwitcherTransitions() { verifyTabSwitcherTransitions() }
    func testBrowserChromeLongPressMenus() { verifyBrowserChromeLongPressMenus() }
    func testAddressBarButtonMenus() { verifyAddressBarButtonMenus() }
    func testBrowserChromeInLandscape() { verifyBrowserChromeInLandscape() }
    func testAddressBarButtonSpacingAfterRotation() { verifyAddressBarButtonSpacingAfterRotation() }
    func testDomainCapsuleAppears() { verifyDomainCapsuleAppears() }
    func testBrowsingMenuOpens() { verifyBrowsingMenuOpens() }
    func testFindInPageGlass() { verifyFindInPageGlass() }
    func testDelegateSessionLifecycle() throws { try verifyDelegateSessionLifecycle() }
    func testDelegateSessionTabAndNavigation() throws { try verifyDelegateSessionTabAndNavigation() }
    func testNativeFindWithoutExperiment() { verifyNativeFindWithoutExperiment() }
    func testLiveDelegateFindInvestigation() throws { try verifyLiveFindInvestigation(delegateSession: true) }
    func testLiveNativeFindInvestigation() throws { try verifyLiveFindInvestigation(delegateSession: false) }
    func testFindResultClearsKeyboardWithFloatingUI() { verifyFindResultClearsKeyboard(floatingUIEnabled: true) }
    func testDefaultCustomizableFireButton() { verifyDefaultCustomizableFireButton() }
    func testNewTabPageScenarios() { verifyNewTabPageScenarios() }
    func testBrowsingScenarios() { verifyBrowsingScenarios() }
    func testRuntimeAddressBarRelocation() { verifyRuntimeAddressBarRelocation() }
    func testConsecutiveAddressBarRelocation() { verifyConsecutiveAddressBarRelocation() }
    func testNewTabPageAddressBarRelocation() { verifyNewTabPageAddressBarRelocation() }
    func testStatusBarScrollEdgeInBothBarPositions() { verifyStatusBarScrollEdgeInBothBarPositions() }
    func testFloatingContentInsets() { verifyFloatingContentInsets() }
    func testUnifiedToggleInputKeyboardGeometry() { verifyUnifiedToggleInputKeyboardGeometry() }
    func testBottomPinnedInputSurvivesKeyboardDismissal() { verifyBottomPinnedInputSurvivesKeyboardDismissal() }
    func testWebInputChromeAfterAddressBarRelocation() { verifyWebInputChromeAfterAddressBarRelocation() }
    func testCollapsedChromeTransitions() { verifyCollapsedChromeTransitions() }
    func testScrollingPerformance() { verifyScrollingPerformance() }
    func testUnifiedToggleInputRotation() { verifyUnifiedToggleInputRotation() }
    func testTabSwitcherRotation() { verifyTabSwitcherRotation() }
    func testChromeDuringSlowLoading() { verifyChromeDuringSlowLoading() }
    func testChromeOnErrorPage() { verifyChromeOnErrorPage() }
    func testFloatingSwipeTabs() { verifyFloatingSwipeTabs() }
    func testNewTabPageFavoritesClearFloatingChromeInBothBarPositions() {
        verifyNewTabPageFavoritesClearFloatingChromeInBothBarPositions()
    }
}

final class FloatingUIBottomBarTests: FloatingUIXCUITestCase {

    override var barPosition: FloatingUIBarPosition { .bottom }

    func testExistingSearchReplacementWithToggleEnabled() { verifyExistingSearchReplacement(toggleEnabled: true) }
    func testExistingSearchReplacementWithToggleDisabled() { verifyExistingSearchReplacement(toggleEnabled: false) }

    func testUnifiedToggleInputTransitions() { verifyUnifiedToggleInputTransitions() }
    func testCustomAIChatPageScrolling() { verifyCustomAIChatPageScrolling() }
    func testTabSwitcherTransitions() { verifyTabSwitcherTransitions() }
    func testBrowserChromeLongPressMenus() { verifyBrowserChromeLongPressMenus() }
    func testAddressBarButtonMenus() { verifyAddressBarButtonMenus() }
    func testBrowserChromeInLandscape() { verifyBrowserChromeInLandscape() }
    func testAddressBarButtonSpacingAfterRotation() { verifyAddressBarButtonSpacingAfterRotation() }
    func testDomainCapsuleAppears() { verifyDomainCapsuleAppears() }
    func testBrowsingMenuOpens() { verifyBrowsingMenuOpens() }
    func testFindInPageGlass() { verifyFindInPageGlass() }
    func testDelegateSessionLifecycle() throws { try verifyDelegateSessionLifecycle() }
    func testFindResultClearsKeyboardWithLegacyUI() { verifyFindResultClearsKeyboard(floatingUIEnabled: false) }
    func testDefaultCustomizableFireButton() { verifyDefaultCustomizableFireButton() }
    func testNewTabPageScenarios() { verifyNewTabPageScenarios() }
    func testBrowsingScenarios() { verifyBrowsingScenarios() }
    func testRuntimeAddressBarRelocation() { verifyRuntimeAddressBarRelocation() }
    func testConsecutiveAddressBarRelocation() { verifyConsecutiveAddressBarRelocation() }
    func testNewTabPageAddressBarRelocation() { verifyNewTabPageAddressBarRelocation() }
    func testFloatingContentInsets() { verifyFloatingContentInsets() }
    func testUnifiedToggleInputKeyboardGeometry() { verifyUnifiedToggleInputKeyboardGeometry() }
    func testBottomPinnedInputSurvivesKeyboardDismissal() { verifyBottomPinnedInputSurvivesKeyboardDismissal() }
    func testWebInputChromeAfterAddressBarRelocation() { verifyWebInputChromeAfterAddressBarRelocation() }
    func testCollapsedChromeTransitions() { verifyCollapsedChromeTransitions() }
    func testScrollingPerformance() { verifyScrollingPerformance() }
    func testUnifiedToggleInputRotation() { verifyUnifiedToggleInputRotation() }
    func testTabSwitcherRotation() { verifyTabSwitcherRotation() }
    func testChromeDuringSlowLoading() { verifyChromeDuringSlowLoading() }
    func testChromeOnErrorPage() { verifyChromeOnErrorPage() }
    func testFloatingSwipeTabs() { verifyFloatingSwipeTabs() }
}

final class FindInPagePadTests: FloatingUIXCUITestCase {

    override var barPosition: FloatingUIBarPosition { .top }

    func testGlassWithFloatingFlagOff() { verifyIPadFindInPageUsesGlassWithFloatingFlagOff() }
}

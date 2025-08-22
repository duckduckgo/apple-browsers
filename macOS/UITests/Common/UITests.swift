//
//  UITests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation
import XCTest
import ObjectiveC

/// Helper values for the UI tests
enum UITests {
    /// Timeout constants for different test requirements
    enum Timeouts {
        /// Mostly, we use timeouts to wait for element existence. This is about 3x longer than needed, for CI resilience
        static let elementExistence: Double = 5.0
        /// The fire animation time has environmental dependencies, so we want to wait for completion so we don't try to type into it
        static let fireAnimation: Double = 30.0
    }

    /// A page simple enough to test favorite, bookmark, and history storage
    /// - Parameter title: The title of the page to match
    /// - Parameter body: The body of the page to match
    /// - Returns: A URL that can be served by `tests-server`
    static func simpleServedPage(titled title: String) -> URL {
        simpleServedPage(titled: title, body: "<p>Sample text for \(title)</p>")
    }

    static func simpleServedPage(titled title: String, body: String) -> URL {
        return URL.testsServer
            .appendingTestParameters(data: """
            <html>
            <head>
            <title>\(title)</title>
            </head>
            <body>
            \(body)
            </body>
            </html>
            """.utf8data)
    }

    static func randomPageTitle(length: Int) -> String {
        return String(UUID().uuidString.prefix(length))
    }

    /// This is intended for setting an autocomplete checkbox state that extends across all test cases and is only run once in the class override
    /// setup() of the case. Setting the autocomplete checkbox state for an individual test shouldn't start and terminate the app, as this function
    /// does.
    /// - Parameter requestedToggleState: How the autocomplete checkbox state should be set
    static func setAutocompleteToggleBeforeTestcaseRuns(_ requestedToggleState: Bool) {
        let app = XCUIApplication.setUp()

        let settings = app.menuItems["MainMenu.preferencesMenuItem"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Reset bookmarks menu item didn't become available in a reasonable timeframe."
        )

        settings.click()
        let generalPreferencesButton = app.buttons["PreferencesSidebar.generalButton"]
        let autocompleteToggle = app.checkBoxes["PreferencesGeneralView.showAutocompleteSuggestions"]
        XCTAssertTrue(
            generalPreferencesButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The user settings appearance section button didn't become available in a reasonable timeframe."
        )
        generalPreferencesButton.click(forDuration: 0.5, thenDragTo: generalPreferencesButton)

        let currentToggleState = try? XCTUnwrap(
            autocompleteToggle.value as? Bool,
            "It wasn't possible to get the \"Autocomplete\" value as a Bool"
        )

        switch (requestedToggleState, currentToggleState) { // Click autocomplete toggle if it is different than our request
        case (false, true), (true, false):
            autocompleteToggle.click()
        default:
            break
        }
        app.terminate()
    }

    /// A debug function that is going to need some other functionality in order to be useful for debugging address bar focus issues
    static func openVanillaBrowser() {
        let app = XCUIApplication.setUp()
        let openVanillaBrowser = app.menuItems["MainMenu.openVanillaBrowser"]
        openVanillaBrowser.clickAfterExistenceTestSucceeds()
        app.typeKey("w", modifierFlags: [.command, .option])
    }

    /// Avoid some first-run states that we aren't testing.
    static func firstRun() {
        let notificationCenter = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        if notificationCenter.exists { // If tests-server is asking for network permissions, deny them.
            notificationCenter.typeKey(.escape, modifierFlags: [])
        }
        let app = XCUIApplication.setUp()
        app.typeKey("n", modifierFlags: .command)
        app.typeKey("w", modifierFlags: [.command, .option])
        app.terminate()
    }
}

class TestFailureObserver: NSObject, XCTestObservation {
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        print("Failed test with name: \(testCase.name)")
        let screenshotName = "\(testCase.name)-failure"
        testCase.takeScreenshot(screenshotName)
    }
}

class UITestCase: XCTestCase {
    var app: XCUIApplication!

    private static let failureObserver = TestFailureObserver()

    override class func setUp() {
        setupXCPointerEventPathSwizzling()
        super.setUp()
        XCTestObservationCenter.shared.addTestObserver(failureObserver)
    }

    override class func tearDown() {
        XCTestObservationCenter.shared.removeTestObserver(failureObserver)
        super.tearDown()
    }

    /// Swizzles XCPointerEventPath private methods to call original implementation
    /// Uses once token pattern to ensure swizzling happens only once
    private static func setupXCPointerEventPathSwizzling() {
        // Using static variable for once semantics (equivalent to dispatch_once)
        struct OnceToken {
            static let token: Void = {
                guard let pointerEventPathClass = NSClassFromString("XCPointerEventPath") else {
                    print("Warning: XCPointerEventPath class not found for swizzling")
                    return
                }

                swizzleMethod(
                    class: pointerEventPathClass,
                    originalSelector: NSSelectorFromString("pressButton:atOffset:clickCount:"),
                    swizzledSelector: #selector(swizzled_pressButton)
                )

                swizzleMethod(
                    class: pointerEventPathClass,
                    originalSelector: NSSelectorFromString("releaseButton:atOffset:clickCount:"),
                    swizzledSelector: #selector(swizzled_releaseButton)
                )
            }()

            /// Helper method to perform method swizzling
            /// - Parameters:
            ///   - class: The class containing the method to swizzle
            ///   - originalSelector: The original method selector
            ///   - swizzledSelector: The replacement method selector
            private static func swizzleMethod(class: AnyClass, originalSelector: Selector, swizzledSelector: Selector) {
                guard let originalMethod = class_getInstanceMethod(`class`, originalSelector),
                      var swizzledMethod = class_getInstanceMethod(UITestCase.self, swizzledSelector) else {
                    print("Warning: Could not find methods for swizzling \(originalSelector) and \(swizzledSelector)")
                    return
                }

                let didAddMethod = class_addMethod(
                    `class`,
                    swizzledSelector,
                    method_getImplementation(swizzledMethod),
                    method_getTypeEncoding(swizzledMethod)
                )

                if didAddMethod {
                    swizzledMethod = class_getInstanceMethod(`class`, swizzledSelector)!
                }
                method_exchangeImplementations(originalMethod, swizzledMethod)
            }
        }

        // Accessing the static property ensures the closure runs exactly once
        _ = OnceToken.token
    }

}

// MARK: - XCPointerEventPath Swizzled Methods

extension UITestCase {

    @TaskLocal static var shouldReplaceButtonWithMiddleMouseButton: Bool = false

    /// Swizzled implementation of pressButton:atOffset:clickCount:
    @objc dynamic private func swizzled_pressButton(_ button: UInt64, at offset: Double, clickCount: UInt64) {
        var button = button
        if Self.shouldReplaceButtonWithMiddleMouseButton {
            button = 3
        }
        self.swizzled_pressButton(button, at: offset, clickCount: clickCount)
    }

    /// Swizzled implementation of releaseButton:atOffset:clickCount:
    @objc dynamic private func swizzled_releaseButton(_ button: UInt64, at offset: Double, clickCount: UInt64) {
        var button = button
        if Self.shouldReplaceButtonWithMiddleMouseButton {
            button = 3
        }
        self.swizzled_releaseButton(button, at: offset, clickCount: clickCount)
    }
}

extension XCTestCase {
    func takeScreenshot(_ name: String) {
        let fullScreenshot = XCUIScreen.main.screenshot()
        let screenshot = XCTAttachment(screenshot: fullScreenshot)
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func assertElement(_ element: XCUIElement, hasValue value: CVarArg, file: StaticString = #file, line: UInt = #line) {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(XCUIElement.value), value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: UITests.Timeouts.elementExistence)
        XCTAssertEqual(result, .completed, "Unexpected status field text content after a \"Find Next\" operation.")
    }
}

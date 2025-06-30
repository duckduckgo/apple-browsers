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
    /// - Returns: A URL that can be served by `tests-server`
    static func simpleServedPage(titled title: String) -> URL {
        return URL.testsServer
            .appendingTestParameters(data: """
            <html>
            <head>
            <title>\(title)</title>
            </head>
            <body>
            <p>Sample text for \(title)</p>
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
    func testCaseWillStart(_ testCase: XCTestCase) {
        testCase.addUIInterruptionMonitor(withDescription: "UITestCase Interruption Monitor") { [weak testCase] element -> Bool in
            return testCase?.handleInterruption(element) ?? false
        }
    }
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        testCase.log("Failed test with name: \(testCase.name)")
        let screenshotName = "\(testCase.name)-failure"
        testCase.takeScreenshot(screenshotName)
    }
}

class UITestCase: XCTestCase {
    private static let failureObserver = TestFailureObserver()
    
    private static let swizzleCompactDescriptionOnce: Void = {
        guard let originalMethod = class_getInstanceMethod(XCUIElement.self, NSSelectorFromString("compactDescription")),
              let swizzledMethod = class_getInstanceMethod(XCUIElement.self, #selector(XCUIElement.xcui_compactDescription)) else {
            print("Failed to get methods for swizzling compactDescription")
            return
        }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()
    
    private static let swizzleElementSnapshotOnce: Void = {
        guard let originalMethod = class_getInstanceMethod(NSClassFromString("XCElementSnapshot")!, NSSelectorFromString("compactDescription")),
              let swizzledMethod = class_getInstanceMethod(NSObject.self, #selector(NSObject.swizzled_compactDescription)) else {
            print("Failed to get methods for swizzling XCUIElementSnapshot compactDescription")
            return
        }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    override class func setUp() {
        super.setUp()
        XCTestObservationCenter.shared.addTestObserver(failureObserver)
        
        // Trigger one-time swizzling
//        _ = swizzleCompactDescriptionOnce
//        _ = swizzleElementSnapshotOnce
    }

    override func setUp() {

    }

    override class func tearDown() {
        XCTestObservationCenter.shared.removeTestObserver(failureObserver)
        super.tearDown()
    }
    
}

extension XCUIElement {

    @objc dynamic func xcui_compactDescription() -> String {
        guard let snapshot = try? self.snapshot() else {
            // Fallback to original implementation if snapshot is unavailable
            return self.xcui_compactDescription()
        }

        return snapshot.jsonDescription
    }
}

extension NSObject {

    @objc dynamic func swizzled_compactDescription() -> String {
        return (self as! XCUIElementSnapshot).jsonDescription
    }
}

extension XCUIElementSnapshot {
    var jsonDescription: String {
        let keys = ["identifier", "elementType", "title", "label", "value", "frame"]
        let snapshotDict = self.toDictionary(keys: keys)
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: snapshotDict, options: [])
            return String(data: jsonData, encoding: .utf8) ?? "Failed to encode JSON"
        } catch {
            return "JSON serialization error: \(error.localizedDescription)"
        }
    }
    
}

extension XCTestCase {

    /// Handle system interruptions during UI tests
    /// Override this method in subclasses to provide custom interruption handling
    func handleInterruption(_ element: XCUIElement) -> Bool {
        log("🔴 UITestCase: Handling interruption - \(element.description)")

        // Capture screenshot of the interrupting element
        attachInterruptionScreenshot(element)

        return false
    }

    /// Capture and attach a screenshot of the interrupting element
    private func attachInterruptionScreenshot(_ element: XCUIElement) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let screenshotName = "interruption-\(timestamp)"

        // Try to get element screenshot first, fallback to full screen
        let screenshot: XCUIScreenshot
        if element.exists {
            screenshot = element.screenshot()
        } else {
            screenshot = XCUIScreen.main.screenshot()
        }

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = screenshotName
        attachment.lifetime = .keepAlways

        // Add to current test context
        add(attachment)
    }

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

    func log(_ message: String) {
        XCTContext.current.recordActivityMessage(message)
    }

    class func log(_ message: String) {
        XCTContext.current.recordActivityMessage(message)
    }

}

extension XCTContext {

    func recordActivityMessage(_ message: String) {
        _=self.perform(NSSelectorFromString("_recordActivityMessageWithFormat:"), with: message.replacingOccurrences(of: "%", with: "%%"))
    }

    static var current: XCTContext! {
        return self.perform(NSSelectorFromString("currentContext"))?.takeUnretainedValue() as? XCTContext
    }
}

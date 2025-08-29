//
//  XCUIElementExtension.swift
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

import XCTest

extension XCUIElement {
    // https://stackoverflow.com/a/63089781/119717
    // Licensed under https://creativecommons.org/licenses/by-sa/4.0/
    // Credit: Adil Hussain

    /**
     * Waits the specified amount of time for the element’s `exists` property to become `false`.
     *
     * - Parameter timeout: The amount of time to wait.
     * - Returns: `false` if the timeout expires without the element coming out of existence.
     */
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let timeStart = Date().timeIntervalSince1970

        while Date().timeIntervalSince1970 <= (timeStart + timeout) {
            if !exists { return true }
        }

        return false
    }

    /// On some individual systems, strings which contain a ":" do not type the ":" when the string is entirely typed with `typeText(...)` into the
    /// address bar,
    /// wherever the ":" occurs in the string. This function stops before the ":" character and then types it with `typeKey(...)` as a workaround for
    /// this bug or unknown system setting.
    /// - Parameters:
    ///   - url: The URL to be typed into the address bar
    ///   - pressingEnter: If the `enter` key should not be pressed after typing this URL in, set this optional parameter to `false`, otherwise it
    /// will be pressed.
    func typeURL(_ url: URL, pressingEnter: Bool = true) {
        let urlString = url.absoluteString
        let urlParts = urlString.split(separator: ":")
        var completedURLSections = 0
        for urlPart in urlParts {
            self.typeText(String(urlPart))
            completedURLSections += 1
            if completedURLSections != urlParts.count {
                self.typeKey(":", modifierFlags: [])
            }
        }
        if pressingEnter {
            self.typeText("\r")
        }
    }

    func pasteURL(_ url: URL, pressingEnter: Bool = true) {
        // Store current pasteboard contents
        let originalTypes = NSPasteboard.general.types ?? []
        var originalContents: [NSPasteboard.PasteboardType: Data] = [:]

        for type in originalTypes {
            if let data = NSPasteboard.general.data(forType: type) {
                originalContents[type] = data
            }
        }

        defer {
            // Restore original pasteboard contents
            NSPasteboard.general.clearContents()
            NSPasteboard.general.declareTypes(originalTypes, owner: nil)
            for (type, data) in originalContents {
                NSPasteboard.general.setData(data, forType: type)
            }
        }

        let urlString = url.absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareTypes([.URL, .string], owner: nil)
        (url as NSURL).write(to: NSPasteboard.general)
        NSPasteboard.general.setString(urlString, forType: .string)

        self.typeKey("v", modifierFlags: [.command])
        if pressingEnter {
            self.typeText("\r")
        }
    }

    /// Check for the existence of the address bar and type a URL into it if it passes. Although it doesn't really make sense to restrict its usage to
    /// the address bar, it is only foreseen and recommended for use with the address bar.
    /// - Parameters:
    ///   - url: The URL to be typed into the address bar (or other element, for which use with this function should be seen as experimental)
    ///   - pressingEnter: If the `enter` key should not be pressed after typing this URL in, set this optional parameter to `false`, otherwise it
    /// will be pressed.
    func typeURLAfterExistenceTestSucceeds(_ url: URL, pressingEnter: Bool = true) {
        XCTAssertTrue(
            self.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The element \(self.debugDescription) didn't load with the expected title in a reasonable timeframe."
        )
        self.typeURL(url, pressingEnter: pressingEnter)
    }

    func clickAfterExistenceTestSucceeds() {
        XCTAssertTrue(
            self.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "\(self.debugDescription) didn't load with the expected title in a reasonable timeframe."
        )
        self.click()
    }

    func hoverAfterExistenceTestSucceeds() {
        XCTAssertTrue(
            self.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "\(self.debugDescription) didn't load with the expected title in a reasonable timeframe."
        )
        self.hover()
    }

    /// Toggles a checkbox or switch element to the desired boolean value if needed.
    /// Supports value types: String ("1"/"on"), NSNumber (non-zero), or falls back to single click.
    func toggleCheckboxIfNeeded(to enabled: Bool, ensureHittable: (XCUIElement) -> Void) {
        if !exists {
            ensureHittable(self)
        }
        XCTAssertTrue(self.exists, "Control should exist before toggling")
        if let valueString = self.value as? String {
            let isOn = valueString == "1" || valueString.lowercased() == "on"
            if isOn == enabled { return }
        } else if let valueNumber = self.value as? NSNumber {
            let isOn = valueNumber.intValue != 0
            if isOn == enabled { return }
        } else {
            XCTFail("\(self.value ??? "<nil>") (\(self.value.map { type(of: $0) } ??? "")) is not a String or NSNumber")
        }
        if !isHittable {
            ensureHittable(self)
        }
        self.click()
    }

    public var tabs: XCUIElementQuery {
        var element = self
        if element is XCUIApplication {
            element = windows.firstMatch
        }

        return element.tabGroups["TabBarViewController.CollectionView"].radioButtons
    }

    func closeTab() throws {
        // Hover the tab to reveal its close ("x") button
        self.hover()

        XCTAssertTrue(self.exists)
        let tabFrame = self.frame

        let normalizedX = (tabFrame.width - 12) / tabFrame.width
        let normalizedY = 0.5

        let coordinate = self.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: normalizedY))
        coordinate.click()
    }

    /// Performs a middle mouse click on the element
    func middleClick() {
        UITestCase.$shouldReplaceButtonWithMiddleMouseButton.withValue(true) {
            rightClick()
        }
    }

    /// Wait for a property of the element to contain a specific substring
    /// - Parameters:
    ///   - keyPath: The key path to the property to check (e.g., \.value, \.label, \.title)
    ///   - substring: The substring that should be contained in the property
    ///   - timeout: Maximum time to wait (default: 30 seconds)
    /// - Returns: True if the condition is met within the timeout, false otherwise
    @discardableResult
    func wait(for keyPath: PartialKeyPath<XCUIElement>,
              contains substring: String,
              timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: .keyPath(keyPath, contains: substring), object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for a property of the element to equal a specific value
    /// - Parameters:
    ///   - keyPath: The key path to the property to check (e.g., \.value, \.label, \.title)
    ///   - value: The value that the property should equal
    ///   - timeout: Maximum time to wait (default: 30 seconds)
    /// - Returns: True if the condition is met within the timeout, false otherwise
    @discardableResult
    func wait<V: CVarArg>(for keyPath: PartialKeyPath<XCUIElement>,
                          equals value: V,
                          timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        let predicate = NSPredicate.keyPath(keyPath, equalTo: value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for a property of the element to equal a specific value
    /// - Parameters:
    ///   - predicate: NSPredicate to wait for
    ///   - timeout: Maximum time to wait (default: 30 seconds)
    /// - Returns: True if the condition is met within the timeout, false otherwise
    @discardableResult
    func wait(for predicate: NSPredicate, timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

}

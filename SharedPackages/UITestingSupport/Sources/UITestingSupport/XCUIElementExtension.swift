//
//  XCUIElementExtension.swift
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

import CoreGraphics
import XCTest

public extension XCUIElement {

    /// Waits for a property of the element to contain a substring.
    @discardableResult
    func wait(for keyPath: PartialKeyPath<XCUIElement>,
              contains substring: String,
              timeout: TimeInterval = UITestTimeouts.navigation) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: .keyPath(keyPath, contains: substring), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits for a property of the element to equal a value.
    @discardableResult
    func wait<V: CVarArg>(for keyPath: PartialKeyPath<XCUIElement>,
                          equals value: V,
                          timeout: TimeInterval = UITestTimeouts.navigation) -> Bool {
        let predicate = NSPredicate.keyPath(keyPath, equalTo: value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits for a predicate to match the element.
    @discardableResult
    func wait(for predicate: NSPredicate, timeout: TimeInterval = UITestTimeouts.navigation) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Scrolls upward until the supplied element is hittable or the timeout expires.
    func swipeUpToReveal(_ element: XCUIElement,
                         timeout: TimeInterval = UITestTimeouts.elementExistence,
                         file: StaticString = #filePath,
                         line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        guard waitForExistence(timeout: deadline.timeIntervalSinceNow) else {
            XCTFail("Scrollable container did not appear: \(self)", file: file, line: line)
            return
        }

        while Date() < deadline {
            if element.isHittable {
                return
            }
            swipeUp()
        }

        XCTFail("Element was not revealed: \(element)", file: file, line: line)
    }

    private func waitForTextEntry(file: StaticString, line: UInt) -> Bool {
        guard wait(
            for: NSPredicate(format: "isHittable == true AND isEnabled == true"),
            timeout: UITestTimeouts.elementExistence) else {
            XCTFail("Text-entry element did not become tappable.", file: file, line: line)
            return false
        }
        return true
    }

    /// Focuses the element, enters text, and optionally presses Return.
    func enterText(_ text: String,
                   pressReturn: Bool = false,
                   file: StaticString = #filePath,
                   line: UInt = #line) {
        guard waitForTextEntry(file: file, line: line) else { return }
        tap()
        typeText(text)
        if pressReturn {
            typeText("\n")
        }
    }

    /// Replaces the current contents of a text-entry element by deleting backward from its insertion point.
    ///
    /// By default this uses the element's string value to determine how many characters to delete and assumes
    /// tapping the element places the insertion point after that value. Secure fields are supported when their
    /// masked value has the same character count as the current text. For a multiline field, callers can provide
    /// its known current text and a normalized tap offset that places the insertion point at the visual end.
    /// Fields that transform their displayed value as text is entered are not supported.
    /// Non-secure values are verified before pressing Return; secure values require a caller's outcome assertion.
    func replaceText(with text: String,
                     currentText: String? = nil,
                     normalizedTapOffset: CGVector? = nil,
                     pressReturn: Bool = false,
                     file: StaticString = #filePath,
                     line: UInt = #line) {
        guard waitForTextEntry(file: file, line: line) else { return }
        let supportedElementTypes: [XCUIElement.ElementType] = [.textField, .secureTextField, .searchField, .textView]
        guard supportedElementTypes.contains(elementType) else {
            XCTFail("Element does not support text replacement.", file: file, line: line)
            return
        }

        if let normalizedTapOffset {
            coordinate(withNormalizedOffset: normalizedTapOffset).tap()
        } else {
            tap()
        }

        guard let textToDelete = currentText ?? value as? String else {
            XCTFail("Text-entry element did not expose a string value.", file: file, line: line)
            return
        }

        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: textToDelete.count))
        typeText(text)
        if elementType != .secureTextField {
            guard wait(
                for: NSPredicate(format: "value == %@", text),
                timeout: UITestTimeouts.elementExistence) else {
                XCTFail("Text-entry element did not contain the replacement text.", file: file, line: line)
                return
            }
        }
        if pressReturn {
            typeText("\n")
        }
    }
}

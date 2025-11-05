//
//  XCUIElementQueryExtension.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import OSLog
import XCTest

extension XCUIElementQuery {

    /// Filter elements containing an element where a property contains a specific substring
    /// - Parameters:
    ///   - keyPath: The key path to the property to check (e.g., \.value, \.label, \.title)
    ///   - substring: The substring that should be contained in the property
    /// - Returns: A filtered XCUIElementQuery containing only matching elements
    func containing(_ keyPath: PartialKeyPath<XCUIElement>, containing substring: String) -> XCUIElementQuery {
        return containing(.keyPath(keyPath, contains: substring))
    }

    /// Filter elements containing an element where a property equals a specific value
    /// - Parameters:
    ///   - keyPath: The key path to the property to check (e.g., \.value, \.label, \.title)
    ///   - value: The value that the property should equal
    /// - Returns: A filtered XCUIElementQuery containing only matching elements
    func containing<V: CVarArg>(_ keyPath: PartialKeyPath<XCUIElement>, equalTo value: V) -> XCUIElementQuery {
        return containing(NSPredicate.keyPath(keyPath, equalTo: value))
    }

    /// Filter elements containing an element where a property equals a specific value
    /// - Parameters:
    ///   - elementType: Type of XCUIElement to contain
    ///   - predicate: The predicate to match against the element
    /// - Returns: A filtered XCUIElementQuery containing only matching elements
    func containing(_ elementType: XCUIElement.ElementType, where predicate: NSPredicate) -> XCUIElementQuery {
        return containing(.keyPath(\.elementType, equalTo: elementType.rawValue).and(predicate))
    }

    /// Filter elements matching a property contains a specific substring
    /// - Parameters:
    ///   - keyPath: The key path to the property to check (e.g., \.value, \.label, \.title)
    ///   - substring: The substring that should be contained in the property
    /// - Returns: A filtered XCUIElementQuery containing only matching elements
    func matching(_ keyPath: PartialKeyPath<XCUIElement>, containing substring: String) -> XCUIElementQuery {
        return matching(.keyPath(keyPath, contains: substring))
    }

    /// Filter elements matching a property equals a specific value
    /// - Parameters:
    ///   - keyPath: The key path to the property to check (e.g., \.value, \.label, \.title)
    ///   - value: The value that the property should equal
    /// - Returns: A filtered XCUIElementQuery containing only matching elements
    func matching<V: CVarArg>(_ keyPath: PartialKeyPath<XCUIElement>, equalTo value: V) -> XCUIElementQuery {
        return matching(NSPredicate.keyPath(keyPath, equalTo: value))
    }

    /// Element matching where a property contains a specific substring
    /// - Parameters:
    ///   - keyPath: The key path to the property to check (e.g., \.value, \.label, \.title)
    ///   - substring: The substring that should be contained in the property
    /// - Returns: A filtered XCUIElement matching the criteria
    func element(matching keyPath: PartialKeyPath<XCUIElement>, containing substring: String) -> XCUIElement {
        return element(matching: .keyPath(keyPath, contains: substring))
    }

    /// Element matching a property equals a specific value
    /// - Parameters:
    ///   - keyPath: The key path to the property to check (e.g., \.value, \.label, \.title)
    ///   - value: The value that the property should equal
    /// - Returns: A filtered XCUIElement matching the criteria
    func element<V: CVarArg>(matching keyPath: PartialKeyPath<XCUIElement>, equalTo value: V) -> XCUIElement {
        return element(matching: NSPredicate.keyPath(keyPath, equalTo: value))
    }

    // MARK: - Waiting Methods

    /// Wait for a predicate condition to be met on this element query
    /// - Parameters:
    ///   - predicate: The predicate to evaluate against this query
    ///   - timeout: Maximum time to wait (default: 30 seconds)
    /// - Returns: True if the condition is met within the timeout, false otherwise
    @discardableResult
    func wait(for predicate: NSPredicate, timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for a KeyPath property to equal a specific value on this element query
    /// - Parameters:
    ///   - keyPath: The key path to the property to check (e.g., \.count)
    ///   - value: The value that the property should equal
    ///   - timeout: Maximum time to wait (default: 30 seconds)
    /// - Returns: True if the condition is met within the timeout, false otherwise
    @discardableResult
    func wait<V: CVarArg & Equatable>(for keyPath: PartialKeyPath<XCUIElementQuery>,
                                      equals value: V,
                                      timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        return wait(for: NSPredicate.keyPath(keyPath, equalTo: value), timeout: timeout)
    }

    /// Wait for a KeyPath numeric property to be within a range on this element query
    /// - Parameters:
    ///   - keyPath: The key path to the numeric property to check (e.g., \.count)
    ///   - range: The range to check against (supports various range types)
    ///   - timeout: Maximum time to wait (default: 30 seconds)
    /// - Returns: True if the condition is met within the timeout, false otherwise
    @discardableResult
    func wait<V: CVarArg & Comparable>(for keyPath: PartialKeyPath<XCUIElementQuery>,
                                       in range: ClosedRange<V>,
                                       timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        return wait(for: NSPredicate.keyPath(keyPath, in: range), timeout: timeout)
    }

    /// Wait for a KeyPath numeric property to be within a half-open range on this element query
    @discardableResult
    func wait<V: CVarArg & Comparable>(for keyPath: PartialKeyPath<XCUIElementQuery>,
                                       in range: Range<V>,
                                       timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        return wait(for: NSPredicate.keyPath(keyPath, in: range), timeout: timeout)
    }

    /// Wait for a KeyPath numeric property to be greater than or equal to a value on this element query
    @discardableResult
    func wait<V: CVarArg & Comparable>(for keyPath: PartialKeyPath<XCUIElementQuery>,
                                       in range: PartialRangeFrom<V>,
                                       timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        return wait(for: NSPredicate.keyPath(keyPath, in: range), timeout: timeout)
    }

    /// Wait for a KeyPath numeric property to be less than a value on this element query
    @discardableResult
    func wait<V: CVarArg & Comparable>(for keyPath: PartialKeyPath<XCUIElementQuery>,
                                       in range: PartialRangeUpTo<V>,
                                       timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        return wait(for: NSPredicate.keyPath(keyPath, in: range), timeout: timeout)
    }

    /// Wait for a KeyPath numeric property to be less than or equal to a value on this element query
    @discardableResult
    func wait<V: CVarArg & Comparable>(for keyPath: PartialKeyPath<XCUIElementQuery>,
                                       in range: PartialRangeThrough<V>,
                                       timeout: TimeInterval = UITests.Timeouts.navigation) -> Bool {
        return wait(for: NSPredicate.keyPath(keyPath, in: range), timeout: timeout)
    }
}

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

import XCTest

public extension XCUIElement {

    /// Swipes up to reveal a row in a list, then waits for it to become tappable.
    func revealRow(_ row: XCUIElement, timeout: TimeInterval = UITestTimeouts.navigation) -> Bool {
        for _ in 0..<5 {
            if row.exists && row.isHittable {
                return true
            }
            swipeUp()
        }
        let hittable = NSPredicate { _, _ in row.exists && row.isHittable }
        return row.wait(for: hittable, timeout: timeout)
    }

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
}

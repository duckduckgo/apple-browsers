//
//  WebExtensionWindowOrderTests.swift
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
@testable import WebExtensions

@MainActor
final class WebExtensionWindowOrderTests: XCTestCase {

    private let order = WebExtensionWindowOrder()
    private let context = "context"

    private func identifiers(of windows: [AnyObject]) -> [ObjectIdentifier] {
        windows.map { ObjectIdentifier($0) }
    }

    func testWindowsKeepTheOrderTheyWereHandedToWebKit() {
        let first = NSObject()
        let second = NSObject()
        let third = NSObject()

        order.register(second, in: context)
        order.register(third, in: context)
        order.register(first, in: context)

        XCTAssertEqual(identifiers(of: order.windows(in: context)), identifiers(of: [second, third, first]))
    }

    func testRegisteringAWindowAgainKeepsItsPlace() {
        let first = NSObject()
        let second = NSObject()
        order.register(first, in: context)
        order.register(second, in: context)

        order.register(first, in: context)

        XCTAssertEqual(identifiers(of: order.windows(in: context)), identifiers(of: [first, second]))
    }

    func testEachContextOrdersItsOwnWindows() {
        let first = NSObject()
        let second = NSObject()
        let otherContext = "other"
        order.register(first, in: context)
        order.register(second, in: context)

        order.register(second, in: otherContext)
        order.register(first, in: otherContext)

        XCTAssertEqual(identifiers(of: order.windows(in: context)), identifiers(of: [first, second]))
        XCTAssertEqual(identifiers(of: order.windows(in: otherContext)), identifiers(of: [second, first]))
    }

    func testAClosedWindowLeavesTheOrder() {
        let first = NSObject()
        var second: NSObject? = NSObject()
        let third = NSObject()
        order.register(first, in: context)
        order.register(second!, in: context)
        order.register(third, in: context)

        second = nil

        XCTAssertEqual(identifiers(of: order.windows(in: context)), identifiers(of: [first, third]))
    }
}

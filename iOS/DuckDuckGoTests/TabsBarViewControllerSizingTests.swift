//
//  TabsBarViewControllerSizingTests.swift
//  DuckDuckGo
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

@testable import DuckDuckGo

final class TabsBarViewControllerSizingTests: XCTestCase {

    private let accuracy: CGFloat = 0.001
    private let minWidth = TabsBarViewController.Constants.minItemWidth

    private func itemWidth(_ available: CGFloat, _ visibleItems: Int, maxWidth: CGFloat) -> CGFloat {
        TabsBarViewController.itemWidth(availableWidth: available, visibleItems: visibleItems, minWidth: minWidth, maxWidth: maxWidth)
    }

    func testTabsAreCappedAtMaxWidth() {
        XCTAssertEqual(itemWidth(900, 1, maxWidth: 300), 300, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 2, maxWidth: 300), 300, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 3, maxWidth: 300), 300, accuracy: accuracy)
    }

    func testTabsFillEquallyWhenMaxWidthDoesNotBind() {
        XCTAssertEqual(itemWidth(900, 4, maxWidth: 300), 225, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 6, maxWidth: 300), 150, accuracy: accuracy)
    }

    func testTabsFloorAtMinWidth() {
        XCTAssertEqual(itemWidth(900, 8, maxWidth: 300), 120, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 20, maxWidth: 300), 120, accuracy: accuracy)
    }

    func testMinWidthWinsWhenMaxBelowFloor() {
        XCTAssertEqual(itemWidth(300, 1, maxWidth: 99), 120, accuracy: accuracy)
    }

    func testZeroVisibleItemsReturnsZero() {
        XCTAssertEqual(itemWidth(900, 0, maxWidth: 300), 0, accuracy: accuracy)
    }
}

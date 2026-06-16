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
    private let minWidth = TabsBarViewController.Constants.minItemWidth          // 120
    private let maxFraction = TabsBarViewController.Constants.maxItemWidthFraction // 1/3

    private func width(_ available: CGFloat, _ visibleItems: Int) -> CGFloat {
        TabsBarViewController.itemWidth(availableWidth: available, visibleItems: visibleItems, minWidth: minWidth, maxWidthFraction: maxFraction)
    }

    func testFirstThreeTabsAreEachOneThird() {
        // 1, 2 and 3 tabs all stay at exactly 1/3 of the strip; they do not stretch to fill.
        let available: CGFloat = 900
        XCTAssertEqual(width(available, 1), 300, accuracy: accuracy)
        XCTAssertEqual(width(available, 2), 300, accuracy: accuracy)
        XCTAssertEqual(width(available, 3), 300, accuracy: accuracy)
    }

    func testOneThirdCapIsWidthIndependent() {
        // The "first 3 tabs are 1/3" rule holds for any strip width.
        XCTAssertEqual(width(720, 1), 240, accuracy: accuracy)
        XCTAssertEqual(width(720, 3), 240, accuracy: accuracy)
        XCTAssertEqual(width(1200, 2), 400, accuracy: accuracy)
    }

    func testFourPlusTabsFillEqually() {
        let available: CGFloat = 900
        XCTAssertEqual(width(available, 4), 225, accuracy: accuracy) // 1/4
        XCTAssertEqual(width(available, 6), 150, accuracy: accuracy) // 1/6
    }

    func testTabsFloorAtMinWidth() {
        // 8 tabs in 900pt would be 112.5pt each; floored to the 120pt minimum (strip then scrolls).
        XCTAssertEqual(width(900, 8), 120, accuracy: accuracy)
        // Many tabs stay pinned at the minimum.
        XCTAssertEqual(width(900, 20), 120, accuracy: accuracy)
    }

    func testMinWidthWinsOnNarrowStrip() {
        // When the strip is too narrow for the 1/3 cap (100pt) and the 120pt floor to coexist,
        // the floor wins: a single tab is 120pt and the strip scrolls rather than shrinking.
        XCTAssertEqual(width(300, 1), 120, accuracy: accuracy)
    }

    func testZeroVisibleItemsReturnsZero() {
        XCTAssertEqual(width(900, 0), 0, accuracy: accuracy)
    }
}

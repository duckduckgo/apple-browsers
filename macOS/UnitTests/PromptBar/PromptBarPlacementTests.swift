//
//  PromptBarPlacementTests.swift
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

import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PromptBarPlacementTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    func testWhenScreenIsWideThenPreferredWidthIsUsedAndBarIsCentered() {
        let frame = PromptBarPlacement.frame(forContentHeight: 56, in: screen)

        XCTAssertEqual(frame.width, PromptBarPlacement.preferredWidth)
        XCTAssertEqual(frame.midX, screen.midX)
    }

    func testWhenScreenIsNarrowerThanPreferredWidthThenMarginsAreHonored() {
        let narrow = NSRect(x: 0, y: 0, width: 400, height: 800)

        let frame = PromptBarPlacement.frame(forContentHeight: 56, in: narrow)

        XCTAssertEqual(frame.width, narrow.width - PromptBarPlacement.horizontalScreenMargin * 2)
        XCTAssertEqual(frame.midX, narrow.midX)
    }

    func testWhenPlacedThenTopEdgeSitsAtTheTopOffsetRatio() {
        let frame = PromptBarPlacement.frame(forContentHeight: 56, in: screen)

        let expectedTop = screen.maxY - (screen.height * PromptBarPlacement.topOffsetRatio).rounded()
        XCTAssertEqual(frame.maxY, expectedTop)
    }

    func testWhenScreenIsOffsetThenFrameIsPlacedWithinThatScreen() {
        let secondScreen = NSRect(x: 1440, y: 200, width: 1200, height: 800)

        let frame = PromptBarPlacement.frame(forContentHeight: 56, in: secondScreen)

        XCTAssertTrue(secondScreen.contains(frame), "Bar should stay inside the target screen")
    }

    func testWhenContentIsTallerThanScreenThenHeightIsClampedAndStaysOnScreen() {
        let frame = PromptBarPlacement.frame(forContentHeight: 5000, in: screen)

        XCTAssertEqual(frame.height, screen.height)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
    }

    func testWhenContentIsTallEnoughToOverflowBelowThenFrameIsPushedUp() {
        // Tall enough that the default top offset would put the bottom edge below the screen.
        let frame = PromptBarPlacement.frame(forContentHeight: 800, in: screen)

        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
    }
}

//
//  UnifiedToggleInputToggleViewTests.swift
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
import UIKit
@testable import DuckDuckGo

final class UnifiedToggleInputToggleViewTests: XCTestCase {

    // Track layout for the cases below: search rest-center at 50, Duck.ai rest-center at 150,
    // so the midpoint sits at 100. Velocities are pt/s.
    private let searchCenterX: CGFloat = 50
    private let duckAICenterX: CGFloat = 150
    private let midpointX: CGFloat = 100

    func testWhenDraggedPastMidpointWithoutFlickThenSnapsToFarSide() {
        let sut = UnifiedToggleInputToggleView()

        let target = sut.resolveTargetMode(indicatorCenterX: 130, midpointX: midpointX, velocityX: 0)

        XCTAssertEqual(target, .aiChat)
    }

    func testWhenDraggedShortOfMidpointWithoutFlickThenSnapsBackToNearSide() {
        let sut = UnifiedToggleInputToggleView()

        let target = sut.resolveTargetMode(indicatorCenterX: 70, midpointX: midpointX, velocityX: 0)

        XCTAssertEqual(target, .search)
    }

    func testWhenFlickedRightFastThenCommitsToAIChatEvenWhenLeftOfMidpoint() {
        let sut = UnifiedToggleInputToggleView()

        // Indicator still on the search side, but a fast rightward flick should win.
        let target = sut.resolveTargetMode(indicatorCenterX: 60, midpointX: midpointX, velocityX: 1500)

        XCTAssertEqual(target, .aiChat)
    }

    func testWhenFlickedLeftFastThenCommitsToSearchEvenWhenRightOfMidpoint() {
        let sut = UnifiedToggleInputToggleView()

        // Indicator already on the Duck.ai side, but a fast leftward flick should win.
        let target = sut.resolveTargetMode(indicatorCenterX: 140, midpointX: midpointX, velocityX: -1500)

        XCTAssertEqual(target, .search)
    }

    func testWhenFlickVelocityBelowThresholdThenUsesPositionOnly() {
        let sut = UnifiedToggleInputToggleView()

        // Right of midpoint with only a gentle leftward drift: position decides → aiChat.
        let target = sut.resolveTargetMode(indicatorCenterX: 130, midpointX: midpointX, velocityX: -50)

        XCTAssertEqual(target, .aiChat)
    }
}

//
//  FloatingOmnibarTransitionMetricsTests.swift
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

final class FloatingOmnibarTransitionMetricsTests: XCTestCase {

    func testWhenFloatingUIIsOffThenDurationMatchesLegacyBottomAndTop() {
        XCTAssertEqual(FloatingOmnibarTransitionMetrics.duration(isBottom: true, isFloatingUIEnabled: false), 0.35)
        XCTAssertEqual(FloatingOmnibarTransitionMetrics.duration(isBottom: false, isFloatingUIEnabled: false), 0.25)
    }

    func testWhenFloatingUIIsOnThenDurationIsTheLegacyValueScaled() {
        let scale = FloatingOmnibarTransitionMetrics.floatingDurationScale
        XCTAssertEqual(
            FloatingOmnibarTransitionMetrics.duration(isBottom: true, isFloatingUIEnabled: true),
            0.35 * scale,
            accuracy: 0.0001)
        XCTAssertEqual(
            FloatingOmnibarTransitionMetrics.duration(isBottom: false, isFloatingUIEnabled: true),
            0.25 * scale,
            accuracy: 0.0001)
    }

    func testWhenReturningFromTabSwitcherThenLiveToolbarRevealIsShorterThanTheMorph() {
        XCTAssertGreaterThan(TabSwitcherTransition.Constants.floatingToolbarRevealDuration, 0)
        XCTAssertLessThan(
            TabSwitcherTransition.Constants.floatingToolbarRevealDuration,
            TabSwitcherTransition.Constants.floatingDuration)
        XCTAssertGreaterThan(TabSwitcherTransition.Constants.floatingToolbarRevealScale, 0)
        XCTAssertLessThan(TabSwitcherTransition.Constants.floatingToolbarRevealScale, 1)
    }

    func testWhenOmnibarDetachesThenToolbarHeightShrinksBelowTheCombinedSlot() {
        let detached = BrowserToolbarView.totalHeight(withOmnibarHeight: 0, isFloating: true)
        let attached = BrowserToolbarView.totalHeight(withOmnibarHeight: 48, isFloating: true)
        XCTAssertGreaterThan(attached, detached)
    }

    func testWhenMinimalChromeUTIBecomesInactiveThenItAnchorsToScreenBottom() {
        let anchor = MainViewCoordinator.OmnibarInactiveAnchor.resolve(isMinimalChromeLayout: true)

        XCTAssertEqual(anchor, .screenBottom)
    }

    func testWhenRegularChromeUTIBecomesInactiveThenItAnchorsToToolbar() {
        let anchor = MainViewCoordinator.OmnibarInactiveAnchor.resolve(isMinimalChromeLayout: false)

        XCTAssertEqual(anchor, .toolbar)
    }
}

final class OmnibarDismissSupersessionTests: XCTestCase {

    @MainActor
    func testWhenReplacementDismissStopsInFlightThenPreviousNTPCleanupDoesNotRun() {
        let coordinator = MainViewCoordinator(parentController: UIViewController())
        var restoredNTPChrome = false
        coordinator.startOmnibarDismissForTesting {
            restoredNTPChrome = true
        }

        coordinator.stopInFlightOmnibarDismiss(runningInterruptCleanup: false)

        XCTAssertFalse(restoredNTPChrome)
    }

    @MainActor
    func testWhenDismissStopsWithoutReplacementThenNTPCleanupRuns() {
        let coordinator = MainViewCoordinator(parentController: UIViewController())
        var restoredNTPChrome = false
        coordinator.startOmnibarDismissForTesting {
            restoredNTPChrome = true
        }

        coordinator.stopInFlightOmnibarDismiss(runningInterruptCleanup: true)

        XCTAssertTrue(restoredNTPChrome)
    }
}

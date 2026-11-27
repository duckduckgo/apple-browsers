//
//  NewTabKeyboardGateTests.swift
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

@MainActor
final class NewTabKeyboardGateTests: XCTestCase {

    private var gate: NewTabKeyboardGate!
    private var focusCount = 0

    override func setUp() {
        super.setUp()
        gate = NewTabKeyboardGate()
        focusCount = 0
    }

    private func requestFocus() {
        gate.whenOpen { [weak self] in self?.focusCount += 1 }
    }

    func testWhenMomentNotReachedThenFocusWaits() {
        requestFocus()

        XCTAssertFalse(gate.isOpen)
        XCTAssertEqual(focusCount, 0)
    }

    func testWhenMomentReachedThenWaitingFocusRunsOnce() {
        requestFocus()
        requestFocus()

        gate.reachMoment()
        gate.reachMoment()

        XCTAssertEqual(focusCount, 2)
    }

    func testWhenGateIsOpenThenFocusRunsImmediately() {
        gate.reachMoment()

        requestFocus()

        XCTAssertEqual(focusCount, 1)
    }

    func testWhenHeldThenFocusWaitsPastTheMomentUntilReleased() {
        let release = gate.hold()
        requestFocus()

        gate.reachMoment()
        XCTAssertEqual(focusCount, 0)

        release()
        XCTAssertEqual(focusCount, 1)
    }

    func testWhenReleasedBeforeTheMomentThenFocusWaitsForTheMoment() {
        let release = gate.hold()
        requestFocus()

        release()
        XCTAssertEqual(focusCount, 0)

        gate.reachMoment()
        XCTAssertEqual(focusCount, 1)
    }

    func testWhenReleasedTwiceThenOtherHoldsStillApply() {
        let release = gate.hold()
        let otherRelease = gate.hold()
        gate.reachMoment()
        requestFocus()

        release()
        release()
        XCTAssertEqual(focusCount, 0)

        otherRelease()
        XCTAssertEqual(focusCount, 1)
    }

    func testWhenOpenedThenHoldsAndMomentNoLongerKeepFocusWaiting() {
        let release = gate.hold()
        requestFocus()

        gate.open()
        XCTAssertEqual(focusCount, 1)

        release()
        requestFocus()
        XCTAssertTrue(gate.isOpen)
        XCTAssertEqual(focusCount, 2)
    }
}

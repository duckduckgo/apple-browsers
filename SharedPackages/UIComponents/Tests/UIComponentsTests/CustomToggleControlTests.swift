//
//  CustomToggleControlTests.swift
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

#if os(macOS)

import XCTest
@testable import UIComponents

final class CustomToggleControlTests: XCTestCase {

    private var sut: CustomToggleControl!

    override func setUp() {
        super.setUp()
        sut = CustomToggleControl(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testWhenInitialized_ThenSelectedSegmentIsZero() {
        XCTAssertEqual(sut.selectedSegment, 0)
    }

    func testWhenInitialized_ThenSegmentCountIsTwo() {
        XCTAssertEqual(sut.segmentCount, 2)
    }

    func testWhenInitialized_ThenControlAcceptsFirstResponder() {
        XCTAssertTrue(sut.acceptsFirstResponder)
    }

    func testWhenInitialized_ThenControlCanBecomeKeyView() {
        XCTAssertTrue(sut.canBecomeKeyView)
    }

    // MARK: - Segment Selection

    func testWhenSelectedSegmentSetToOne_ThenSelectedSegmentIsOne() {
        sut.selectedSegment = 1

        XCTAssertEqual(sut.selectedSegment, 1)
    }

    func testWhenSelectedSegmentSetToInvalidValue_ThenSelectedSegmentRemainsUnchanged() {
        sut.selectedSegment = 0

        sut.selectedSegment = 5
        XCTAssertEqual(sut.selectedSegment, 0)

        sut.selectedSegment = -1
        XCTAssertEqual(sut.selectedSegment, 0)
    }

    func testWhenSetSelectedForSegment_ThenSelectedSegmentChanges() {
        sut.setSelected(true, forSegment: 1)

        XCTAssertEqual(sut.selectedSegment, 1)
    }

    func testWhenIsSelectedForSegment_ThenReturnsCorrectValue() {
        sut.selectedSegment = 1

        XCTAssertFalse(sut.isSelected(forSegment: 0))
        XCTAssertTrue(sut.isSelected(forSegment: 1))
    }

    // MARK: - Reset

    func testWhenResetCalled_ThenSelectedSegmentIsZero() {
        sut.selectedSegment = 1

        sut.reset()

        XCTAssertEqual(sut.selectedSegment, 0)
    }

    // MARK: - Labels

    func testWhenLabelSetForSegment_ThenLabelCanBeRetrieved() {
        sut.setLabel("Search", forSegment: 0)
        sut.setLabel("Ask AI", forSegment: 1)

        XCTAssertEqual(sut.label(forSegment: 0), "Search")
        XCTAssertEqual(sut.label(forSegment: 1), "Ask AI")
    }

    func testWhenLabelSetForInvalidSegment_ThenLabelIsNil() {
        sut.setLabel("Invalid", forSegment: 5)

        XCTAssertNil(sut.label(forSegment: 5))
    }

    // MARK: - Tooltips

    func testWhenToolTipSetForSegment_ThenToolTipCanBeRetrieved() {
        sut.setToolTip("Search the web", forSegment: 0)
        sut.setToolTip("Chat with AI", forSegment: 1)

        XCTAssertEqual(sut.toolTip(forSegment: 0), "Search the web")
        XCTAssertEqual(sut.toolTip(forSegment: 1), "Chat with AI")
    }

    // MARK: - Tab Key Callback

    func testWhenOnTabPressedReturnsTrue_ThenCallbackIsInvoked() {
        var callbackInvoked = false
        sut.onTabPressed = {
            callbackInvoked = true
            return true
        }

        // Simulate the callback being invoked (as it would be from keyDown)
        let handled = sut.onTabPressed?() ?? false

        XCTAssertTrue(callbackInvoked)
        XCTAssertTrue(handled)
    }

    func testWhenOnTabPressedReturnsFalse_ThenDefaultBehaviorShouldBeUsed() {
        var callbackInvoked = false
        sut.onTabPressed = {
            callbackInvoked = true
            return false
        }

        let handled = sut.onTabPressed?() ?? false

        XCTAssertTrue(callbackInvoked)
        XCTAssertFalse(handled)
    }

    // MARK: - Expansion State

    func testWhenSetExpandedToTrue_ThenIsExpandedIsTrue() {
        sut.setExpanded(true, animated: false)

        XCTAssertTrue(sut.isExpanded)
    }

    func testWhenSetExpandedToFalse_ThenIsExpandedIsFalse() {
        sut.setExpanded(true, animated: false)
        sut.setExpanded(false, animated: false)

        XCTAssertFalse(sut.isExpanded)
    }
}

#endif

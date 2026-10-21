//
//  NavigationBarBadgeAnimationViewTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NavigationBarBadgeAnimationViewTests: XCTestCase {

    var sut: NavigationBarBadgeAnimationView!

    override func setUp() {
        super.setUp()
        sut = NavigationBarBadgeAnimationView()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Prepare Animation Tests

    func testPrepareAnimation_cookiePopupManaged_createsBadgeNotificationContainer() {
        // When
        sut.prepareAnimation(.cookiePopupManaged)

        // Then
        XCTAssertNotNil(sut.animatedView, "Should create animated view")
        XCTAssertTrue(sut.animatedView is BadgeNotificationContainerView, "Should create BadgeNotificationContainerView for cookies")
    }

    func testPrepareAnimation_cookiePopupHidden_createsBadgeNotificationContainer() {
        // When
        sut.prepareAnimation(.cookiePopupHidden)

        // Then
        XCTAssertNotNil(sut.animatedView, "Should create animated view")
        XCTAssertTrue(sut.animatedView is BadgeNotificationContainerView, "Should create BadgeNotificationContainerView for hidden popup")
    }

    func testPrepareAnimation_trackersBlocked_createsBadgeNotificationContainer() {
        // When
        sut.prepareAnimation(.trackersBlocked(count: 10))

        // Then
        XCTAssertNotNil(sut.animatedView, "Should create animated view")
        XCTAssertTrue(sut.animatedView is BadgeNotificationContainerView, "Should create BadgeNotificationContainerView for trackers")
    }

    func testPrepareAnimation_trackersBlocked_configuresContainerWithCorrectCount() {
        // Given
        let count = 15

        // When
        sut.prepareAnimation(.trackersBlocked(count: count))

        // Then
        guard let container = sut.animatedView as? BadgeNotificationContainerView else {
            XCTFail("animatedView should be BadgeNotificationContainerView")
            return
        }

        XCTAssertEqual(container.trackerCount, count, "Should configure container with correct tracker count")
        XCTAssertTrue(container.useShieldIcon, "Should use shield icon for tracker notification")
        XCTAssertNotNil(container.textGenerator, "Should have text generator for counting animation")
    }

    func testPrepareAnimation_addsViewAsSubview() {
        // When
        sut.prepareAnimation(.trackersBlocked(count: 10))

        // Then
        XCTAssertEqual(sut.subviews.count, 1, "Should have one subview")
        XCTAssertEqual(sut.subviews.first, sut.animatedView, "Subview should be the animated view")
    }

    func testPrepareAnimation_removesExistingAnimation() {
        // Given - prepare first animation
        sut.prepareAnimation(.cookiePopupManaged)
        let firstView = sut.animatedView

        // When - prepare second animation
        sut.prepareAnimation(.trackersBlocked(count: 10))

        // Then
        XCTAssertNotEqual(sut.animatedView, firstView, "Should replace with new animated view")
        XCTAssertNil(firstView?.superview, "First view should be removed from superview")
    }

    // MARK: - Start Animation Tests

    func testStartAnimation_callsAnimatedViewStartAnimation() {
        // Given
        sut.prepareAnimation(.trackersBlocked(count: 10))
        let expectation = expectation(description: "Animation completion")

        // When
        sut.startAnimation {
            expectation.fulfill()
        }

        // Then - total animation is ~2.35s (0.3*2 + 1.75)
        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - Remove Animation Tests

    func testRemoveAnimation_removesAnimatedViewFromSuperview() {
        // Given
        sut.prepareAnimation(.trackersBlocked(count: 10))
        XCTAssertNotNil(sut.animatedView?.superview, "Should have superview initially")

        // When
        sut.removeAnimation()

        // Then
        XCTAssertNil(sut.animatedView?.superview, "Should be removed from superview")
    }
}

//
//  FireWindowSubscriptionPromoDelegateTests.swift
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

import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class FireWindowSubscriptionPromoDelegateTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Visibility Tests

    func testWhenVisibilityUpdatedToTrueThenDelegateIsVisible() {
        let delegate = FireWindowSubscriptionPromoDelegate()
        let source = NSObject()

        delegate.updateVisibility(true, for: source)

        XCTAssertTrue(delegate.isVisible)
    }

    func testWhenVisibilityUpdatedToFalseThenDelegateIsNotVisible() {
        let delegate = FireWindowSubscriptionPromoDelegate()
        let source = NSObject()

        delegate.updateVisibility(true, for: source)
        delegate.updateVisibility(false, for: source)

        XCTAssertFalse(delegate.isVisible)
    }

    func testWhenNoUpdatesThenDelegateIsNotVisible() {
        let delegate = FireWindowSubscriptionPromoDelegate()

        XCTAssertFalse(delegate.isVisible)
    }

    func testWhenVisibilityUpdatedThenPublisherEmitsCorrectValue() {
        let delegate = FireWindowSubscriptionPromoDelegate()
        let source = NSObject()

        let expectation = expectation(description: "Visibility emitted")
        var receivedVisible: Bool?
        delegate.isVisiblePublisher
            .dropFirst()
            .sink { visible in
                receivedVisible = visible
                expectation.fulfill()
            }
            .store(in: &cancellables)

        delegate.updateVisibility(true, for: source)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(try XCTUnwrap(receivedVisible))
    }

    func testResultWhenHiddenIsIgnoredWithNoCooldown() {
        let delegate = FireWindowSubscriptionPromoDelegate()

        XCTAssertEqual(delegate.resultWhenHidden, .ignored(cooldown: 0))
    }

    // MARK: - Multi-Window Tests

    func testWhenMultipleSourcesVisibleAndOneHidesThenDelegateRemainsVisible() {
        let delegate = FireWindowSubscriptionPromoDelegate()
        let sourceA = NSObject()
        let sourceB = NSObject()

        delegate.updateVisibility(true, for: sourceA)
        delegate.updateVisibility(true, for: sourceB)
        delegate.updateVisibility(false, for: sourceA)

        XCTAssertTrue(delegate.isVisible)
    }

    func testWhenAllSourcesHideThenDelegateIsNotVisible() {
        let delegate = FireWindowSubscriptionPromoDelegate()
        let sourceA = NSObject()
        let sourceB = NSObject()

        delegate.updateVisibility(true, for: sourceA)
        delegate.updateVisibility(true, for: sourceB)
        delegate.updateVisibility(false, for: sourceA)
        delegate.updateVisibility(false, for: sourceB)

        XCTAssertFalse(delegate.isVisible)
    }
}

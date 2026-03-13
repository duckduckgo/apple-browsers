//
//  SessionRestorePromoDelegateTests.swift
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

final class SessionRestorePromoDelegateTests: XCTestCase {

    private var coordinator: SessionRestorePromptCoordinatorMock!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        coordinator = SessionRestorePromptCoordinatorMock()
    }

    override func tearDown() {
        coordinator = nil
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Visibility Tests

    func testWhenSessionRestorePromptShownThenDelegateIsVisible() {
        let delegate = SessionRestorePromoDelegate(coordinator: coordinator)

        coordinator.state = .promptShown

        XCTAssertTrue(delegate.isVisible)
    }

    func testWhenSessionRestorePromptNotShownThenDelegateIsNotVisible() {
        let delegate = SessionRestorePromoDelegate(coordinator: coordinator)

        coordinator.state = .promptDismissed

        XCTAssertFalse(delegate.isVisible)
    }

    func testWhenSessionRestorePromptShownThenDelegatePublisherEmitsVisible() {
        let delegate = SessionRestorePromoDelegate(coordinator: coordinator)

        let expectation = expectation(description: "Visibility is emitted")
        var receivedVisible: Bool?
        delegate.isVisiblePublisher
            .dropFirst()
            .sink { visible in
                receivedVisible = visible
                expectation.fulfill()
            }
            .store(in: &cancellables)

        coordinator.state = .promptShown
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(try XCTUnwrap(receivedVisible))
    }

    func testWhenSessionRestorePromptDismissedThenDelegatePublisherEmitsNotVisible() {
        let coordinator = SessionRestorePromptCoordinatorMock()
        coordinator.state = .promptShown
        let delegate = SessionRestorePromoDelegate(coordinator: coordinator)

        let expectation = expectation(description: "Visibility is emitted")
        var receivedVisible: Bool?
        delegate.isVisiblePublisher
            .dropFirst()
            .sink { visible in
                receivedVisible = visible
                expectation.fulfill()
            }
            .store(in: &cancellables)

        coordinator.state = .promptDismissed
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(try XCTUnwrap(receivedVisible))
    }

    func testWhenSessionRestorePromptDismissedThenDelegateResultIsIgnoredWithNoCooldown() {
        let delegate = SessionRestorePromoDelegate(coordinator: coordinator)

        coordinator.state = .promptDismissed

        XCTAssertEqual(delegate.resultWhenHidden, .ignored(cooldown: 0))

    }

    func testWhenSessionRestorePromptRetractedThenDelegateResultIsNoChange() {
        let delegate = SessionRestorePromoDelegate(coordinator: coordinator)

        coordinator.state = .uiReady

        XCTAssertEqual(delegate.resultWhenHidden, .noChange)

    }
}

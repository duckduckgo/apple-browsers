//
//  BrokenSitePromptPresentationCoordinatorTests.swift
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

final class BrokenSitePromptPresentationCoordinatorTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testWhenNoPromptShown_ThenPromoIsNotVisible() {
        let coordinator = BrokenSitePromptPresentationCoordinator()

        XCTAssertFalse(coordinator.isVisible)
    }

    func testWhenPromptShown_ThenPromoBecomesVisible() {
        let coordinator = BrokenSitePromptPresentationCoordinator()

        coordinator.promptDidShow()

        XCTAssertTrue(coordinator.isVisible)
    }

    func testWhenPromptHidden_ThenPromoIsNoLongerVisible() {
        let coordinator = BrokenSitePromptPresentationCoordinator()

        coordinator.promptDidShow()
        coordinator.promptDidHide()

        XCTAssertFalse(coordinator.isVisible)
    }

    /// A stuck-visible promo would block every medium+ internal promo, so an unbalanced hide must still clear it.
    func testWhenHideCalledMoreOftenThanShow_ThenPromoIsNotStuckVisible() {
        let coordinator = BrokenSitePromptPresentationCoordinator()

        coordinator.promptDidShow()
        coordinator.promptDidShow()
        coordinator.promptDidHide()

        XCTAssertFalse(coordinator.isVisible)
    }

    func testWhenHiddenBeforeEverShown_ThenPromoStaysHidden() {
        let coordinator = BrokenSitePromptPresentationCoordinator()

        coordinator.promptDidHide()

        XCTAssertFalse(coordinator.isVisible)

        coordinator.promptDidShow()

        XCTAssertTrue(coordinator.isVisible)
    }

    func testWhenSubscribing_ThenCurrentVisibilityIsReplayed() {
        let coordinator = BrokenSitePromptPresentationCoordinator()
        coordinator.promptDidShow()

        var received: [Bool] = []
        coordinator.isVisiblePublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        XCTAssertEqual(received, [true])
    }

    func testWhenVisibilityChanges_ThenPublisherEmitsWithoutDuplicates() {
        let coordinator = BrokenSitePromptPresentationCoordinator()

        var received: [Bool] = []
        coordinator.isVisiblePublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        coordinator.promptDidShow()
        coordinator.promptDidShow()
        coordinator.promptDidHide()
        coordinator.promptDidHide()

        XCTAssertEqual(received, [false, true, false])
        XCTAssertFalse(coordinator.isVisible)
    }

    /// The limiter — not promo history — decides when the prompt may appear again, so hiding must not
    /// permanently retire the promo the way `.actioned` or a bare `.ignored()` would.
    func testWhenHidden_ThenResultDoesNotPermanentlyRetireThePromo() {
        let coordinator = BrokenSitePromptPresentationCoordinator()

        guard case .ignored(let cooldown) = coordinator.resultWhenHidden else {
            return XCTFail("Expected .ignored, got \(coordinator.resultWhenHidden)")
        }
        XCTAssertEqual(cooldown, 0)
    }
}

//
//  FireModePromotionsCoordinatorTests.swift
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
import Core
import Persistence
import PersistenceTestingUtils
@testable import DuckDuckGo

final class FireModePromotionsCoordinatorTests: XCTestCase {

    private var sut: FireModePromotionsCoordinator!
    private var mockCapability: MockFireModeCapability!
    private var keyValueStore: InMemoryKeyValueStore!
    private var storage: any KeyedStoring<FireModePromotionKeys> { keyValueStore.keyedStoring() }

    override func setUp() {
        super.setUp()
        mockCapability = MockFireModeCapability()
        keyValueStore = InMemoryKeyValueStore()
        sut = makeSUT()
    }

    override func tearDown() {
        keyValueStore = nil
        mockCapability = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - NTP Promotion: Feature Flag

    func testWhenFeatureFlagIsDisabledThenNotEligible() {
        setNTPEligibleState()
        mockCapability.isFireModeEnabled = false

        XCTAssertFalse(sut.isNTPPromotionEligible)
    }

    func testWhenFeatureFlagIsEnabledAndConditionsMetThenStillNotEligible() {
        setNTPEligibleState()

        XCTAssertFalse(sut.isNTPPromotionEligible)
    }

    // MARK: - NTP Promotion: Burn Prerequisite

    func testWhenUserHasNotBurnedTabsThenNotEligible() {
        mockCapability.isFireModeEnabled = true

        XCTAssertFalse(sut.isNTPPromotionEligible)
    }

    func testWhenUserHasBurnedTabsThenStillNotEligible() {
        setNTPEligibleState()

        XCTAssertFalse(sut.isNTPPromotionEligible)
    }

    func testWhenMarkBurnPerformedCalledThenStillNotEligible() {
        mockCapability.isFireModeEnabled = true
        sut.markBurnPerformed()

        let freshSUT = makeSUT()
        XCTAssertFalse(freshSUT.isNTPPromotionEligible)
    }

    // MARK: - NTP Promotion: Fire Mode Visited

    func testWhenUserHasVisitedFireModeThenNotEligible() {
        setNTPEligibleState()
        sut.markFireModeVisited()

        XCTAssertFalse(sut.isNTPPromotionEligible)
    }

    // MARK: - NTP Promotion: Dismissed

    func testWhenPromotionIsDismissedThenNotEligible() {
        setNTPEligibleState()
        sut.markNTPPromotionDismissed()

        XCTAssertFalse(sut.isNTPPromotionEligible)
    }

    // MARK: - NTP Promotion: Show At Most Once

    func testWhenPromotionShownThenNotEligibleAgain() {
        setNTPEligibleState()
        sut.markNTPPromotionShown()

        XCTAssertFalse(sut.isNTPPromotionEligible)
    }

    // MARK: - NTP Promotion: markNTPPromotionShown

    func testWhenMarkShownCalledFirstTimeThenSetsFirstSeenDate() {
        sut.markNTPPromotionShown()

        XCTAssertNotNil(storage.ntpFirstSeenDate)
    }

    func testWhenMarkShownCalledMultipleTimesThenDoesNotOverwriteFirstSeenDate() {
        sut.markNTPPromotionShown()
        let firstDate = storage.ntpFirstSeenDate

        sut.markNTPPromotionShown()
        let secondDate = storage.ntpFirstSeenDate

        XCTAssertEqual(firstDate, secondDate)
    }

    // MARK: - Tab Switcher Tip: Not Expired Initially

    func testWhenTipNeverShownThenNotExpired() {
        XCTAssertFalse(sut.isTabSwitcherTipExpired)
    }

    // MARK: - Tab Switcher Tip: markTabSwitcherTipShown

    func testWhenMarkTabSwitcherTipShownCalledFirstTimeThenSetsFirstSeenDate() {
        sut.markTabSwitcherTipShown()

        XCTAssertNotNil(storage.tabSwitcherTipFirstSeenDate)
    }

    func testWhenMarkTabSwitcherTipShownCalledMultipleTimesThenDoesNotOverwriteFirstSeenDate() {
        sut.markTabSwitcherTipShown()
        let firstDate = storage.tabSwitcherTipFirstSeenDate

        sut.markTabSwitcherTipShown()
        let secondDate = storage.tabSwitcherTipFirstSeenDate

        XCTAssertEqual(firstDate, secondDate)
    }

    // MARK: - Tab Switcher Tip: Expiration

    func testWhenTipShownWithinThreeDaysThenNotExpired() {
        sut.markTabSwitcherTipShown()

        XCTAssertFalse(sut.isTabSwitcherTipExpired)
    }

    func testWhenTipShownMoreThanThreeDaysAgoThenExpired() {
        let fourDaysAgo = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        storage.tabSwitcherTipFirstSeenDate = fourDaysAgo

        XCTAssertTrue(sut.isTabSwitcherTipExpired)
    }

    // MARK: - Helpers

    private func makeSUT() -> FireModePromotionsCoordinator {
        FireModePromotionsCoordinator(fireModeCapability: mockCapability, storage: storage)
    }

    private func setNTPEligibleState() {
        mockCapability.isFireModeEnabled = true
        sut.markBurnPerformed()
    }
}

// MARK: - Mock

private final class MockFireModeCapability: FireModeCapable {
    var isFireModeEnabled = false
}

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
@testable import DuckDuckGo

final class FireModePromotionsCoordinatorTests: XCTestCase {

    private var sut: FireModePromotionsCoordinator!
    private var mockCapability: MockFireModeCapability!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        mockCapability = MockFireModeCapability()
        userDefaults = UserDefaults(suiteName: "\(type(of: self))")!
        userDefaults.removePersistentDomain(forName: "\(type(of: self))")
        sut = makeSUT()
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "\(type(of: self))")
        userDefaults = nil
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

    func testWhenFeatureFlagIsEnabledAndConditionsMetThenEligible() {
        setNTPEligibleState()

        XCTAssertTrue(sut.isNTPPromotionEligible)
    }

    // MARK: - NTP Promotion: Burn Prerequisite

    func testWhenUserHasNotBurnedTabsThenNotEligible() {
        mockCapability.isFireModeEnabled = true

        XCTAssertFalse(sut.isNTPPromotionEligible)
    }

    func testWhenUserHasBurnedTabsThenEligible() {
        setNTPEligibleState()

        XCTAssertTrue(sut.isNTPPromotionEligible)
    }

    func testWhenMarkBurnPerformedCalledThenBurnStateIsPersisted() {
        mockCapability.isFireModeEnabled = true
        sut.markBurnPerformed()

        let freshSUT = makeSUT()
        XCTAssertTrue(freshSUT.isNTPPromotionEligible)
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

    // MARK: - NTP Promotion: Expiration

    func testWhenPromotionShownWithinThreeDaysThenEligible() {
        setNTPEligibleState()
        sut.markNTPPromotionShown()

        XCTAssertTrue(sut.isNTPPromotionEligible)
    }

    func testWhenPromotionShownMoreThanThreeDaysAgoThenNotEligible() {
        setNTPEligibleState()
        let fourDaysAgo = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        userDefaults.set(fourDaysAgo, forKey: "com.duckduckgo.ios.firePromotion.ntp.firstSeenDate")

        XCTAssertFalse(sut.isNTPPromotionEligible)
    }

    func testWhenPromotionNeverShownAndConditionsMetThenEligible() {
        setNTPEligibleState()

        XCTAssertTrue(sut.isNTPPromotionEligible)
    }

    // MARK: - NTP Promotion: markNTPPromotionShown

    func testWhenMarkShownCalledFirstTimeThenSetsFirstSeenDate() {
        sut.markNTPPromotionShown()

        let storedDate = userDefaults.object(forKey: "com.duckduckgo.ios.firePromotion.ntp.firstSeenDate") as? Date
        XCTAssertNotNil(storedDate)
    }

    func testWhenMarkShownCalledMultipleTimesThenDoesNotOverwriteFirstSeenDate() {
        sut.markNTPPromotionShown()
        let firstDate = userDefaults.object(forKey: "com.duckduckgo.ios.firePromotion.ntp.firstSeenDate") as? Date

        sut.markNTPPromotionShown()
        let secondDate = userDefaults.object(forKey: "com.duckduckgo.ios.firePromotion.ntp.firstSeenDate") as? Date

        XCTAssertEqual(firstDate, secondDate)
    }

    // MARK: - Tab Switcher Tip: Not Expired Initially

    func testWhenTipNeverShownThenNotExpired() {
        XCTAssertFalse(sut.isTabSwitcherTipExpired)
    }

    // MARK: - Tab Switcher Tip: markTabSwitcherTipShown

    func testWhenMarkTabSwitcherTipShownCalledFirstTimeThenSetsFirstSeenDate() {
        sut.markTabSwitcherTipShown()

        let storedDate = userDefaults.object(forKey: "com.duckduckgo.ios.firePromotion.tabSwitcherTip.firstSeenDate") as? Date
        XCTAssertNotNil(storedDate)
    }

    func testWhenMarkTabSwitcherTipShownCalledMultipleTimesThenDoesNotOverwriteFirstSeenDate() {
        sut.markTabSwitcherTipShown()
        let firstDate = userDefaults.object(forKey: "com.duckduckgo.ios.firePromotion.tabSwitcherTip.firstSeenDate") as? Date

        sut.markTabSwitcherTipShown()
        let secondDate = userDefaults.object(forKey: "com.duckduckgo.ios.firePromotion.tabSwitcherTip.firstSeenDate") as? Date

        XCTAssertEqual(firstDate, secondDate)
    }

    // MARK: - Tab Switcher Tip: Expiration

    func testWhenTipShownWithinThreeDaysThenNotExpired() {
        sut.markTabSwitcherTipShown()

        XCTAssertFalse(sut.isTabSwitcherTipExpired)
    }

    func testWhenTipShownMoreThanThreeDaysAgoThenExpired() {
        let fourDaysAgo = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        userDefaults.set(fourDaysAgo, forKey: "com.duckduckgo.ios.firePromotion.tabSwitcherTip.firstSeenDate")

        XCTAssertTrue(sut.isTabSwitcherTipExpired)
    }

    // MARK: - Helpers

    private func makeSUT() -> FireModePromotionsCoordinator {
        FireModePromotionsCoordinator(fireModeCapability: mockCapability, userDefaults: userDefaults)
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

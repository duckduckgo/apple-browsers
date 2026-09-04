//
//  BrokenSitePromoDelegateTests.swift
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

import BrokenSitePrompt
import Combine
@_spi(Testing) import PixelKit
import PrivacyConfig
import SharedTestUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BrokenSitePromoDelegateTests: XCTestCase {

    private static let promoId = "broken-site"

    private var configManager: MockPrivacyConfigurationManaging!
    private var limiterStore: MockBrokenSitePromptLimiterStore!
    private var limiter: BrokenSitePromptLimiter!
    private var onboardingStateUpdater: MockOnboardingStateUpdater!
    private var windowControllersManager: WindowControllersManagerMock!
    private var pixelFiring: PixelKitMock!
    private var sut: BrokenSitePromoDelegate!

    override func setUp() {
        super.setUp()
        configManager = MockPrivacyConfigurationManaging()
        configManager.mockConfig.isFeatureEnabledCheck = { feature, _ in feature == .brokenSitePrompt }
        limiterStore = MockBrokenSitePromptLimiterStore()
        limiter = BrokenSitePromptLimiter(privacyConfigManager: configManager, store: limiterStore)
        onboardingStateUpdater = MockOnboardingStateUpdater()
        onboardingStateUpdater.state = .onboardingCompleted
        windowControllersManager = WindowControllersManagerMock()
        pixelFiring = PixelKitMock()
        sut = BrokenSitePromoDelegate(privacyConfigManager: configManager,
                                      limiter: limiter,
                                      onboardingStateUpdater: onboardingStateUpdater,
                                      windowControllersManager: windowControllersManager,
                                      pixelFiring: pixelFiring)
    }

    override func tearDown() {
        sut = nil
        pixelFiring = nil
        windowControllersManager = nil
        onboardingStateUpdater = nil
        limiter = nil
        limiterStore = nil
        configManager = nil
        super.tearDown()
    }

    private var history: PromoHistoryRecord { PromoHistoryRecord(id: Self.promoId) }

    // MARK: - Eligibility

    func testWhenOnboardingCompleteAndLimiterAllowsThenEligible() {
        XCTAssertTrue(limiter.shouldShowToast())
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenOnboardingNotCompletedThenNotEligible() {
        onboardingStateUpdater.state = .ongoing

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenFeatureDisabledThenNotEligible() {
        configManager.mockConfig.isFeatureEnabledCheck = { _, _ in false }

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenLimiterDoesNotAllowThenNotEligible() {
        limiter.didShowToast()

        XCTAssertFalse(limiter.shouldShowToast())
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenLimiterDismissStreakExceededThenNotEligible() {
        limiter.didShowToast()
        limiter.didDismissToast()
        limiter.didDismissToast()
        limiter.didDismissToast()

        // Advance date beyond regular cooldown interval
        limiter.debugAdvanceDate(by: limiter.coolDownInterval + .day)

        XCTAssertFalse(sut.isEligible)
    }

    func testEligibilityPublisherReplaysCurrentValue() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        XCTAssertEqual(received, [true])
        cancellable.cancel()
    }

    func testWhenFeatureDisabledEligibilityPublisherEmitsFalse() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        configManager.mockConfig.isFeatureEnabledCheck = { _, _ in false }
        configManager.updatesSubject.send(())

        XCTAssertEqual(received.last, false)
        cancellable.cancel()
    }

    // MARK: - Presentation failure

    func testWhenNoKeyWindowThenResolvesWithNoChangeAndDoesNotTouchLimiter() async {
        let result = await sut.show(history: history, force: false)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(limiterStore.lastToastShownDate, .distantPast)
        XCTAssertEqual(limiterStore.toastDismissStreakCounter, 0)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - hide()

    func testWhenHideCalledBeforeShowThenItIsANoOp() {
        sut.hide()
        sut.hide()

        XCTAssertEqual(limiterStore.toastDismissStreakCounter, 0)
    }
}

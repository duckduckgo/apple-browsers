//
//  VPNUpsellDotBadgePromoDelegateTests.swift
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
import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import Subscription
import SubscriptionTestingUtilities
import XCTest
@_spi(Testing) import Networking
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class VPNUpsellDotBadgePromoDelegateTests: XCTestCase {

    private static let now = Date()

    private var featureFlagger: MockFeatureFlagger!
    private var notificationCenter: NotificationCenter!
    private var subscriptionManager: SubscriptionManagerMock!
    private var persistor: MockVPNUpsellUserDefaultsPersistor!
    private var manager: VPNUpsellVisibilityManager!
    private var isShowing = false
    private var cancellables = Set<AnyCancellable>()
    private var sut: VPNUpsellDotBadgePromoDelegate!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub[FeatureFlag.promoQueueVPNUpsellPromo.rawValue] = true
        notificationCenter = NotificationCenter()
        subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        persistor = MockVPNUpsellUserDefaultsPersistor()
        isShowing = false
        manager = makeManager(isNewUser: true)
        sut = makeSUT()
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        manager = nil
        persistor = nil
        subscriptionManager = nil
        notificationCenter = nil
        featureFlagger = nil
        super.tearDown()
    }

    private func makeManager(isNewUser: Bool) -> VPNUpsellVisibilityManager {
        let manager = VPNUpsellVisibilityManager(isNewUser: isNewUser,
                                                 subscriptionManager: subscriptionManager,
                                                 defaultBrowserProvider: MockDefaultBrowserProvider(),
                                                 contextualOnboardingPublisher: Just(true).eraseToAnyPublisher(),
                                                 timerDuration: 0.01,
                                                 notificationCenter: notificationCenter)
        manager.setup(isFirstLaunch: false, isOnboardingFinished: true)
        return manager
    }

    private func makeSUT() -> VPNUpsellDotBadgePromoDelegate {
        let sut = VPNUpsellDotBadgePromoDelegate(featureFlagger: featureFlagger,
                                                 visibilityManager: manager,
                                                 persistor: persistor,
                                                 dateProvider: { Self.now })
        sut.isShowingPublisher
            .sink { [unowned self] in self.isShowing = $0 }
            .store(in: &cancellables)
        return sut
    }

    /// Starts `show` and yields so it runs up to its suspension point.
    private func startShow(force: Bool = false) async -> Task<PromoResult, Never> {
        let task = Task { await sut.show(history: PromoHistoryRecord(id: "vpn-upsell-dot-badge"), force: force) }
        await Task.yield()
        return task
    }

    private func waitForEligibility(_ expected: Bool) {
        let expectation = expectation(description: "eligibility becomes \(expected)")
        sut.isEligiblePublisher
            .first { $0 == expected }
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        waitForExpectations(timeout: 2)
    }

    // MARK: - Eligibility

    func testWhenFlagOnAndManagerEligibleThenIsEligible() {
        XCTAssertEqual(manager.state, .eligible)
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenFlagOffThenIsNotEligible() {
        featureFlagger.featuresStub[FeatureFlag.promoQueueVPNUpsellPromo.rawValue] = false
        sut = makeSUT()

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenManagerIsNotEligibleThenIsNotEligible() {
        manager = makeManager(isNewUser: false)
        sut = makeSUT()

        XCTAssertEqual(manager.state, .notEligible)
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenManagerBecomesNotEligibleThenEligibilityPublisherEmitsFalse() {
        XCTAssertTrue(sut.isEligible)
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        notificationCenter.post(name: .entitlementsDidChange, object: nil)

        waitForEligibility(false)
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenFlagIsTurnedOffAtRuntimeThenEligibilityPublisherEmitsFalse() {
        XCTAssertTrue(sut.isEligible)
        var values: [Bool] = []
        sut.isEligiblePublisher.sink { values.append($0) }.store(in: &cancellables)

        featureFlagger.featuresStub[FeatureFlag.promoQueueVPNUpsellPromo.rawValue] = false
        featureFlagger.triggerUpdate()

        XCTAssertEqual(values, [true, false])
        XCTAssertFalse(sut.isEligible)
    }

    // MARK: - Legacy retirement

    func testWhenLegacyPopoverWasViewedThenShowRetires() async {
        persistor.legacyPopoverViewed = true

        let result = await sut.show(history: PromoHistoryRecord(id: "id"), force: false)

        XCTAssertEqual(result, .retired)
        XCTAssertFalse(isShowing)
    }

    func testWhenLegacyUpsellWasDismissedThenShowRetires() async {
        persistor.legacyUpsellDismissed = true

        let result = await sut.show(history: PromoHistoryRecord(id: "id"), force: false)

        XCTAssertEqual(result, .retired)
    }

    func testWhenButtonWasFirstPinnedSevenDaysAgoThenShowRetires() async {
        persistor.legacyFirstPinnedDate = Self.now.addingTimeInterval(.days(-7))

        let result = await sut.show(history: PromoHistoryRecord(id: "id"), force: false)

        XCTAssertEqual(result, .retired)
    }

    func testWhenButtonWasFirstPinnedSixDaysAgoThenShowDoesNotRetire() async {
        persistor.legacyFirstPinnedDate = Self.now.addingTimeInterval(.days(-6))

        let task = await startShow()

        XCTAssertTrue(isShowing)
        sut.hide()
        _ = await task.value
    }

    func testWhenForcedThenShowBypassesRetirement() async {
        persistor.legacyPopoverViewed = true
        persistor.legacyUpsellDismissed = true
        persistor.legacyFirstPinnedDate = Self.now.addingTimeInterval(.days(-30))

        let task = await startShow(force: true)

        XCTAssertTrue(isShowing)
        sut.hide()
        _ = await task.value
    }

    // MARK: - Resolution

    func testWhenButtonClickedWhileShowingThenActioned() async {
        let task = await startShow()
        XCTAssertTrue(isShowing)

        sut.buttonClicked()

        let result = await task.value
        XCTAssertEqual(result, .actioned)
        XCTAssertFalse(isShowing)
    }

    func testWhenUnpinnedWhileShowingThenPermanentlyIgnored() async {
        let task = await startShow()

        sut.handlePinningChange(isPinned: false)

        let result = await task.value
        XCTAssertEqual(result, .ignored())
        XCTAssertFalse(isShowing)
    }

    func testWhenPinnedWhileShowingThenStaysShown() async {
        let task = await startShow()

        sut.handlePinningChange(isPinned: true)

        XCTAssertTrue(isShowing)
        sut.hide()
        _ = await task.value
    }

    func testWhenHiddenWhileShowingThenNoChange() async {
        let task = await startShow()

        sut.hide()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(isShowing)
    }

    func testWhenHiddenTwiceThenItIsSafe() async {
        let task = await startShow()

        sut.hide()
        sut.hide()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
    }

    func testWhenHiddenAfterResolutionThenResultIsUnchanged() async {
        let task = await startShow()
        sut.buttonClicked()

        sut.hide()

        let result = await task.value
        XCTAssertEqual(result, .actioned)
        XCTAssertFalse(isShowing)
    }

    func testWhenNotShowingThenHideUnpinAndButtonClickDoNothing() {
        sut.hide()
        sut.handlePinningChange(isPinned: false)
        sut.buttonClicked()

        XCTAssertFalse(isShowing)
    }
}

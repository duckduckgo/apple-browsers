//
//  VPNUpsellPromoSessionTests.swift
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
final class VPNUpsellPromoSessionTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var notificationCenter: NotificationCenter!
    private var subscriptionManager: SubscriptionManagerMock!
    private var manager: VPNUpsellVisibilityManager!
    private var isShowing = false
    private var cancellables = Set<AnyCancellable>()
    private var sut: VPNUpsellPromoSession!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub[FeatureFlag.promoQueueVPNUpsellPromo.rawValue] = true
        notificationCenter = NotificationCenter()
        subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        isShowing = false
        manager = makeManager(isNewUser: true)
        sut = makeSUT()
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        manager = nil
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

    private func makeSUT() -> VPNUpsellPromoSession {
        let sut = VPNUpsellPromoSession(featureFlagger: featureFlagger, visibilityManager: manager)
        sut.isShowingPublisher
            .sink { [unowned self] in self.isShowing = $0 }
            .store(in: &cancellables)
        return sut
    }

    /// Starts `begin` and yields so it runs up to its suspension point.
    private func startBegin() async -> Task<PromoResult, Never> {
        let task = Task { await sut.begin() }
        await Task.yield()
        XCTAssertTrue(isShowing, "begin() did not reach its suspension point")
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

    // MARK: - Lifecycle

    func testWhenBeginCalledThenIsShowingAndActive() async {
        let task = await startBegin()

        XCTAssertTrue(isShowing)
        XCTAssertTrue(sut.isActive)
        sut.end()
        _ = await task.value
    }

    func testWhenResolvedThenBeginReturnsResultAndIsNoLongerShowing() async {
        let task = await startBegin()

        sut.resolve(.actioned)

        let result = await task.value
        XCTAssertEqual(result, .actioned)
        XCTAssertFalse(isShowing)
        XCTAssertFalse(sut.isActive)
    }

    func testWhenResolvedWhileNotActiveThenNothingHappensAndLaterBeginStillWaits() async {
        sut.resolve(.actioned)
        XCTAssertFalse(isShowing)
        XCTAssertFalse(sut.isActive)

        let task = await startBegin()

        // The earlier call must not have left state behind that resolves the next begin.
        XCTAssertTrue(sut.isActive)
        sut.resolve(.ignored())
        let result = await task.value
        XCTAssertEqual(result, .ignored())
        XCTAssertFalse(isShowing)
    }

    func testWhenEndedBeforeAnyResultThenNoChange() async {
        let task = await startBegin()

        sut.end()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(isShowing)
        XCTAssertFalse(sut.isActive)
    }

    func testWhenEndedTwiceThenItIsSafe() async {
        let task = await startBegin()

        sut.end()
        sut.end()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(isShowing)
    }

    func testWhenEndedWhileNotActiveThenNothingHappensAndLaterBeginStillWaits() async {
        sut.end()
        XCTAssertFalse(isShowing)

        let task = await startBegin()

        XCTAssertTrue(sut.isActive)
        sut.resolve(.actioned)
        let result = await task.value
        XCTAssertEqual(result, .actioned)
    }

    func testWhenEndedAfterResolutionThenResultIsUnchanged() async {
        let task = await startBegin()
        sut.resolve(.actioned)

        sut.end()

        let result = await task.value
        XCTAssertEqual(result, .actioned)
        XCTAssertFalse(isShowing)
    }

    func testWhenBeginCalledWhilePreviousWaitPendingThenPreviousWaitResumesWithNoChange() async {
        let first = await startBegin()

        let second = Task { await sut.begin() }
        let firstResult = await first.value
        XCTAssertEqual(firstResult, .noChange)
        await Task.yield()
        XCTAssertTrue(isShowing, "second begin() did not reach its suspension point")
        XCTAssertTrue(sut.isActive)

        sut.resolve(.actioned)
        let secondResult = await second.value
        XCTAssertEqual(secondResult, .actioned)
        XCTAssertFalse(isShowing)
    }
}

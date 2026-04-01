//
//  FreemiumDBPPromoDelegateTests.swift
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
import Common
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import Freemium
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class FreemiumDBPPromoDelegateTests: XCTestCase {

    private var sut: FreemiumDBPPromoDelegate!
    private var coordinator: FreemiumDBPPromotionViewCoordinator!
    private var mockUserStateManager: MockFreemiumDBPUserStateManager!
    private var mockFeature: MockFreemiumDBPFeature!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        mockUserStateManager = MockFreemiumDBPUserStateManager()
        mockFeature = MockFreemiumDBPFeature()
        mockFeature.featureAvailable = true

        coordinator = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: MockFreemiumDBPPresenter(),
            dataBrokerProtectionFreemiumPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler(),
            contextualOnboardingPublisher: Empty<Bool, Never>().eraseToAnyPublisher()
        )

        sut = FreemiumDBPPromoDelegate(coordinator: coordinator)
    }

    override func tearDown() {
        sut = nil
        coordinator = nil
        mockUserStateManager = nil
        mockFeature = nil
        cancellables = []
    }

    // MARK: - Eligibility

    func testIsEligible_whenAllConditionsMet() {
        XCTAssertTrue(sut.isEligible)
    }

    func testIsEligible_whenFeatureUnavailable() {
        mockFeature.isAvailableSubject.send(false)
        let expectation = XCTestExpectation()
        coordinator.$isFeatureAvailable.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        wait(for: [expectation], timeout: 2.0)

        XCTAssertFalse(sut.isEligible)
    }

    // MARK: - Legacy dismissal (eligibility)

    func testIsEligible_falseForLegacyDismissal_whenPreScanBanner() {
        mockUserStateManager.didDismissHomePagePromotion = true
        mockUserStateManager.firstScanResults = nil

        coordinator = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: MockFreemiumDBPPresenter(),
            dataBrokerProtectionFreemiumPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler(),
            contextualOnboardingPublisher: Empty<Bool, Never>().eraseToAnyPublisher()
        )
        sut = FreemiumDBPPromoDelegate(coordinator: coordinator)

        XCTAssertFalse(sut.isEligible)
    }

    func testIsEligible_trueForLegacyDismissal_whenScanResultsExist() {
        mockUserStateManager.didDismissHomePagePromotion = true
        mockUserStateManager.firstScanResults = FreemiumDBPMatchResults(matchesCount: 3, brokerCount: 1)

        coordinator = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: MockFreemiumDBPPresenter(),
            dataBrokerProtectionFreemiumPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler(),
            contextualOnboardingPublisher: Empty<Bool, Never>().eraseToAnyPublisher()
        )
        sut = FreemiumDBPPromoDelegate(coordinator: coordinator)

        XCTAssertTrue(sut.isEligible)
    }

    // MARK: - show()

    func testShow_suspendsAndWaitsForUserAction() async {
        let task = Task {
            await sut.show(history: PromoHistoryRecord(id: "test"), force: false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(coordinator.viewModel)

        sut.hide()
        _ = await task.value
    }

    func testShow_suspendsAndResumesWithActionedOnProceed() async {
        let task = Task {
            await sut.show(history: PromoHistoryRecord(id: "test"), force: false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        coordinator.onUserAction?(.actioned)

        let result = await task.value
        XCTAssertEqual(result, .actioned)
    }

    func testShow_suspendsAndResumesWithIgnoredOnClose() async {
        let task = Task {
            await sut.show(history: PromoHistoryRecord(id: "test"), force: false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        coordinator.onUserAction?(.ignored())

        let result = await task.value
        XCTAssertEqual(result, .ignored())
    }

    // MARK: - hide()

    func testHide_resumesContinuationWithNoChange() async {
        let task = Task {
            await sut.show(history: PromoHistoryRecord(id: "test"), force: false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        sut.hide()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
    }

    func testHide_clearsViewModel() async {
        let task = Task {
            await sut.show(history: PromoHistoryRecord(id: "test"), force: false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(coordinator.viewModel)
        sut.hide()
        XCTAssertNil(coordinator.viewModel)

        _ = await task.value
    }

    func testHide_isIdempotent() {
        sut.hide()
        sut.hide()
    }

    // MARK: - show() edge cases

    func testShow_doubleCallResumesFirstContinuation() async {
        // First show — suspends
        let firstTask = Task {
            await sut.show(history: PromoHistoryRecord(id: "test"), force: false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Second show — should resume first with .noChange
        let secondTask = Task {
            await sut.show(history: PromoHistoryRecord(id: "test"), force: false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        let firstResult = await firstTask.value
        XCTAssertEqual(firstResult, .noChange)

        // Clean up second
        sut.hide()
        _ = await secondTask.value
    }

    // MARK: - isEligiblePublisher

    func testIsEligiblePublisher_emitsTrueWhenAllConditionsMet() {
        let expectation = XCTestExpectation(description: "publisher emits true")
        sut.isEligiblePublisher
            .first()
            .sink { eligible in
                if eligible { expectation.fulfill() }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)
    }

    func testIsEligiblePublisher_emitsFalseWhenFeatureBecomesUnavailable() {
        let expectation = XCTestExpectation(description: "publisher emits false")
        sut.isEligiblePublisher
            .dropFirst() // skip initial true
            .sink { eligible in
                if !eligible { expectation.fulfill() }
            }
            .store(in: &cancellables)

        mockFeature.featureAvailable = false

        wait(for: [expectation], timeout: 2.0)
    }

    func testRefreshEligibility_reEmitsWhenValueChanges() {
        // Start with feature unavailable
        mockFeature.featureAvailable = false
        let unavailableExpectation = XCTestExpectation(description: "publisher emits false")
        coordinator.$isFeatureAvailable.dropFirst().sink { available in
            if !available { unavailableExpectation.fulfill() }
        }.store(in: &cancellables)
        wait(for: [unavailableExpectation], timeout: 2.0)

        var emissions: [Bool] = []
        let expectation = XCTestExpectation(description: "publisher emits after refresh")
        expectation.expectedFulfillmentCount = 2

        sut.isEligiblePublisher
            .sink { eligible in
                emissions.append(eligible)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Make feature available again and refresh
        mockFeature.featureAvailable = true
        let availableExpectation = XCTestExpectation(description: "feature becomes available")
        coordinator.$isFeatureAvailable.dropFirst().sink { available in
            if available { availableExpectation.fulfill() }
        }.store(in: &cancellables)
        wait(for: [availableExpectation], timeout: 2.0)

        sut.refreshEligibility()

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(emissions.last, true)
    }

    func testScanResultsNotification_callsOnScanResultsUpdated() {
        let expectation = XCTestExpectation(description: "onScanResultsUpdated called via notification")
        let originalCallback = coordinator.onScanResultsUpdated
        coordinator.onScanResultsUpdated = {
            originalCallback?()
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .freemiumDBPResultPollingComplete, object: nil)

        wait(for: [expectation], timeout: 2.0)
    }

}

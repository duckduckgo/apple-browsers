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

    func testIsEligible_whenDismissed() {
        mockUserStateManager.didDismissHomePagePromotion = true
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

    func testIsEligible_whenDisplayWindowExpired() {
        coordinator.displayWindowStartDate = Date().addingTimeInterval(-.days(8))
        coordinator.updateDisplayWindowExpiredState()

        XCTAssertFalse(sut.isEligible)
    }

    // MARK: - Fast-path eligibility

    func testIsEligible_fastPath_whenFeatureUnavailableButFlagEnabled() {
        // Simulate startup timing: isAvailable is false (product availability not settled)
        // but feature flag is enabled and display window is active
        coordinator.displayWindowStartDate = Date()
        coordinator.updateDisplayWindowExpiredState()
        mockFeature.featureAvailable = false
        mockFeature.mockFeatureFlagEnabled = true

        // Re-sync coordinator state
        let expectation = XCTestExpectation()
        coordinator.$isFeatureAvailable.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        wait(for: [expectation], timeout: 2.0)

        XCTAssertTrue(sut.isEligible)
    }

    func testIsEligible_fastPath_whenFeatureFlagDisabled() {
        // Even during active display window, feature flag must be respected
        coordinator.displayWindowStartDate = Date()
        coordinator.updateDisplayWindowExpiredState()
        mockFeature.mockFeatureFlagEnabled = false

        XCTAssertFalse(sut.isEligible)
    }

    // MARK: - show()

    func testShow_setsDisplayWindowStartDate() async {
        XCTAssertNil(coordinator.displayWindowStartDate)

        let task = Task {
            await sut.show(history: PromoHistoryRecord(id: "test"), force: false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(coordinator.displayWindowStartDate)

        sut.hide()
        _ = await task.value
    }

    func testShow_returnsIgnoredWhenWindowExpired() async {
        coordinator.displayWindowStartDate = Date().addingTimeInterval(-.days(8))
        coordinator.updateDisplayWindowExpiredState()

        let result = await sut.show(history: PromoHistoryRecord(id: "test"), force: false)

        XCTAssertEqual(result, .ignored(cooldown: .days(28)))
        XCTAssertNil(coordinator.displayWindowStartDate)
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
}

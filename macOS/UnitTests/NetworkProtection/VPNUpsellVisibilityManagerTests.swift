//
//  VPNUpsellVisibilityManagerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine
import VPN
import BrowserServicesKit
import SubscriptionTestingUtilities
import Subscription
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class VPNUpsellVisibilityManagerTests: XCTestCase {

    var sut: VPNUpsellVisibilityManager!
    var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockDefaultBrowserProvider: MockDefaultBrowserProvider!
    fileprivate var mockPersistor: MockVPNUpsellUserDefaultsPersistor!
    var firedPixels: [PrivacyProPixel] = []

    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        mockFeatureFlagger = MockFeatureFlagger()
        mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockPersistor = MockVPNUpsellUserDefaultsPersistor()
        firedPixels = []
        cancellables = Set<AnyCancellable>()

        mockFeatureFlagger.enabledFeatureFlags = [.vpnToolbarUpsell]
    }

    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        mockFeatureFlagger = nil
        mockDefaultBrowserProvider = nil
        mockPersistor = nil
        firedPixels = []
        cancellables?.removeAll()
        cancellables = nil
        super.tearDown()
    }

    // MARK: - State Tests

    func testWhenUserIsEligible_ItShowsTheUpsellOnSecondLaunch() {
        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)

        // Then
        XCTAssertEqual(sut.state, .visible)
    }

    func testWhenUserIsIneligible_ItDoesNotShowTheUpsell() {
        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: false)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenFeatureIsDisabled_ItDoesNotShowTheUpsell() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenUserIsAuthenticated_ItDoesNotShowTheUpsell() {
        // Given
        mockSubscriptionManager.accessTokenResult = .success("mock-token")

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenUserIsEligible_ItFiresPixelOnTransitionToVisible() {
        // Given
        let expectation = XCTestExpectation(description: "Pixel should be fired")
        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true) { [weak self] pixel in
            self?.firedPixels.append(pixel)
            if pixel.name == PrivacyProPixel.privacyProToolbarButtonShown.name {
                expectation.fulfill()
            }
        }

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(sut.state, .visible)
        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, PrivacyProPixel.privacyProToolbarButtonShown.name)
    }

    // MARK: - Manual Unpinning Tests

    func testWhenUserManuallyUnpinsButton_ItDismissesTheUpsell() {
        // Given
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)

        let expectation = XCTestExpectation(description: "State should change to dismissed")

        sut.$state
            .sink { state in
                if state == .dismissed {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        sut.handlePinningChange(isPinned: false)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(sut.state, .dismissed)
        XCTAssertTrue(mockPersistor.vpnUpsellDismissed)
    }

    func testWhenUserPinsButton_ItStoresFirstPinnedDate() {
        // Given
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)

        // When
        sut.handlePinningChange(isPinned: true)

        // Then
        XCTAssertNotNil(mockPersistor.vpnUpsellFirstPinnedDate)
    }

    func testWhenUserPinsButtonAgain_ItDoesNotOverwriteFirstPinnedDate() {
        // Given
        let originalDate = Date().addingTimeInterval(-3600)
        mockPersistor.vpnUpsellFirstPinnedDate = originalDate
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)

        // When
        sut.handlePinningChange(isPinned: true)

        // Then
        XCTAssertEqual(mockPersistor.vpnUpsellFirstPinnedDate, originalDate)
    }

    func testWhenSevenDaysHavePassedSincePinning_ItDismissesTheUpsell() {
        // Given
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        mockPersistor.vpnUpsellFirstPinnedDate = eightDaysAgo

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, autoDismissDays: 7)

        // Then
        XCTAssertEqual(sut.state, .dismissed)
    }

    func testWhenSixDaysHavePassedSincePinning_ItShowsTheUpsell() {
        // Given
        let sixDaysAgo = Date().addingTimeInterval(-6 * 24 * 60 * 60)
        mockPersistor.vpnUpsellFirstPinnedDate = sixDaysAgo

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, autoDismissDays: 7)

        // Then
        XCTAssertEqual(sut.state, .visible)
    }

    func testWhenManuallyDismissed_ItDismissesTheUpsell() {
        // Given
        mockPersistor.vpnUpsellDismissed = true

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)

        // Then
        XCTAssertEqual(sut.state, .dismissed)
    }

    func testWhenUserBecomesAuthenticated_ItDoesNotShowTheUpsell() {
        // Given
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)

        let expectation = XCTestExpectation(description: "State should change to notEligible")

        sut.$state
            .sink { state in
                if state == .notEligible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockSubscriptionManager.accessTokenResult = .success("mock-token")
        NotificationCenter.default.post(name: .entitlementsDidChange, object: nil)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(sut.state, .notEligible)
    }

    // MARK: - First Launch Timer Tests

    func testWhenUserIsEligible_ItWaitsForConditionsOnFirstLaunch() {
        // Given
        let onboardingSubject = PassthroughSubject<Bool, Never>()

        let expectation = XCTestExpectation(description: "State should be waitingForConditions")

        // When
        sut = VPNUpsellVisibilityManager(
            isFirstLaunch: true,
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: onboardingSubject.eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger,
            persistor: mockPersistor,
            timerDuration: 0.1,
            pixelHandler: { _ in }
        )

        sut.setup(isFirstLaunch: true)

        sut.$state
            .sink { state in
                if state == .waitingForConditions {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(sut.state, .waitingForConditions)
    }

    func testWhenUserIsEligible_AndConditionsAreMetOnFirstLaunch_ItStartsTheTimer() {
        // Given
        let onboardingSubject = PassthroughSubject<Bool, Never>()
        mockDefaultBrowserProvider.isDefault = true

        sut = VPNUpsellVisibilityManager(
            isFirstLaunch: true,
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: onboardingSubject.eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger,
            persistor: mockPersistor,
            timerDuration: 10,
            pixelHandler: { _ in }
        )

        sut.setup(isFirstLaunch: true)

        let expectation = XCTestExpectation(description: "State should transition to waitingForTimer")

        sut.$state
            .sink { state in
                if state == .waitingForTimer {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        onboardingSubject.send(true)
        NotificationCenter.default.post(name: .defaultBrowserPromptPresented, object: nil)

        // Then
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(sut.state, .waitingForTimer)
    }

    func testWhenUserIsEligible_AndConditionsAreMetOnFirstLaunch_AndTimerCompletes_ItShowsTheUpsell() {
        // Given
        let onboardingSubject = PassthroughSubject<Bool, Never>()
        mockDefaultBrowserProvider.isDefault = true

        sut = VPNUpsellVisibilityManager(
            isFirstLaunch: true,
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: onboardingSubject.eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger,
            persistor: mockPersistor,
            timerDuration: 0.1,
            pixelHandler: { _ in }
        )

        sut.setup(isFirstLaunch: true)

        let expectation = XCTestExpectation(description: "State should transition to visible")

        sut.$state
            .sink { state in
                if state == .visible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        onboardingSubject.send(true)
        NotificationCenter.default.post(name: .defaultBrowserPromptPresented, object: nil)

        // Then
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(sut.state, .visible)
    }

    // MARK: - Edge Cases

    func testWhenUserIsNewButAuthenticated_ItDoesNotShowTheUpsell() {
        // Given
        mockSubscriptionManager.accessTokenResult = .success("mock-token")

        // When
        sut = createUpsellManager(isFirstLaunch: true, isNewUser: true)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenUserIsNotNew_ItDoesNotShowTheUpsell() {
        // When
        sut = createUpsellManager(isFirstLaunch: true, isNewUser: false)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenShowingTheUpsell_AndFeatureFlagIsDisabledAtInitialSetup_ButBecomesEnabledBeforeTheTrigger_ItShowsTheUpsell() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        let onboardingSubject = PassthroughSubject<Bool, Never>()
        mockDefaultBrowserProvider.isDefault = true

        sut = VPNUpsellVisibilityManager(
            isFirstLaunch: true,
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: onboardingSubject.eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger,
            persistor: mockPersistor,
            timerDuration: 0.1,
            pixelHandler: { _ in }
        )

        sut.setup(isFirstLaunch: true)

        let expectation = XCTestExpectation(description: "State should transition to visible")

        sut.$state
            .sink { state in
                if state == .visible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockFeatureFlagger.enabledFeatureFlags = [.vpnToolbarUpsell]
        onboardingSubject.send(true)
        NotificationCenter.default.post(name: .defaultBrowserPromptPresented, object: nil)

        // Then
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(sut.state, .visible)
    }

    // MARK: - Purchase Eligibility Tests

    func testWhenUserCannotPurchaseSubscription_ItDoesNotShowTheUpsell() {
        // Given
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)
        XCTAssertEqual(sut.state, .notEligible)

        // When
        mockSubscriptionManager.canPurchaseSubject.send(false)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenUserCanPurchaseSubscription_ItShowsTheUpsell() {
        // Given
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true)
        XCTAssertEqual(sut.state, .notEligible)

        // When
        mockSubscriptionManager.canPurchaseSubject.send(true)

        // Then
        XCTAssertEqual(sut.state, .visible)
    }
}

// MARK: - Helpers

extension VPNUpsellVisibilityManagerTests {
    private func createUpsellManager(
        isFirstLaunch: Bool,
        isNewUser: Bool,
        autoDismissDays: Int = 7,
        pixelHandler: @escaping (PrivacyProPixel) -> Void = { _ in }
    ) -> VPNUpsellVisibilityManager {
        let manager = VPNUpsellVisibilityManager(
            isFirstLaunch: isFirstLaunch,
            isNewUser: isNewUser,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: Just(true).eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger,
            persistor: mockPersistor,
            timerDuration: 0.01,
            autoDismissDays: autoDismissDays,
            pixelHandler: pixelHandler
        )

        manager.setup(isFirstLaunch: isFirstLaunch)

        return manager
    }
}

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
@_spi(Testing) import Networking

@MainActor
final class VPNUpsellVisibilityManagerTests: XCTestCase {

    var sut: VPNUpsellVisibilityManager!
    var mockSubscriptionManager: SubscriptionManagerMock!
    var mockDefaultBrowserProvider: MockDefaultBrowserProvider!
    fileprivate var mockPersistor: MockVPNUpsellUserDefaultsPersistor!
    var firedPixels: [SubscriptionPixel] = []

    var notificationCenter: NotificationCenter!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = SubscriptionManagerMock()
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockPersistor = MockVPNUpsellUserDefaultsPersistor()
        firedPixels = []
        notificationCenter = NotificationCenter()
        cancellables = Set<AnyCancellable>()

    }

    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        mockDefaultBrowserProvider = nil
        mockPersistor = nil
        firedPixels = []
        cancellables?.removeAll()
        cancellables = nil
        notificationCenter = nil
        super.tearDown()
    }

    // MARK: - State Tests

    func testWhenUserIsEligible_ItShowsTheUpsellOnSecondLaunch() {
        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: true)

        // Then
        XCTAssertEqual(sut.state, .eligible)
    }

    func testWhenOnboardingIsPending_ItDoesNotShowTheUpsell() {
        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: false)

        // Then
        XCTAssertEqual(sut.state, .waitingForConditions)
    }

    func testWhenUserIsIneligible_ItDoesNotShowTheUpsell() {
        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: false, isOnboardingFinished: false)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenUserIsAuthenticated_ItDoesNotShowTheUpsell() {
        // Given
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: false)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenUserBecomesAuthenticated_ItDoesNotShowTheUpsell() {
        // Given
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: true)

        let expectation = XCTestExpectation(description: "State should change to notEligible")

        sut.$state
            .sink { state in
                if state == .notEligible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        notificationCenter.post(name: .entitlementsDidChange, object: nil)

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
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: onboardingSubject.eraseToAnyPublisher(),
            timerDuration: 0.1,
            notificationCenter: notificationCenter
        )

        sut.setup(isFirstLaunch: true, isOnboardingFinished: false)

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
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: onboardingSubject.eraseToAnyPublisher(),
            timerDuration: 10,
            notificationCenter: notificationCenter
        )

        sut.setup(isFirstLaunch: true, isOnboardingFinished: false)

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
        notificationCenter.post(name: .defaultBrowserPromptPresented, object: nil)

        // Then
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(sut.state, .waitingForTimer)
    }

    func testWhenUserIsEligible_AndConditionsAreMetOnFirstLaunch_AndTimerCompletes_ItShowsTheUpsell() {
        // Given
        let onboardingSubject = PassthroughSubject<Bool, Never>()
        mockDefaultBrowserProvider.isDefault = true

        sut = VPNUpsellVisibilityManager(
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: onboardingSubject.eraseToAnyPublisher(),
            timerDuration: 0.1,
            notificationCenter: notificationCenter
        )

        sut.setup(isFirstLaunch: true, isOnboardingFinished: false)

        let expectation = XCTestExpectation(description: "State should transition to visible")

        sut.$state
            .sink { state in
                if state == .eligible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        onboardingSubject.send(true)
        notificationCenter.post(name: .defaultBrowserPromptPresented, object: nil)

        // Then
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(sut.state, .eligible)
    }

    // MARK: - Edge Cases

    func testWhenUserIsNewButAuthenticated_ItDoesNotShowTheUpsell() {
        // Given
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        // When
        sut = createUpsellManager(isFirstLaunch: true, isNewUser: true, isOnboardingFinished: false)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenUserIsNotNew_ItDoesNotShowTheUpsell() {
        // When
        sut = createUpsellManager(isFirstLaunch: true, isNewUser: false, isOnboardingFinished: false)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenShowingTheUpsell_AndFeatureFlagIsDisabledAtInitialSetup_ButBecomesEnabledBeforeTheTrigger_ItShowsTheUpsell() {
        // Given
        let onboardingSubject = PassthroughSubject<Bool, Never>()
        mockDefaultBrowserProvider.isDefault = true

        sut = VPNUpsellVisibilityManager(
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: onboardingSubject.eraseToAnyPublisher(),
            timerDuration: 0.1,
            notificationCenter: notificationCenter
        )

        sut.setup(isFirstLaunch: true, isOnboardingFinished: false)

        let expectation = XCTestExpectation(description: "State should transition to visible")

        sut.$state
            .sink { state in
                if state == .eligible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        onboardingSubject.send(true)
        notificationCenter.post(name: .defaultBrowserPromptPresented, object: nil)

        // Then
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(sut.state, .eligible)
    }

    // MARK: - Purchase Eligibility Tests

    func testWhenAppStoreProductsAreAvailableAtSetup_ItIsEligibleSynchronously() {
        // Given
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        mockSubscriptionManager.hasAppStoreProductsAvailable = true

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: true)

        // Then: no publisher emission is needed
        XCTAssertEqual(sut.state, .eligible)
    }

    func testWhenAppStoreProductsBecomeUnavailable_ItBecomesNotEligible() {
        // Given
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: true)
        XCTAssertEqual(sut.state, .eligible)

        // When
        mockSubscriptionManager.hasAppStoreProductsAvailable = false

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenAppStoreProductsAreUnavailableAtSetup_ItIsNotEligible() {
        // Given
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        mockSubscriptionManager.hasAppStoreProductsAvailable = false

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: true)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
    }

    func testWhenAppStoreProductsBecomeAvailableAfterSetup_ItBecomesEligible() {
        // Given
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        mockSubscriptionManager.hasAppStoreProductsAvailable = false
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: true)
        XCTAssertEqual(sut.state, .notEligible)

        // When
        mockSubscriptionManager.hasAppStoreProductsAvailable = true

        // Then
        XCTAssertEqual(sut.state, .eligible)
    }

    // MARK: - Became Eligible Notification

    func testWhenTransitioningToEligible_ItPostsBecameEligibleNotification() {
        // Given
        var postCount = 0
        notificationCenter.publisher(for: .vpnUpsellBecameEligible)
            .sink { _ in postCount += 1 }
            .store(in: &cancellables)

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: true)

        // Then
        XCTAssertEqual(sut.state, .eligible)
        XCTAssertEqual(postCount, 1)
    }

    func testWhenEligibleIsEmittedAgain_ItDoesNotPostAgain() {
        // Given
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        var postCount = 0
        notificationCenter.publisher(for: .vpnUpsellBecameEligible)
            .sink { _ in postCount += 1 }
            .store(in: &cancellables)
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: true)
        XCTAssertEqual(postCount, 1)

        // When: a repeated value that maps to eligible again
        mockSubscriptionManager.hasAppStoreProductsAvailable = true

        // Then
        XCTAssertEqual(sut.state, .eligible)
        XCTAssertEqual(postCount, 1)
    }

    func testWhenNotEligible_ItDoesNotPostBecameEligibleNotification() {
        // Given
        var postCount = 0
        notificationCenter.publisher(for: .vpnUpsellBecameEligible)
            .sink { _ in postCount += 1 }
            .store(in: &cancellables)

        // When
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: false, isOnboardingFinished: true)

        // Then
        XCTAssertEqual(sut.state, .notEligible)
        XCTAssertEqual(postCount, 0)
    }

    func testWhenUserSubscribes_ItBecomesNotEligible() {
        // Given
        sut = createUpsellManager(isFirstLaunch: false, isNewUser: true, isOnboardingFinished: true)
        XCTAssertEqual(sut.state, .eligible)
        let expectation = expectation(description: "state becomes notEligible")
        sut.$state
            .first { $0 == .notEligible }
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        // When
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        notificationCenter.post(name: .entitlementsDidChange, object: nil)

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(sut.state, .notEligible)
    }
}

// MARK: - Helpers

extension VPNUpsellVisibilityManagerTests {
    private func createUpsellManager(
        isFirstLaunch: Bool,
        isNewUser: Bool,
        isOnboardingFinished: Bool
    ) -> VPNUpsellVisibilityManager {
        let manager = VPNUpsellVisibilityManager(
            isNewUser: isNewUser,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: Just(true).eraseToAnyPublisher(),
            timerDuration: 0.01,
            notificationCenter: notificationCenter
        )

        manager.setup(isFirstLaunch: isFirstLaunch, isOnboardingFinished: isOnboardingFinished)

        return manager
    }
}

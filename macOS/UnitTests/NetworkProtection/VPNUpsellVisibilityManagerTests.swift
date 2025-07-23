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
import BrowserServicesKit
import Common
import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class VPNUpsellVisibilityManagerTests: XCTestCase {

    var sut: VPNUpsellVisibilityManager!
    var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var mockFeatureFlagger: MockFeatureFlagger!
    var defaultBrowserSubject: CurrentValueSubject<Bool, Never>!
    var contextualOnboardingSubject: CurrentValueSubject<Bool, Never>!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()

        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        mockFeatureFlagger = MockFeatureFlagger()
        defaultBrowserSubject = CurrentValueSubject<Bool, Never>(false)
        contextualOnboardingSubject = CurrentValueSubject<Bool, Never>(false)
        cancellables = Set<AnyCancellable>()
        mockFeatureFlagger.enabledFeatureFlags = [.vpnToolbarUpsell]
    }

    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        mockFeatureFlagger = nil
        defaultBrowserSubject = nil
        contextualOnboardingSubject = nil
        cancellables = nil
        super.tearDown()
    }

    func testWhenUserIsSubscribed_ItDoesNotShowUpsell() {
        sut = createSUT(isFirstLaunch: true, isNewUser: true, isUserAuthenticated: true)

        XCTAssertFalse(sut.shouldShowUpsell)
    }

    func testWhenUserIsNotNew_ItDoesNotShowUpsell() {
        sut = createSUT(isFirstLaunch: true, isNewUser: false, isUserAuthenticated: false)

        XCTAssertFalse(sut.shouldShowUpsell)
    }

    func testWhenNotFirstLaunch_ItShowsUpsellImmediately() {
        sut = createSUT(isFirstLaunch: false, isNewUser: true, isUserAuthenticated: false)

        XCTAssertTrue(sut.shouldShowUpsell)
    }

    func testWhenContextualOnboardingIsComplete_AndDefaultBrowserIsSet_ItStartsTimer() {
        let expectation = XCTestExpectation(description: "Timer should complete")
        sut = createSUT(isFirstLaunch: true, isNewUser: true, isUserAuthenticated: false, timerDuration: 0.1)

        sut.$shouldShowUpsell
            .dropFirst()
            .sink { (shouldShow: Bool) in
                if shouldShow {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        contextualOnboardingSubject.send(true)
        defaultBrowserSubject.send(true)

        wait(for: [expectation], timeout: 1.0)
        // Then
        XCTAssertTrue(sut.shouldShowUpsell)
    }

    func testWhenOnlyContextualOnboardingIsComplete_ItDoesNotStartTimer() {
        sut = createSUT(isFirstLaunch: true, isNewUser: true, isUserAuthenticated: false, timerDuration: 0.1)

        let expectation = XCTestExpectation(description: "Should not show upsell")
        expectation.isInverted = true

        sut.$shouldShowUpsell
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        contextualOnboardingSubject.send(true)

        wait(for: [expectation], timeout: 1.0)
        // Then
        XCTAssertFalse(sut.shouldShowUpsell)
    }

    func testWhenOnlyDefaultBrowserIsSet_ItDoesNotStartTimer() {
        sut = createSUT(isFirstLaunch: true, isNewUser: true, isUserAuthenticated: false, timerDuration: 0.1)

        let expectation = XCTestExpectation(description: "Should not show upsell")
        expectation.isInverted = true

        sut.$shouldShowUpsell
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        defaultBrowserSubject.send(true)

        wait(for: [expectation], timeout: 1.0)
        // Then
        XCTAssertFalse(sut.shouldShowUpsell)
    }

    func testWhenMultipleTimerStartAttempts_OnlyOneTimerRuns() {
        let expectation = XCTestExpectation(description: "Timer should complete once")
        expectation.expectedFulfillmentCount = 1
        sut = createSUT(isFirstLaunch: true, isNewUser: true, isUserAuthenticated: false, timerDuration: 0.1)

        sut.$shouldShowUpsell
            .dropFirst()
            .sink { (shouldShow: Bool) in
                if shouldShow {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        contextualOnboardingSubject.send(true)
        defaultBrowserSubject.send(true)
        contextualOnboardingSubject.send(true)
        defaultBrowserSubject.send(true)

        wait(for: [expectation], timeout: 1.0)
        // Then
        XCTAssertTrue(sut.shouldShowUpsell)
    }

    func testWhenSubscriptionChanges_ItHidesUpsellAndCancelsTimer() {
        let expectation = XCTestExpectation(description: "Visibility should be false")
        sut = createSUT(isFirstLaunch: true, isNewUser: true, isUserAuthenticated: false, timerDuration: 0.1)

        sut.$shouldShowUpsell
            .dropFirst()
            .sink { (shouldShow: Bool) in
                // Then
                XCTAssertFalse(shouldShow)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        contextualOnboardingSubject.send(true)
        defaultBrowserSubject.send(true)

        // When
        mockSubscriptionManager.accessTokenResult = .success("mock-token")
        NotificationCenter.default.post(name: .entitlementsDidChange, object: nil)

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenTimerCompletes_ItUpdatesVisibility() {
        let expectation = XCTestExpectation(description: "Timer completion updates visibility")
        sut = createSUT(isFirstLaunch: true, isNewUser: true, isUserAuthenticated: false, timerDuration: 0.1)

        sut.$shouldShowUpsell
            .dropFirst()
            .sink { (shouldShow: Bool) in
                // Then
                XCTAssertTrue(shouldShow)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        contextualOnboardingSubject.send(true)
        defaultBrowserSubject.send(true)

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenFeatureFlagIsDisabled_ItDoesNotShowUpsell() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        let expectation = XCTestExpectation(description: "Should not show upsell")

        sut = createSUT(isFirstLaunch: true, isNewUser: true, isUserAuthenticated: false, timerDuration: 0.1)

        sut.$shouldShowUpsell
            .dropFirst()
            .sink { (shouldShow: Bool) in
                // Then
                XCTAssertFalse(shouldShow)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        contextualOnboardingSubject.send(true)
        defaultBrowserSubject.send(true)

        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Helpers

extension VPNUpsellVisibilityManagerTests {
    private func createSUT(
        isFirstLaunch: Bool,
        isNewUser: Bool,
        isUserAuthenticated: Bool,
        timerDuration: TimeInterval = 0.1
    ) -> VPNUpsellVisibilityManager {
        mockSubscriptionManager.accessTokenResult = isUserAuthenticated ? .success("mock-token") : .failure(SubscriptionManagerError.noTokenAvailable)

        return VPNUpsellVisibilityManager(
            isFirstLaunch: isFirstLaunch,
            isNewUser: isNewUser,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserPublisher: defaultBrowserSubject.eraseToAnyPublisher(),
            contextualOnboardingPublisher: contextualOnboardingSubject.eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger,
            timerDuration: timerDuration
        )
    }
}

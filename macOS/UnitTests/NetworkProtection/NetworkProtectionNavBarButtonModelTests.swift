//
//  NetworkProtectionNavBarButtonModelTests.swift
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
import NetworkProtectionUI
import BrowserServicesKit
import SubscriptionTestingUtilities
import Subscription
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class NetworkProtectionNavBarButtonModelTests: XCTestCase {

    var sut: NetworkProtectionNavBarButtonModel!
    fileprivate var mockPersistor: MockVPNUpsellUserDefaultsPersistor!
    var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var cancellable: AnyCancellable?

    override func setUp() {
        super.setUp()
        mockPersistor = MockVPNUpsellUserDefaultsPersistor()
        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
    }

    override func tearDown() {
        sut = nil
        cancellable?.cancel()
        cancellable = nil
        mockPersistor = nil
        mockSubscriptionManager = nil
        super.tearDown()
    }

    func testWhenUpsellManagerNeedsToShowVPNButton_ItShowsButton() {
        // Given
        let upsellManager = createUpsellManager(shouldShowUpsell: true)
        sut = createButtonModel(with: upsellManager)
        let expectation = XCTestExpectation(description: "showVPNButton should become true")

        cancellable = sut.$showVPNButton
            .dropFirst()
            .sink { showButton in
                if showButton {
                    expectation.fulfill()
                }
            }

        // When
        sut.updateVisibility()

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(sut.showVPNButton)
    }

    func testWhenUpsellManagerDoesNotNeedToShowVPNButton_ItFallsBackToRegularLogic() {
        // Given
        let upsellManager = createUpsellManager(shouldShowUpsell: false)
        sut = createButtonModel(with: upsellManager)
        let expectation = XCTestExpectation(description: "showVPNButton should become false")

        cancellable = sut.$showVPNButton
            .dropFirst()
            .sink { showButton in
                if !showButton {
                    expectation.fulfill()
                }
            }

        // When
        sut.updateVisibility()

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(sut.showVPNButton)
    }

    func testWhenUpsellButtonIsUnpinned_ItHidesTheButton() {
        // Given
        let upsellManager = createUpsellManager(shouldShowUpsell: true)
        sut = createButtonModel(with: upsellManager)

        var receivedValues: [Bool] = []

        let expectation = XCTestExpectation(description: "Button should be hidden after upsell dismissal")

        cancellable = sut.$showVPNButton
            .dropFirst()
            .sink { showButton in
                receivedValues.append(showButton)
                if receivedValues.count > 1 {
                    expectation.fulfill()
                }
            }

        sut.updateVisibility()

        // When
        upsellManager.handlePinningChange(isPinned: false)

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(receivedValues.first!)
        XCTAssertFalse(receivedValues.last!)
    }

    func testWhenUpsellButtonIsAutoDismissed_ItHidesTheButton() {
        // Given
        mockPersistor.vpnUpsellFirstPinnedDate = Date().addingTimeInterval(-8 * 24 * 60 * 60)

        let upsellManager = createUpsellManager(shouldShowUpsell: false)
        sut = createButtonModel(with: upsellManager)

        let expectation = XCTestExpectation(description: "Button should be hidden due to auto-dismiss")

        cancellable = sut.$showVPNButton
            .dropFirst()
            .sink { showButton in
                if !showButton {
                    expectation.fulfill()
                }
            }

        // When
        sut.updateVisibility()

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(sut.showVPNButton)
    }

    func testWhenUserBecomesAuthenticated_ItHidesTheButton() {
        // Given
        let upsellManager = createUpsellManager(shouldShowUpsell: true)
        sut = createButtonModel(with: upsellManager)

        sut.updateVisibility()

        let expectation = XCTestExpectation(description: "Button should be hidden after authentication")

        cancellable = sut.$showVPNButton
            .dropFirst()
            .sink { showButton in
                if !showButton {
                    expectation.fulfill()
                }
            }

        // When
        mockSubscriptionManager.accessTokenResult = .success("mock-token")
        NotificationCenter.default.post(name: .entitlementsDidChange, object: nil)

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(sut.showVPNButton)
    }

    func testWhenUpsellButtonIsDismissed_ItRemainsHidden() {
        // Given
        mockPersistor.vpnUpsellDismissed = true

        let upsellManager = createUpsellManager(shouldShowUpsell: false)
        sut = createButtonModel(with: upsellManager)

        // When
        sut.updateVisibility()

        // Then
        XCTAssertFalse(sut.showVPNButton)
    }

    func testWhenFeatureFlagIsDisabled_ItDoesNotAffectTheButton() {
        // Given
        let upsellManager = createUpsellManager(
            shouldShowUpsell: false,
            featureEnabled: false
        )
        sut = createButtonModel(with: upsellManager)

        // When
        upsellManager.handlePinningChange(isPinned: false)

        // Then
        XCTAssertFalse(mockPersistor.vpnUpsellDismissed)
        XCTAssertFalse(sut.showVPNButton)
    }

    func testItUpdatesBlueDotVisibility() {
        // Given
        let upsellManager = createUpsellManager(shouldShowUpsell: true)
        sut = createButtonModel(with: upsellManager)

        let expectation = XCTestExpectation(description: "shouldShowNotificationDot should become false")

        cancellable = sut.$shouldShowNotificationDot
            .dropFirst()
            .sink { shouldShowNotificationDot in
                if !shouldShowNotificationDot {
                    expectation.fulfill()
                }
            }

        // When
        upsellManager.dismissNotificationDot()

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(sut.shouldShowNotificationDot)
    }
}

// MARK: - Helpers

extension NetworkProtectionNavBarButtonModelTests {
    private func createUpsellManager(
        shouldShowUpsell: Bool,
        featureEnabled: Bool = true
    ) -> VPNUpsellVisibilityManager {
        let mockFeatureFlagger = MockFeatureFlagger()
        let mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockDefaultBrowserProvider.isDefault = true

        if featureEnabled && shouldShowUpsell {
            mockFeatureFlagger.enabledFeatureFlags = [.vpnToolbarUpsell]
        }

        let manager = VPNUpsellVisibilityManager(
            isFirstLaunch: false,
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserProvider: mockDefaultBrowserProvider,
            contextualOnboardingPublisher: Just(true).eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger,
            persistor: mockPersistor,
            timerDuration: 0.01
        )

        manager.setup(isFirstLaunch: false)

        return manager
    }

    private func createButtonModel(with upsellManager: VPNUpsellVisibilityManager) -> NetworkProtectionNavBarButtonModel {
        let popoverManager = NetPPopoverManagerMock()
        let pinningManager = TestPinningManager()
        let vpnGatekeeper = MockVPNFeatureGatekeeper(
            canStartVPN: true,
            isInstalled: true,
            isVPNVisible: true,
            onboardStatusPublisher: Just(.completed).eraseToAnyPublisher()
        )
        let statusReporter = TestNetworkProtectionStatusReporter()
        let iconProvider = NavigationBarIconProvider()

        return NetworkProtectionNavBarButtonModel(
            popoverManager: popoverManager,
            pinningManager: pinningManager,
            vpnGatekeeper: vpnGatekeeper,
            statusReporter: statusReporter,
            iconProvider: iconProvider,
            vpnUpsellVisibilityManager: upsellManager
        )
    }
}

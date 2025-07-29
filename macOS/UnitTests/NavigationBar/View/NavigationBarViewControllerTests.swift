//
//  NavigationBarViewControllerTests.swift
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
final class NavigationBarVPNNotificationTests: XCTestCase {

    var networkProtectionButtonModel: NetworkProtectionNavBarButtonModel!
    var networkProtectionButton: NetworkProtectionButton!
    var cancellable: AnyCancellable?
    fileprivate var mockPersistor: MockVPNUpsellUserDefaultsPersistor!
    var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var mockFeatureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        mockPersistor = MockVPNUpsellUserDefaultsPersistor()
        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        mockFeatureFlagger = MockFeatureFlagger()
        networkProtectionButton = NetworkProtectionButton()
    }

    override func tearDown() {
        cancellable?.cancel()
        cancellable = nil
        networkProtectionButtonModel = nil
        networkProtectionButton = nil
        mockPersistor = nil
        mockSubscriptionManager = nil
        mockFeatureFlagger = nil
        super.tearDown()
    }

    func testWhenShowingUpsellButton_TheVPNButtonShowsNotification() {
        // Given
        createModelWithUpsellState(shouldShowUpsell: true)
        let expectation = XCTestExpectation(description: "Notification should become visible")

        cancellable = networkProtectionButtonModel.$shouldShowUpsell
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] shouldShowUpsell in
                self?.networkProtectionButton.isNotificationVisible = shouldShowUpsell
                if shouldShowUpsell {
                    expectation.fulfill()
                }
            }

        // When
        networkProtectionButtonModel.updateVisibility()

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(networkProtectionButton.isNotificationVisible)
    }

    func testWhenNotShowingUpsellButton_TheVPNButtonHidesNotification() {
        // Given
        createModelWithUpsellState(shouldShowUpsell: false)
        let expectation = XCTestExpectation(description: "Notification should remain hidden")

        cancellable = networkProtectionButtonModel.$shouldShowUpsell
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] shouldShowUpsell in
                self?.networkProtectionButton.isNotificationVisible = shouldShowUpsell
                if !shouldShowUpsell {
                    expectation.fulfill()
                }
            }

        // When
        networkProtectionButtonModel.updateVisibility()

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(networkProtectionButton.isNotificationVisible)
    }

    // MARK: - Helpers

    private func createModelWithUpsellState(shouldShowUpsell: Bool) {
        let vpnUpsellVisibilityManager = createUpsellManager(shouldShowUpsell: shouldShowUpsell)
        networkProtectionButtonModel = createButtonModel(with: vpnUpsellVisibilityManager)
    }

    private func createUpsellManager(shouldShowUpsell: Bool, featureEnabled: Bool = true) -> VPNUpsellVisibilityManager {
        if featureEnabled && shouldShowUpsell {
            mockFeatureFlagger.enabledFeatureFlags = [.vpnToolbarUpsell]
        }

        return VPNUpsellVisibilityManager(
            isFirstLaunch: false,
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserPublisher: Just(true).eraseToAnyPublisher(),
            contextualOnboardingPublisher: Just(true).eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger,
            persistor: mockPersistor,
            timerDuration: 0.01
        )
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

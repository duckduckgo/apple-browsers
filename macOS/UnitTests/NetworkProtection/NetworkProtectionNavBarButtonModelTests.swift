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
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class NetworkProtectionNavBarButtonModelTests: XCTestCase {

    var sut: NetworkProtectionNavBarButtonModel!
    var cancellable: AnyCancellable?

    override func tearDown() {
        sut = nil
        cancellable?.cancel()
        cancellable = nil
        super.tearDown()
    }

    func testWhenUpsellManagerNeedsToShowVPNButton_ItShowsButton() {
        // Given
        let upsellManager = createUpsellManager(shouldShowUpsell: true)
        sut = createButtonModel(with: upsellManager)
        let expectation = XCTestExpectation(description: "showVPNButton should become true")

        cancellable = sut.$showVPNButton
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
}

// MARK: - Helpers

extension NetworkProtectionNavBarButtonModelTests {
    private func createUpsellManager(shouldShowUpsell: Bool) -> VPNUpsellVisibilityManager {
        let mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        let mockFeatureFlagger = MockFeatureFlagger()

        if shouldShowUpsell {
            mockFeatureFlagger.enabledFeatureFlags = [.vpnToolbarUpsell]
        }

        return VPNUpsellVisibilityManager(
            isFirstLaunch: false,
            isNewUser: true,
            subscriptionManager: mockSubscriptionManager,
            defaultBrowserPublisher: Just(true).eraseToAnyPublisher(),
            contextualOnboardingPublisher: Just(true).eraseToAnyPublisher(),
            featureFlagger: mockFeatureFlagger
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

// MARK: - Mocks

private final class TestPinningManager: PinningManager {
    func togglePinning(for view: PinnableView) {}
    func isPinned(_ view: PinnableView) -> Bool { false }
    func wasManuallyToggled(_ view: PinnableView) -> Bool { false }
    func pin(_ view: PinnableView) {}
    func unpin(_ view: PinnableView) {}
    func shortcutTitle(for view: PinnableView) -> String { "" }
}

private final class TestNetworkProtectionStatusReporter: NetworkProtectionStatusReporter {
    private let ipcClient = IPCClientMock()

    var statusObserver: ConnectionStatusObserver { ipcClient.ipcStatusObserver }
    var serverInfoObserver: ConnectionServerInfoObserver { ipcClient.ipcServerInfoObserver }
    var connectionErrorObserver: ConnectionErrorObserver { ipcClient.ipcConnectionErrorObserver }
    var connectivityIssuesObserver: ConnectivityIssueObserver { ipcClient.ipcConnectivityIssuesObserver }
    var controllerErrorMessageObserver: ControllerErrorMesssageObserver { ipcClient.ipcControllerErrorMessageObserver }
    var dataVolumeObserver: DataVolumeObserver { ipcClient.ipcDataVolumeObserver }
    var knownFailureObserver: KnownFailureObserver { ipcClient.ipcKnownFailureObserver }
}

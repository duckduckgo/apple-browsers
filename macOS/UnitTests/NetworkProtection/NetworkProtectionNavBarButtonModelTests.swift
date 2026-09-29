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
import PrivacyConfig
import SubscriptionTestingUtilities
import Subscription
@testable import DuckDuckGo_Privacy_Browser
@_spi(Testing) import Networking

@MainActor
final class NetworkProtectionNavBarButtonModelTests: XCTestCase {

    var sut: NetworkProtectionNavBarButtonModel!
    fileprivate var mockPersistor: MockVPNUpsellUserDefaultsPersistor!
    var mockSubscriptionManager: SubscriptionManagerMock!
    var cancellable: AnyCancellable?
    private var buttonDelegate: VPNUpsellToolbarButtonPromoDelegate!
    private var dotDelegate: VPNUpsellDotBadgePromoDelegate!
    private var showTasks: [Task<PromoResult, Never>] = []

    override func setUp() {
        super.setUp()
        mockPersistor = MockVPNUpsellUserDefaultsPersistor()
        mockSubscriptionManager = SubscriptionManagerMock()
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        showTasks = []
    }

    override func tearDown() {
        buttonDelegate?.hide()
        dotDelegate?.hide()
        showTasks = []
        buttonDelegate = nil
        dotDelegate = nil
        sut = nil
        cancellable?.cancel()
        cancellable = nil
        mockPersistor = nil
        mockSubscriptionManager = nil
        super.tearDown()
    }

    func testWhenUpsellManagerNeedsToShowVPNButton_ItShowsButton() async {
        // Given
        sut = createButtonModel()
        await settleInitialVisibilityUpdate()

        // When
        await showButtonPromo()

        // Then
        await waitUntil(sut.$showVPNButton, equals: true)
        XCTAssertTrue(sut.showVPNButton)
    }

    func testWhenUpsellManagerDoesNotNeedToShowVPNButton_ItFallsBackToRegularLogic() async {
        // Given
        sut = createButtonModel()

        // When
        sut.updateVisibility()

        // Then
        await waitUntil(sut.$showVPNButton, equals: false)
        XCTAssertFalse(sut.showVPNButton)
    }

    func testWhenUpsellButtonIsUnpinned_ItHidesTheButton() async {
        // Given
        sut = createButtonModel()
        await settleInitialVisibilityUpdate()
        await showButtonPromo()
        await waitUntil(sut.$showVPNButton, equals: true)

        // When
        buttonDelegate.handlePinningChange(isPinned: false)

        // Then
        await waitUntil(sut.$showVPNButton, equals: false)
        XCTAssertFalse(sut.showVPNButton)
        XCTAssertFalse(sut.shouldShowUpsell)
    }

    func testWhenUpsellIsDismissed_ItHidesTheButton() async {
        // Given
        sut = createButtonModel()
        await settleInitialVisibilityUpdate()
        await showButtonPromo()
        await waitUntil(sut.$showVPNButton, equals: true)

        // When
        buttonDelegate.dismissUpsell()

        // Then
        await waitUntil(sut.$showVPNButton, equals: false)
        XCTAssertFalse(sut.showVPNButton)
    }

    func testWhenButtonPromoIsHidden_ItHidesTheButton() async {
        // Given
        sut = createButtonModel()
        await settleInitialVisibilityUpdate()
        await showButtonPromo()
        await waitUntil(sut.$showVPNButton, equals: true)

        // When
        buttonDelegate.hide()

        // Then
        await waitUntil(sut.$showVPNButton, equals: false)
        XCTAssertFalse(sut.showVPNButton)
    }

    func testWhenOnlyButtonPromoIsShowing_NotificationDotIsHidden() async {
        // Given
        sut = createButtonModel()

        // When
        await showButtonPromo()
        await waitUntil(sut.$shouldShowUpsell, equals: true)

        // Then
        XCTAssertTrue(sut.shouldShowUpsell)
        XCTAssertFalse(sut.shouldShowNotificationDot)
    }

    func testWhenOnlyDotPromoIsShowing_NotificationDotIsHidden() async {
        // Given
        sut = createButtonModel()

        // When
        await showDotPromo()
        await Task.yield()
        await Task.yield()

        // Then
        XCTAssertFalse(sut.shouldShowUpsell)
        XCTAssertFalse(sut.shouldShowNotificationDot)
    }

    func testWhenButtonAndDotPromosAreShowing_NotificationDotIsShown() async {
        // Given
        sut = createButtonModel()

        // When
        await showButtonPromo()
        await showDotPromo()

        // Then
        await waitUntil(sut.$shouldShowNotificationDot, equals: true)
        XCTAssertTrue(sut.shouldShowNotificationDot)
    }

    func testWhenDotPromoResolves_NotificationDotIsHiddenButButtonRemains() async {
        // Given
        sut = createButtonModel()
        await settleInitialVisibilityUpdate()
        await showButtonPromo()
        await showDotPromo()
        await waitUntil(sut.$shouldShowNotificationDot, equals: true)

        // When
        dotDelegate.buttonClicked()

        // Then
        await waitUntil(sut.$shouldShowNotificationDot, equals: false)
        XCTAssertFalse(sut.shouldShowNotificationDot)
        XCTAssertTrue(sut.shouldShowUpsell)
        XCTAssertTrue(sut.showVPNButton)
    }

    func testWhenButtonPromoHides_NotificationDotIsHiddenEvenIfDotPromoIsStillShowing() async {
        // Given
        sut = createButtonModel()
        await settleInitialVisibilityUpdate()
        await showButtonPromo()
        await showDotPromo()
        await waitUntil(sut.$shouldShowNotificationDot, equals: true)

        // When
        buttonDelegate.hide()

        // Then
        await waitUntil(sut.$shouldShowNotificationDot, equals: false)
        XCTAssertFalse(sut.shouldShowNotificationDot)
        XCTAssertFalse(sut.shouldShowUpsell)
    }

}

// MARK: - Helpers

extension NetworkProtectionNavBarButtonModelTests {
    private func showButtonPromo() async {
        let delegate = buttonDelegate!
        showTasks.append(Task { await delegate.show(history: PromoHistoryRecord(id: "vpn-upsell-toolbar-button"), force: true) })
        await Task.yield()
    }

    private func showDotPromo() async {
        let delegate = dotDelegate!
        showTasks.append(Task { await delegate.show(history: PromoHistoryRecord(id: "vpn-upsell-dot-badge"), force: true) })
        await Task.yield()
    }

    /// The model kicks off `updateVisibility()` on init from its status subscriptions. Let those in-flight
    /// updates finish so they can't overwrite the state a test is about to arrange.
    private func settleInitialVisibilityUpdate() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    private func waitUntil<P: Publisher>(_ publisher: P, equals expected: Bool, file: StaticString = #filePath, line: UInt = #line) async where P.Output == Bool, P.Failure == Never {
        let expectation = expectation(description: "value becomes \(expected)")
        // @Published emits in willSet, so hop to the next run loop turn to observe the stored value.
        let cancellable = publisher.first { $0 == expected }.receive(on: DispatchQueue.main).sink { _ in expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()
    }

    private func createButtonModel() -> NetworkProtectionNavBarButtonModel {
        let upsellManager = VPNUpsellVisibilityManager(isNewUser: false,
                                                       subscriptionManager: mockSubscriptionManager,
                                                       defaultBrowserProvider: MockDefaultBrowserProvider(),
                                                       contextualOnboardingPublisher: Just(true).eraseToAnyPublisher(),
                                                       notificationCenter: NotificationCenter())
        buttonDelegate = VPNUpsellToolbarButtonPromoDelegate(featureFlagger: MockFeatureFlagger(),
                                                             visibilityManager: upsellManager,
                                                             persistor: mockPersistor)
        dotDelegate = VPNUpsellDotBadgePromoDelegate(featureFlagger: MockFeatureFlagger(),
                                                     visibilityManager: upsellManager,
                                                     persistor: mockPersistor)

        let popoverManager = NetPPopoverManagerMock()
        let pinningManager = TestPinningManager()
        let vpnGatekeeper = MockVPNFeatureGatekeeper(
            canStartVPN: true,
            isInstalled: true,
            isVPNVisible: true,
            onboardStatusPublisher: Just(.completed).eraseToAnyPublisher()
        )
        let statusReporter = TestNetworkProtectionStatusReporter()

        let themeManager = MockThemeManager()
        return NetworkProtectionNavBarButtonModel(
            popoverManager: popoverManager,
            pinningManager: pinningManager,
            vpnGatekeeper: vpnGatekeeper,
            statusReporter: statusReporter,
            themeManager: themeManager,
            vpnUpsellToolbarButtonPromoDelegate: buttonDelegate,
            vpnUpsellDotBadgePromoDelegate: dotDelegate
        )
    }
}

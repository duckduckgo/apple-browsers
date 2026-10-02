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
    private var pinningManager: RecordingPinningManager!

    override func setUp() {
        super.setUp()
        mockPersistor = MockVPNUpsellUserDefaultsPersistor()
        mockSubscriptionManager = SubscriptionManagerMock()
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        showTasks = []
        pinningManager = RecordingPinningManager()
    }

    override func tearDown() {
        buttonDelegate?.hide()
        dotDelegate?.hide()
        showTasks = []
        buttonDelegate = nil
        dotDelegate = nil
        sut = nil
        pinningManager = nil
        cancellable?.cancel()
        cancellable = nil
        mockPersistor = nil
        mockSubscriptionManager = nil
        super.tearDown()
    }

    func testWhenUpsellManagerNeedsToShowVPNButton_ItShowsButton() async {
        // Given
        sut = await createSettledButtonModel()

        // When
        await showButtonPromo()

        // Then
        await waitUntil(sut.$showVPNButton, equals: true)
        XCTAssertTrue(sut.showVPNButton)
    }

    func testWhenNoUpsellIsShowing_AndVPNCanStartAndIsPinned_ItShowsButton() async {
        // Given
        sut = await createSettledButtonModel()
        XCTAssertFalse(sut.showVPNButton)
        pinningManager.pin(.networkProtection)

        // When
        sut.updateVisibility()

        // Then
        await waitUntil(sut.$showVPNButton, equals: true)
        XCTAssertTrue(sut.showVPNButton)
    }

    func testWhenNoUpsellIsShowing_AndVPNCannotStart_ItUnpinsAndHidesButton() async {
        // Given
        sut = await createSettledButtonModel(canStartVPN: false)
        pinningManager.pin(.networkProtection)

        // When
        sut.updateVisibility()

        // Then
        await waitUntil(pinningManager.$pinned.map { !$0.contains(.networkProtection) }, equals: true)
        XCTAssertFalse(sut.showVPNButton)
        XCTAssertFalse(pinningManager.isPinned(.networkProtection))
    }

    func testWhenUpsellStartsShowingWhileAwaitingCanStartVPN_ItKeepsTheButtonPinnedAndShown() async {
        // Given
        let gate = CanStartVPNGate()
        sut = createButtonModel(canStartVPNGate: gate)
        pinningManager.pin(.networkProtection)
        var showVPNButtonValues: [Bool] = []
        let resumedUpdateAssigned = expectation(description: "resumed update assigns showVPNButton")
        // Emissions: initial value, the upsell showing, then the suspended update once released.
        cancellable = sut.$showVPNButton.sink { value in
            showVPNButtonValues.append(value)
            if showVPNButtonValues.count == 3 { resumedUpdateAssigned.fulfill() }
        }
        await waitUntil(gate.pendingCount.map { $0 >= 1 }, equals: true)

        // When: the promo is restored while the visibility update is suspended, then the update resumes with false
        await showButtonPromo()
        await waitUntil(sut.$showVPNButton, equals: true)
        gate.release(false)

        // Then: the resumed update emits a final value, which must not unpin or hide the button
        await fulfillment(of: [resumedUpdateAssigned], timeout: 2.0)
        XCTAssertEqual(showVPNButtonValues.last, true)
        XCTAssertTrue(pinningManager.isPinned(.networkProtection))
        XCTAssertEqual(pinningManager.unpinCount, 0)
        XCTAssertTrue(sut.showVPNButton)
    }

    func testWhenUpsellButtonIsUnpinned_ItHidesTheButton() async {
        // Given
        sut = await createSettledButtonModel()
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
        sut = await createSettledButtonModel()
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
        sut = await createSettledButtonModel()
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

    func testWhenDotPromoIsShowing_NotificationDotOnlyShowsWhileButtonPromoIsShowing() async {
        // Given
        sut = await createSettledButtonModel()
        await showDotPromo()
        XCTAssertFalse(sut.shouldShowUpsell)

        // When the button promo joins, the dot appears
        await showButtonPromo()
        await waitUntil(sut.$shouldShowNotificationDot, equals: true)

        // When the button promo goes away, the dot goes with it
        buttonDelegate.hide()
        await waitUntil(sut.$shouldShowNotificationDot, equals: false)
        XCTAssertFalse(sut.shouldShowUpsell)
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
        sut = await createSettledButtonModel()
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
        sut = await createSettledButtonModel()
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

    private func waitUntil<P: Publisher>(_ publisher: P, equals expected: Bool, file: StaticString = #filePath, line: UInt = #line) async where P.Output == Bool, P.Failure == Never {
        let expectation = expectation(description: "value becomes \(expected)")
        // @Published emits in willSet, so hop to the next run loop turn to observe the stored value.
        let cancellable = publisher.first { $0 == expected }.receive(on: DispatchQueue.main).sink { _ in expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()
    }

    /// The model runs one `updateVisibility()` from its initial upsell subscription. That update ends by assigning
    /// `showVPNButton`, so waiting for that assignment ensures it can't overwrite state a test is about to arrange.
    private func createSettledButtonModel(canStartVPN: Bool = true) async -> NetworkProtectionNavBarButtonModel {
        let model = createButtonModel(canStartVPN: canStartVPN)
        await waitUntilAssigned(model.$showVPNButton)
        return model
    }

    private func waitUntilAssigned<P: Publisher>(_ publisher: P) async where P.Failure == Never {
        let expectation = expectation(description: "value assigned")
        let cancellable = publisher.dropFirst().first().receive(on: DispatchQueue.main).sink { _ in expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()
    }

    private func createButtonModel(canStartVPN: Bool = true, canStartVPNGate: CanStartVPNGate? = nil) -> NetworkProtectionNavBarButtonModel {
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
        let vpnGatekeeper = MockVPNFeatureGatekeeper(
            canStartVPN: canStartVPN,
            isInstalled: true,
            isVPNVisible: true,
            onboardStatusPublisher: Just(.completed).eraseToAnyPublisher(),
            canStartVPNGate: canStartVPNGate
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

private final class RecordingPinningManager: PinningManager {
    @Published private(set) var pinned: Set<PinnableView> = []
    private(set) var unpinCount = 0

    func togglePinning(for view: PinnableView) {
        if pinned.contains(view) { pinned.remove(view) } else { pinned.insert(view) }
    }
    func isPinned(_ view: PinnableView) -> Bool { pinned.contains(view) }
    // Reports the user as having chosen the pin state, so the model's first-time auto-pin doesn't interfere.
    func wasManuallyToggled(_ view: PinnableView) -> Bool { true }
    func pin(_ view: PinnableView) { pinned.insert(view) }
    func unpin(_ view: PinnableView) {
        unpinCount += 1
        pinned.remove(view)
    }
    func shortcutTitle(for view: PinnableView) -> String { "" }
}

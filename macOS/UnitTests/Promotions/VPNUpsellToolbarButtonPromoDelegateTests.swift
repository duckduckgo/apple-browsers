//
//  VPNUpsellToolbarButtonPromoDelegateTests.swift
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
import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import Subscription
import SubscriptionTestingUtilities
import XCTest
@_spi(Testing) import Networking
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class VPNUpsellToolbarButtonPromoDelegateTests: XCTestCase {

    private static let now = Date()

    private var featureFlagger: MockFeatureFlagger!
    private var notificationCenter: NotificationCenter!
    private var subscriptionManager: SubscriptionManagerMock!
    private var persistor: MockVPNUpsellUserDefaultsPersistor!
    private var manager: VPNUpsellVisibilityManager!
    private var firedPixels: [SubscriptionPixel] = []
    private var isShowing = false
    private var cancellables = Set<AnyCancellable>()
    private var sut: VPNUpsellToolbarButtonPromoDelegate!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub[FeatureFlag.promoQueueVPNUpsellPromo.rawValue] = true
        notificationCenter = NotificationCenter()
        subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        persistor = MockVPNUpsellUserDefaultsPersistor()
        firedPixels = []
        isShowing = false
        manager = makeManager(isNewUser: true)
        sut = makeSUT()
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        manager = nil
        persistor = nil
        subscriptionManager = nil
        notificationCenter = nil
        featureFlagger = nil
        firedPixels = []
        super.tearDown()
    }

    private func makeManager(isNewUser: Bool) -> VPNUpsellVisibilityManager {
        let manager = VPNUpsellVisibilityManager(isNewUser: isNewUser,
                                                 subscriptionManager: subscriptionManager,
                                                 defaultBrowserProvider: MockDefaultBrowserProvider(),
                                                 contextualOnboardingPublisher: Just(true).eraseToAnyPublisher(),
                                                 timerDuration: 0.01,
                                                 notificationCenter: notificationCenter)
        manager.setup(isFirstLaunch: false, isOnboardingFinished: true)
        return manager
    }

    private func makeSUT() -> VPNUpsellToolbarButtonPromoDelegate {
        let sut = VPNUpsellToolbarButtonPromoDelegate(featureFlagger: featureFlagger,
                                                      visibilityManager: manager,
                                                      persistor: persistor,
                                                      pixelHandler: { [unowned self] in self.firedPixels.append($0) },
                                                      dateProvider: { Self.now })
        sut.isShowingPublisher
            .sink { [unowned self] in self.isShowing = $0 }
            .store(in: &cancellables)
        return sut
    }

    /// Starts `show` and yields so it runs up to its suspension point.
    private func startShow(force: Bool = false) async -> Task<PromoResult, Never> {
        let task = Task { await sut.show(history: PromoHistoryRecord(id: "vpn-upsell-toolbar-button"), force: force) }
        await Task.yield()
        XCTAssertTrue(isShowing, "show() did not reach its suspension point")
        return task
    }

    // MARK: - Legacy retirement

    func testWhenLegacyUpsellWasDismissedThenShowRetires() async {
        persistor.legacyUpsellDismissed = true

        let result = await sut.show(history: PromoHistoryRecord(id: "id"), force: false)

        XCTAssertEqual(result, .retired)
        XCTAssertFalse(isShowing)
        XCTAssertTrue(firedPixels.isEmpty)
    }

    func testWhenButtonWasFirstPinnedSevenDaysAgoThenShowRetires() async {
        persistor.legacyFirstPinnedDate = Self.now.addingTimeInterval(.days(-7))

        let result = await sut.show(history: PromoHistoryRecord(id: "id"), force: false)

        XCTAssertEqual(result, .retired)
    }

    func testWhenButtonWasFirstPinnedSixDaysAgoThenShowDoesNotRetire() async {
        persistor.legacyFirstPinnedDate = Self.now.addingTimeInterval(.days(-6))

        let task = await startShow()

        XCTAssertTrue(isShowing)
        sut.hide()
        let result = await task.value
        XCTAssertEqual(result, .noChange)
    }

    func testWhenForcedThenShowBypassesRetirement() async {
        persistor.legacyUpsellDismissed = true
        persistor.legacyFirstPinnedDate = Self.now.addingTimeInterval(.days(-30))

        let task = await startShow(force: true)

        XCTAssertTrue(isShowing)
        sut.hide()
        _ = await task.value
    }

    // MARK: - Showing

    func testWhenShownThenIsShowingAndShownPixelFiredOnce() async {
        let task = await startShow()

        XCTAssertTrue(isShowing)
        XCTAssertEqual(firedPixels.map(\.name), [SubscriptionPixel.subscriptionToolbarButtonShown.name])
        sut.hide()
        _ = await task.value
    }

    func testWhenShownWithForceThenShownPixelIsNotFired() async {
        let task = await startShow(force: true)

        XCTAssertTrue(isShowing)
        XCTAssertTrue(firedPixels.isEmpty)
        sut.hide()
        _ = await task.value
    }

    // MARK: - Resolution

    func testWhenUnpinnedWhileShowingThenPermanentlyIgnored() async {
        let task = await startShow()

        sut.handlePinningChange(isPinned: false)

        let result = await task.value
        XCTAssertEqual(result, .ignored())
        XCTAssertFalse(isShowing)
    }

    func testWhenPinnedWhileShowingThenStaysShown() async {
        let task = await startShow()

        sut.handlePinningChange(isPinned: true)

        XCTAssertTrue(isShowing)
        sut.hide()
        let result = await task.value
        XCTAssertEqual(result, .noChange)
    }

    func testWhenUpsellDismissedWhileShowingThenPermanentlyIgnored() async {
        let task = await startShow()

        sut.dismissUpsell()

        let result = await task.value
        XCTAssertEqual(result, .ignored())
        XCTAssertFalse(isShowing)
    }

    func testWhenNotShowingThenHideUnpinAndDismissDoNothing() async {
        sut.hide()
        sut.handlePinningChange(isPinned: false)
        sut.dismissUpsell()
        XCTAssertFalse(isShowing)

        let task = await startShow()

        // The earlier calls must not have left state behind that resolves or blocks the next show.
        XCTAssertTrue(isShowing)
        sut.dismissUpsell()
        let result = await task.value
        XCTAssertEqual(result, .ignored())
        XCTAssertFalse(isShowing)
        XCTAssertEqual(firedPixels.map(\.name), [SubscriptionPixel.subscriptionToolbarButtonShown.name])
    }
}

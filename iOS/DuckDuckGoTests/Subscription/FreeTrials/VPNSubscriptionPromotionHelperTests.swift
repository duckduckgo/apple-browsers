//
//  VPNSubscriptionPromotionHelperTests.swift
//  DuckDuckGo
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
@testable import Subscription
import Core
import PersistenceTestingUtils
import SubscriptionTestingUtilities
@testable import DuckDuckGo

final class VPNSubscriptionPromotionHelperTests: XCTestCase {

    private var sut: VPNSubscriptionPromotionHelping!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    private var mockFreeTrialsHelper: MockSubscriptionFreeTrialsHelper!
    private var mockKeyValueStore: MockKeyValueStore!
    private var mockFreeTrialBadgePersistor: FreeTrialBadgePersisting!
    private var mockPixelFiring: PixelFiringMock!

    override func setUpWithError() throws {
        mockFeatureFlagger = MockFeatureFlagger()
        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        mockFreeTrialsHelper = MockSubscriptionFreeTrialsHelper()
        mockKeyValueStore = MockKeyValueStore()
        mockFreeTrialBadgePersistor = FreeTrialBadgePersistor(keyValueStore: mockKeyValueStore)
        sut = VPNSubscriptionPromotionHelper(featureFlagger: mockFeatureFlagger,
                                             subscriptionManager: mockSubscriptionManager,
                                             freeTrialsHelper: mockFreeTrialsHelper,
                                             freeTrialBadgePersistor: mockFreeTrialBadgePersistor,
                                             pixelFiring: PixelFiringMock.self)
    }

    override func tearDownWithError() throws {
        sut = nil
        mockFeatureFlagger = nil
        mockSubscriptionManager = nil
        mockFreeTrialsHelper = nil
        mockKeyValueStore = nil
        mockFreeTrialBadgePersistor = nil
        mockPixelFiring = nil
    }

    func testWhenSubscriptionIsActive_subscriptionPromoStatusIsSubscribed() {
        // When
        let startedAt = Date().startOfDay
        let expiresAt = Date().startOfDay.daysAgo(-10)
        let subscription = DuckDuckGoSubscription(
            productId: "test",
            name: "test",
            billingPeriod: .yearly,
            startedAt: startedAt,
            expiresOrRenewsAt: expiresAt,
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: []
        )
        mockSubscriptionManager.returnSubscription = .success(subscription)

        // Then
        XCTAssertEqual(sut.subscriptionPromoStatus, .subscribed)
    }

    func testWhenSubscriptionIsNotActive_AndShouldDisplayIsTrue_subscriptionPromoStatusIsPill() {
        // When
        mockSubscriptionManager.returnSubscription = .none
        mockFeatureFlagger.enabledFeatureFlags = [.vpnMenuItem]
        mockFreeTrialsHelper.areFreeTrialsEnabledValue = true
        mockKeyValueStore.set(0, forKey: "free-trial-badge.view-count")

        // Then
        XCTAssertEqual(sut.subscriptionPromoStatus, .pill)
    }

    func testWhenSubscriptionIsNotActive_AndFeatureFlaggerIsDisabled_subscriptionPromoStatusIsNoPill() {
        // When
        mockSubscriptionManager.returnSubscription = .none
        mockFeatureFlagger.enabledFeatureFlags = []
        mockFreeTrialsHelper.areFreeTrialsEnabledValue = true
        mockKeyValueStore.set(0, forKey: "free-trial-badge.view-count")

        // Then
        XCTAssertEqual(sut.subscriptionPromoStatus, .noPill)
    }

    func testWhenSubscriptionIsNotActive_AndFreeTrialsAreDisabled_subscriptionPromoStatusIsNoPill() {
        // When
        mockSubscriptionManager.returnSubscription = .none
        mockFeatureFlagger.enabledFeatureFlags = [.vpnMenuItem]
        mockFreeTrialsHelper.areFreeTrialsEnabledValue = false
        mockKeyValueStore.set(0, forKey: "free-trial-badge.view-count")

        // Then
        XCTAssertEqual(sut.subscriptionPromoStatus, .noPill)
    }

    func testWhenSubscriptionIsNotActive_AndBadgeLimitIsReached_subscriptionPromoStatusIsNoPill() {
        // When
        mockSubscriptionManager.returnSubscription = .none
        mockFeatureFlagger.enabledFeatureFlags = [.vpnMenuItem]
        mockFreeTrialsHelper.areFreeTrialsEnabledValue = true
        mockKeyValueStore.set(4, forKey: "free-trial-badge.view-count")

        // Then
        XCTAssertEqual(sut.subscriptionPromoStatus, .noPill)
    }

    func testSubscriptionURLComponents() {
        // When
        let components = sut.subscriptionURLComponents()

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "origin" })?.value, SubscriptionFunnelOrigin.newTabMenu.rawValue)
    }

    func testSubscriptionPromoWasShown_IncrementsPersistorCount() {
        // When
        mockFeatureFlagger.enabledFeatureFlags = [.vpnMenuItem]
        sut.subscriptionPromoWasShown()

        // Then
        XCTAssertEqual(mockFreeTrialBadgePersistor.viewCount, 1)
    }

    func testWhenFeatureFlagIsDisabled_SubscriptionPromoWasShown_DoesNotIncrementPersistorCount() {
        // When
        mockFeatureFlagger.enabledFeatureFlags = []
        sut.subscriptionPromoWasShown()

        // Then
        XCTAssertEqual(mockFreeTrialBadgePersistor.viewCount, 0)
    }


    func testFireTapPixel() {
        // When
        sut.fireTapPixel()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.browsingMenuVPN.name)
        XCTAssertEqual(PixelFiringMock.lastParams, ["status": "no_pill"])
    }

}

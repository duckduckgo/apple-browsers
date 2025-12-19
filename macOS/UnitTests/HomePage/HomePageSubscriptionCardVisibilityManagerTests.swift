//
//  HomePageSubscriptionCardVisibilityManagerTests.swift
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

import Foundation
import Combine
import XCTest
import SubscriptionTestingUtilities

@testable import Subscription
@testable import DuckDuckGo_Privacy_Browser

final class HomePageSubscriptionCardVisibilityManagerTests: XCTestCase {
    var sut: HomePageSubscriptionCardVisibilityManager!
    var subscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var persistor: MockHomePageSubscriptionCardPersisting!
    var cancellable: AnyCancellable!

    override func setUp() {
        super.setUp()
        subscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        subscriptionManager.returnSubscription = .failure(SubscriptionManagerError.noTokenAvailable)
        persistor = MockHomePageSubscriptionCardPersisting()
    }

    override func tearDown() {
        subscriptionManager = nil
        persistor = nil
        sut = nil
        cancellable = nil
        super.tearDown()
    }

    func testWhenUserHasSubscription_ItDoesNotShowCard() {
        let expectation = XCTestExpectation(description: "shouldShowSubscriptionCard should be false")
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
            activeOffers: [],
            tier: nil
        )
        subscriptionManager.returnSubscription = .success(subscription)

        sut = HomePageSubscriptionCardVisibilityManager(subscriptionManager: subscriptionManager, persistor: persistor)

        cancellable = sut.$shouldShowSubscriptionCard.sink { shouldShowSubscriptionCard in
            if !shouldShowSubscriptionCard {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenUserHasSubscription_ItStoresFlagInPersistor() {
        let expectation = XCTestExpectation(description: "userHadSubscription should be true")
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
            activeOffers: [],
            tier: nil
        )
        subscriptionManager.returnSubscription = .success(subscription)

        sut = HomePageSubscriptionCardVisibilityManager(subscriptionManager: subscriptionManager, persistor: persistor)

        cancellable = sut.$shouldShowSubscriptionCard.sink { [weak self] _ in
            if self?.persistor.userHadSubscription ?? false {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenUserDoesNotInitiallyHaveSubscription_ButLaterSubscribes_ItHidesCard() {
        let expectation = XCTestExpectation(description: "shouldShowSubscriptionCard should be false")

        sut = HomePageSubscriptionCardVisibilityManager(subscriptionManager: subscriptionManager, persistor: persistor)

        cancellable = sut.$shouldShowSubscriptionCard.sink { shouldShowSubscriptionCard in
            if !shouldShowSubscriptionCard {
                expectation.fulfill()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .entitlementsDidChange, object: nil)
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenUserHadAPreviousSubscriptionItDoesNotShowCard() {
        let expectation = XCTestExpectation(description: "shouldShowSubscriptionCard should be false")
        persistor.userHadSubscription = true

        sut = HomePageSubscriptionCardVisibilityManager(subscriptionManager: subscriptionManager, persistor: persistor)

        cancellable = sut.$shouldShowSubscriptionCard.sink { shouldShowSubscriptionCard in
            if !shouldShowSubscriptionCard {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenUserHadPreviousDismissedSubscriptionCard_ItDoesNotShowCard() {
        let expectation = XCTestExpectation(description: "shouldShowSubscriptionCard should be false")
        persistor.shouldShowSubscriptionSetting = false

        sut = HomePageSubscriptionCardVisibilityManager(subscriptionManager: subscriptionManager, persistor: persistor)

        cancellable = sut.$shouldShowSubscriptionCard.sink { shouldShowSubscriptionCard in
            if !shouldShowSubscriptionCard {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenUserCannotPurchaseSubscriptionItDoesNotShowCard() {
        let expectation = XCTestExpectation(description: "shouldShowSubscriptionCard should be false")

        sut = HomePageSubscriptionCardVisibilityManager(subscriptionManager: subscriptionManager, persistor: persistor)

        cancellable = sut.$shouldShowSubscriptionCard.sink { shouldShowSubscriptionCard in
            if !shouldShowSubscriptionCard {
                expectation.fulfill()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.subscriptionManager.hasAppStoreProductsAvailableSubject.send(false)
        }

        wait(for: [expectation], timeout: 1.0)
    }
}

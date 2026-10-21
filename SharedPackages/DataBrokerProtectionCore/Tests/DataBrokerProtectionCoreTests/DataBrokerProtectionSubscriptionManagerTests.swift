//
//  DataBrokerProtectionSubscriptionManagerTests.swift
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
@testable import DataBrokerProtectionCore
import Common
import SubscriptionTestingUtilities
import Subscription

final class DataBrokerProtectionSubscriptionManagerTests: XCTestCase {

    var subscriptionManager: DataBrokerProtectionSubscriptionManager!
    var mockSubscriptionManager: SubscriptionManagerMock!
    var mockRunTypeProvider: MockAppRunTypeProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockSubscriptionManager = SubscriptionManagerMock()
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        mockRunTypeProvider = MockAppRunTypeProvider()
        subscriptionManager = DataBrokerProtectionSubscriptionManager(
            subscriptionManager: mockSubscriptionManager,
            runTypeProvider: mockRunTypeProvider
        )
    }

    override func tearDownWithError() throws {
        subscriptionManager = nil
        mockSubscriptionManager = nil
        mockRunTypeProvider = nil
        try super.tearDownWithError()
    }

    func testWhenSubscriptionBridgeReturnsTrue_isUserEligibleForFreeTrial_ReturnsTrue() {
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        XCTAssertTrue(subscriptionManager.isUserEligibleForFreeTrial())
    }

    func testWhenSubscriptionBridgeReturnsFalse_isUserEligibleForFreeTrial_ReturnsFalse() {
        mockSubscriptionManager.isEligibleForFreeTrialResult = false
        XCTAssertFalse(subscriptionManager.isUserEligibleForFreeTrial())
    }

    func testWhenSubscriptionPlatformIsStripe_isUserEligibleForFreeTrial_ReturnsTrue() {
        mockSubscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        XCTAssertTrue(subscriptionManager.isUserEligibleForFreeTrial())
    }
}

final class MockAppRunTypeProvider: AppRunTypeProviding {
    var runType = AppVersion.AppRunType.unitTests
}

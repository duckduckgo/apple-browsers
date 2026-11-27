//
//  VPNSettingsEnvironmentTests.swift
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

import Subscription
import VPN
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class VPNSettingsEnvironmentTests: XCTestCase {

    private var suiteName: String!
    private var settings: VPNSettings!

    override func setUp() {
        super.setUp()
        suiteName = "VPNSettingsEnvironmentTests-\(UUID().uuidString)"
        settings = VPNSettings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        settings = nil
        suiteName = nil
        super.tearDown()
    }

    private func subscriptionEnvironment(_ serviceEnvironment: SubscriptionEnvironment.ServiceEnvironment) -> SubscriptionEnvironment {
        SubscriptionEnvironment(serviceEnvironment: serviceEnvironment, purchasePlatform: .stripe)
    }

    func testWhenTheSubscriptionIsProductionThenTheStagingVPNSwitchesToProduction() {
        settings.selectedEnvironment = .staging

        settings.alignTo(subscriptionEnvironment: subscriptionEnvironment(.production))

        XCTAssertEqual(settings.selectedEnvironment, .production)
    }

    func testWhenTheSubscriptionIsStagingThenTheProductionVPNSwitchesToStaging() {
        settings.selectedEnvironment = .production

        settings.alignTo(subscriptionEnvironment: subscriptionEnvironment(.staging))

        XCTAssertEqual(settings.selectedEnvironment, .staging)
    }

    func testWhenTheSubscriptionSwitchesBackAndForthThenTheVPNFollowsEachTime() {
        settings.alignTo(subscriptionEnvironment: subscriptionEnvironment(.staging))
        XCTAssertEqual(settings.selectedEnvironment, .staging)

        settings.alignTo(subscriptionEnvironment: subscriptionEnvironment(.production))
        XCTAssertEqual(settings.selectedEnvironment, .production)

        settings.alignTo(subscriptionEnvironment: subscriptionEnvironment(.staging))
        XCTAssertEqual(settings.selectedEnvironment, .staging)
    }
}

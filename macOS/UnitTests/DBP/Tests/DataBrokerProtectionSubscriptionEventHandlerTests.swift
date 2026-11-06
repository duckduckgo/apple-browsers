//
//  DataBrokerProtectionSubscriptionEventHandlerTests.swift
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

import XCTest
import Common
import DataBrokerProtection_macOS
import DataBrokerProtectionCore

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DataBrokerProtectionSubscriptionEventHandlerTests: XCTestCase {

    private var featureDisabler: MockFeatureDisabler!
    private var authenticationManager: MockEntitlementStatusAuthenticationManager!
    private var firedPixels: [String] = []
    private var sut: DataBrokerProtectionSubscriptionEventHandler!

    override func setUp() async throws {
        featureDisabler = MockFeatureDisabler()
        authenticationManager = MockEntitlementStatusAuthenticationManager()
        firedPixels = []
        let pixelHandler = EventMapping<DataBrokerProtectionMacOSPixels> { [weak self] event, _, _, _ in
            self?.firedPixels.append(String(describing: event))
        }
        sut = DataBrokerProtectionSubscriptionEventHandler(featureDisabler: featureDisabler,
                                                           authenticationManager: authenticationManager,
                                                           pixelHandler: pixelHandler)
    }

    override func tearDown() async throws {
        sut = nil
        authenticationManager = nil
        featureDisabler = nil
    }

    func testEntitlementLost_tokenWithoutTheEntitlement_disablesAndDeletes() async {
        authenticationManager.entitlementStatusValue = .disabled

        await sut.entitlementsDidChange(hasEntitlements: false)

        XCTAssertTrue(featureDisabler.disableAndDeleteWasCalled)
        XCTAssertEqual(firedPixels, ["entitlementCheckInvalid"])
    }

    func testEntitlementLost_noTokenCanBeRead_keepsTheData() async {
        authenticationManager.entitlementStatusValue = .error

        await sut.entitlementsDidChange(hasEntitlements: false)

        XCTAssertFalse(featureDisabler.disableAndDeleteWasCalled)
        XCTAssertEqual(firedPixels, ["entitlementCheckError"])
    }

    func testEntitlementLost_tokenRestoredWithTheEntitlement_keepsTheData() async {
        authenticationManager.entitlementStatusValue = .enabled

        await sut.entitlementsDidChange(hasEntitlements: false)

        XCTAssertFalse(featureDisabler.disableAndDeleteWasCalled)
        XCTAssertEqual(firedPixels, ["entitlementCheckValid"])
    }

    func testEntitlementGained_keepsTheDataWithoutCheckingTheToken() async {
        authenticationManager.entitlementStatusValue = .disabled

        await sut.entitlementsDidChange(hasEntitlements: true)

        XCTAssertFalse(featureDisabler.disableAndDeleteWasCalled)
        XCTAssertEqual(firedPixels, ["entitlementCheckValid"])
        XCTAssertEqual(authenticationManager.entitlementStatusCallCount, 0)
    }

    func testSignOut_disablesAndDeletes() {
        sut.handleAccountDidSignOut()

        XCTAssertTrue(featureDisabler.disableAndDeleteWasCalled)
    }
}

private final class MockEntitlementStatusAuthenticationManager: DataBrokerProtectionAuthenticationManaging {
    var entitlementStatusValue: DataBrokerProtectionEntitlementStatus = .error
    private(set) var entitlementStatusCallCount = 0

    var isUserAuthenticated: Bool { get async { false } }
    var isUserEligibleForFreeTrial: Bool { false }
    func accessToken() async -> String? { nil }
    func getAuthHeader() async -> String? { nil }

    func entitlementStatus() async -> DataBrokerProtectionEntitlementStatus {
        entitlementStatusCallCount += 1
        return entitlementStatusValue
    }
}

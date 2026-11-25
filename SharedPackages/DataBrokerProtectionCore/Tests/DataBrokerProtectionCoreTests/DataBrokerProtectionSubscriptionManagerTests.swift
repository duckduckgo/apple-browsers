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
@_spi(Testing) import Networking
import DataBrokerProtectionDebugServer

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

    #if DEBUG
    func testLaunchOverridePrecedesSavedAndIntegrationTokensWithoutChangingAccount() async throws {
        let saved = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultTokenContainer = saved
        mockSubscriptionManager.resultFeatures = [.dataBrokerProtection]
        mockRunTypeProvider.runType = .integrationTests
        let manager = subscriptionManager.debugRunnerManager(environment: ["PIR_DEBUG_ACCESS_TOKEN": "provided-token"])
        XCTAssertFalse(subscriptionManager.isDebugAccessTokenProvided)
        let authentication = DataBrokerProtectionAuthenticationManager(subscriptionManager: manager)
        let token = await manager.accessToken()
        let header = await authentication.getAuthHeader()
        let entitled = try await manager.hasValidEntitlement()
        let debugEntitled = try await manager.debugEntitlement()
        XCTAssertEqual(token, "provided-token")
        XCTAssertEqual(header, "bearer provided-token")
        XCTAssertFalse(entitled)
        XCTAssertFalse(debugEntitled)
        XCTAssertFalse(manager.isEntitlementCheckBypassed)
        XCTAssertEqual(mockSubscriptionManager.getAccessTokenCallCount, 0)
        XCTAssertEqual(mockSubscriptionManager.getTokenContainerCallCount, 0)
        XCTAssertEqual(mockSubscriptionManager.isFeatureEnabledCallCount, 0)
        XCTAssertEqual(mockSubscriptionManager.resultTokenContainer?.accessToken, saved.accessToken)
    }

    @MainActor
    func testLaunchOverrideDiagnosticsNeverClaimSavedEntitlementOrIntegrationBypass() async throws {
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockRunTypeProvider.runType = .integrationTests
        let manager = subscriptionManager.debugRunnerManager(environment: ["PIR_DEBUG_ACCESS_TOKEN": "private-credential"])
        let suite = "PIRSubscriptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DataBrokerProtectionSettings(defaults: defaults, debugEnvironment: .staging)
        let result = await DebugPrerequisiteResult.subscription(manager, settings: settings)
        XCTAssertEqual(result.status, .credentialProvided)
        XCTAssertEqual(result.backend, "provided-token")
        XCTAssertEqual(result.environment, "staging")
        XCTAssertEqual(result.authenticated, true)
        XCTAssertNil(result.entitled)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(result), encoding: .utf8))
        XCTAssertFalse(json.contains("private-credential"))
        XCTAssertEqual(mockSubscriptionManager.getTokenContainerCallCount, 0)
    }

    func testInvalidLaunchOverrideFailsClosedWithoutReadingSavedAccount() async throws {
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockRunTypeProvider.runType = .integrationTests
        for invalid in ["", "token with space", "token\n", "token\u{0}", String(repeating: "a", count: 65_537)] {
            let manager = subscriptionManager.debugRunnerManager(environment: ["PIR_DEBUG_ACCESS_TOKEN": invalid])
            let authentication = DataBrokerProtectionAuthenticationManager(subscriptionManager: manager)
            let token = await manager.accessToken()
            let header = await authentication.getAuthHeader()
            let authenticated = await authentication.isUserAuthenticated
            let entitled = try await manager.hasValidEntitlement()
            XCTAssertTrue(manager.isDebugAccessTokenProvided)
            XCTAssertFalse(manager.isDebugAccessTokenValid)
            XCTAssertNil(token)
            XCTAssertNil(header)
            XCTAssertFalse(authenticated)
            XCTAssertFalse(entitled)
        }
        XCTAssertEqual(mockSubscriptionManager.getAccessTokenCallCount, 0)
        XCTAssertEqual(mockSubscriptionManager.getTokenContainerCallCount, 0)
        XCTAssertEqual(mockSubscriptionManager.isFeatureEnabledCallCount, 0)
    }
    #endif

    func testAbsentOverrideKeepsSavedAccountAndEntitlementPolicy() async throws {
        let saved = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultTokenContainer = saved
        mockSubscriptionManager.resultFeatures = [.dataBrokerProtection]
        let token = await subscriptionManager.accessToken()
        let entitled = try await subscriptionManager.hasValidEntitlement()
        let debugEntitled = try await subscriptionManager.debugEntitlement()
        XCTAssertEqual(token, saved.accessToken)
        XCTAssertTrue(entitled)
        XCTAssertTrue(debugEntitled)
        XCTAssertFalse(subscriptionManager.isDebugAccessTokenProvided)
        XCTAssertEqual(mockSubscriptionManager.getAccessTokenCallCount, 1)
        XCTAssertEqual(mockSubscriptionManager.getTokenContainerCallCount, 1)
        XCTAssertEqual(mockSubscriptionManager.isFeatureEnabledCallCount, 1)
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

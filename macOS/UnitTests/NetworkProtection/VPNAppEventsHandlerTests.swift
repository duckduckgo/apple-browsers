//
//  VPNAppEventsHandlerTests.swift
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

import Combine
import FeatureFlags
import Foundation
import XCTest
@testable import DuckDuckGo_Privacy_Browser
@testable import NetworkProtection

final class VPNAppEventsHandlerTests: XCTestCase {

    /// Tests that VPN login items are disabled and not restarted at startup when user has no VPN access.
    ///
    func testVPNLoginItemStartupCheckpointIfUserHasNoVPNAccess() {
        let loginItemsDisabledExpectation = expectation(description: "The login items should be disabled")
        let loginItemsRestartedExpectation = expectation(description: "The login items should NOT be restarted")
        loginItemsRestartedExpectation.isInverted = true

        let mockFeatureGatekeeper = MockVPNFeatureGatekeeper(
            canStartVPN: false,
            isInstalled: true,
            isVPNVisible: true,
            onboardStatusPublisher: Just(.completed).eraseToAnyPublisher())

        let mockLoginItemsManager = MockLoginItemsManager(disableLoginItemsCallback: { _ in
            loginItemsDisabledExpectation.fulfill()
        }, restartLoginItemsCallback: { _ in
            loginItemsRestartedExpectation.fulfill()
        }) { _ in
            true
        }

        let appEventsHandler = VPNAppEventsHandler(
            featureGatekeeper: mockFeatureGatekeeper,
            featureFlagOverridesPublisher: Empty<(FeatureFlag, Bool), Never>().eraseToAnyPublisher(),
            loginItemsManager: mockLoginItemsManager,
            defaults: UserDefaults(suiteName: UUID().uuidString)!)

        appEventsHandler.applicationDidFinishLaunching()

        waitForExpectations(timeout: 0.1)
    }

    /// Tests that VPN login items are not disabled and are restarted at startup when user has VPN access.
    ///
    func testVPNLoginItemStartupCheckpointIfUserHasVPNAccess() {
        let loginItemsDisabledExpectation = expectation(description: "The login items should NOT be disabled")
        loginItemsDisabledExpectation.isInverted = true
        let loginItemsRestartedExpectation = expectation(description: "The login items should be restarted")

        let mockFeatureGatekeeper = MockVPNFeatureGatekeeper(
            canStartVPN: true,
            isInstalled: true,
            isVPNVisible: true,
            onboardStatusPublisher: Just(.completed).eraseToAnyPublisher())

        let mockLoginItemsManager = MockLoginItemsManager(disableLoginItemsCallback: { _ in
            loginItemsDisabledExpectation.fulfill()
        }, restartLoginItemsCallback: { _ in
            loginItemsRestartedExpectation.fulfill()
        }) { _ in
            true
        }

        let appEventsHandler = VPNAppEventsHandler(
            featureGatekeeper: mockFeatureGatekeeper,
            featureFlagOverridesPublisher: Empty<(FeatureFlag, Bool), Never>().eraseToAnyPublisher(),
            loginItemsManager: mockLoginItemsManager,
            defaults: UserDefaults(suiteName: UUID().uuidString)!)

        appEventsHandler.applicationDidFinishLaunching()

        waitForExpectations(timeout: 0.1)
    }
}

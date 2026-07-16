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
import NetworkProtectionIPC
import NetworkProtectionUI
import SystemExtensionManager
import XCTest
@testable import DuckDuckGo_Privacy_Browser
@testable import VPN

// MARK: - Mock IPC Client

final class MockVPNControllerXPCClient: VPNControllerXPCClientProtocol {
    var stopCallback: ((Error?) -> Void)?
    var stopCallCount = 0
    var shouldFailStop = false
    var stopError: Error?

    func register(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func register(version: String, bundlePath: String, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func start(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func stop(completion: @escaping (Error?) -> Void) {
        stopCallCount += 1
        stopCallback = completion

        if shouldFailStop {
            completion(stopError ?? NSError(domain: "TestError", code: 1, userInfo: nil))
        } else {
            completion(nil)
        }
    }

    func fetchLastError(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func refreshSystemState(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func command(_ command: VPNCommand) async throws {
        // Mock implementation
    }
}

// MARK: - Tests

final class VPNAppEventsHandlerTests: XCTestCase {

    func testSystemStateResolverWhenUsingSystemExtensionAndSystemExtensionNeedsActionThenReturnsAllowExtensionForEveryVPNConfigurationState() {
        let actionableSystemExtensionStates: [SystemExtensionActivationState] = [
            .awaitingUserApproval,
            .disabled,
            .uninstalling,
            .notInstalled
        ]

        for systemExtensionState in actionableSystemExtensionStates {
            for vpnConfigurationState in NetworkProtectionVPNConfigurationState.allCases {
                let result = NetworkProtectionSystemStateResolver.resolvedOnboardingStatus(
                    usesSystemExtension: true,
                    systemExtensionState: systemExtensionState,
                    vpnConfigurationState: vpnConfigurationState,
                    existingStatus: .completed
                )

                XCTAssertEqual(result, .isOnboarding(step: .userNeedsToAllowExtension))
            }
        }
    }

    func testSystemStateResolverWhenUsingSystemExtensionAndSystemExtensionStateIsUnknownThenPreservesExistingStatus() {
        let existingStatuses: [OnboardingStatus] = [
            .completed,
            .isOnboarding(step: .userNeedsToAllowExtension),
            .isOnboarding(step: .userNeedsToAllowVPNConfiguration)
        ]

        for existingStatus in existingStatuses {
            for vpnConfigurationState in NetworkProtectionVPNConfigurationState.allCases {
                let result = NetworkProtectionSystemStateResolver.resolvedOnboardingStatus(
                    usesSystemExtension: true,
                    systemExtensionState: .unknown,
                    vpnConfigurationState: vpnConfigurationState,
                    existingStatus: existingStatus
                )

                XCTAssertEqual(result, existingStatus)
            }
        }
    }

    func testSystemStateResolverWhenUsingSystemExtensionAndSystemExtensionIsEnabledThenMapsVPNConfigurationState() {
        let expectations: [(NetworkProtectionVPNConfigurationState, OnboardingStatus)] = [
            (.installedAndEnabled, .completed),
            (.installedButDisabled, .isOnboarding(step: .userNeedsToAllowVPNConfiguration)),
            (.missingOrInvalid, .isOnboarding(step: .userNeedsToAllowVPNConfiguration))
        ]

        for (vpnConfigurationState, expectedStatus) in expectations {
            let result = NetworkProtectionSystemStateResolver.resolvedOnboardingStatus(
                usesSystemExtension: true,
                systemExtensionState: .enabled,
                vpnConfigurationState: vpnConfigurationState,
                existingStatus: .isOnboarding(step: .userNeedsToAllowExtension)
            )

            XCTAssertEqual(result, expectedStatus)
        }
    }

    func testSystemStateResolverWhenNotUsingSystemExtensionThenIgnoresSystemExtensionStateAndMapsVPNConfigurationState() {
        let expectations: [(NetworkProtectionVPNConfigurationState, OnboardingStatus)] = [
            (.installedAndEnabled, .completed),
            (.installedButDisabled, .isOnboarding(step: .userNeedsToAllowVPNConfiguration)),
            (.missingOrInvalid, .isOnboarding(step: .userNeedsToAllowVPNConfiguration))
        ]
        let systemExtensionStates: [SystemExtensionActivationState] = [
            .enabled,
            .awaitingUserApproval,
            .disabled,
            .uninstalling,
            .notInstalled,
            .unknown
        ]

        for systemExtensionState in systemExtensionStates {
            for (vpnConfigurationState, expectedStatus) in expectations {
                let result = NetworkProtectionSystemStateResolver.resolvedOnboardingStatus(
                    usesSystemExtension: false,
                    systemExtensionState: systemExtensionState,
                    vpnConfigurationState: vpnConfigurationState,
                    existingStatus: .isOnboarding(step: .userNeedsToAllowExtension)
                )

                XCTAssertEqual(result, expectedStatus)
            }
        }
    }

    func testSystemStateResolverContinuesStartingTunnelAfterSystemExtensionActivationWhenReadyForVPNConfiguration() {
        XCTAssertTrue(NetworkProtectionSystemStateResolver.shouldContinueStartingTunnel(afterSystemExtensionActivation: .completed))
        XCTAssertFalse(NetworkProtectionSystemStateResolver.shouldContinueStartingTunnel(afterSystemExtensionActivation: .isOnboarding(step: .userNeedsToAllowExtension)))
        XCTAssertTrue(NetworkProtectionSystemStateResolver.shouldContinueStartingTunnel(afterSystemExtensionActivation: .isOnboarding(step: .userNeedsToAllowVPNConfiguration)))
    }

    /// Tests that VPN login items are disabled and not restarted at startup when user has no VPN access.
    ///
    func testVPNLoginItemStartupCheckpointIfUserHasNoVPNAccess() async {
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
        }, isAnyEnabledCallback: { _ in
            true
        }, isAnyInstalledCallback: { _ in
            true
        })

        let mockIPCClient = MockVPNControllerXPCClient()

        let appEventsHandler = VPNAppEventsHandler(
            featureGatekeeper: mockFeatureGatekeeper,
            featureFlagOverridesPublisher: Empty<(FeatureFlag, Bool), Never>().eraseToAnyPublisher(),
            loginItemsManager: mockLoginItemsManager,
            ipcClient: mockIPCClient,
            defaults: UserDefaults(suiteName: UUID().uuidString)!)

        appEventsHandler.applicationDidFinishLaunching()
        await fulfillment(of: [loginItemsDisabledExpectation, loginItemsRestartedExpectation], timeout: 3)

        // Verify that stop was called
        XCTAssertEqual(mockIPCClient.stopCallCount, 1)
    }

    /// Tests that VPN login items are not disabled and are restarted at startup when user has VPN access.
    ///
    func testVPNLoginItemStartupCheckpointIfUserHasVPNAccess() async {
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
        }, isAnyEnabledCallback: { _ in
            true
        }, isAnyInstalledCallback: { _ in
            true
        })

        let mockIPCClient = MockVPNControllerXPCClient()

        let appEventsHandler = VPNAppEventsHandler(
            featureGatekeeper: mockFeatureGatekeeper,
            featureFlagOverridesPublisher: Empty<(FeatureFlag, Bool), Never>().eraseToAnyPublisher(),
            loginItemsManager: mockLoginItemsManager,
            ipcClient: mockIPCClient,
            defaults: UserDefaults(suiteName: UUID().uuidString)!)

        appEventsHandler.applicationDidFinishLaunching()
        await fulfillment(of: [loginItemsDisabledExpectation, loginItemsRestartedExpectation], timeout: 3)

        // Verify that stop was not called
        XCTAssertEqual(mockIPCClient.stopCallCount, 0)
    }
}

//
//  FailureRecoveryHandlerTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import VPN
import VPNTestUtils

final class FailureRecoveryHandlerTests: XCTestCase {
    private var deviceManager: MockNetworkProtectionDeviceManagement!
    private var reassertingControl: MockReasserting!
    private var failureRecoveryHandler: FailureRecoveryHandler!

    private static let testConfig = FailureRecoveryHandler.RetryConfig(
        times: 0, // Means failure will bubble up after the first try
        initialDelay: .seconds(1),
        maxDelay: .seconds(30),
        factor: 2.0
    )

    override func setUp() {
        super.setUp()
        deviceManager = MockNetworkProtectionDeviceManagement()
        reassertingControl = MockReasserting()
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            reassertingControl: reassertingControl,
            retryConfig: Self.testConfig,
            eventHandler: { _ in }
        )
        self.executionTimeAllowance = 5
    }

    override func tearDown() {
        deviceManager = nil
        failureRecoveryHandler = nil
        super.tearDown()
    }

    func testAttemptRecovery_callsDeviceManagerWithExpectedValues() async {
        let expectedServerName = "expectedServerName"
        let server = NetworkProtectionServer.registeredServer(named: expectedServerName)
        let expectedExcludeLocalNetworks = false
        await failureRecoveryHandler.attemptRecovery(
            to: server,
            excludeLocalNetworks: expectedExcludeLocalNetworks,
            dnsSettings: .ddg(blockRiskyDomains: false)
        ) {_ in }
        guard let spyGenerateTunnelConfiguration = deviceManager.spyGenerateTunnelConfiguration else {
            XCTFail("attemptRecovery not called")
            return
        }
        XCTAssertEqual(spyGenerateTunnelConfiguration.excludeLocalNetworks, expectedExcludeLocalNetworks)

        guard case .failureRecovery(let serverName) = spyGenerateTunnelConfiguration.selectionMethod else {
            XCTFail("Expected selectionMethod to equal failureRecover. Got \(spyGenerateTunnelConfiguration.selectionMethod)")
            return
        }
        XCTAssertEqual(serverName, expectedServerName)
    }

    func testAttemptRecovery_serverNameDifferentFromPreviousServerName_callsConfigUpdateWithNewConfigAndServer() async throws {
        let lastServerName = "oldServerName"
        let newServerName = "newServerName"
        let lastAndNewAllowedIPs = ["1.2.3.4/5", "6.7.8.9/10"]

        let configFetchResult = await attemptRecoveryReturningConfigResult(
            with: lastServerName,
            newServerName: newServerName,
            lastAllowedIPs: lastAndNewAllowedIPs,
            newAllowedIPs: lastAndNewAllowedIPs
        )

        XCTAssertEqual(newServerName, configFetchResult?.tunnelConfiguration.name)
        XCTAssertEqual(newServerName, configFetchResult?.server.serverName)
    }

    func testAttemptRecovery_allowedIPsDiffersFromPreviousAllowedIPs_returnsNewConfigAndServer() async throws {
        let lastAndNewServerName = "previousAndNewServerName"

        let configFetchResult = await attemptRecoveryReturningConfigResult(
            with: lastAndNewServerName,
            newServerName: lastAndNewServerName,
            lastAllowedIPs: ["1.2.3.4/5", "6.7.8.9/10"],
            newAllowedIPs: ["10.9.8.7/6", "5.4.3.2/1"]
        )

        XCTAssertEqual(lastAndNewServerName, configFetchResult?.tunnelConfiguration.name)
        XCTAssertEqual(lastAndNewServerName, configFetchResult?.server.serverName)
    }

    func testAttemptRecovery_sendsStartedEvent() async throws {
        var startedCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            reassertingControl: reassertingControl,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .started = step {
                    startedCount += 1
                }
            }
        )
        deviceManager.stubGenerateTunnelConfiguration = (
            tunnelConfiguration: .make(),
            server: .mockRegisteredServer
        )
        await failureRecoveryHandler.attemptRecovery(
            to: .mockRegisteredServer,
            excludeLocalNetworks: false,
            dnsSettings: .ddg(blockRiskyDomains: false)
        ) {_ in }

        XCTAssertEqual(startedCount, 1)
    }

    func testAttemptRecovery_configGenerationFailure_sendsFailedEvent() async throws {
        var failedCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            reassertingControl: reassertingControl,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .failed = step {
                    failedCount += 1
                }
                if case .completed = step {
                    XCTFail("Expected no completed events")
                }
            }
        )

        await attemptRecoveryWithConfigGenerationFailure()

        XCTAssertEqual(failedCount, 1)
    }

    func testAttemptRecovery_configUpdateFailed_sendsFailedEvent() async throws {
        var failedCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            reassertingControl: reassertingControl,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .failed = step {
                    failedCount += 1
                }
                if case .completed = step {
                    XCTFail("Expected no completed events")
                }
            }
        )

        await attemptRecoveryWithConfigUpdateFailure()

        XCTAssertEqual(failedCount, 1)
    }

    func testAttemptRecovery_lastAndNewServerNamesAndAllowedIPsAreEqual_sendsHealthyCompletedEvent() async throws {
        var healthyCompleteCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            reassertingControl: reassertingControl,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .completed(.healthy) = step {
                    healthyCompleteCount += 1
                } else if case .failed = step {
                    XCTFail("Expected no failed events")
                }
            }
        )
        await attemptRecoveryWithLastAndNewServerNamesAndAllowedIPsEqual()

        XCTAssertEqual(healthyCompleteCount, 1)
    }

    func testAttemptRecovery_lastAndNewServerNamesAreDifferent_sendsUnhealthyCompletedEvent() async throws {
        var unhealthyCompleteCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            reassertingControl: reassertingControl,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .completed(.unhealthy) = step {
                    unhealthyCompleteCount += 1
                } else if case .failed = step {
                    XCTFail("Expected no failed events")
                }
            }
        )
        let lastServerName = "oldServerName"
        let newServerName = "newServerName"
        let lastAndNewAllowedIPs = ["1.2.3.4/5", "6.7.8.9/10"]

        await attemptRecoveryReturningConfigResult(
            with: lastServerName,
            newServerName: newServerName,
            lastAllowedIPs: lastAndNewAllowedIPs,
            newAllowedIPs: lastAndNewAllowedIPs
        )

        XCTAssertEqual(unhealthyCompleteCount, 1)
    }

    func testAttemptRecovery_lastAndNewAllowedIPsAreDifferent_sendsUnhealthyCompletedEvent() async throws {
        let lastAndNewServerName = "previousAndNewServerName"

        var unhealthyCompleteCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            reassertingControl: reassertingControl,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .completed(.unhealthy) = step {
                    unhealthyCompleteCount += 1
                } else if case .failed = step {
                    XCTFail("Expected no failed events")
                }
            }
        )

        await attemptRecoveryReturningConfigResult(
            with: lastAndNewServerName,
            newServerName: lastAndNewServerName,
            lastAllowedIPs: ["1.2.3.4/5", "6.7.8.9/10"],
            newAllowedIPs: ["10.9.8.7/6", "5.4.3.2/1"]
        )

        XCTAssertEqual(unhealthyCompleteCount, 1)
    }

    func testAttemptRecovery_startsReasserting() async {
        await attemptRecoveryWithLastAndNewServerNamesAndAllowedIPsEqual()
        XCTAssertEqual(reassertingControl.startReassertingCallCount, 1)
    }

    func testAttemptRecovery_lastAndNewServerNamesAndAllowedIPsAreEqual_stopsReasserting() async {
        await attemptRecoveryWithLastAndNewServerNamesAndAllowedIPsEqual()
        XCTAssertEqual(reassertingControl.stopReassertingCallCount, 1)
    }

    func testAttemptRecovery_lastAndNewServerNamesDiffer_stopsReasserting() async {
        let lastAndNewAllowedIPs = ["1.2.3.4/5", "10.9.8.7/6"]
        await attemptRecoveryReturningConfigResult(with: "server1", newServerName: "server2", lastAllowedIPs: lastAndNewAllowedIPs, newAllowedIPs: lastAndNewAllowedIPs)
        XCTAssertEqual(reassertingControl.stopReassertingCallCount, 1)
    }

    func testAttemptRecovery_lastAndNewAllowedIPsDiffer_stopsReasserting() async {
        let lastAndNewServerName = "server1"
        await attemptRecoveryReturningConfigResult(with: lastAndNewServerName, newServerName: lastAndNewServerName, lastAllowedIPs: ["1.2.3.4/5", "10.9.8.7/6"], newAllowedIPs: ["4.5.6.7/5", "5.1.6.2/6"])
        XCTAssertEqual(reassertingControl.stopReassertingCallCount, 1)
    }

    func testAttemptRecovery_configFetchFails_retries() async {
        let retryConfig = FailureRecoveryHandler.RetryConfig(times: 3, initialDelay: 0.1, maxDelay: 1.0, factor: 2)
        var failedCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(deviceManager: deviceManager, reassertingControl: reassertingControl, retryConfig: retryConfig, eventHandler: { step in
            if case .failed = step {
                failedCount += 1
            }
        })
        await attemptRecoveryWithConfigUpdateFailure()
        XCTAssertEqual(failedCount, 3)
    }

    func testAttemptRecovery_configUpdateFails_retries() async {
        let retryConfig = FailureRecoveryHandler.RetryConfig(times: 3, initialDelay: 0.1, maxDelay: 1.0, factor: 2)
        var failedCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(deviceManager: deviceManager, reassertingControl: reassertingControl, retryConfig: retryConfig, eventHandler: { step in
            if case .failed = step {
                failedCount += 1
            }
        })
        await attemptRecoveryWithConfigUpdateFailure()
        XCTAssertEqual(failedCount, 3)
    }

    func attemptRecoveryWithLastAndNewServerNamesAndAllowedIPsEqual() async {
        let lastAndNewServerName = "previousAndNewServerName"
        let lastAndNewAllowedIPs = ["1.2.3.4/5", "10.9.8.7/6"]

        await attemptRecoveryReturningConfigResult(
            with: lastAndNewServerName,
            newServerName: lastAndNewServerName,
            lastAllowedIPs: lastAndNewAllowedIPs,
            newAllowedIPs: lastAndNewAllowedIPs
        )
    }

    func attemptRecoveryWithConfigGenerationFailure() async {
        deviceManager.stubGenerateTunnelConfigurationError = NetworkProtectionError.noServerRegistrationInfo
        await failureRecoveryHandler.attemptRecovery(
            to: .mockRegisteredServer,
            excludeLocalNetworks: false,
            dnsSettings: .ddg(blockRiskyDomains: false)
        ) {_ in }
    }

    func attemptRecoveryWithConfigUpdateFailure() async {
        let newServerName = "server2"
        let newServer = NetworkProtectionServer.registeredServer(named: newServerName, allowedIPs: ["1.2.3.4/5", "10.9.8.7/6"])

        deviceManager.stubGenerateTunnelConfiguration = (
            tunnelConfiguration: .make(named: newServerName),
            server: newServer
        )

        await failureRecoveryHandler.attemptRecovery(
            to: .mockRegisteredServer,
            excludeLocalNetworks: false,
            dnsSettings: .ddg(blockRiskyDomains: false)
        ) { _ in
            let underlyingError = NSError(domain: "test", code: 1)
            throw WireGuardAdapterError.startWireGuardBackend(underlyingError)
        }
    }

    @discardableResult
    func attemptRecoveryReturningConfigResult(with lastServerName: String, newServerName: String, lastAllowedIPs: [String], newAllowedIPs: [String]) async -> NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult? {
        let lastServer = NetworkProtectionServer.registeredServer(named: lastServerName, allowedIPs: lastAllowedIPs)
        let newServer = NetworkProtectionServer.registeredServer(named: newServerName, allowedIPs: newAllowedIPs)

        deviceManager.stubGenerateTunnelConfiguration = (
            tunnelConfiguration: .make(named: newServerName),
            server: newServer
        )

        var newConfigResult: NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult?

        await failureRecoveryHandler.attemptRecovery(to: lastServer, excludeLocalNetworks: false, dnsSettings: .ddg(blockRiskyDomains: false)) { configResult in
            newConfigResult = configResult
        }
        return newConfigResult
    }
}

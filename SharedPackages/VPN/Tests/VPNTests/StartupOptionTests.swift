//
//  StartupOptionTests.swift
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

import Foundation
import XCTest
@testable import VPN

final class StartupOptionsTests: XCTestCase {

    /// Tests that the startup options have correct default values when the VPN is started by the system.
    ///
    /// If a check fails it means that either:
    /// - The default option changed, and this test must be adjusted; or
    /// - The default option was changed by mistake, and there's a regression
    ///
    func testStartupOptionsHaveCorrectDefaultValuesWhenStartedByTheSystem() {
        let rawOptions = [String: Any]()
        let options = StartupOptions(options: rawOptions)

#if os(macOS)
        XCTAssertEqual(options.authToken, .useExisting)
        XCTAssertEqual(options.isAuthV2Enabled, .useExisting)
        XCTAssertEqual(options.tokenContainer, .useExisting)
#endif
        XCTAssertEqual(options.enableTester, .useExisting)
        XCTAssertEqual(options.vpnSettings, .useExisting)
        XCTAssertFalse(options.simulateCrash)
        XCTAssertFalse(options.simulateError)
        XCTAssertFalse(options.simulateMemoryCrash)
        XCTAssertEqual(options.startupMethod, .manualByTheSystem)
    }

    /// Tests that the startup options have correct default values when the VPN is started by the system.
    ///
    /// If a check fails it means that either:
    /// - The default option changed, and this test must be adjusted; or
    /// - The default option was changed by mistake, and there's a regression
    ///
    func testStartupOptionsHaveCorrectDefaultValuesWhenStartedByTheApp() async throws {
        let rawOptions: [String: Any] = [
            NetworkProtectionOptionKey.activationAttemptId: UUID().uuidString,
            NetworkProtectionOptionKey.isOnDemand: NSNumber(value: false)
        ]
        let options = StartupOptions(options: rawOptions)

#if os(macOS)
        XCTAssertEqual(options.authToken, .reset)
        XCTAssertEqual(options.isAuthV2Enabled, .reset)
        XCTAssertEqual(options.tokenContainer, .reset)
#endif
        XCTAssertEqual(options.enableTester, .reset)
        XCTAssertEqual(options.vpnSettings, .reset)
        XCTAssertFalse(options.simulateCrash)
        XCTAssertFalse(options.simulateError)
        XCTAssertFalse(options.simulateMemoryCrash)
        XCTAssertEqual(options.startupMethod, .manualByMainApp)
    }

    /// Tests that the startup options have correct default values when the VPN is started by the system.
    ///
    /// If a check fails it means that either:
    /// - The default option changed, and this test must be adjusted; or
    /// - The default option was changed by mistake, and there's a regression
    ///
    func testStartupOptionsHaveCorrectDefaultValuesWhenStartedByOnDemand() async throws {
        let rawOptions: [String: Any] = [
            NetworkProtectionOptionKey.isOnDemand: NSNumber(value: true)
        ]
        let options = StartupOptions(options: rawOptions)

#if os(macOS)
        XCTAssertEqual(options.authToken, .useExisting)
        XCTAssertEqual(options.isAuthV2Enabled, .useExisting)
        XCTAssertEqual(options.tokenContainer, .useExisting)
#endif
        XCTAssertEqual(options.enableTester, .useExisting)
        XCTAssertEqual(options.vpnSettings, .useExisting)
        XCTAssertFalse(options.simulateCrash)
        XCTAssertFalse(options.simulateError)
        XCTAssertFalse(options.simulateMemoryCrash)
        XCTAssertEqual(options.startupMethod, .automaticOnDemand)
    }

    // MARK: - VPN Settings Tests

    func testVPNSettingsCanBeEncodedAndParsed() throws {
        // Create a VPN settings snapshot
        let settingsSnapshot = VPNSettingsSnapshot(
            registrationKeyValidity: .custom(86400), // 24 hours
            selectedEnvironment: .production,
            selectedServer: .automatic,
            selectedLocation: .nearest,
            dnsSettings: .ddg(blockRiskyDomains: true),
            excludeLocalNetworks: false
        )

        // Encode it
        let encodedData = try JSONEncoder().encode(settingsSnapshot)

        // Create startup options with encoded settings
        let rawOptions: [String: Any] = [
            NetworkProtectionOptionKey.activationAttemptId: UUID().uuidString,
            NetworkProtectionOptionKey.settings: encodedData
        ]

        let options = StartupOptions(options: rawOptions)

        // Verify the settings were parsed correctly
        XCTAssertEqual(options.startupMethod, .manualByMainApp)

        guard case .set(let parsedSnapshot) = options.vpnSettings else {
            XCTFail("Expected .set case but got \(options.vpnSettings)")
            return
        }

        XCTAssertEqual(parsedSnapshot.registrationKeyValidity, .custom(86400))
        XCTAssertEqual(parsedSnapshot.selectedEnvironment, .production)
        XCTAssertEqual(parsedSnapshot.selectedServer, .automatic)
        XCTAssertEqual(parsedSnapshot.selectedLocation, .nearest)
        XCTAssertEqual(parsedSnapshot.excludeLocalNetworks, false)
    }

    func testVPNSettingsSnapshotCanBeCapturedFromVPNSettings() {
        let vpnSettings = VPNSettings(defaults: .standard)
        vpnSettings.selectedEnvironment = .production
        vpnSettings.selectedServer = .endpoint("test-server")
        vpnSettings.selectedLocation = .nearest
        vpnSettings.registrationKeyValidity = .custom(3600)
        vpnSettings.excludeLocalNetworks = true

        let snapshot = VPNSettingsSnapshot(from: vpnSettings)

        XCTAssertEqual(snapshot.selectedEnvironment, .production)
        XCTAssertEqual(snapshot.selectedServer, .endpoint("test-server"))
        XCTAssertEqual(snapshot.selectedLocation, .nearest)
        XCTAssertEqual(snapshot.registrationKeyValidity, .custom(3600))
        XCTAssertEqual(snapshot.excludeLocalNetworks, true)
    }

    func testVPNSettingsSnapshotCanApplyToVPNSettings() {
        let vpnSettings = VPNSettings(defaults: .standard)

        let snapshot = VPNSettingsSnapshot(
            registrationKeyValidity: .custom(7200),
            selectedEnvironment: .production,
            selectedServer: .endpoint("apply-server"),
            selectedLocation: .nearest,
            dnsSettings: .ddg(blockRiskyDomains: false),
            excludeLocalNetworks: true
        )

        snapshot.applyTo(vpnSettings)

        XCTAssertEqual(vpnSettings.registrationKeyValidity, .custom(7200))
        XCTAssertEqual(vpnSettings.selectedEnvironment, .production)
        XCTAssertEqual(vpnSettings.selectedServer, .endpoint("apply-server"))
        XCTAssertEqual(vpnSettings.selectedLocation, .nearest)
        XCTAssertEqual(vpnSettings.excludeLocalNetworks, true)
    }

    func testCorruptedVPNSettingsResultInResetOption() {
        let corruptedData = "invalid json data".data(using: .utf8)!

        let rawOptions: [String: Any] = [
            NetworkProtectionOptionKey.activationAttemptId: UUID().uuidString,
            NetworkProtectionOptionKey.settings: corruptedData
        ]

        let options = StartupOptions(options: rawOptions)

        // Should fall back to .reset when JSON decoding fails
        XCTAssertEqual(options.vpnSettings, .reset)
    }
}

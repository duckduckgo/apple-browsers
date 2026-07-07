//
//  VPNTunnelPixelTests.swift
//  DuckDuckGo
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
import PixelKit
import PersistenceTestingUtils
@testable import Core

/// Validates that firing VPN packet-tunnel pixels through `PixelKit` (via `VPNTunnelPixel` and the
/// `fireVPNTunnel(…)` helpers) produces exactly the same wire pixel names the legacy `Pixel` /
/// `DailyPixel` stack produced — the migration must not fork any existing metric.
///
/// The provider itself lives in the `PacketTunnelProvider` app-extension target, which has no unit
/// test target, so the migration's correctness is validated here at the bridge/helper layer.
final class VPNTunnelPixelTests: XCTestCase {

    private var appVersion: String { "1.2.3" }

    // MARK: - Capture helper

    private final class FiredPixel {
        let name: String
        let params: [String: String]
        init(name: String, params: [String: String]) {
            self.name = name
            self.params = params
        }
    }

    /// Installs a `PixelKit` whose fire request records every emitted pixel, runs `body`, and
    /// returns the recorded pixels.
    private func capture(_ body: () -> Void) -> [FiredPixel] {
        var fired: [FiredPixel] = []
        PixelKit.setUp(dryRun: false,
                       appVersion: appVersion,
                       source: PixelKit.Source.iOS.rawValue,
                       session: "VPNTunnelPixelTests",
                       defaultHeaders: [:],
                       defaults: InMemoryThrowingKeyValueStore()) { name, _, params, _, _, onComplete in
            fired.append(FiredPixel(name: name, params: params))
            onComplete(true, nil)
        }
        defer { PixelKit.tearDown() }
        body()
        return fired
    }

    private func firedNames(_ body: () -> Void) -> Set<String> {
        Set(capture(body).map(\.name))
    }

    // MARK: - Wire-name parity per helper

    func testDailyAndCountHelperMatchesLegacyWireNames() {
        // Expected suffixes are read from the same constant the legacy `DailyPixel` stack used,
        // so wire-name parity holds by construction even if that constant ever changes.
        let dailySuffix = DailyPixel.Constant.legacyDailyPixelSuffixes.dailySuffix
        let countSuffix = DailyPixel.Constant.legacyDailyPixelSuffixes.countSuffix
        for event in Self.dailyAndCountEvents {
            let names = firedNames { PixelKit.fireVPNTunnel(dailyAndCount: event) }
            XCTAssertEqual(names, [event.name + dailySuffix, event.name + countSuffix],
                           "Unexpected wire names for \(event.name)")
        }
    }

    func testDailyHelperMatchesLegacyWireNames() {
        for event in Self.dailyEvents {
            let names = firedNames { PixelKit.fireVPNTunnel(daily: event) }
            XCTAssertEqual(names, [event.name],
                           "Unexpected wire names for \(event.name)")
        }
    }

    func testStandardHelperMatchesLegacyWireNames() {
        for event in Self.standardEvents {
            let names = firedNames { PixelKit.fireVPNTunnel(standard: event) }
            XCTAssertEqual(names, [event.name],
                           "Unexpected wire names for \(event.name)")
        }
    }

    // MARK: - Parameters

    /// appVersion is included by default, matching the legacy `includedParameters: [.appVersion]`.
    func testAppVersionIsIncluded() {
        let fired = capture { PixelKit.fireVPNTunnel(dailyAndCount: .networkProtectionTunnelStartAttempt) }
        XCTAssertFalse(fired.isEmpty)
        for pixel in fired {
            XCTAssertEqual(pixel.params[PixelKit.Parameters.appVersion], appVersion)
        }
    }

    /// Errors are encoded into the same `e` / `d` parameters the legacy stack used.
    func testErrorIsEncodedAsErrorCodeAndDomain() {
        let error = NSError(domain: "TestErrorDomain", code: 42)
        let fired = capture {
            PixelKit.fireVPNTunnel(dailyAndCount: .networkProtectionTunnelStartFailure, error: error)
        }
        XCTAssertFalse(fired.isEmpty)
        for pixel in fired {
            XCTAssertEqual(pixel.params[PixelKit.Parameters.errorCode], "42")
            XCTAssertEqual(pixel.params[PixelKit.Parameters.errorDomain], "TestErrorDomain")
        }
    }

    /// Additional parameters supplied at the call site are preserved.
    func testAdditionalParametersArePreserved() {
        let fired = capture {
            PixelKit.fireVPNTunnel(dailyAndCount: .networkProtectionEnableAttemptSuccess,
                                   withAdditionalParameters: ["source": "test-source"])
        }
        XCTAssertFalse(fired.isEmpty)
        for pixel in fired {
            XCTAssertEqual(pixel.params["source"], "test-source")
        }
    }

    // MARK: - Migrated event tables (audit surface)
    //
    // Each event below is fired by NetworkProtectionPacketTunnelProvider. The grouping records the
    // legacy firing mechanism it migrates from, which determines the PixelKit frequency:
    //   • fireDailyAndCount / persistentPixel.fireDailyAndCount → .legacyDailyAndCount (name_d + name_c)
    //   • DailyPixel.fire                                        → .legacyDailyNoSuffix (name verbatim)
    //   • Pixel.fire                                             → .standard            (name verbatim)

    /// Fired via `DailyPixel.fireDailyAndCount` or `persistentPixel.fireDailyAndCount`.
    private static let dailyAndCountEvents: [Pixel.Event] = [
        // Provider events
        .networkProtectionConnectionTesterFailureDetected,
        .networkProtectionConnectionTesterExtendedFailureDetected,
        .networkProtectionConnectionTesterFailureRecovered(failureCount: 1),
        .networkProtectionConnectionTesterExtendedFailureRecovered(failureCount: 1),
        .networkProtectionEnableAttemptConnecting,
        .networkProtectionEnableAttemptSuccess,
        .networkProtectionEnableAttemptFailure,
        .networkProtectionTunnelFailureDetected,
        .networkProtectionTunnelFailureRecovered,
        .networkProtectionLatency(quality: "excellent"),
        .networkProtectionTunnelStopFailure,
        .networkProtectionTunnelStopSuccess,
        .networkProtectionTunnelWakeFailure,
        .networkProtectionFailureRecoveryStarted,
        .networkProtectionFailureRecoveryCompletedHealthy,
        .networkProtectionFailureRecoveryCompletedUnhealthy,
        .networkProtectionFailureRecoveryFailed,
        .networkProtectionTunnelStartAttemptOnDemandWithoutAccessToken,
        .networkProtectionAdapterEndTemporaryShutdownStateAttemptFailure,
        .networkProtectionAdapterEndTemporaryShutdownStateRecoverySuccess,
        .networkProtectionAdapterEndTemporaryShutdownStateRecoveryFailure,
        .networkProtectionDisconnected,
        .subscriptionKeychainAccessError,
        // Persistent-pixel events (retry now handled internally by PixelKit)
        .networkProtectionRekeyAttempt,
        .networkProtectionRekeyFailure,
        .networkProtectionRekeyCompleted,
        .networkProtectionTunnelStartAttempt,
        .networkProtectionTunnelStartFailure,
        .networkProtectionTunnelStartSuccess,
        .networkProtectionTunnelUpdateAttempt,
        .networkProtectionTunnelUpdateFailure,
        .networkProtectionTunnelUpdateSuccess,
        .networkProtectionServerMigrationAttempt,
        .networkProtectionServerMigrationAttemptFailure,
        .networkProtectionServerMigrationAttemptSuccess,
        .networkProtectionConnectionFailureLoopDetected,
        // Debug events — all funnel through a single fireDailyAndCount call site
        .networkProtectionTunnelConfigurationNoServerRegistrationInfo,
        .networkProtectionClientFailedToFetchServerList,
        .networkProtectionKeychainReadError,
        .networkProtectionWireguardErrorCannotStartWireguardBackend,
        .networkProtectionUnhandledError,
        .networkProtectionClientFailedToFetchServerStatus
    ]

    /// Fired via `DailyPixel.fire` (once per day, name emitted verbatim).
    private static let dailyEvents: [Pixel.Event] = [
        .networkProtectionActiveUser,
        .networkProtectionLatencyError,
        .networkProtectionMemoryWarning,
        .networkProtectionMemoryCritical
    ]

    /// Fired via `Pixel.fire` (every call, name emitted verbatim).
    private static let standardEvents: [Pixel.Event] = [
        .networkProtectionTunnelStopAttempt
    ]
}

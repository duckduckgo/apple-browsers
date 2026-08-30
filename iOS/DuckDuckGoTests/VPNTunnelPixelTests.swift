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
@testable import PixelKit
import PersistenceTestingUtils
@testable import Core

/// Validates that firing VPN packet-tunnel pixels through `PixelKit` (via `VPNTunnelPixel` and the
/// `fireVPNTunnel(…)` helpers) preserves the base names and `_d` / `_c` frequency suffixes while
/// intentionally removing the legacy `_ios_phone` / `_ios_tablet` form-factor suffix.
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

    private final class RetryQueueStore: PixelRetryQueueStoring {
        private let lock = NSLock()
        private var stored = [PixelRetryQueueItem]()
        var onRemove: ((Set<UUID>) -> Void)?

        var items: [PixelRetryQueueItem] {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }

        func append(_ items: [PixelRetryQueueItem]) throws {
            lock.lock()
            defer { lock.unlock() }
            stored.append(contentsOf: items)
        }

        func remove(itemsWithIDs ids: Set<UUID>) throws {
            lock.lock()
            stored.removeAll { ids.contains($0.id) }
            let onRemove = onRemove
            lock.unlock()
            onRemove?(ids)
        }

        func storedItems() throws -> [PixelRetryQueueItem] {
            items
        }
    }

    private final class RetryFireRequest {
        private let lock = NSLock()
        private var succeeds = false
        private var replayedNames = [String]()
        var onReplay: ((String) -> Void)?

        func startSucceeding() {
            lock.lock()
            defer { lock.unlock() }
            succeeds = true
        }

        func replayedPixelNames() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return replayedNames
        }

        lazy var fireRequest: PixelKit.FireRequest = { [self] name, _, parameters, _, _, completion in
            lock.lock()
            let succeeds = succeeds
            if parameters["retriedPixel"] == "1" {
                replayedNames.append(name)
            }
            let onReplay = onReplay
            lock.unlock()

            completion(succeeds, nil)
            if parameters["retriedPixel"] == "1" {
                onReplay?(name)
            }
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

    // MARK: - Wire names per helper

    func testDailyAndCountHelperPreservesFrequencySuffixesWithoutFormFactorSuffix() {
        // Expected suffixes are read from the same constant the legacy `DailyPixel` stack used.
        // The migrated names intentionally omit the legacy `_ios_phone` / `_ios_tablet` suffix.
        let dailySuffix = DailyPixel.Constant.legacyDailyPixelSuffixes.dailySuffix
        let countSuffix = DailyPixel.Constant.legacyDailyPixelSuffixes.countSuffix
        for event in Self.dailyAndCountEvents {
            let names = firedNames { PixelKit.fireVPNTunnel(dailyAndCount: event) }
            XCTAssertEqual(names, [event.name + dailySuffix, event.name + countSuffix],
                           "Unexpected wire names for \(event.name)")
            XCTAssertFalse(names.contains { $0.hasSuffix("_ios_phone") || $0.hasSuffix("_ios_tablet") })
        }
    }

    func testAdapterShutdownDailyAndCountPixelsPreserveStandardFrequencySuffixes() {
        for event in Self.standardDailyAndCountEvents {
            let names = firedNames {
                PixelKit.fireVPNTunnel(dailyAndCount: event, legacySuffixes: false)
            }
            XCTAssertEqual(names, [event.name + "_daily", event.name + "_count"],
                           "Unexpected wire names for \(event.name)")
            XCTAssertFalse(names.contains { $0.hasSuffix("_ios_phone") || $0.hasSuffix("_ios_tablet") })
        }
    }

    func testDailyHelperEmitsUnsuffixedFormFactorName() {
        for event in Self.dailyEvents {
            let names = firedNames { PixelKit.fireVPNTunnel(daily: event) }
            XCTAssertEqual(names, [event.name],
                           "Unexpected wire names for \(event.name)")
        }
    }

    func testStandardHelperEmitsUnsuffixedFormFactorName() {
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

    /// Retry-enabled failed sends are queued and replayed with the original wire names and parameters.
    func testRetryEnabledFailedSendIsQueuedAndReplayed() {
        let store = RetryQueueStore()
        let request = RetryFireRequest()
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.iOS.rawValue,
                                session: UUID().uuidString,
                                channel: nil,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                dateGenerator: Date.init,
                                defaults: InMemoryThrowingKeyValueStore(),
                                retryQueueStore: store,
                                fireRequest: request.fireRequest)
        let replayed = expectation(description: "Expect queued pixels to replay")
        replayed.expectedFulfillmentCount = 2
        let removed = expectation(description: "Expect replayed pixels to be removed from the queue")
        store.onRemove = { ids in
            XCTAssertEqual(ids.count, 2)
            removed.fulfill()
        }
        request.onReplay = { _ in replayed.fulfill() }

        pixelKit.fireVPNTunnel(dailyAndCount: .networkProtectionTunnelStartAttempt,
                               retryOnFailure: true,
                               withAdditionalParameters: ["source": "test-source"])

        XCTAssertEqual(store.items.map(\.pixelName).sorted(),
                       [Pixel.Event.networkProtectionTunnelStartAttempt.name + "_c",
                        Pixel.Event.networkProtectionTunnelStartAttempt.name + "_d"])
        XCTAssertTrue(store.items.allSatisfy { $0.parameters["source"] == "test-source" })

        request.startSucceeding()
        pixelKit.fire(VPNTunnelPixel(.networkProtectionTunnelStopAttempt), frequency: .standard)

        wait(for: [replayed, removed], timeout: 1.0)
        XCTAssertEqual(request.replayedPixelNames().sorted(),
                       [Pixel.Event.networkProtectionTunnelStartAttempt.name + "_c",
                        Pixel.Event.networkProtectionTunnelStartAttempt.name + "_d"])
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - Migrated event tables (audit surface)
    //
    // Each event below is fired by NetworkProtectionPacketTunnelProvider. The grouping records the
    // legacy firing mechanism it migrates from, which determines the PixelKit frequency:
    //   • fireDailyAndCount / persistentPixel.fireDailyAndCount → .legacyDailyAndCount (name_d + name_c)
    //   • adapter-shutdown DailyPixel.fireDailyAndCount          → .dailyAndCount (name_daily + name_count)
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

    /// Fired via `DailyPixel.fireDailyAndCount` without legacy suffixes.
    private static let standardDailyAndCountEvents: [Pixel.Event] = [
        .networkProtectionAdapterEndTemporaryShutdownStateAttemptFailure,
        .networkProtectionAdapterEndTemporaryShutdownStateRecoverySuccess,
        .networkProtectionAdapterEndTemporaryShutdownStateRecoveryFailure
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

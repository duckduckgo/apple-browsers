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
@testable import Core

/// Exercises the direct Pixel.Event + PixelKit retry contract used by the tunnel.
/// The extension has no unit-test target; provider call-site mappings are audited separately.
final class VPNTunnelPixelTests: XCTestCase {

    private struct FiredPixel {
        let name: String
        let parameters: [String: String]
    }

    private final class RetryQueueStore: PixelRetryQueueStoring {
        private let lock = NSLock()
        private var stored: [PixelRetryQueueItem] = []
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
            lock.unlock()
            onRemove?(ids)
        }

        func storedItems() throws -> [PixelRetryQueueItem] {
            items
        }
    }

    private final class FireRequestRecorder {
        private let lock = NSLock()
        private var succeeds = false
        private var recorded: [FiredPixel] = []

        var pixels: [FiredPixel] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func startSucceeding() {
            lock.lock()
            defer { lock.unlock() }
            succeeds = true
        }

        lazy var fireRequest: PixelKit.FireRequest = { [weak self] name, _, parameters, _, _, completion in
            guard let self else {
                completion(false, nil)
                return
            }
            lock.lock()
            recorded.append(FiredPixel(name: name, parameters: parameters))
            let succeeds = succeeds
            lock.unlock()
            completion(succeeds, nil)
        }
    }

    private let appVersion = "1.2.3"
    private let fireDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makePixelKit(source: PixelKit.Source = .iOS,
                             store: RetryQueueStore,
                             request: FireRequestRecorder) -> PixelKit {
        let suiteName = "VPNTunnelPixelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return PixelKit(dryRun: false,
                        appVersion: appVersion,
                        source: source.rawValue,
                        session: UUID().uuidString,
                        channel: nil,
                        defaultHeaders: [:],
                        pixelCalendar: nil,
                        dateGenerator: { [fireDate] in fireDate },
                        defaults: defaults,
                        retryQueueStore: store,
                        fireRequest: request.fireRequest)
    }

    func testWhenVPNPixelFailsThenBothLegacyVariantsReplayWithOriginalParameters() {
        for (source, suffix) in [(PixelKit.Source.iOS, "_ios_phone"), (.iPadOS, "_ios_tablet")] {
            let store = RetryQueueStore()
            let request = FireRequestRecorder()
            let pixelKit = makePixelKit(source: source, store: store, request: request)
            let error = NSError(domain: "VPNError", code: 42,
                                userInfo: [NSUnderlyingErrorKey: NSError(domain: "UnderlyingVPNError", code: 7)])
            let event = Pixel.Event.networkProtectionRekeyFailure.withError(error)
            let expectedNames = ["m_netp_rekey_failure_c" + suffix, "m_netp_rekey_failure_d" + suffix]

            pixelKit.fire(event, frequency: .legacyDailyAndCount, options: .withRetry)

            XCTAssertEqual(request.pixels.map(\.name).sorted(), expectedNames)
            XCTAssertEqual(store.items.map(\.pixelName).sorted(), expectedNames)
            for pixel in request.pixels {
                XCTAssertEqual(pixel.parameters["appVersion"], appVersion)
                XCTAssertEqual(pixel.parameters["e"], "42")
                XCTAssertEqual(pixel.parameters["d"], "VPNError")
                XCTAssertEqual(pixel.parameters["ue"], "7")
                XCTAssertEqual(pixel.parameters["ud"], "UnderlyingVPNError")
                XCTAssertNil(pixel.parameters["originalPixelTimestamp"])
                XCTAssertNil(pixel.parameters["retriedPixel"])
            }

            let queued = store.items
            let removed = expectation(description: "Successful replays remove both queued variants")
            store.onRemove = { ids in
                XCTAssertEqual(ids, Set(queued.map(\.id)))
                removed.fulfill()
            }
            request.startSucceeding()
            // A successful non-retry event must also drain the new queue.
            pixelKit.fire(Pixel.Event.networkProtectionTunnelStopAttempt)
            wait(for: [removed], timeout: 2.0)

            let replays = request.pixels.filter { $0.parameters["retriedPixel"] == "1" }
            XCTAssertEqual(replays.map(\.name).sorted(), expectedNames)
            for replay in replays {
                let original = queued.first { $0.pixelName == replay.name }
                var expectedParameters = original?.parameters ?? [:]
                expectedParameters["originalPixelTimestamp"] = "2023-11-14T22:13:20Z"
                expectedParameters["retriedPixel"] = "1"
                XCTAssertEqual(replay.parameters, expectedParameters)
            }
            XCTAssertTrue(store.items.isEmpty)
        }
    }

    func testWhenPersistentVPNEventsSucceedThenDailyIsSuppressedButCountContinues() {
        let store = RetryQueueStore()
        let request = FireRequestRecorder()
        request.startSucceeding()
        let pixelKit = makePixelKit(store: store, request: request)

        for event in Self.persistentEvents {
            pixelKit.fire(event, frequency: .legacyDailyAndCount, options: .withRetry)
            pixelKit.fire(event, frequency: .legacyDailyAndCount, options: .withRetry)

            let dailyName = event.name + "_d_ios_phone"
            let countName = event.name + "_c_ios_phone"
            XCTAssertEqual(request.pixels.filter { $0.name == dailyName }.count, 1, event.name)
            XCTAssertEqual(request.pixels.filter { $0.name == countName }.count, 2, event.name)
        }
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(request.pixels.allSatisfy {
            $0.parameters["originalPixelTimestamp"] == nil && $0.parameters["retriedPixel"] == nil
        })
    }

    func testWhenVPNPixelDoesNotOptIntoRetryThenFailureIsNotQueued() {
        let store = RetryQueueStore()
        let request = FireRequestRecorder()
        let pixelKit = makePixelKit(store: store, request: request)

        pixelKit.fire(Pixel.Event.networkProtectionTunnelStopFailure.withError(NSError(domain: "VPNError", code: 42)),
                      frequency: .legacyDailyAndCount)

        XCTAssertEqual(request.pixels.count, 2)
        XCTAssertTrue(store.items.isEmpty)
    }

    // These are the existing PersistentPixel events, not a production routing table.
    private static let persistentEvents: [Pixel.Event] = [
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
        .networkProtectionConnectionFailureLoopDetected
    ]
}

//
//  TabTerminationTelemetryTests.swift
//  DuckDuckGoTests
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

import FeatureFlags
import Persistence
import PersistenceTestingUtils
import PixelKit
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class TabTerminationTelemetryTests: XCTestCase {

    private var date = Date(timeIntervalSince1970: 1_000_000)

    func testInteractionStateRestorationPixelNamesRemainBackwardCompatible() {
        XCTAssertEqual(TabTerminationTelemetryPixel.interactionStateFailedToRestore.name,
                       "m_d_tab-interaction-state_failed-to-restore")
        XCTAssertEqual(TabTerminationTelemetryPixel.interactionStateFailedToRestoreDaily.name,
                       "m_d_tab-interaction-state_failed-to-restore_daily")
    }

    func testWhenFeatureIsDisabledThenNoPixelsFire() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(featureEnabled: false, pixelFiring: pixelFiring)

        telemetry.didReceiveMemoryWarning()
        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertTrue(pixelFiring.calls.isEmpty)
    }

    func testWhenTerminationOccursInForegroundThenExpectedPixelsFire() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring,
                                      applicationState: .active,
                                      memoryFootprint: 600 * 1_048_576)

        telemetry.webContentProcessDidTerminate(activeTabCount: 7)

        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_foreground")?.frequency, .dailyAndCount)
        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_occurrence_1")?.frequency, .daily)
        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_memory_512-1023")?.frequency, .dailyAndCount)
        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_active-tabs_6-10")?.frequency, .dailyAndCount)
        XCTAssertEqual(pixelFiring.calls.count, 4)
    }

    func testWhenTerminationOccursInBackgroundThenBackgroundPixelFires() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring, applicationState: .background)

        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertNotNil(pixelFiring.call(named: "debug_webkit_termination_background"))
        XCTAssertNil(pixelFiring.call(named: "debug_webkit_termination_foreground"))
    }

    func testWhenTerminationsRepeatThenOccurrenceIsBucketedAndResetsDaily() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring)

        for _ in 0..<6 {
            telemetry.webContentProcessDidTerminate(activeTabCount: 1)
        }

        XCTAssertEqual(pixelFiring.calls.filter { $0.event.name.hasPrefix("debug_webkit_termination_occurrence_") }.map(\.event.name), [
            "debug_webkit_termination_occurrence_1",
            "debug_webkit_termination_occurrence_2",
            "debug_webkit_termination_occurrence_3",
            "debug_webkit_termination_occurrence_4",
            "debug_webkit_termination_occurrence_5-plus",
            "debug_webkit_termination_occurrence_5-plus"
        ])

        date.addTimeInterval(86_400)
        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertEqual(pixelFiring.calls.last { $0.event.name.hasPrefix("debug_webkit_termination_occurrence_") }?.event.name,
                       "debug_webkit_termination_occurrence_1")
    }

    func testMemoryBuckets() {
        let megabyte: UInt64 = 1_048_576
        let cases: [(UInt64, String)] = [
            (511 * megabyte, "less-512"),
            (512 * megabyte, "512-1023"),
            (1024 * megabyte, "1024-2047"),
            (2048 * megabyte, "2048-4095"),
            (4096 * megabyte, "4096-8191"),
            (8192 * megabyte, "8192-16383"),
            (16384 * megabyte, "16384-plus")
        ]

        for (bytes, expectedName) in cases {
            XCTAssertEqual(TabTerminationTelemetryPixel.memory(.init(bytes: bytes)).name,
                           "debug_webkit_termination_memory_\(expectedName)")
        }
    }

    func testActiveTabBuckets() {
        let cases = [
            (1, "1"),
            (2, "2-5"),
            (6, "6-10"),
            (11, "11-20"),
            (21, "21-40"),
            (41, "41-60"),
            (61, "61-80"),
            (81, "81-plus")
        ]

        for (count, expectedName) in cases {
            XCTAssertEqual(TabTerminationTelemetryPixel.activeTabs(.init(count)).name,
                           "debug_webkit_termination_active-tabs_\(expectedName)")
        }
    }

    func testWhenMemoryFootprintIsUnavailableAndNoWarningOccurredThenOptionalPixelsDoNotFire() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring, memoryFootprint: nil)

        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertFalse(pixelFiring.calls.contains { $0.event.name.hasPrefix("debug_webkit_termination_memory_") })
        XCTAssertFalse(pixelFiring.calls.contains { $0.event.name.hasPrefix("debug_webkit_termination_time-since-memory-warning_") })
    }

    func testWhenMemoryWarningOccurredThenElapsedTimePixelFires() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring)
        telemetry.didReceiveMemoryWarning()
        date.addTimeInterval(6)

        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_time-since-memory-warning_10")?.frequency, .standard)
    }

    private func makeTelemetry(featureEnabled: Bool = true,
                               pixelFiring: MockTabTerminationPixelFiring,
                               applicationState: UIApplication.State = .active,
                               memoryFootprint: UInt64? = 100 * 1_048_576) -> DefaultTabTerminationTelemetry {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: featureEnabled ? [.tabTerminationTelemetry] : [])
        return DefaultTabTerminationTelemetry(
            featureFlagger: featureFlagger,
            keyValueStore: MockKeyValueStore(),
            pixelFiring: pixelFiring,
            applicationState: { applicationState },
            memoryFootprint: { memoryFootprint },
            date: { self.date })
    }
}

private final class MockTabTerminationPixelFiring: PixelFiring {

    struct Call {
        let event: PixelKitEvent
        let frequency: PixelKit.Frequency
    }

    private(set) var calls: [Call] = []

    func fire(_ event: PixelKitEvent,
              frequency: PixelKit.Frequency,
              includeAppVersionParameter: Bool,
              withAdditionalParameters: [String: String]?,
              withNamePrefix: String?,
              doNotEnforcePrefix: Bool,
              onComplete: @escaping PixelKit.CompletionBlock) {
        calls.append(.init(event: event, frequency: frequency))
        onComplete(true, nil)
    }

    func call(named name: String) -> Call? {
        calls.first { $0.event.name == name }
    }
}

//
//  MemoryUsageIntervalPixelTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class MemoryUsageIntervalPixelTests: XCTestCase {

    // MARK: - Pixel Name

    func testPixelName() {
        let context = MemoryReportingContext(
            browserMemoryMB: 1024,
            windows: 2,
            tabs: 7,
            architecture: "ARM",
            syncEnabled: false
        )
        let pixel = MemoryUsageIntervalPixel.memoryUsage(trigger: .startup, context: context)

        XCTAssertEqual(pixel.name, "m_mac_memory_usage")
    }

    func testPixelNameIsSameForAllTriggers() {
        let context = MemoryReportingContext(
            browserMemoryMB: 512,
            windows: 1,
            tabs: 4,
            architecture: "Intel",
            syncEnabled: true
        )

        for trigger in MemoryUsageIntervalPixel.Trigger.allCases {
            let pixel = MemoryUsageIntervalPixel.memoryUsage(trigger: trigger, context: context)
            XCTAssertEqual(pixel.name, "m_mac_memory_usage", "Name should be the same for trigger \(trigger)")
        }
    }

    // MARK: - Parameters

    func testParametersIncludeTriggerAndContext() {
        let context = MemoryReportingContext(
            browserMemoryMB: 2048,
            windows: 4,
            tabs: 11,
            architecture: "ARM",
            syncEnabled: true
        )
        let pixel = MemoryUsageIntervalPixel.memoryUsage(trigger: .h4, context: context)

        let params = pixel.parameters
        XCTAssertNotNil(params)
        XCTAssertEqual(params?["trigger"], "4h")
        XCTAssertEqual(params?["browser_memory_mb"], "2048")
        XCTAssertEqual(params?["windows"], "4")
        XCTAssertEqual(params?["tabs"], "11")
        XCTAssertEqual(params?["architecture"], "ARM")
        XCTAssertEqual(params?["sync_enabled"], "true")
    }

    func testParametersForStartupTrigger() {
        let context = MemoryReportingContext(
            browserMemoryMB: 0,
            windows: 1,
            tabs: 1,
            architecture: "Intel",
            syncEnabled: false
        )
        let pixel = MemoryUsageIntervalPixel.memoryUsage(trigger: .startup, context: context)

        let params = pixel.parameters
        XCTAssertEqual(params?["trigger"], "startup")
        XCTAssertEqual(params?["browser_memory_mb"], "0")
        XCTAssertEqual(params?["windows"], "1")
        XCTAssertEqual(params?["tabs"], "1")
        XCTAssertEqual(params?["architecture"], "Intel")
        XCTAssertEqual(params?["sync_enabled"], "false")
    }

    func testAllTriggerRawValues() {
        let expected: [(MemoryUsageIntervalPixel.Trigger, String)] = [
            (.startup, "startup"),
            (.h1, "1h"),
            (.h2, "2h"),
            (.h4, "4h"),
            (.h8, "8h"),
            (.h24, "24h")
        ]

        for (trigger, expectedRawValue) in expected {
            XCTAssertEqual(trigger.rawValue, expectedRawValue, "Trigger \(trigger) should have rawValue \(expectedRawValue)")
        }
    }

    // MARK: - Trigger Elapsed Seconds

    func testTriggerElapsedSeconds() {
        XCTAssertNil(MemoryUsageIntervalPixel.Trigger.startup.elapsedSeconds)
        XCTAssertEqual(MemoryUsageIntervalPixel.Trigger.h1.elapsedSeconds, 3600)
        XCTAssertEqual(MemoryUsageIntervalPixel.Trigger.h2.elapsedSeconds, 7200)
        XCTAssertEqual(MemoryUsageIntervalPixel.Trigger.h4.elapsedSeconds, 14400)
        XCTAssertEqual(MemoryUsageIntervalPixel.Trigger.h8.elapsedSeconds, 28800)
        XCTAssertEqual(MemoryUsageIntervalPixel.Trigger.h24.elapsedSeconds, 86400)
    }

    // MARK: - Context Parameters

    func testContextParametersKeys() {
        let context = MemoryReportingContext(
            browserMemoryMB: 512,
            windows: 2,
            tabs: 4,
            architecture: "ARM",
            syncEnabled: true
        )
        let params = context.parameters

        XCTAssertEqual(params.count, 5)
        XCTAssertNotNil(params["browser_memory_mb"])
        XCTAssertNotNil(params["windows"])
        XCTAssertNotNil(params["tabs"])
        XCTAssertNotNil(params["architecture"])
        XCTAssertNotNil(params["sync_enabled"])
    }

    func testPixelParametersCount() {
        let context = MemoryReportingContext(
            browserMemoryMB: 1024,
            windows: 1,
            tabs: 2,
            architecture: "ARM",
            syncEnabled: false
        )
        let pixel = MemoryUsageIntervalPixel.memoryUsage(trigger: .h1, context: context)

        // 5 context params + 1 trigger = 6 total
        XCTAssertEqual(pixel.parameters?.count, 6)
    }

    // MARK: - Unknown Fallback

    func testWhenDependenciesAreNil_ThenParametersAreUnknown() {
        let context = MemoryReportingContext(
            browserMemoryMB: 512,
            windows: nil,
            tabs: nil,
            architecture: "ARM",
            syncEnabled: nil
        )
        let params = context.parameters

        XCTAssertEqual(params["browser_memory_mb"], "512")
        XCTAssertEqual(params["windows"], "unknown")
        XCTAssertEqual(params["tabs"], "unknown")
        XCTAssertEqual(params["architecture"], "ARM")
        XCTAssertEqual(params["sync_enabled"], "unknown")
    }

    func testWhenDependenciesAreNil_ThenParameterCountIsUnchanged() {
        let context = MemoryReportingContext(
            browserMemoryMB: 1024,
            windows: nil,
            tabs: nil,
            architecture: "Intel",
            syncEnabled: nil
        )
        let pixel = MemoryUsageIntervalPixel.memoryUsage(trigger: .startup, context: context)

        // All keys are still present even when values are "unknown"
        XCTAssertEqual(pixel.parameters?.count, 6)
    }
}

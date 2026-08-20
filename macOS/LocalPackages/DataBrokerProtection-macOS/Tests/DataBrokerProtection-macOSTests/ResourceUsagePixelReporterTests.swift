//
//  ResourceUsagePixelReporterTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//

import XCTest
@testable import DataBrokerProtection_macOS

final class ResourceUsagePixelReporterTests: XCTestCase {

    private let reporter = ResourceUsagePixelReporter()

    func testRunEventContainsTheCompleteBucketedContract() {
        let event = reporter.makeRunEvent(
            makeSnapshot(
                cpuTime: 11,
                elapsedTime: 19,
                averagePercent: 100,
                agentPeakBytes: 8 * 1_048_576,
                webPeakBytes: nil,
                hadCriticalPressure: true
            ),
            isOnBattery: nil,
            thermalState: .serious
        )

        XCTAssertEqual(event.parameters, [
            "cpu_time_seconds_bucket": "10",
            "elapsed_seconds_bucket": "10",
            "core_utilization_percent_bucket": "100",
            "agent_peak_footprint_mb_bucket": "8",
            "web_peak_footprint_mb_bucket": "unknown",
            "had_critical_pressure": "true",
            "on_battery": "unknown",
            "thermal_state": "serious",
            "architecture": expectedArchitecture
        ])
    }

    func testBucketBoundariesMatchThePixelDefinition() {
        let cases: [(value: Double, duration: String, utilization: String, memory: String)] = [
            (0, "0", "0", "0"),
            (5, "5", "3", "0"),
            (8, "5", "6", "8"),
            (16, "10", "12", "16"),
            (25, "20", "25", "16"),
            (50, "40", "50", "32"),
            (100, "80", "100", "64"),
            (200, "160", "200", "128"),
            (400, "320", "400", "256"),
            (65_536, "40960", "400", "65536")
        ]

        for testCase in cases {
            let parameters = reporter.makeRunEvent(
                makeSnapshot(
                    cpuTime: testCase.value,
                    elapsedTime: testCase.value,
                    averagePercent: testCase.value,
                    agentPeakBytes: UInt64(testCase.value * 1_048_576),
                    webPeakBytes: 0,
                    hadCriticalPressure: false
                ),
                isOnBattery: false,
                thermalState: .nominal
            ).parameters

            XCTAssertEqual(parameters?["cpu_time_seconds_bucket"], testCase.duration, "value: \(testCase.value)")
            XCTAssertEqual(parameters?["elapsed_seconds_bucket"], testCase.duration, "value: \(testCase.value)")
            XCTAssertEqual(parameters?["core_utilization_percent_bucket"], testCase.utilization, "value: \(testCase.value)")
            XCTAssertEqual(parameters?["agent_peak_footprint_mb_bucket"], testCase.memory, "value: \(testCase.value)")
        }
    }

    private func makeSnapshot(cpuTime: TimeInterval,
                              elapsedTime: TimeInterval,
                              averagePercent: Double,
                              agentPeakBytes: UInt64,
                              webPeakBytes: UInt64?,
                              hadCriticalPressure: Bool) -> ResourceSnapshot {
        ResourceSnapshot(
            cpu: .init(
                elapsedTime: elapsedTime,
                agentTime: cpuTime,
                webProcessesTime: 0,
                averagePercent: averagePercent
            ),
            memory: .init(
                agent: .init(footprintBytes: agentPeakBytes, peakFootprintBytes: agentPeakBytes),
                webProcesses: .init(footprintBytes: webPeakBytes, peakFootprintBytes: webPeakBytes, processCount: nil),
                hadCriticalPressure: hadCriticalPressure
            )
        )
    }

    private var expectedArchitecture: String {
        #if arch(arm64)
        "ARM"
        #else
        "Intel"
        #endif
    }
}

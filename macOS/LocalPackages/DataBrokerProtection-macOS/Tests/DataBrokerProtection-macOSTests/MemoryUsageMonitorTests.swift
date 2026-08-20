//
//  MemoryUsageMonitorTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//

import XCTest
@testable import DataBrokerProtection_macOS

final class MemoryUsageMonitorTests: XCTestCase {

    func testReportPreservesPeaksAcrossUnavailableAndLowerSamples() {
        var samples = [
            MemoryUsageSample(agentFootprint: 100, webProcessesFootprint: 200, webProcessCount: 2),
            MemoryUsageSample(agentFootprint: 150, webProcessesFootprint: nil, webProcessCount: 2),
            MemoryUsageSample(agentFootprint: 120, webProcessesFootprint: 180, webProcessCount: 1)
        ].makeIterator()
        var monitor = MemoryUsageMonitor(
            webProcessPIDs: [1, 2],
            sampleProvider: { _ in samples.next()! }
        )

        monitor.recordSample(webProcessPIDs: [1, 2])
        XCTAssertNil(monitor.makeReport().webProcesses.footprintBytes)
        XCTAssertEqual(monitor.makeReport().webProcesses.peakFootprintBytes, 200)

        monitor.recordSample(webProcessPIDs: [1])
        XCTAssertTrue(monitor.recordCriticalPressure())
        XCTAssertFalse(monitor.recordCriticalPressure())
        let report = monitor.makeReport()

        XCTAssertEqual(report.agent.footprintBytes, 120)
        XCTAssertEqual(report.agent.peakFootprintBytes, 150)
        XCTAssertEqual(report.webProcesses.footprintBytes, 180)
        XCTAssertEqual(report.webProcesses.peakFootprintBytes, 200)
        XCTAssertEqual(report.webProcesses.processCount, 1)
        XCTAssertTrue(report.hadCriticalPressure)
    }
}

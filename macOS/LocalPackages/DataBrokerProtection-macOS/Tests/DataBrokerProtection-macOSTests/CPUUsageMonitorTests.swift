//
//  CPUUsageMonitorTests.swift
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
@testable import DataBrokerProtection_macOS

final class CPUUsageMonitorTests: XCTestCase {

    func testReportAccountsForProcessLifecyclesWithoutLosingRecordedCPU() {
        let existing = CPUUsageSample.ProcessIdentity(pid: 1, startAbsoluteTime: 50)
        let createdDuringRun = CPUUsageSample.ProcessIdentity(pid: 2, startAbsoluteTime: 150)
        let discoveredLate = CPUUsageSample.ProcessIdentity(pid: 3, startAbsoluteTime: 50)
        let reusedPID = CPUUsageSample.ProcessIdentity(pid: 1, startAbsoluteTime: 160)
        var samples = [
            CPUUsageSample(agent: 100, webProcesses: [existing: 50], uptime: 10),
            CPUUsageSample(
                agent: 140,
                webProcesses: [existing: 70, createdDuringRun: 20, discoveredLate: 40],
                uptime: 20
            ),
            CPUUsageSample(
                agent: nil,
                webProcesses: [createdDuringRun: 35, discoveredLate: 55, reusedPID: 10],
                uptime: 30
            )
        ].makeIterator()
        var monitor = CPUUsageMonitor(
            webProcessPIDs: [existing.pid],
            runStartAbsoluteTime: 100,
            sampleProvider: { _ in samples.next()! },
            secondsFromMachTime: { TimeInterval($0) }
        )

        monitor.recordSample(webProcessPIDs: [existing.pid, createdDuringRun.pid, discoveredLate.pid])
        monitor.recordSample(webProcessPIDs: [createdDuringRun.pid, discoveredLate.pid, reusedPID.pid])
        let report = monitor.makeReport()

        XCTAssertEqual(report.elapsedTime, 20)
        XCTAssertEqual(report.agentTime, 40)
        XCTAssertEqual(report.webProcessesTime, 80)
        XCTAssertEqual(report.averagePercent, 600)
    }
}

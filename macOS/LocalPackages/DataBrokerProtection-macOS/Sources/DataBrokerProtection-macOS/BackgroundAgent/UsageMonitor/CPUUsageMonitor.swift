//
//  CPUUsageMonitor.swift
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

import Foundation

/// Measures CPU used by the agent and WebContent processes during one PIR queue run.
///
/// macOS gives us a running total for each process, measured from when that process started. It does not give us the
/// total for an arbitrary period such as a PIR run, so this monitor calculates the run total as follows:
///
/// - **Existing process:** A process already running when PIR starts gets an initial reading. Later readings count only
///   the increase. For example, readings of 12 seconds at the start and 15 seconds later add 3 seconds to this PIR run.
/// - **New process:** A WebContent process created after PIR starts has no CPU from before the run. Its entire first
///   reading is therefore counted, and later readings again count only the increase.
/// - **Late discovery:** A process first discovered during the run but created before it uses that first reading as its
///   starting point. We cannot separate its earlier CPU into before-run and during-run work, so the first reading is not
///   counted; only increases seen in later readings are counted.
///
/// **Frequent sampling:** WebContent processes can exit at any time, and macOS no longer lets us read a process's counter
/// after it exits. Taking a reading every 10 seconds saves work observed so far. We keep that saved amount after the
/// process exits. Any CPU used after its last reading but before it exits cannot be recovered, so frequent readings
/// reduce—but do not eliminate—undercounting for short-lived processes.
struct CPUUsageMonitor {

    private typealias Identity = CPUUsageSample.ProcessIdentity
    private typealias ProcessCPUTime = CPUUsageSample.ProcessCPUTime

    /// Mach timers count ticks rather than nanoseconds. `numer / denom` converts one tick to nanoseconds.
    private static let timebaseInfo: mach_timebase_info_data_t = {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        return timebaseInfo
    }()

    /// Turns a process's running lifetime total into the amount counted for this PIR run.
    private struct CPUCounter {
        private var previous: ProcessCPUTime?
        private(set) var total: ProcessCPUTime = 0

        init(baseline: ProcessCPUTime? = nil) {
            previous = baseline
        }

        mutating func record(_ current: ProcessCPUTime, wasCreatedDuringRun: Bool = false) {
            if let previous, current >= previous {
                total += current - previous
            } else if previous == nil, wasCreatedDuringRun {
                total += current
            }
            previous = current
        }
    }

    private var agent: CPUCounter
    // Keep counters for exited processes so their recorded CPU remains in the run total.
    private var webContent: [Identity: CPUCounter]
    private let runStartAbsoluteTime: UInt64
    private let startUptime: TimeInterval
    private var latestUptime: TimeInterval

    init(webContentPIDs: Set<pid_t>, runStartAbsoluteTime: UInt64) {
        let sample = CPUUsageSampler().takeSample(webContentPIDs: webContentPIDs)
        agent = CPUCounter(baseline: sample.agent)
        webContent = sample.webContent.mapValues { CPUCounter(baseline: $0) }
        self.runStartAbsoluteTime = runStartAbsoluteTime
        startUptime = sample.uptime
        latestUptime = sample.uptime
    }

    mutating func recordSample(webContentPIDs: Set<pid_t>) {
        let sample = CPUUsageSampler().takeSample(webContentPIDs: webContentPIDs)
        updateAgentCPUTime(with: sample.agent)
        updateWebContentCPUTime(with: sample.webContent)
        latestUptime = sample.uptime
    }

    // MARK: - Reporting

    func makeReport() -> ResourceSnapshot.CPUUsage {
        let elapsedTime = max(0, latestUptime - startUptime)
        let agentTime = Self.seconds(fromMachTime: agent.total)
        let webContentCPUTime = webContent.values.reduce(ProcessCPUTime(0)) { $0 + $1.total }
        let webContentTime = Self.seconds(fromMachTime: webContentCPUTime)
        let totalTime = agentTime + webContentTime
        // CPU seconds divided by elapsed run time is average usage of one core. Concurrent work can exceed 100%.
        let averagePercent = elapsedTime > 0 ? totalTime / elapsedTime * 100 : 0

        return ResourceSnapshot.CPUUsage(
            elapsedTime: elapsedTime,
            agentTime: agentTime,
            webContentTime: webContentTime,
            averagePercent: averagePercent
        )
    }

    /// Converts Mach timer ticks to seconds using the machine-specific tick-to-nanosecond ratio.
    private static func seconds(fromMachTime value: ProcessCPUTime) -> TimeInterval {
        TimeInterval(value) * TimeInterval(timebaseInfo.numer) / TimeInterval(timebaseInfo.denom) / TimeInterval(NSEC_PER_SEC)
    }

    // MARK: - CPU Accumulation

    private mutating func updateAgentCPUTime(with cpuTime: ProcessCPUTime?) {
        guard let cpuTime else { return }
        agent.record(cpuTime)
    }

    private mutating func updateWebContentCPUTime(
        with counters: [Identity: ProcessCPUTime]
    ) {
        for (identity, cpuTime) in counters {
            webContent[identity, default: CPUCounter()].record(
                cpuTime,
                wasCreatedDuringRun: identity.startAbsoluteTime >= runStartAbsoluteTime
            )
        }
    }
}

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

/// Tracks cumulative CPU usage across one PIR queue run. WebContent counters become unavailable when
/// a process exits, so the resource monitor records them regularly to reduce missed work.
struct CPUUsageMonitor {

    private typealias Identity = CPUUsageSample.ProcessIdentity
    private typealias ProcessCPUTime = CPUUsageSample.ProcessCPUTime

    /// Converts cumulative process-lifetime readings into CPU consumed during the monitored run.
    /// In the `CPUUsageSample` example, the agent contributes `3s`, A contributes `2s`, and B contributes
    /// its first `2s` plus a `3s` delta. The accumulated result is `agent: 3s`, `WebContent: 7s`, even
    /// after A exits.
    private struct CPUCounter {
        private var previous: ProcessCPUTime?
        private(set) var total: ProcessCPUTime = 0

        init(baseline: ProcessCPUTime? = nil) {
            previous = baseline
        }

        mutating func record(_ current: ProcessCPUTime, wasCreatedDuringRun: Bool = false) {
            if let previous, current >= previous {
                // Process CPU counters are cumulative, so subsequent readings contribute only their delta.
                total += current - previous
            } else if previous == nil, wasCreatedDuringRun {
                // A process created during this run contributes its entire first lifetime reading.
                total += current
            }
            previous = current
        }
    }

    private let sampler = CPUUsageSampler()
    private var agent = CPUCounter()
    // Retaining counters across disappearance preserves CPU already observed for each WebContent process.
    private var webContent: [Identity: CPUCounter] = [:]
    // Used to include lifetime CPU only for WebContent processes created during this run.
    private var runStartAbsoluteTime: UInt64?
    // Used to normalize cumulative CPU time into average core-equivalent utilization.
    private var startUptime: TimeInterval?
    private var latestUptime: TimeInterval?

    // MARK: - Run Lifecycle

    /// Establishes baselines so CPU consumed before this PIR run is excluded.
    mutating func start(webContentPIDs: Set<pid_t>, runStartAbsoluteTime: UInt64) {
        reset()
        let sample = sampler.takeSample(webContentPIDs: webContentPIDs)
        agent = CPUCounter(baseline: sample.agent)
        webContent = sample.webContent.mapValues { CPUCounter(baseline: $0) }
        self.runStartAbsoluteTime = runStartAbsoluteTime
        startUptime = sample.uptime
        latestUptime = sample.uptime
    }

    /// Adds CPU consumed since the previous sample to the active run.
    mutating func recordSample(webContentPIDs: Set<pid_t>) {
        let sample = sampler.takeSample(webContentPIDs: webContentPIDs)
        updateAgentCPUTime(with: sample.agent)
        updateWebContentCPUTime(with: sample.webContent)
        latestUptime = sample.uptime
    }

    mutating func reset() {
        agent = CPUCounter()
        webContent = [:]
        runStartAbsoluteTime = nil
        startUptime = nil
        latestUptime = nil
    }

    // MARK: - Reporting

    func makeReport() -> ResourceSnapshot.CPUUsage {
        let elapsedTime: TimeInterval
        if let startUptime, let latestUptime {
            elapsedTime = max(0, latestUptime - startUptime)
        } else {
            elapsedTime = 0
        }
        let agentTime = TimeInterval(agent.total) / TimeInterval(NSEC_PER_SEC)
        let webContentCPUTime = webContent.values.reduce(ProcessCPUTime(0)) { $0 + $1.total }
        let webContentTime = TimeInterval(webContentCPUTime) / TimeInterval(NSEC_PER_SEC)
        let totalTime = agentTime + webContentTime
        // This is core-equivalent utilization: one fully occupied core is 100%, so totals may exceed 100%.
        let averagePercent = elapsedTime > 0 ? totalTime / elapsedTime * 100 : 0

        return ResourceSnapshot.CPUUsage(
            agentTime: agentTime,
            webContentTime: webContentTime,
            averagePercent: averagePercent
        )
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
            // A process created during this run contributes its lifetime CPU; an older process's first
            // reading is only a baseline. Start time also distinguishes recycled PIDs.
            webContent[identity, default: CPUCounter()].record(
                cpuTime,
                wasCreatedDuringRun: identity.startAbsoluteTime >= (runStartAbsoluteTime ?? .max)
            )
        }
    }
}

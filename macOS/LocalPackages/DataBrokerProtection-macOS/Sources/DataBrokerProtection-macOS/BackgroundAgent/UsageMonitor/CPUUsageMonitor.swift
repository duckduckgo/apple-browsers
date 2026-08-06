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
/// a process exits, so the resource monitor records them every 10 seconds to reduce missed work.
struct CPUUsageMonitor {

    private typealias Identity = CPUUsageSample.ProcessIdentity
    private typealias Reading = CPUUsageSample.ProcessReading

    private let sampler = CPUUsageSampler()
    private var previousAgent: Reading?
    // Retaining the last reading across disappearance avoids resetting a temporarily undiscovered process.
    private var previousWebContent: [Identity: Reading] = [:]
    private var agentTimeNanoseconds: UInt64 = 0
    private var webContentTimeNanoseconds: UInt64 = 0
    private var runStartAbsoluteTime: UInt64?
    private var startUptime: TimeInterval?
    private var discoveredCount = 0
    private var readableCount = 0

    // MARK: - Run Lifecycle

    /// Establishes baselines so CPU consumed before this PIR run is excluded.
    mutating func start(webContentPIDs: Set<pid_t>, runStartAbsoluteTime: UInt64) {
        reset()
        let sample = sampler.takeSample(webContentPIDs: webContentPIDs)
        previousAgent = sample.agent
        previousWebContent = sample.webContent
        self.runStartAbsoluteTime = runStartAbsoluteTime
        startUptime = sample.uptime
        updateProcessCounts(with: sample)
    }

    /// Adds CPU consumed since the previous sample to the active run.
    mutating func recordSample(webContentPIDs: Set<pid_t>) {
        let sample = sampler.takeSample(webContentPIDs: webContentPIDs)
        updateAgentCPUTime(with: sample.agent)
        updateWebContentCPUTime(with: sample.webContent)
        updateProcessCounts(with: sample)
    }

    mutating func reset() {
        previousAgent = nil
        previousWebContent = [:]
        agentTimeNanoseconds = 0
        webContentTimeNanoseconds = 0
        runStartAbsoluteTime = nil
        startUptime = nil
        discoveredCount = 0
        readableCount = 0
    }

    // MARK: - Reporting

    func makeReport(at systemUptime: TimeInterval) -> ResourceSnapshot.CPUUsage {
        let elapsedTime = max(0, systemUptime - (startUptime ?? systemUptime))
        let agentTime = TimeInterval(agentTimeNanoseconds) / TimeInterval(NSEC_PER_SEC)
        let webContentTime = TimeInterval(webContentTimeNanoseconds) / TimeInterval(NSEC_PER_SEC)
        let totalTime = agentTime + webContentTime
        // This is core-equivalent utilization: one fully occupied core is 100%, so totals may exceed 100%.
        let averagePercent = elapsedTime > 0 ? totalTime / elapsedTime * 100 : 0

        return ResourceSnapshot.CPUUsage(
            agentTime: agentTime,
            webContentTime: webContentTime,
            averagePercent: averagePercent,
            coverage: .init(
                discoveredCount: discoveredCount,
                readableCount: readableCount
            )
        )
    }

    // MARK: - CPU Accumulation

    private mutating func updateAgentCPUTime(with reading: Reading?) {
        guard let reading else { return }

        agentTimeNanoseconds += cpuDelta(
            for: reading,
            previousReading: previousAgent,
            includeLifetimeForNewProcess: false
        )
        previousAgent = reading
    }

    private mutating func updateWebContentCPUTime(
        with readings: [Identity: Reading]
    ) {
        for (identity, reading) in readings {
            // A process created during this run contributes its lifetime CPU; an older process's first
            // reading is only a baseline. Start time also distinguishes recycled PIDs.
            webContentTimeNanoseconds += cpuDelta(
                for: reading,
                previousReading: previousWebContent[identity],
                includeLifetimeForNewProcess: identity.startAbsoluteTime >= (runStartAbsoluteTime ?? .max)
            )
            previousWebContent[identity] = reading
        }
    }

    private func cpuDelta(for reading: Reading,
                          previousReading: Reading?,
                          includeLifetimeForNewProcess: Bool) -> UInt64 {
        guard let previousReading else {
            return includeLifetimeForNewProcess ? reading.totalNanoseconds : 0
        }
        guard reading.totalNanoseconds >= previousReading.totalNanoseconds else { return 0 }
        return reading.totalNanoseconds - previousReading.totalNanoseconds
    }

    private mutating func updateProcessCounts(with sample: CPUUsageSample) {
        discoveredCount = sample.discoveredCount
        readableCount = sample.webContent.count
    }
}

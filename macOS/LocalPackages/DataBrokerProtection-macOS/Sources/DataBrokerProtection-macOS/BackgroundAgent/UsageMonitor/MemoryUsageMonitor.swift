//
//  MemoryUsageMonitor.swift
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

/// Tracks current and peak memory usage across one PIR queue run.
struct MemoryUsageMonitor {

    private let sampler = MemoryUsageSampler()
    private var peakAgentFootprintBytes: UInt64 = 0
    private var peakWebContentBytes: UInt64?
    private var hadCriticalPressure = false

    // MARK: - Run Lifecycle

    mutating func start(webContentPIDs: [pid_t]?) {
        reset()
        updatePeaks(with: sampler.takeSample(webContentPIDs: webContentPIDs))
    }

    mutating func recordCriticalPressure() {
        hadCriticalPressure = true
    }

    mutating func reset() {
        peakAgentFootprintBytes = 0
        peakWebContentBytes = nil
        hadCriticalPressure = false
    }

    // MARK: - Reporting

    mutating func makeReport(webContentPIDs: [pid_t]?) -> ResourceSnapshot.MemoryUsage {
        let sample = sampler.takeSample(webContentPIDs: webContentPIDs)
        updatePeaks(with: sample)

        return ResourceSnapshot.MemoryUsage(
            agent: .init(
                footprintBytes: sample.agentFootprintBytes,
                peakFootprintBytes: peakAgentFootprintBytes
            ),
            webContent: .init(
                residentBytes: sample.webContentResidentBytes,
                peakResidentBytes: peakWebContentBytes,
                processCount: sample.webContentCount
            ),
            hadCriticalPressure: hadCriticalPressure
        )
    }

    private mutating func updatePeaks(with sample: MemoryUsageSample) {
        peakAgentFootprintBytes = max(
            peakAgentFootprintBytes,
            sample.agentFootprintBytes
        )
        if let residentBytes = sample.webContentResidentBytes {
            peakWebContentBytes = max(peakWebContentBytes ?? 0, residentBytes)
        }
    }
}

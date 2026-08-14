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

/// Tracks the latest memory reading and the highest readings seen during one PIR queue run.
struct MemoryUsageMonitor {

    private typealias MemoryFootprint = MemoryUsageSample.MemoryFootprint

    private struct PeakUsage {
        var agentFootprint: MemoryFootprint = 0
        var webContentFootprint: MemoryFootprint?

        mutating func record(_ sample: MemoryUsageSample) {
            agentFootprint = max(agentFootprint, sample.agentFootprint)
            if let footprint = sample.webContentFootprint {
                webContentFootprint = max(webContentFootprint ?? 0, footprint)
            }
        }
    }

    private var current: MemoryUsageSample
    private var peak: PeakUsage
    private var hadCriticalPressure = false

    /// Immediately takes the first memory reading for the run.
    init(webContentPIDs: Set<pid_t>?) {
        let sample = MemoryUsageSampler().takeSample(webContentPIDs: webContentPIDs)
        current = sample
        peak = PeakUsage(
            agentFootprint: sample.agentFootprint,
            webContentFootprint: sample.webContentFootprint
        )
    }

    /// Replaces the current reading and updates the highest values seen in this run.
    mutating func recordSample(webContentPIDs: Set<pid_t>?) {
        let sample = MemoryUsageSampler().takeSample(webContentPIDs: webContentPIDs)
        current = sample
        peak.record(sample)
    }

    /// Remembers that macOS reported critically low memory and returns whether this is the first such event in the run.
    mutating func recordCriticalPressure() -> Bool {
        let isFirstEvent = !hadCriticalPressure
        hadCriticalPressure = true
        return isFirstEvent
    }

    // MARK: - Reporting

    func makeReport() -> ResourceSnapshot.MemoryUsage {
        return ResourceSnapshot.MemoryUsage(
            agent: .init(
                footprintBytes: current.agentFootprint,
                peakFootprintBytes: peak.agentFootprint
            ),
            webContent: .init(
                footprintBytes: current.webContentFootprint,
                peakFootprintBytes: peak.webContentFootprint,
                processCount: current.webContentCount
            ),
            hadCriticalPressure: hadCriticalPressure
        )
    }
}

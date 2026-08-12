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

    private struct RunState {
        var current = MemoryUsageSample.unavailable
        var peak = PeakUsage()
        var hadCriticalPressure = false
    }

    private let sampler = MemoryUsageSampler()
    private var state = RunState()

    // MARK: - Run Lifecycle

    /// Clears data from the previous run and immediately takes the first memory reading.
    mutating func start(webContentPIDs: [pid_t]?) {
        reset()
        recordSample(webContentPIDs: webContentPIDs)
    }

    /// Replaces the current reading and updates the highest values seen in this run.
    mutating func recordSample(webContentPIDs: [pid_t]?) {
        let sample = sampler.takeSample(webContentPIDs: webContentPIDs)
        state.current = sample
        state.peak.record(sample)
    }

    /// Remembers that macOS reported critically low memory and returns whether this is the first such event in the run.
    mutating func recordCriticalPressure() -> Bool {
        let isFirstEvent = !state.hadCriticalPressure
        state.hadCriticalPressure = true
        return isFirstEvent
    }

    mutating func reset() {
        state = RunState()
    }

    // MARK: - Reporting

    func makeReport() -> ResourceSnapshot.MemoryUsage {
        return ResourceSnapshot.MemoryUsage(
            agent: .init(
                footprintBytes: state.current.agentFootprint,
                peakFootprintBytes: state.peak.agentFootprint
            ),
            webContent: .init(
                footprintBytes: state.current.webContentFootprint,
                peakFootprintBytes: state.peak.webContentFootprint,
                processCount: state.current.webContentCount
            ),
            hadCriticalPressure: state.hadCriticalPressure
        )
    }
}

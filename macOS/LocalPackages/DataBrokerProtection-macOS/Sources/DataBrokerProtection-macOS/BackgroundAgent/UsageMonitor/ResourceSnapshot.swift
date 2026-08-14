//
//  ResourceSnapshot.swift
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

/// The CPU and memory measurements collected for one PIR queue run.
struct ResourceSnapshot {

    struct CPUUsage {
        /// Time elapsed since monitoring started, in seconds.
        let elapsedTime: TimeInterval
        /// CPU time used by the background agent during the run, in seconds.
        let agentTime: TimeInterval
        /// CPU time used by all observed WebContent processes during the run, in seconds.
        let webContentTime: TimeInterval
        /// Average CPU use during the run. One fully used core is 100%; multiple cores can exceed 100%.
        let averagePercent: Double

        /// Combined agent and WebContent CPU time, in seconds.
        var totalTime: TimeInterval {
            agentTime + webContentTime
        }
    }

    struct MemoryUsage {
        struct Agent {
            /// Memory attributed to the agent in the latest reading, in bytes. Zero can also mean the read failed.
            let footprintBytes: UInt64
            /// Highest agent-memory reading observed during the run, in bytes. Zero can also mean no successful read was made.
            let peakFootprintBytes: UInt64
        }

        struct WebContent {
            /// Memory attributed to all WebContent processes in the latest reading, or `nil` if it could not be read completely.
            let footprintBytes: UInt64?
            /// Highest complete WebContent-memory reading observed during the run, or `nil` if none was available.
            let peakFootprintBytes: UInt64?
            /// Number of WebContent processes found in the latest reading, or `nil` if discovery failed.
            let processCount: Int?
        }

        let agent: Agent
        let webContent: WebContent
        /// Whether macOS reported critically low available memory during the run.
        let hadCriticalPressure: Bool
    }

    let cpu: CPUUsage
    let memory: MemoryUsage
}

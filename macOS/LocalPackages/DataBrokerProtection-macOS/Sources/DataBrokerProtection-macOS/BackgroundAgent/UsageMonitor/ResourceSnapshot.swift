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

/// A snapshot of one monitored PIR queue run.
public struct ResourceSnapshot: Equatable, Sendable {

    public struct CPUUsage: Equatable, Sendable {
        /// Cumulative agent CPU time; separates coordinator overhead from WebContent work.
        public let agentTime: TimeInterval
        /// Cumulative observed WebContent CPU time; attributes cost to broker-page execution.
        public let webContentTime: TimeInterval
        /// Total CPU time normalized by elapsed monitoring time; 100% represents one fully occupied core.
        public let averagePercent: Double
        /// WebContent process discovery and readability for the latest CPU accounting sample.
        public let coverage: ProcessCoverage

        /// Cumulative agent and observed WebContent CPU time; measures total captured CPU cost.
        public var totalTime: TimeInterval {
            agentTime + webContentTime
        }
    }

    public struct ProcessCoverage: Equatable, Sendable {
        /// WebContent processes discovered for CPU accounting.
        public let discoveredCount: Int
        /// Discovered WebContent processes with readable CPU counters.
        public let readableCount: Int
    }

    public struct MemoryUsage: Equatable, Sendable {
        public struct Agent: Equatable, Sendable {
            /// Current physical footprint; identifies sustained coordinator memory usage.
            public let footprintBytes: UInt64
            /// Highest sampled physical footprint; identifies coordinator memory spikes.
            public let peakFootprintBytes: UInt64
        }

        public struct WebContent: Equatable, Sendable {
            /// Current summed physical footprint, or `nil` if unavailable; identifies sustained usage.
            public let footprintBytes: UInt64?
            /// Highest sampled physical-footprint sum; identifies broker-page memory spikes.
            public let peakFootprintBytes: UInt64?
            /// Current process count, or `nil` if unavailable; relates usage to process fan-out.
            public let processCount: Int?
        }

        public let agent: Agent
        public let webContent: WebContent
        /// Whether critical memory pressure occurred during the run; provides a direct system-impact signal.
        public let hadCriticalPressure: Bool
    }

    /// The publication time, used to establish sample freshness and cadence.
    public let sampledAt: Date
    public let cpu: CPUUsage
    public let memory: MemoryUsage
}

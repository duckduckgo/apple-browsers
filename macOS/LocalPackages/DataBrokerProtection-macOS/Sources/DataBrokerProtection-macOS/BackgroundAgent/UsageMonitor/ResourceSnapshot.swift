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
public struct ResourceSnapshot: Equatable, Sendable {

    public struct CPUUsage: Equatable, Sendable {
        /// CPU time used by the background agent during the run, in seconds.
        public let agentTime: TimeInterval
        /// CPU time used by all observed WebContent processes during the run, in seconds.
        public let webContentTime: TimeInterval
        /// Average CPU use during the run. One fully used core is 100%; multiple cores can exceed 100%.
        public let averagePercent: Double

        /// Combined agent and WebContent CPU time, in seconds.
        public var totalTime: TimeInterval {
            agentTime + webContentTime
        }
    }

    public struct MemoryUsage: Equatable, Sendable {
        public struct Agent: Equatable, Sendable {
            /// Memory attributed to the agent in the latest reading, in bytes. Zero can also mean the read failed.
            public let footprintBytes: UInt64
            /// Highest agent-memory reading observed during the run, in bytes. Zero can also mean no successful read was made.
            public let peakFootprintBytes: UInt64
        }

        public struct WebContent: Equatable, Sendable {
            /// Memory attributed to all WebContent processes in the latest reading, or `nil` if it could not be read completely.
            public let footprintBytes: UInt64?
            /// Highest complete WebContent-memory reading observed during the run, or `nil` if none was available.
            public let peakFootprintBytes: UInt64?
            /// Number of WebContent processes found in the latest reading, or `nil` if discovery failed.
            public let processCount: Int?
        }

        public let agent: Agent
        public let webContent: WebContent
        /// Whether macOS reported critically low available memory during the run.
        public let hadCriticalPressure: Bool
    }

    public let cpu: CPUUsage
    public let memory: MemoryUsage
}

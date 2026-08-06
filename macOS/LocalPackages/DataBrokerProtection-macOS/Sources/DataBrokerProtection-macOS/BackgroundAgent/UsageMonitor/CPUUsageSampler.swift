//
//  CPUUsageSampler.swift
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

/// One point-in-time read of cumulative process CPU counters. Each value contains all user and system
/// CPU consumed since that process started, not CPU consumed since the previous sample. For example:
/// - Run start reads `agent: 100s`, `WebContent[A]: 3s`; both become baselines, so run usage is `0s`.
/// - Next reads `agent: 102s`, `A: 5s`, `B: 2s`; B started during the run, so run usage is
///   `agent: 2s`, `WebContent: 4s` (`A: 2s`, `B: 2s`).
/// - Later reads `agent: 103s`, `B: 5s`; run usage is `agent: 3s`, `WebContent: 7s`, retaining A's `2s`.
struct CPUUsageSample {
    /// Cumulative user and system CPU time in nanoseconds.
    typealias ProcessCPUTime = UInt64

    struct ProcessIdentity: Hashable {
        /// The process identifier, which the system may reuse after a process exits.
        let pid: pid_t
        /// Process start time paired with the PID to distinguish reused identifiers.
        let startAbsoluteTime: UInt64
    }

    /// Cumulative agent CPU time, or `nil` when its process counter could not be read.
    let agent: ProcessCPUTime?
    /// Cumulative WebContent CPU time keyed by stable process identity.
    let webContent: [ProcessIdentity: ProcessCPUTime]
    /// System uptime when this sample was taken.
    let uptime: TimeInterval
}

/// Reads cumulative user and system CPU counters for the agent and currently live WebContent processes.
struct CPUUsageSampler {

    /// Reads the agent and the supplied currently live WebContent PIDs.
    func takeSample(webContentPIDs: Set<pid_t>) -> CPUUsageSample {
        let webContent = Dictionary(
            uniqueKeysWithValues: webContentPIDs.compactMap { pid in
                Self.processCPUTime(for: pid).map { ($0.identity, $0.cpuTime) }
            }
        )
        return CPUUsageSample(
            agent: Self.processCPUTime(for: getpid())?.cpuTime,
            webContent: webContent,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private static func processCPUTime(
        for pid: pid_t
    ) -> (identity: CPUUsageSample.ProcessIdentity, cpuTime: CPUUsageSample.ProcessCPUTime)? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }

        return (
            identity: .init(pid: pid, startAbsoluteTime: usage.ri_proc_start_abstime),
            cpuTime: usage.ri_user_time + usage.ri_system_time
        )
    }
}

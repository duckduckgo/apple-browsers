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

/// One reading of the CPU counters maintained by macOS for each process.
///
/// Each value is a running total from when the process started, not CPU used since our previous reading.
/// `CPUUsageMonitor` compares these readings to determine how much belongs to the current PIR run.
struct CPUUsageSample {
    /// Total time spent running process code and macOS system code on its behalf, in Mach timebase ticks.
    typealias ProcessCPUTime = UInt64

    struct ProcessIdentity: Hashable {
        /// The numeric ID assigned to the process by macOS.
        let pid: pid_t
        /// Paired with `pid` because macOS can give the same numeric ID to a later process.
        let startAbsoluteTime: UInt64
    }

    /// The agent's total CPU time since it started, or `nil` if macOS could not read it.
    let agent: ProcessCPUTime?
    /// Each live web process's total CPU time since it started.
    let webProcesses: [ProcessIdentity: ProcessCPUTime]
    /// The system uptime at this reading, used to calculate how long the monitored run has lasted.
    let uptime: TimeInterval
}

/// Reads the CPU counters for the agent and the currently running web processes.
struct CPUUsageSampler {

    func takeSample(webProcessPIDs: Set<pid_t>) -> CPUUsageSample {
        let webProcesses = Dictionary(
            uniqueKeysWithValues: webProcessPIDs.compactMap { pid in
                Self.processCPUTime(for: pid).map { ($0.identity, $0.cpuTime) }
            }
        )
        return CPUUsageSample(
            agent: Self.processCPUTime(for: getpid())?.cpuTime,
            webProcesses: webProcesses,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    /// Reads the total CPU time used by one process since it started.
    ///
    /// `proc_pid_rusage` asks macOS for statistics about a process by its numeric ID. The version-4 record contains the
    /// process start time plus separate counters for time spent running app code and macOS system code. We add those two
    /// counters together. This returns `nil` if the process exits before it can be read or the query otherwise fails.
    private static func processCPUTime(
        for pid: pid_t
    ) -> (identity: CPUUsageSample.ProcessIdentity, cpuTime: CPUUsageSample.ProcessCPUTime)? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            // The API accepts a generic resource-usage pointer, so temporarily view our version-4 buffer as that type.
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

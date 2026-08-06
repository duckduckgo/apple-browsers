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

struct CPUUsageSample {
    struct ProcessIdentity: Hashable {
        let pid: pid_t
        let startAbsoluteTime: UInt64
    }

    struct ProcessReading {
        let identity: ProcessIdentity
        let totalNanoseconds: UInt64
    }

    let agent: ProcessReading?
    let webContent: [ProcessIdentity: ProcessReading]
    let discoveredCount: Int
    let uptime: TimeInterval
}

/// Reads cumulative user and system CPU counters for the agent and currently live WebContent processes.
struct CPUUsageSampler {

    func takeSample(webContentPIDs: Set<pid_t>) -> CPUUsageSample {
        let webContent = Dictionary(
            uniqueKeysWithValues: webContentPIDs.compactMap { pid in
                Self.processReading(for: pid).map { ($0.identity, $0) }
            }
        )
        return CPUUsageSample(
            agent: Self.processReading(for: getpid()),
            webContent: webContent,
            discoveredCount: webContentPIDs.count,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private static func processReading(for pid: pid_t) -> CPUUsageSample.ProcessReading? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }

        return CPUUsageSample.ProcessReading(
            identity: .init(pid: pid, startAbsoluteTime: usage.ri_proc_start_abstime),
            totalNanoseconds: usage.ri_user_time + usage.ri_system_time
        )
    }
}

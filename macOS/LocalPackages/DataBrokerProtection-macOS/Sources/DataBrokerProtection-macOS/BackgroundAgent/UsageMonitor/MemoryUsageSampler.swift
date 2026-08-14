//
//  MemoryUsageSampler.swift
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

/// One reading of the physical memory attributed to the agent and its WebContent processes.
struct MemoryUsageSample {
    /// Physical memory attributed to a process, in bytes.
    typealias MemoryFootprint = UInt64

    /// Memory attributed to the agent, or zero if macOS could not read it.
    let agentFootprint: MemoryFootprint
    /// Memory attributed to all discovered WebContent processes, or `nil` if the total could not be read completely.
    let webContentFootprint: MemoryFootprint?
    /// Number of WebContent processes found, or `nil` if they could not be discovered.
    let webContentCount: Int?
}

/// Uses the same physical-memory measurement as AppHealth for the agent. For WebContent, it deliberately uses physical
/// footprint instead of AppHealth's resident-size measurement, which can count the same shared memory in several processes.
struct MemoryUsageSampler {

    /// A missing process list means WebContent usage is unavailable; an empty list means it is known to be zero.
    func takeSample(webContentPIDs: Set<pid_t>?) -> MemoryUsageSample {
        let webContentFootprint = webContentPIDs.flatMap(Self.combinedPhysicalFootprint)
        return MemoryUsageSample(
            agentFootprint: Self.agentPhysicalFootprint(),
            webContentFootprint: webContentFootprint,
            webContentCount: webContentPIDs?.count
        )
    }

    private static func combinedPhysicalFootprint(for pids: Set<pid_t>) -> MemoryUsageSample.MemoryFootprint? {
        var total: MemoryUsageSample.MemoryFootprint = 0
        for pid in pids {
            guard let footprint = physicalFootprint(for: pid) else { return nil }
            total += footprint
        }
        return total
    }

    /// Reads memory used by the background agent itself.
    ///
    /// `task_info` asks macOS for memory statistics about the current process (`mach_task_self_`). We report
    /// `phys_footprint`, in bytes: the amount of RAM macOS considers this process responsible for. Unlike resident size,
    /// this avoids charging the full size of shared memory to every process and includes compressed memory attributed to
    /// the process. If macOS cannot provide the statistics, this returns zero.
    private static func agentPhysicalFootprint() -> MemoryUsageSample.MemoryFootprint {
        var vmInfo = task_vm_info_data_t()
        // The Mach API describes the output buffer's size in `integer_t` units, rather than bytes.
        var vmInfoCount = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &vmInfo) { pointer in
            // Swift sees `vmInfo` as a struct, while the Mach API expects a pointer to its underlying integers.
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmInfoCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmInfoCount)
            }
        }
        return result == KERN_SUCCESS ? UInt64(vmInfo.phys_footprint) : 0
    }

    /// Reads memory used by one WebContent process.
    ///
    /// WebContent runs in a separate process, so it cannot be queried as the current Mach task. Instead,
    /// `proc_pid_rusage` asks macOS for statistics about that process by PID. `ri_phys_footprint` is the same kind of
    /// physical-memory measurement used for the agent above. This returns `nil` if the process exits before it can be
    /// read, or if macOS otherwise cannot provide its statistics.
    private static func physicalFootprint(for pid: pid_t) -> MemoryUsageSample.MemoryFootprint? {
        // This struct is the output buffer. `RUSAGE_INFO_V4` tells macOS which version of the buffer we supplied;
        // version 4 is used because it includes `ri_phys_footprint`.
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }
}

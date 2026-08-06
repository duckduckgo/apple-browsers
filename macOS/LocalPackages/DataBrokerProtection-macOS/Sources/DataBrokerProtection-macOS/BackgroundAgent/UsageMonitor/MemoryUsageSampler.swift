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

struct MemoryUsageSample {
    let agentFootprintBytes: UInt64
    let webContentResidentBytes: UInt64?
    let webContentCount: Int?
}

/// Mirrors `getCurrentMemoryUsage()` and `getWebContentProcessMemory()` in the AppHealth
/// `MemoryUsageMonitor`.
struct MemoryUsageSampler {

    func takeSample(webContentPIDs: [pid_t]?) -> MemoryUsageSample {
        // getWebContentProcessMemory() also sums resident size, including shared mappings at full size.
        let residentBytes = webContentPIDs.map { pids in
            pids.compactMap(Self.residentMemorySize).reduce(0, +)
        }
        return MemoryUsageSample(
            agentFootprintBytes: Self.agentPhysicalFootprint(),
            webContentResidentBytes: residentBytes,
            webContentCount: webContentPIDs?.count
        )
    }

    private static func agentPhysicalFootprint() -> UInt64 {
        var vmInfo = task_vm_info_data_t()
        var vmInfoCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result = withUnsafeMutablePointer(to: &vmInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmInfoCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmInfoCount)
            }
        }
        return result == KERN_SUCCESS ? UInt64(vmInfo.phys_footprint) : 0
    }

    private static func residentMemorySize(for pid: pid_t) -> UInt64? {
        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
        return result == size ? taskInfo.pti_resident_size : nil
    }
}

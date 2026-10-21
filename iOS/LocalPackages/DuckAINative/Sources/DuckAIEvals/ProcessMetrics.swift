//
//  ProcessMetrics.swift
//  DuckDuckGo
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

import Darwin
import Foundation

/// Samples this process's memory footprint (the number iOS compares against its memory limit) every 100 ms during a run.
public final class ProcessMetrics: DeviceMetricsSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Int64 = 0
    private var sampler: Task<Void, Never>?

    public init() {}

    public func beginRun() {
        lock.withLock {
            peak = Self.physicalFootprint()
            sampler?.cancel()
            sampler = Task.detached { [weak self] in
                while !Task.isCancelled {
                    let sample = Self.physicalFootprint()
                    self?.lock.withLock { self?.peak = max(self?.peak ?? 0, sample) }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }

    public func endRun() -> (peakMemoryBytes: Int64?, thermalState: String?) {
        let peak = lock.withLock {
            sampler?.cancel()
            sampler = nil
            return max(self.peak, Self.physicalFootprint())
        }
        return (peak, Self.thermalState)
    }

    public static func physicalFootprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    public static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

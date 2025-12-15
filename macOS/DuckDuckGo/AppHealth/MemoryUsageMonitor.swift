//
//  MemoryUsageMonitor.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import os.log

/// A monitor that periodically reports the memory usage of the current process.
final class MemoryUsageMonitor: @unchecked Sendable {

    /// The interval between memory usage reports.
    let interval: TimeInterval

    /// A closure called each time memory usage is reported.
    var onMemoryReport: ((MemoryReport) -> Void)?

    private var monitoringTask: Task<Void, Never>?
    private let logger: Logger

    /// Represents a snapshot of memory usage.
    struct MemoryReport: Sendable {
        /// Memory used by the process in bytes.
        let usedBytes: UInt64
        /// Memory used by the process in megabytes.
        var usedMB: Double { Double(usedBytes) / Double(Self.oneMB) }
        /// Memory used by the process in gigabytes.
        var usedGB: Double { Double(usedBytes) / Double(Self.oneGB) }
        /// Timestamp when the report was generated.
        let timestamp: Date

        private static let oneMB: UInt64 = 1_048_576
        private static let oneGB: UInt64 = 1_073_741_824
    }

    /// Creates a new memory usage monitor.
    /// - Parameter interval: The interval between reports. Defaults to 5 seconds.
    init(interval: TimeInterval = 5.0, logger: Logger?) {
        self.interval = interval
        self.logger = logger ?? Logger(subsystem: "MemoryUsageMonitor", category: "")
    }

    /// Starts monitoring memory usage.
    func start() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let report = self.getCurrentMemoryUsage()

                self.logger.info("Memory usage: \(report.usedMB, format: .fixed(precision: 2)) MB")
                self.onMemoryReport?(report)

                try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(self.interval))
            }
        }
    }

    /// Stops monitoring memory usage.
    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Returns the current memory usage of the process.
    func getCurrentMemoryUsage() -> MemoryReport {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let usedBytes: UInt64
        if result == KERN_SUCCESS {
            usedBytes = UInt64(info.resident_size)
        } else {
            logger.warning("Failed to get memory info: \(result)")
            usedBytes = 0
        }

        return MemoryReport(usedBytes: usedBytes, timestamp: Date())
    }

    deinit {
        stop()
    }
}

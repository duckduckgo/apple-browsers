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

import AppKit
import Combine
import Foundation
import os.log
import PrivacyConfig

protocol MemoryUsageMonitoring {
    var memoryReportPublisher: AnyPublisher<MemoryUsageMonitor.MemoryReport, Never> { get }
}

/// A monitor that periodically reports the memory usage of the current process.
final class MemoryUsageMonitor: @unchecked Sendable, MemoryUsageMonitoring {

    /// The interval between memory usage reports.
    let interval: TimeInterval

    /// A publisher that emits an event each time a memory usage report is updated.
    let memoryReportPublisher: AnyPublisher<MemoryReport, Never>

    private var monitoringTask: Task<Void, Never>?
    private let logger: Logger?
    private let memoryReportSubject = PassthroughSubject<MemoryReport, Never>()
    private var cancellables: Set<AnyCancellable> = []

    /// Represents a snapshot of memory usage.
    struct MemoryReport: Sendable {
        /// Resident memory size in bytes (includes shared libraries at full size).
        let residentBytes: UInt64
        /// Physical footprint in bytes (memory process is responsible for, matches Activity Monitor).
        let physFootprintBytes: UInt64

        /// Resident memory in megabytes.
        var residentMB: Double { Double(residentBytes) / Double(Self.oneMB) }
        /// Resident memory in gigabytes.
        var residentGB: Double { Double(residentBytes) / Double(Self.oneGB) }

        /// Physical footprint in megabytes.
        var physFootprintMB: Double { Double(physFootprintBytes) / Double(Self.oneMB) }
        /// Physical footprint in gigabytes.
        var physFootprintGB: Double { Double(physFootprintBytes) / Double(Self.oneGB) }

        var residentMemoryString: String {
            if residentBytes > Self.oneGB {
                let formattedValue = Self.gbFormatter.string(from: NSNumber(value: residentGB)) ?? String(residentGB)
                return "\(formattedValue) GB"
            }
            let formattedValue = Self.mbFormatter.string(from: NSNumber(value: residentMB)) ?? String(residentMB)
            return "\(formattedValue) MB"
        }

        var footprintMemoryString: String {
            if physFootprintBytes > Self.oneGB {
                let formattedValue = Self.gbFormatter.string(from: NSNumber(value: physFootprintGB)) ?? String(physFootprintGB)
                return "\(formattedValue) GB"
            }
            let formattedValue = Self.mbFormatter.string(from: NSNumber(value: physFootprintMB)) ?? String(physFootprintMB)
            return "\(formattedValue) MB"
        }

        /// Comparison string showing both resident and physical footprint values.
        var comparisonString: String {
            return "R:\(residentMemoryString) | F:\(footprintMemoryString)"
        }

        private static let oneMB: UInt64 = 1_048_576
        private static let oneGB: UInt64 = 1_073_741_824
        private static let gbFormatter: NumberFormatter = {
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.minimumFractionDigits = 2
            numberFormatter.maximumFractionDigits = 2
            return numberFormatter
        }()
        private static let mbFormatter: NumberFormatter = {
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.minimumFractionDigits = 0
            numberFormatter.maximumFractionDigits = 0
            return numberFormatter
        }()
    }

    /// Creates a new memory usage monitor.
    /// - Parameter interval: The interval between reports. Defaults to 3 seconds.
    init(interval: TimeInterval = 3.0, logger: Logger? = nil) {
        self.interval = interval
        self.logger = logger
        self.memoryReportPublisher = memoryReportSubject.eraseToAnyPublisher()
    }

    func enableIfNeeded(featureFlagger: FeatureFlagger) {
        featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.memoryUsageMonitor)
            }
            .prepend(featureFlagger.isFeatureOn(.memoryUsageMonitor))
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMemoryMonitorFeatureFlagEnabled in
                if isMemoryMonitorFeatureFlagEnabled {
                    self?.start()
                } else {
                    self?.stop()
                }
            }
            .store(in: &cancellables)
    }

    /// Starts monitoring memory usage.
    private func start() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let report = self.getCurrentMemoryUsage()

                self.logger?.info("Memory usage - resident: \(report.residentMemoryString), footprint: \(report.footprintMemoryString)")
                await MainActor.run {
                    self.memoryReportSubject.send(report)
                }

                try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(self.interval))
            }
        }
    }

    /// Stops monitoring memory usage.
    private func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Returns the current memory usage of the process.
    func getCurrentMemoryUsage() -> MemoryReport {
        // Get resident_size from mach_task_basic_info
        var basicInfo = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let basicResult = withUnsafeMutablePointer(to: &basicInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
            }
        }

        let residentBytes: UInt64
        if basicResult == KERN_SUCCESS {
            residentBytes = UInt64(basicInfo.resident_size)
        } else {
            logger?.warning("Failed to get basic memory info: \(basicResult)")
            residentBytes = 0
        }

        // Get phys_footprint from task_vm_info
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4

        let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }

        let physFootprintBytes: UInt64
        if vmResult == KERN_SUCCESS {
            physFootprintBytes = UInt64(vmInfo.phys_footprint)
        } else {
            logger?.warning("Failed to get VM info: \(vmResult)")
            physFootprintBytes = 0
        }

        return MemoryReport(residentBytes: residentBytes, physFootprintBytes: physFootprintBytes)
    }

    deinit {
        stop()
    }
}

/// This protocol describes an object that can present a memory usage stat.
@MainActor
protocol MemoryUsagePresenting: AnyObject {
    /// This function is called by MemoryUsageDisplayer to ask the presenter to add the `view`
    /// to the view hierarchy.
    ///
    /// The view is a single `NSTextField`.
    ///
    func embedMemoryUsageView(_ view: NSView)
}

/// This class encapsulates logic of providing a memory usage stat view with regular updates,
/// ready for displaying in a way defined by `presenter`.
@MainActor
final class MemoryUsageDisplayer {
    let memoryUsageMonitor: MemoryUsageMonitor
    let featureFlagger: FeatureFlagger
    weak var presenter: MemoryUsagePresenting?
    private var memoryUsageMonitorView: NSView?
    private var cancellables: Set<AnyCancellable> = []
    private var viewUpdatesCancellable: AnyCancellable?

    init(memoryUsageMonitor: MemoryUsageMonitor, featureFlagger: FeatureFlagger) {
        self.memoryUsageMonitor = memoryUsageMonitor
        self.featureFlagger = featureFlagger
    }

    /// This function should be called once in order to display the memory usage view if needed.
    ///
    /// It checks the feature flag, and if enabled, it proceeeds with displaying memory monitor view.
    /// It also subscribes to feature flag changes and is able to react to updates in real time and
    /// present/hide the view as needed.
    ///
    func setUpMemoryMonitorView() {
        featureFlagger.updatesPublisher
            .compactMap { [weak self] in
                self?.featureFlagger.isFeatureOn(.memoryUsageMonitor)
            }
            .prepend(featureFlagger.isFeatureOn(.memoryUsageMonitor))
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMemoryMonitorFeatureFlagEnabled in
                if isMemoryMonitorFeatureFlagEnabled {
                    self?.showMemoryMonitor()
                } else {
                    self?.hideMemoryMonitor()
                }
            }
            .store(in: &cancellables)
    }

    /// This function shows memory monitor and sets up view updates via memory report publisher.
    private func showMemoryMonitor() {
        guard let presenter, featureFlagger.isFeatureOn(.memoryUsageMonitor) else {
            return
        }
        let label = NSTextField()
        label.isEditable = false
        label.font = NSFont.monospacedSystemFont(ofSize: 8.0, weight: .regular)
        label.isBezeled = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.drawsBackground = false

        presenter.embedMemoryUsageView(label)

        memoryUsageMonitorView = label
        viewUpdatesCancellable = memoryUsageMonitor.memoryReportPublisher
            .prepend(memoryUsageMonitor.getCurrentMemoryUsage())
            .sink { [weak label] report in
                label?.stringValue = report.comparisonString
                label?.sizeToFit()
            }
    }

    /// This function hides memory monitor by removing it from the superview and removing the usage updates subscription.
    private func hideMemoryMonitor() {
        memoryUsageMonitorView?.removeFromSuperview()
        memoryUsageMonitorView = nil
        viewUpdatesCancellable?.cancel()
        viewUpdatesCancellable = nil
    }
}

#if DEBUG
extension MemoryUsageMonitor {
    /// Simulates a memory report for testing purposes.
    ///
    /// This method is intended **only for use by the Debug menu** to manually trigger
    /// memory usage reporting without waiting for actual memory changes. It allows developers
    /// to test threshold pixel firing for specific memory values.
    ///
    /// - Parameter physFootprintMB: Memory usage in megabytes to simulate
    ///
    /// - Warning: Do not use this method in production code. It is designed exclusively
    ///   for debugging and testing purposes via the Debug menu.
    ///
    func simulateMemoryReport(physFootprintMB: Double) {
        let physFootprintBytes = UInt64(physFootprintMB * 1_048_576)
        let report = MemoryReport(
            residentBytes: physFootprintBytes,
            physFootprintBytes: physFootprintBytes
        )
        memoryReportSubject.send(report)
    }
}
#endif

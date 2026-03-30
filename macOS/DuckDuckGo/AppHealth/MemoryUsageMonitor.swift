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
import WebKit

protocol MemoryUsageMonitoring {
    func getCurrentMemoryUsage() -> MemoryUsageMonitor.MemoryReport
}

/// A monitor that periodically reports the memory usage of the current process.
final class MemoryUsageMonitor: @unchecked Sendable, MemoryUsageMonitoring {

    /// The interval between memory usage reports.
    let interval: TimeInterval

    /// A publisher that emits an event each time a memory usage report is updated.
    let memoryReportPublisher: AnyPublisher<MemoryReport, Never>

    private var monitoringTask: Task<Void, Never>?
    private let logger: Logger?
    private let internalUserDecider: InternalUserDecider
    private let memoryReportSubject = PassthroughSubject<MemoryReport, Never>()
    private var cancellables: Set<AnyCancellable> = []

    /// When set and the user is an internal user, `getCurrentMemoryUsage()` returns this value
    /// instead of real system memory. Used for testing threshold pixels via the Debug menu.
    private var simulatedReport: MemoryReport?

    /// Represents a snapshot of memory usage.
    struct MemoryReport: Sendable {
        /// Resident memory size in bytes (includes shared libraries at full size).
        let residentBytes: UInt64
        /// Physical footprint in bytes (memory process is responsible for, matches Activity Monitor).
        let physFootprintBytes: UInt64
        /// Total resident memory of all WebContent processes in bytes, or `nil` if unavailable.
        let webContentBytes: UInt64?
        /// Number of WebContent processes found, or `nil` if unavailable.
        let webContentProcessCount: Int?

        /// Resident memory in megabytes.
        var residentMB: Double { Double(residentBytes) / Double(Self.oneMB) }
        /// Resident memory in gigabytes.
        var residentGB: Double { Double(residentBytes) / Double(Self.oneGB) }

        /// Physical footprint in megabytes.
        var physFootprintMB: Double { Double(physFootprintBytes) / Double(Self.oneMB) }
        /// Physical footprint in gigabytes.
        var physFootprintGB: Double { Double(physFootprintBytes) / Double(Self.oneGB) }

        /// WebContent memory in megabytes, or `nil` if unavailable.
        var webContentMB: Double? { webContentBytes.map { Double($0) / Double(Self.oneMB) } }
        /// WebContent memory in gigabytes, or `nil` if unavailable.
        var webContentGB: Double? { webContentBytes.map { Double($0) / Double(Self.oneGB) } }

        /// Total memory (main process footprint + WebContent) in bytes, or `nil` if WebContent is unavailable.
        var totalBytes: UInt64? { webContentBytes.map { physFootprintBytes + $0 } }
        var totalMB: Double? { totalBytes.map { Double($0) / Double(Self.oneMB) } }
        var totalGB: Double? { totalBytes.map { Double($0) / Double(Self.oneGB) } }

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

        var webContentMemoryString: String {
            guard let webContentBytes, let webContentMB, let webContentGB else { return "N/A" }
            if webContentBytes > Self.oneGB {
                let formattedValue = Self.gbFormatter.string(from: NSNumber(value: webContentGB)) ?? String(webContentGB)
                return "\(formattedValue) GB"
            }
            let formattedValue = Self.mbFormatter.string(from: NSNumber(value: webContentMB)) ?? String(webContentMB)
            return "\(formattedValue) MB"
        }

        var totalMemoryString: String {
            guard let totalBytes, let totalMB, let totalGB else { return "N/A" }
            if totalBytes > Self.oneGB {
                let formattedValue = Self.gbFormatter.string(from: NSNumber(value: totalGB)) ?? String(totalGB)
                return "\(formattedValue) GB"
            }
            let formattedValue = Self.mbFormatter.string(from: NSNumber(value: totalMB)) ?? String(totalMB)
            return "\(formattedValue) MB"
        }

        /// Comparison string showing physical footprint and WebContent values.
        var comparisonString: String {
            let wcCount = webContentProcessCount.map(String.init) ?? "?"
            return "M:\(footprintMemoryString) | WC:\(webContentMemoryString)(\(wcCount))"
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
    /// - Parameters:
    ///   - interval: The interval between reports. Defaults to 3 seconds.
    ///   - internalUserDecider: Used to gate simulated memory reports to internal users only.
    ///   - logger: Optional logger for debugging.
    init(interval: TimeInterval = 3.0, internalUserDecider: InternalUserDecider, logger: Logger? = nil) {
        self.interval = interval
        self.internalUserDecider = internalUserDecider
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
    ///
    /// For internal users, if a simulated report has been set via `simulateMemoryReport`,
    /// that value is returned instead of the real system memory.
    func getCurrentMemoryUsage() -> MemoryReport {
        if internalUserDecider.isInternalUser, let simulatedReport {
            return simulatedReport
        }

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

        let webContentInfo = Self.getWebContentProcessMemory()

        return MemoryReport(
            residentBytes: residentBytes,
            physFootprintBytes: physFootprintBytes,
            webContentBytes: webContentInfo?.totalBytes,
            webContentProcessCount: webContentInfo?.processCount)
    }

    /// Queries WebContent process memory using the private WebKit API to get PIDs,
    /// then reads each process's resident memory via proc_pidinfo.
    ///
    /// Returns `nil` if the private API is unavailable or fails, so callers can
    /// distinguish "0 bytes used" from "unable to measure."
    ///
    /// - Parameters:
    ///   - pidProvider: Override for PID collection. When `nil` (default), uses the real
    ///     `WKProcessPool._webContentProcessInfo` API. Provided for testing only.
    ///   - memoryProvider: Override for per-PID resident size lookup. When `nil` (default),
    ///     uses `proc_pidinfo`. Returns `nil` for a given PID if memory is unreadable
    ///     (e.g. the process has exited). Provided for testing only.
    static func getWebContentProcessMemory(
        pidProvider: (() -> [pid_t]?)? = nil,
        memoryProvider: ((pid_t) -> UInt64?)? = nil
    ) -> (totalBytes: UInt64, processCount: Int)? {
        // _webContentProcessInfo must be called on the main thread. WebKit's
        // AuxiliaryProcessProxy objects are owned and destroyed on the main thread;
        // calling this API off the main thread races with WebContent process termination,
        // causing a use-after-free crash inside AuxiliaryProcessProxy::taskInfo.
        // We extract the PIDs (plain integers) on the main thread, then query
        // proc_pidinfo with those values — proc_pidinfo is a syscall with no WebKit
        // involvement and handles dead processes safely via its return value.
        //
        // Callers and their thread context:
        //   - MemoryUsageThresholdReporter.checkThresholdAndFire — Task.detached(priority: .utility) [background] ← crash path
        //   - MemoryUsageMonitor internal polling loop            — Task {} [background]
        //   - MemoryPressureReporter.handleMemoryPressureEvent   — @MainActor [main thread]
        //   - MemoryUsageIntervalReporter                        — await MainActor.run { } [main thread]
        //   - MemoryUsageDisplayer.present(in:)                  — @MainActor [main thread]
        //
        // DispatchQueue.main.sync from the main thread deadlocks, so we skip the dispatch
        // when already on the main thread. Thread.isMainThread is the right guard here: all
        // main-thread callers use @MainActor or await MainActor.run, and Swift's MainActor
        // is backed by DispatchQueue.main, so Thread.isMainThread is equivalent to holding
        // the main queue's serial token for these callers. If that backing ever changed, the
        // guard would need to be revisited.
        let collectPIDs: () -> [pid_t]?
        if let pidProvider {
            collectPIDs = pidProvider
        } else {
            let selector = Selector(("_webContentProcessInfo"))
            guard WKProcessPool.responds(to: selector) else { return nil }
            // autoreleasepool ensures the objects returned by the private API are kept alive
            // for the duration of the call. takeUnretainedValue() does not retain, and
            // _webContentProcessInfo's memory management convention is unknown — if it returns
            // an autoreleased value, the array and its AuxiliaryProcessProxy-derived elements
            // could be freed before compactMap finishes without an explicit pool scope.
            collectPIDs = {
                autoreleasepool {
                    guard let processInfoList = WKProcessPool.perform(selector)?
                        .takeUnretainedValue() as? [NSObject] else { return nil }
                    let pidSelector = Selector(("pid"))
                    return processInfoList.compactMap { processInfo in
                        guard processInfo.responds(to: pidSelector),
                              let pid = processInfo.value(forKey: "pid") as? pid_t,
                              pid > 0 else { return nil }
                        return pid
                    }
                }
            }
        }

        let pids: [pid_t]? = Thread.isMainThread
            ? collectPIDs()
            : DispatchQueue.main.sync { collectPIDs() }

        guard let pids else { return nil }

        var totalBytes: UInt64 = 0
        var processCount = 0

        for pid in pids {
            guard pid > 0 else { continue }
            let residentSize: UInt64?
            if let memoryProvider {
                residentSize = memoryProvider(pid)
            } else {
                var taskInfo = proc_taskinfo()
                let size = Int32(MemoryLayout<proc_taskinfo>.size)
                let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
                // A reused PID between collectPIDs() and proc_pidinfo() could attribute another
                // process's memory to WebContent, slightly inflating the total. The window is
                // vanishingly small and the over-count is acceptable for telemetry purposes.
                residentSize = result == size ? taskInfo.pti_resident_size : nil
            }

            if let residentSize {
                totalBytes += residentSize
                processCount += 1
            }
        }

        return (totalBytes, processCount)
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

extension MemoryUsageMonitor {
    /// Simulates a memory report for testing purposes (internal users only).
    ///
    /// Sets a simulated memory value that `getCurrentMemoryUsage()` will return instead
    /// of real system memory. Only takes effect for internal users.
    /// Used via the Debug menu to test threshold pixel firing for specific memory values.
    ///
    /// - Parameter physFootprintMB: Memory usage in megabytes to simulate
    func simulateMemoryReport(physFootprintMB: Double) {
        guard internalUserDecider.isInternalUser else { return }
        let physFootprintBytes = UInt64(physFootprintMB * 1_048_576)
        let report = MemoryReport(
            residentBytes: physFootprintBytes,
            physFootprintBytes: physFootprintBytes,
            webContentBytes: nil,
            webContentProcessCount: nil
        )
        simulatedReport = report
        memoryReportSubject.send(report)
    }

    /// Clears any simulated memory report, reverting `getCurrentMemoryUsage()` to real system values.
    func clearSimulatedMemoryReport() {
        simulatedReport = nil
    }
}

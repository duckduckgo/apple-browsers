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

/// A monitor that periodically reports the memory usage of the current process.
final class MemoryUsageMonitor: @unchecked Sendable {

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
        /// Memory used by the process in bytes.
        let usedBytes: UInt64
        /// Memory used by the process in megabytes.
        var usedMB: Double { Double(usedBytes) / Double(Self.oneMB) }
        /// Memory used by the process in gigabytes.
        var usedGB: Double { Double(usedBytes) / Double(Self.oneGB) }

        var usedMemoryString: String {
            if usedBytes > Self.oneGB {
                let formattedValue = Self.gbFormatter.string(from: NSNumber(value: usedGB)) ?? String(usedGB)
                return "\(formattedValue) GB"
            }
            let formattedValue = Self.mbFormatter.string(from: NSNumber(value: usedMB)) ?? String(usedMB)
            return "\(formattedValue) MB"
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

                self.logger?.info("Memory usage: \(report.usedMemoryString)")
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
            logger?.warning("Failed to get memory info: \(result)")
            usedBytes = 0
        }
        return MemoryReport(usedBytes: usedBytes)
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
                label?.stringValue = report.usedMemoryString
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

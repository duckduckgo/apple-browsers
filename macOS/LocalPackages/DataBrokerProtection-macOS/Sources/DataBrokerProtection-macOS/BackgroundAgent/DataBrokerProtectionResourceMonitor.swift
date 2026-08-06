//
//  DataBrokerProtectionResourceMonitor.swift
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
import DataBrokerProtectionCore
import os.log
import WebKit

public struct DataBrokerProtectionResourceSnapshot: Equatable, Sendable {
    public let sampledAt: Date
    public let cpuTime: TimeInterval
    public let agentCPUTime: TimeInterval
    public let webContentCPUTime: TimeInterval
    public let averageCPUPercent: Double
    public let agentPhysicalFootprintBytes: UInt64
    public let peakAgentPhysicalFootprintBytes: UInt64
    public let webContentResidentBytes: UInt64?
    public let peakWebContentResidentBytes: UInt64?
    public let webContentProcessCount: Int?
    public let webContentCPUDiscoveredProcessCount: Int
    public let webContentCPUReadableProcessCount: Int
    public let didEncounterCriticalMemoryPressure: Bool
}

public protocol DataBrokerProtectionResourceMonitoring: AnyObject {
    var debugResourceUsage: DBPDebugResourceUsage { get }

    @MainActor
    func start()

    @MainActor
    func stop()
}

// Every access is serialized by the lock; Sendable allows debug-server reads off the main actor.
private final class ResourceUsageStore: @unchecked Sendable {
    private let lock = NSLock()
    private var resourceUsage = DBPDebugResourceUsage(isMonitoring: false, latestSample: nil)

    func get() -> DBPDebugResourceUsage {
        lock.withLock { resourceUsage }
    }

    func update(isMonitoring: Bool, latestSample: DBPDebugResourceUsage.Sample?) {
        lock.withLock {
            resourceUsage = DBPDebugResourceUsage(isMonitoring: isMonitoring, latestSample: latestSample)
        }
    }
}

private struct ProcessIdentity: Hashable {
    let pid: pid_t
    let startAbsoluteTime: UInt64
}

private struct ProcessCPUUsage {
    let identity: ProcessIdentity
    let cpuTimeNanoseconds: UInt64
}

private struct CPUMeasurement {
    let agentUsage: ProcessCPUUsage?
    let webContentUsages: [ProcessIdentity: ProcessCPUUsage]
    let webContentDiscoveredProcessCount: Int
    let systemUptime: TimeInterval
}

private struct MemoryMeasurement {
    let agentPhysicalFootprintBytes: UInt64
    let webContentResidentBytes: UInt64?
    let webContentProcessCount: Int?
}

/// Monitors one accepted PIR queue run. CPU counters are sampled every 10 seconds and accumulated
/// for the agent and its live WebContent processes; memory is sampled when a snapshot is published.
/// The first snapshot is published after 10 seconds, then every 60 seconds, and once when the run ends.
@MainActor
public final class DataBrokerProtectionResourceMonitor: DataBrokerProtectionResourceMonitoring {

    private enum Constants {
        static let cpuSampleIntervalNanoseconds = UInt64(10) * NSEC_PER_SEC
        static let cpuSamplesPerReport = 6
        static let bytesPerMebibyte = Double(1 << 20)
        static let bytesPerGibibyte = Double(1 << 30)
    }

    public private(set) var latestSnapshot: DataBrokerProtectionResourceSnapshot?
    public private(set) var isMonitoring = false

    public nonisolated var debugResourceUsage: DBPDebugResourceUsage {
        resourceUsageStore.get()
    }

    private nonisolated let resourceUsageStore = ResourceUsageStore()
    private var monitoringTask: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var previousAgentUsage: ProcessCPUUsage?
    // Retaining the last reading across disappearance avoids resetting a temporarily undiscovered process.
    private var previousWebContentUsages: [ProcessIdentity: ProcessCPUUsage] = [:]
    private var accumulatedAgentCPUTimeNanoseconds: UInt64 = 0
    private var accumulatedWebContentCPUTimeNanoseconds: UInt64 = 0
    private var runStartAbsoluteTime: UInt64?
    private var monitoringStartUptime: TimeInterval?
    private var webContentCPUDiscoveredProcessCount = 0
    private var webContentCPUReadableProcessCount = 0
    private var peakAgentPhysicalFootprintBytes: UInt64 = 0
    private var peakWebContentResidentBytes: UInt64?
    private var didEncounterCriticalMemoryPressure = false

    public init() {}

    public func start() {
        guard !isMonitoring else { return }

        resetRunState()
        isMonitoring = true
        resourceUsageStore.update(
            isMonitoring: true,
            latestSample: latestSnapshot.map(DBPDebugResourceUsage.Sample.init)
        )
        startMemoryPressureMonitoring()

        runStartAbsoluteTime = mach_absolute_time()
        let initialCPUMeasurement = collectCPUMeasurement()
        previousAgentUsage = initialCPUMeasurement.agentUsage
        previousWebContentUsages = initialCPUMeasurement.webContentUsages
        monitoringStartUptime = initialCPUMeasurement.systemUptime
        updateCPUProcessCounts(with: initialCPUMeasurement)
        updateMemoryPeaks(with: collectMemoryMeasurement())

        monitoringTask = Task { [weak self] in
            do {
                var cpuSampleIndex = 0
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: Constants.cpuSampleIntervalNanoseconds)
                    try Task.checkCancellation()
                    self?.sampleCPU()
                    if cpuSampleIndex.isMultiple(of: Constants.cpuSamplesPerReport) {
                        self?.publishSnapshot()
                    }
                    cpuSampleIndex += 1
                }
            } catch {
                return
            }
        }
    }

    public func stop() {
        guard isMonitoring else { return }

        sampleCPU()
        publishSnapshot()
        monitoringTask?.cancel()
        monitoringTask = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        isMonitoring = false
        resourceUsageStore.update(
            isMonitoring: false,
            latestSample: latestSnapshot.map(DBPDebugResourceUsage.Sample.init)
        )
    }

    private func resetRunState() {
        previousAgentUsage = nil
        previousWebContentUsages = [:]
        accumulatedAgentCPUTimeNanoseconds = 0
        accumulatedWebContentCPUTimeNanoseconds = 0
        runStartAbsoluteTime = nil
        monitoringStartUptime = nil
        webContentCPUDiscoveredProcessCount = 0
        webContentCPUReadableProcessCount = 0
        peakAgentPhysicalFootprintBytes = 0
        peakWebContentResidentBytes = nil
        didEncounterCriticalMemoryPressure = false
    }

    private func sampleCPU() {
        let measurement = collectCPUMeasurement()
        updateAgentCPUTime(with: measurement.agentUsage)
        updateWebContentCPUTime(with: measurement.webContentUsages)
        updateCPUProcessCounts(with: measurement)
    }

    private func publishSnapshot() {
        let memoryMeasurement = collectMemoryMeasurement()
        updateMemoryPeaks(with: memoryMeasurement)

        let systemUptime = ProcessInfo.processInfo.systemUptime
        let elapsedTime = max(0, systemUptime - (monitoringStartUptime ?? systemUptime))
        let agentCPUTime = TimeInterval(accumulatedAgentCPUTimeNanoseconds) / TimeInterval(NSEC_PER_SEC)
        let webContentCPUTime = TimeInterval(accumulatedWebContentCPUTimeNanoseconds) / TimeInterval(NSEC_PER_SEC)
        let cpuTime = agentCPUTime + webContentCPUTime
        // This is core-equivalent utilization: one fully occupied core is 100%, so totals may exceed 100%.
        let averageCPUPercent = elapsedTime > 0 ? cpuTime / elapsedTime * 100 : 0

        let snapshot = DataBrokerProtectionResourceSnapshot(
            sampledAt: Date(),
            cpuTime: cpuTime,
            agentCPUTime: agentCPUTime,
            webContentCPUTime: webContentCPUTime,
            averageCPUPercent: averageCPUPercent,
            agentPhysicalFootprintBytes: memoryMeasurement.agentPhysicalFootprintBytes,
            peakAgentPhysicalFootprintBytes: peakAgentPhysicalFootprintBytes,
            webContentResidentBytes: memoryMeasurement.webContentResidentBytes,
            peakWebContentResidentBytes: peakWebContentResidentBytes,
            webContentProcessCount: memoryMeasurement.webContentProcessCount,
            webContentCPUDiscoveredProcessCount: webContentCPUDiscoveredProcessCount,
            webContentCPUReadableProcessCount: webContentCPUReadableProcessCount,
            didEncounterCriticalMemoryPressure: didEncounterCriticalMemoryPressure
        )
        latestSnapshot = snapshot
        resourceUsageStore.update(
            isMonitoring: isMonitoring,
            latestSample: DBPDebugResourceUsage.Sample(snapshot)
        )
        log(snapshot)
    }

    private func log(_ snapshot: DataBrokerProtectionResourceSnapshot) {
        let webContentResident = snapshot.webContentResidentBytes.map(Self.formattedMemory) ?? "unavailable"
        let peakWebContentResident = snapshot.peakWebContentResidentBytes.map(Self.formattedMemory) ?? "unavailable"
        let webContentProcessCount = snapshot.webContentProcessCount.map(String.init) ?? "unavailable"
        let fields = [
            "agentCPUTimeSeconds=\(snapshot.agentCPUTime)",
            "webContentCPUTimeSeconds=\(snapshot.webContentCPUTime)",
            "totalCPUTimeSeconds=\(snapshot.cpuTime)",
            "averageCPUPercent=\(snapshot.averageCPUPercent)",
            "agentFootprint=\(Self.formattedMemory(snapshot.agentPhysicalFootprintBytes))",
            "peakAgentFootprint=\(Self.formattedMemory(snapshot.peakAgentPhysicalFootprintBytes))",
            "webContentResident=\(webContentResident)",
            "peakWebContentResident=\(peakWebContentResident)",
            "webContentProcessCount=\(webContentProcessCount)",
            "webContentCPUPIDs=\(snapshot.webContentCPUReadableProcessCount)/"
                + "\(snapshot.webContentCPUDiscoveredProcessCount)",
            "criticalMemoryPressure=\(snapshot.didEncounterCriticalMemoryPressure)"
        ]
        let message = "PIR resource sample: " + fields.joined(separator: ", ")
        Logger.dataBrokerProtection.info("\(message, privacy: .public)")
    }

    private func updateAgentCPUTime(with usage: ProcessCPUUsage?) {
        guard let usage else { return }

        accumulatedAgentCPUTimeNanoseconds += cpuDelta(
            for: usage,
            previousUsage: previousAgentUsage,
            includeLifetimeForNewProcess: false
        )
        previousAgentUsage = usage
    }

    private func updateWebContentCPUTime(with usages: [ProcessIdentity: ProcessCPUUsage]) {
        for (identity, usage) in usages {
            // A process created during this run contributes its lifetime CPU; an older process's first
            // reading is only a baseline. Start time also distinguishes recycled PIDs.
            accumulatedWebContentCPUTimeNanoseconds += cpuDelta(
                for: usage,
                previousUsage: previousWebContentUsages[identity],
                includeLifetimeForNewProcess: identity.startAbsoluteTime >= (runStartAbsoluteTime ?? .max)
            )
            previousWebContentUsages[identity] = usage
        }
    }

    private func cpuDelta(for usage: ProcessCPUUsage,
                          previousUsage: ProcessCPUUsage?,
                          includeLifetimeForNewProcess: Bool) -> UInt64 {
        guard let previousUsage else {
            return includeLifetimeForNewProcess ? usage.cpuTimeNanoseconds : 0
        }
        guard usage.cpuTimeNanoseconds >= previousUsage.cpuTimeNanoseconds else { return 0 }
        return usage.cpuTimeNanoseconds - previousUsage.cpuTimeNanoseconds
    }

    private func updateCPUProcessCounts(with measurement: CPUMeasurement) {
        webContentCPUDiscoveredProcessCount = measurement.webContentDiscoveredProcessCount
        webContentCPUReadableProcessCount = measurement.webContentUsages.count
    }

    private func updateMemoryPeaks(with measurement: MemoryMeasurement) {
        peakAgentPhysicalFootprintBytes = max(
            peakAgentPhysicalFootprintBytes,
            measurement.agentPhysicalFootprintBytes
        )

        if let webContentResidentBytes = measurement.webContentResidentBytes {
            peakWebContentResidentBytes = max(peakWebContentResidentBytes ?? 0, webContentResidentBytes)
        }
    }

    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard source?.data.contains(.critical) == true else { return }
            // Pressure is event-based, so keep it set for the remainder of this run.
            self?.didEncounterCriticalMemoryPressure = true
            self?.sampleCPU()
            self?.publishSnapshot()
        }
        source.resume()
        memoryPressureSource = source
    }

    private func collectCPUMeasurement() -> CPUMeasurement {
        let agentPID = getpid()
        // WebKit only exposes currently live PIDs. A process born and terminated between ticks is unobservable.
        let webContentPIDs = Set(Self.webContentProcessIdentifiers() ?? [])
        let webContentUsages = Dictionary(uniqueKeysWithValues: webContentPIDs.compactMap { pid in
            Self.cpuUsage(for: pid).map { ($0.identity, $0) }
        })

        return CPUMeasurement(
            agentUsage: Self.cpuUsage(for: agentPID),
            webContentUsages: webContentUsages,
            webContentDiscoveredProcessCount: webContentPIDs.count,
            systemUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func collectMemoryMeasurement() -> MemoryMeasurement {
        let webContentPIDs = Self.webContentProcessIdentifiers()
        // AppHealth uses the same split: TASK_VM_INFO physical footprint for this process and
        // PROC_PIDTASKINFO resident size summed across WebContent processes.
        let webContentMemory = webContentPIDs.map { processIdentifiers in
            processIdentifiers.compactMap(Self.residentMemorySize).reduce(0, +)
        }

        return MemoryMeasurement(
            agentPhysicalFootprintBytes: Self.agentPhysicalFootprint(),
            webContentResidentBytes: webContentMemory,
            webContentProcessCount: webContentPIDs?.count
        )
    }

    private static func cpuUsage(for pid: pid_t) -> ProcessCPUUsage? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }

        return ProcessCPUUsage(
            identity: ProcessIdentity(pid: pid, startAbsoluteTime: usage.ri_proc_start_abstime),
            cpuTimeNanoseconds: usage.ri_user_time + usage.ri_system_time
        )
    }

    private static func formattedMemory(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= Constants.bytesPerGibibyte {
            return String(format: "%.2f GiB (%llu bytes)", value / Constants.bytesPerGibibyte, bytes)
        }
        return String(format: "%.1f MiB (%llu bytes)", value / Constants.bytesPerMebibyte, bytes)
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

    private static func webContentProcessIdentifiers() -> [pid_t]? {
        let processInfoSelector = Selector(("_webContentProcessInfo"))
        guard WKProcessPool.responds(to: processInfoSelector) else { return nil }

        let pidSelector = Selector(("pid"))
        return autoreleasepool {
            guard let processInfoList = WKProcessPool.perform(processInfoSelector)?
                .takeUnretainedValue() as? [NSObject] else {
                return nil
            }
            return processInfoList.compactMap { processInfo in
                guard processInfo.responds(to: pidSelector),
                      let pid = processInfo.value(forKey: "pid") as? pid_t,
                      pid > 0 else {
                    return nil
                }
                return pid
            }
        }
    }

    deinit {
        monitoringTask?.cancel()
        memoryPressureSource?.cancel()
    }
}

private extension DBPDebugResourceUsage.Sample {
    init(_ snapshot: DataBrokerProtectionResourceSnapshot) {
        self.init(
            sampledAt: snapshot.sampledAt,
            cpuTimeSeconds: snapshot.cpuTime,
            agentCPUTimeSeconds: snapshot.agentCPUTime,
            webContentCPUTimeSeconds: snapshot.webContentCPUTime,
            averageCPUPercent: snapshot.averageCPUPercent,
            agentPhysicalFootprintBytes: snapshot.agentPhysicalFootprintBytes,
            peakAgentPhysicalFootprintBytes: snapshot.peakAgentPhysicalFootprintBytes,
            webContentResidentBytes: snapshot.webContentResidentBytes,
            peakWebContentResidentBytes: snapshot.peakWebContentResidentBytes,
            webContentProcessCount: snapshot.webContentProcessCount,
            webContentCPUDiscoveredProcessCount: snapshot.webContentCPUDiscoveredProcessCount,
            webContentCPUReadableProcessCount: snapshot.webContentCPUReadableProcessCount,
            didEncounterCriticalMemoryPressure: snapshot.didEncounterCriticalMemoryPressure
        )
    }
}

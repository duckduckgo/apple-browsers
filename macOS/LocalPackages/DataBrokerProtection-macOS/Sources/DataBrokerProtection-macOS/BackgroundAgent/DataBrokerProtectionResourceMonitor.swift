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
    public let averageCPUPercent: Double
    public let agentPhysicalFootprintBytes: UInt64
    public let peakAgentPhysicalFootprintBytes: UInt64
    public let webContentResidentBytes: UInt64?
    public let peakWebContentResidentBytes: UInt64?
    public let webContentProcessCount: Int?
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

private struct ProcessResourceUsage {
    let cpuTimeNanoseconds: UInt64
}

private struct ResourceMeasurement {
    let processUsages: [pid_t: ProcessResourceUsage]
    let agentPhysicalFootprintBytes: UInt64
    let webContentResidentBytes: UInt64?
    let webContentProcessCount: Int?
    let systemUptime: TimeInterval
}

@MainActor
public final class DataBrokerProtectionResourceMonitor: DataBrokerProtectionResourceMonitoring {

    private enum Constants {
        static let initialSampleDelayNanoseconds = UInt64(10) * NSEC_PER_SEC
        static let sampleIntervalNanoseconds = UInt64(60) * NSEC_PER_SEC
    }

    public private(set) var latestSnapshot: DataBrokerProtectionResourceSnapshot?
    public private(set) var isMonitoring = false

    public nonisolated var debugResourceUsage: DBPDebugResourceUsage {
        resourceUsageStore.get()
    }

    private nonisolated let resourceUsageStore = ResourceUsageStore()
    private var monitoringTask: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var previousProcessUsages: [pid_t: ProcessResourceUsage] = [:]
    private var accumulatedCPUTimeNanoseconds: UInt64 = 0
    private var monitoringStartUptime: TimeInterval?
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

        let initialMeasurement = collectMeasurement()
        previousProcessUsages = initialMeasurement.processUsages
        monitoringStartUptime = initialMeasurement.systemUptime
        updateMemoryPeaks(with: initialMeasurement)

        monitoringTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Constants.initialSampleDelayNanoseconds)
                while !Task.isCancelled {
                    self?.sample()
                    try await Task.sleep(nanoseconds: Constants.sampleIntervalNanoseconds)
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    public func stop() {
        guard isMonitoring else { return }

        sample()
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
        previousProcessUsages = [:]
        accumulatedCPUTimeNanoseconds = 0
        monitoringStartUptime = nil
        peakAgentPhysicalFootprintBytes = 0
        peakWebContentResidentBytes = nil
        didEncounterCriticalMemoryPressure = false
    }

    private func sample() {
        let measurement = collectMeasurement()
        updateCPUTime(with: measurement.processUsages)
        updateMemoryPeaks(with: measurement)

        let elapsedTime = max(0, measurement.systemUptime - (monitoringStartUptime ?? measurement.systemUptime))
        let cpuTime = TimeInterval(accumulatedCPUTimeNanoseconds) / TimeInterval(NSEC_PER_SEC)
        let averageCPUPercent = elapsedTime > 0 ? cpuTime / elapsedTime * 100 : 0

        let snapshot = DataBrokerProtectionResourceSnapshot(
            sampledAt: Date(),
            cpuTime: cpuTime,
            averageCPUPercent: averageCPUPercent,
            agentPhysicalFootprintBytes: measurement.agentPhysicalFootprintBytes,
            peakAgentPhysicalFootprintBytes: peakAgentPhysicalFootprintBytes,
            webContentResidentBytes: measurement.webContentResidentBytes,
            peakWebContentResidentBytes: peakWebContentResidentBytes,
            webContentProcessCount: measurement.webContentProcessCount,
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
        let webContentResidentBytes = snapshot.webContentResidentBytes.map(String.init) ?? "unavailable"
        let peakWebContentResidentBytes = snapshot.peakWebContentResidentBytes.map(String.init) ?? "unavailable"
        let webContentProcessCount = snapshot.webContentProcessCount.map(String.init) ?? "unavailable"
        let fields = [
            "cpuTimeSeconds=\(snapshot.cpuTime)",
            "averageCPUPercent=\(snapshot.averageCPUPercent)",
            "agentFootprintBytes=\(snapshot.agentPhysicalFootprintBytes)",
            "peakAgentFootprintBytes=\(snapshot.peakAgentPhysicalFootprintBytes)",
            "webContentResidentBytes=\(webContentResidentBytes)",
            "peakWebContentResidentBytes=\(peakWebContentResidentBytes)",
            "webContentProcessCount=\(webContentProcessCount)",
            "criticalMemoryPressure=\(snapshot.didEncounterCriticalMemoryPressure)"
        ]
        let message = "PIR resource sample: " + fields.joined(separator: ", ")
        Logger.dataBrokerProtection.info("\(message, privacy: .public)")
    }

    private func updateCPUTime(with processUsages: [pid_t: ProcessResourceUsage]) {
        for (pid, usage) in processUsages {
            let previousCPUTime = previousProcessUsages[pid]?.cpuTimeNanoseconds ?? 0
            if usage.cpuTimeNanoseconds >= previousCPUTime {
                accumulatedCPUTimeNanoseconds += usage.cpuTimeNanoseconds - previousCPUTime
            }
        }
        previousProcessUsages = processUsages
    }

    private func updateMemoryPeaks(with measurement: ResourceMeasurement) {
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
            self?.didEncounterCriticalMemoryPressure = true
            self?.sample()
        }
        source.resume()
        memoryPressureSource = source
    }

    private func collectMeasurement() -> ResourceMeasurement {
        let agentPID = getpid()
        let webContentPIDs = Self.webContentProcessIdentifiers()
        let processIdentifiers = Set([agentPID] + (webContentPIDs ?? []))
        let processUsages = Dictionary(uniqueKeysWithValues: processIdentifiers.compactMap { pid in
            Self.resourceUsage(for: pid).map { (pid, $0) }
        })
        let webContentMemory = webContentPIDs.map { processIdentifiers in
            processIdentifiers.compactMap(Self.residentMemorySize).reduce(0, +)
        }

        return ResourceMeasurement(
            processUsages: processUsages,
            agentPhysicalFootprintBytes: Self.agentPhysicalFootprint(),
            webContentResidentBytes: webContentMemory,
            webContentProcessCount: webContentPIDs?.count,
            systemUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private static func resourceUsage(for pid: pid_t) -> ProcessResourceUsage? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }

        return ProcessResourceUsage(
            cpuTimeNanoseconds: usage.ri_user_time + usage.ri_system_time
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
            averageCPUPercent: snapshot.averageCPUPercent,
            agentPhysicalFootprintBytes: snapshot.agentPhysicalFootprintBytes,
            peakAgentPhysicalFootprintBytes: snapshot.peakAgentPhysicalFootprintBytes,
            webContentResidentBytes: snapshot.webContentResidentBytes,
            peakWebContentResidentBytes: snapshot.peakWebContentResidentBytes,
            webContentProcessCount: snapshot.webContentProcessCount,
            didEncounterCriticalMemoryPressure: snapshot.didEncounterCriticalMemoryPressure
        )
    }
}

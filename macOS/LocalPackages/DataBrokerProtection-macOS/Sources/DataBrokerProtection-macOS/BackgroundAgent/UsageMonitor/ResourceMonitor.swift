//
//  ResourceMonitor.swift
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

public protocol ResourceMonitoring: AnyObject {
    var debugResourceUsage: DBPDebugResourceUsage { get }
    func start()
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

/// Monitors one accepted PIR queue run on a dedicated serial queue. CPU is collected every 10 seconds;
/// memory is sampled and snapshots are published after 10 seconds, every 60 seconds, and at run end.
/// Only WebKit PID discovery hops to the main queue because WebKit owns those proxy objects there.
public final class ResourceMonitor: ResourceMonitoring, @unchecked Sendable {

    // MARK: - State

    private enum Constants {
        static let cpuSampleIntervalNanoseconds = UInt64(10) * NSEC_PER_SEC
        static let cpuSamplesPerReport = 6
        static let bytesPerMebibyte = Double(1 << 20)
        static let bytesPerGibibyte = Double(1 << 30)
    }

    // Mutable monitoring state is accessed only on this queue; debug reads use the locked store above.
    private let monitorQueue = DispatchQueue(label: "com.duckduckgo.pir.resource-monitor", qos: .utility)
    // Stores the latest published state for reads that do not run on monitorQueue.
    private let resourceUsageStore = ResourceUsageStore()
    // Drives 10-second CPU accounting while a PIR queue run is active.
    private var monitoringTimer: DispatchSourceTimer?
    // Records critical memory-pressure events for the active run.
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    // The last published snapshot, retained after monitoring stops for debugging.
    private var latestSnapshot: ResourceSnapshot?
    private var isMonitoring = false
    // Counts CPU samples so every sixth 10-second sample publishes a snapshot.
    private var cpuSampleIndex = 0
    private var cpuUsageMonitor = CPUUsageMonitor()
    private var memoryUsageMonitor = MemoryUsageMonitor()

    // MARK: - Public API

    /// A thread-safe view of the monitor state exposed by the debug server.
    public var debugResourceUsage: DBPDebugResourceUsage {
        resourceUsageStore.get()
    }

    public init() {}

    public func start() {
        monitorQueue.async { [weak self] in
            self?.startMonitoring()
        }
    }

    public func stop() {
        monitorQueue.async { [weak self] in
            self?.stopMonitoring()
        }
    }

    deinit {
        monitoringTimer?.cancel()
        memoryPressureSource?.cancel()
    }

    // MARK: - Run Lifecycle

    private func startMonitoring() {
        guard !isMonitoring else { return }

        resetRunState()
        isMonitoring = true
        resourceUsageStore.update(
            isMonitoring: true,
            latestSample: latestSnapshot.map(DBPDebugResourceUsage.Sample.init)
        )
        startMemoryPressureMonitoring()

        let runStartAbsoluteTime = mach_absolute_time()
        cpuUsageMonitor.start(
            webContentPIDs: currentWebContentPIDs(),
            runStartAbsoluteTime: runStartAbsoluteTime
        )
        memoryUsageMonitor.start(webContentPIDs: Self.webContentPIDs())

        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(
            deadline: .now() + .nanoseconds(Int(Constants.cpuSampleIntervalNanoseconds)),
            repeating: .nanoseconds(Int(Constants.cpuSampleIntervalNanoseconds))
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.sampleCPU()
            if self.cpuSampleIndex.isMultiple(of: Constants.cpuSamplesPerReport) {
                self.publishSnapshot()
            }
            self.cpuSampleIndex += 1
        }
        timer.resume()
        monitoringTimer = timer
    }

    private func stopMonitoring() {
        guard isMonitoring else { return }

        sampleCPU()
        publishSnapshot()
        monitoringTimer?.cancel()
        monitoringTimer = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        isMonitoring = false
        resourceUsageStore.update(
            isMonitoring: false,
            latestSample: latestSnapshot.map(DBPDebugResourceUsage.Sample.init)
        )
    }

    private func resetRunState() {
        cpuSampleIndex = 0
        cpuUsageMonitor.reset()
        memoryUsageMonitor.reset()
    }

    // MARK: - Sampling and Publication

    private func sampleCPU() {
        cpuUsageMonitor.recordSample(webContentPIDs: currentWebContentPIDs())
    }

    private func publishSnapshot() {
        let cpuUsage = cpuUsageMonitor.makeReport(at: ProcessInfo.processInfo.systemUptime)
        let memoryUsage = memoryUsageMonitor.makeReport(
            webContentPIDs: Self.webContentPIDs()
        )
        let snapshot = ResourceSnapshot(
            sampledAt: Date(),
            cpu: cpuUsage,
            memory: memoryUsage
        )
        latestSnapshot = snapshot
        resourceUsageStore.update(
            isMonitoring: isMonitoring,
            latestSample: DBPDebugResourceUsage.Sample(snapshot)
        )
        log(snapshot)
    }

    // MARK: - Logging

    private func log(_ snapshot: ResourceSnapshot) {
        let webContentResident = snapshot.memory.webContent.residentBytes.map(Self.formattedMemory) ?? "unavailable"
        let peakWebContentResident = snapshot.memory.webContent.peakResidentBytes
            .map(Self.formattedMemory) ?? "unavailable"
        let webContentCount = snapshot.memory.webContent.processCount.map(String.init) ?? "unavailable"
        let fields = [
            "agentCPUTimeSeconds=\(snapshot.cpu.agentTime)",
            "webContentCPUTimeSeconds=\(snapshot.cpu.webContentTime)",
            "totalCPUTimeSeconds=\(snapshot.cpu.totalTime)",
            "averageCPUPercent=\(snapshot.cpu.averagePercent)",
            "agentFootprint=\(Self.formattedMemory(snapshot.memory.agent.footprintBytes))",
            "peakAgentFootprint=\(Self.formattedMemory(snapshot.memory.agent.peakFootprintBytes))",
            "webContentResident=\(webContentResident)",
            "peakWebContentResident=\(peakWebContentResident)",
            "webContentProcessCount=\(webContentCount)",
            "webContentCPUPIDs=\(snapshot.cpu.coverage.readableCount)/"
                + "\(snapshot.cpu.coverage.discoveredCount)",
            "criticalMemoryPressure=\(snapshot.memory.hadCriticalPressure)"
        ]
        let message = "PIR resource sample: " + fields.joined(separator: ", ")
        Logger.dataBrokerProtection.info("\(message, privacy: .public)")
    }

    private static func formattedMemory(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= Constants.bytesPerGibibyte {
            return String(format: "%.2f GiB (%llu bytes)", value / Constants.bytesPerGibibyte, bytes)
        }
        return String(format: "%.1f MiB (%llu bytes)", value / Constants.bytesPerMebibyte, bytes)
    }

    // MARK: - Memory Pressure

    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: monitorQueue)
        source.setEventHandler { [weak self, weak source] in
            guard source?.data.contains(.critical) == true else { return }
            // Pressure is event-based, so keep it set for the remainder of this run.
            self?.memoryUsageMonitor.recordCriticalPressure()
            self?.sampleCPU()
            self?.publishSnapshot()
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: - WebContent Process Discovery

    private func currentWebContentPIDs() -> Set<pid_t> {
        // WebKit only exposes currently live PIDs. A process born and terminated between ticks is unobservable.
        return Set(Self.webContentPIDs() ?? [])
    }

    private static func webContentPIDs() -> [pid_t]? {
        let processInfoSelector = Selector(("_webContentProcessInfo"))
        let pidSelector = Selector(("pid"))
        let collectPIDs: () -> [pid_t]? = {
            autoreleasepool {
                guard WKProcessPool.responds(to: processInfoSelector) else { return nil }
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

        // WebKit owns these unretained proxy objects on the main thread. The monitor queue is never
        // synchronously awaited, so this main-queue hop cannot form a queue-to-main deadlock.
        return Thread.isMainThread
            ? collectPIDs()
            : DispatchQueue.main.sync(execute: collectPIDs)
    }
}

// MARK: - Debug API Mapping

private extension DBPDebugResourceUsage.Sample {
    init(_ snapshot: ResourceSnapshot) {
        self.init(
            sampledAt: snapshot.sampledAt,
            cpuTimeSeconds: snapshot.cpu.totalTime,
            agentCPUTimeSeconds: snapshot.cpu.agentTime,
            webContentCPUTimeSeconds: snapshot.cpu.webContentTime,
            averageCPUPercent: snapshot.cpu.averagePercent,
            agentPhysicalFootprintBytes: snapshot.memory.agent.footprintBytes,
            peakAgentPhysicalFootprintBytes: snapshot.memory.agent.peakFootprintBytes,
            webContentResidentBytes: snapshot.memory.webContent.residentBytes,
            peakWebContentResidentBytes: snapshot.memory.webContent.peakResidentBytes,
            webContentProcessCount: snapshot.memory.webContent.processCount,
            webContentCPUDiscoveredProcessCount: snapshot.cpu.coverage.discoveredCount,
            webContentCPUReadableProcessCount: snapshot.cpu.coverage.readableCount,
            didEncounterCriticalMemoryPressure: snapshot.memory.hadCriticalPressure
        )
    }
}

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
import os.log

public protocol ResourceMonitoring: AnyObject {
    func start()
    func stop()
}

/// Monitors resource usage for one accepted PIR queue run.
///
/// This monitors the background agent plus its web processes, not the whole machine.
///
/// CPU is read from cumulative process-lifetime counters at the run boundaries and every 10 seconds, then converted to
/// within-run deltas. Average CPU is total agent + web-process CPU time divided by elapsed time, so it is core-equivalent
/// utilization: one fully occupied core is 100% and concurrent work can exceed 100%.
///
/// Memory is physical footprint, sampled at the run start, after 10 seconds, every 60 seconds thereafter, on critical
/// memory pressure, and at the run end. The monitor logs these snapshots and emits bucketed pixels for the run summary,
/// plus a pixel if macOS reports critical memory pressure.
public final class ResourceMonitor: ResourceMonitoring, @unchecked Sendable {

    // MARK: - Run State

    private struct ActiveRun {
        var cpu: CPUUsageMonitor
        var memory: MemoryUsageMonitor
        var cpuSamplesUntilNextReport: Int
        let timer: DispatchSourceTimer
        let memoryPressureSource: DispatchSourceMemoryPressure
        let isOnBattery: Bool?
    }

    // MARK: - Dependencies and State

    private struct Constants {
        static let cpuSampleInterval: TimeInterval = .seconds(10)
        static let cpuSamplesPerReport = 6
        static let bytesPerMebibyte = Double(1 << 20)
        static let bytesPerGibibyte = Double(1 << 30)
    }

    // Mutable monitoring state is accessed only on this queue.
    private let monitorQueue = DispatchQueue(label: "com.duckduckgo.pir.resource-monitor", qos: .utility)

    private let webProcessIDProvider = WebProcessIDProvider()
    private let powerSourceProvider = PowerSourceProvider()
    private let pixelReporter = ResourceUsagePixelReporter()
    private var activeRun: ActiveRun?

    // MARK: - Public API

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
        activeRun?.timer.cancel()
        activeRun?.memoryPressureSource.cancel()
    }

    // MARK: - Run Lifecycle

    private func startMonitoring() {
        guard activeRun == nil else { return }

        let runStartAbsoluteTime = mach_absolute_time()
        let webProcessPIDs = webProcessIDProvider.currentProcessIDs()
        let cpu = CPUUsageMonitor(
            webProcessPIDs: webProcessPIDs ?? [],
            runStartAbsoluteTime: runStartAbsoluteTime
        )
        let memory = MemoryUsageMonitor(webProcessPIDs: webProcessPIDs)

        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        let memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: .critical,
            queue: monitorQueue
        )
        let sampleInterval = DispatchTimeInterval.nanoseconds(
            Int(Constants.cpuSampleInterval * Double(NSEC_PER_SEC))
        )
        timer.schedule(
            deadline: .now() + sampleInterval,
            repeating: sampleInterval
        )
        timer.setEventHandler { [weak self] in
            self?.handleTimerEvent()
        }
        memoryPressureSource.setEventHandler { [weak self, weak memoryPressureSource] in
            guard let self, memoryPressureSource?.data.contains(.critical) == true else { return }
            if self.activeRun?.memory.recordCriticalPressure() == true {
                self.pixelReporter.reportCriticalMemoryPressure()
            }
            self.recordResourcesAndPublishSnapshot()
        }
        activeRun = ActiveRun(
            cpu: cpu,
            memory: memory,
            cpuSamplesUntilNextReport: 1,
            timer: timer,
            memoryPressureSource: memoryPressureSource,
            isOnBattery: powerSourceProvider.isOnBattery()
        )
        timer.resume()
        memoryPressureSource.resume()
    }

    private func stopMonitoring() {
        guard let currentRun = activeRun else { return }

        if let snapshot = recordResourcesAndPublishSnapshot() {
            pixelReporter.reportRun(
                snapshot,
                isOnBattery: currentRun.isOnBattery,
                thermalState: ProcessInfo.processInfo.thermalState
            )
        }
        activeRun?.timer.cancel()
        activeRun?.memoryPressureSource.cancel()
        activeRun = nil
    }

    // MARK: - Sampling and Publication

    private func handleTimerEvent() {
        let webProcessPIDs = webProcessIDProvider.currentProcessIDs()
        activeRun?.cpu.recordSample(webProcessPIDs: webProcessPIDs ?? [])
        activeRun?.cpuSamplesUntilNextReport -= 1

        guard activeRun?.cpuSamplesUntilNextReport == 0 else { return }

        activeRun?.cpuSamplesUntilNextReport = Constants.cpuSamplesPerReport
        activeRun?.memory.recordSample(webProcessPIDs: webProcessPIDs)
        makeAndLogSnapshot()
    }

    @discardableResult
    private func recordResourcesAndPublishSnapshot() -> ResourceSnapshot? {
        let webProcessPIDs = webProcessIDProvider.currentProcessIDs()
        activeRun?.cpu.recordSample(webProcessPIDs: webProcessPIDs ?? [])
        activeRun?.memory.recordSample(webProcessPIDs: webProcessPIDs)
        return makeAndLogSnapshot()
    }
}

// MARK: - Snapshot & Logging

private extension ResourceMonitor {
    @discardableResult
    private func makeAndLogSnapshot() -> ResourceSnapshot? {
        guard let activeRun else { return nil }

        let snapshot = ResourceSnapshot(
            cpu: activeRun.cpu.makeReport(),
            memory: activeRun.memory.makeReport()
        )
        log(snapshot)
        return snapshot
    }

    private func log(_ snapshot: ResourceSnapshot) {
        let webProcessesFootprint = snapshot.memory.webProcesses.footprintBytes
            .map(Self.formattedMemory) ?? "unavailable"
        let peakWebProcessesFootprint = snapshot.memory.webProcesses.peakFootprintBytes
            .map(Self.formattedMemory) ?? "unavailable"
        let webProcessCount = snapshot.memory.webProcesses.processCount.map(String.init) ?? "unavailable"
        let message = """
        PIR run resources: elapsed=\(Self.formattedDuration(snapshot.cpu.elapsedTime)) | \
        CPU during run: agent=\(Self.formattedCPUTime(snapshot.cpu.agentTime)), \
        web processes=\(Self.formattedCPUTime(snapshot.cpu.webProcessesTime)), \
        total=\(Self.formattedCPUTime(snapshot.cpu.totalTime)), \
        average=\(String(format: "%.1f", snapshot.cpu.averagePercent))% of one core | \
        Physical memory: agent current=\(Self.formattedMemory(snapshot.memory.agent.footprintBytes)), \
        peak=\(Self.formattedMemory(snapshot.memory.agent.peakFootprintBytes)); \
        web processes current=\(webProcessesFootprint), count=\(webProcessCount), \
        peak=\(peakWebProcessesFootprint) | \
        Critical memory pressure during run=\(snapshot.memory.hadCriticalPressure)
        """
        Logger.dataBrokerProtection.info("\(message, privacy: .public)")
    }

    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }

    private static func formattedCPUTime(_ seconds: TimeInterval) -> String {
        String(format: "%.3fs", seconds)
    }

    private static func formattedMemory(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= Constants.bytesPerGibibyte {
            return String(format: "%.2f GiB", value / Constants.bytesPerGibibyte)
        }
        return String(format: "%.1f MiB", value / Constants.bytesPerMebibyte)
    }
}

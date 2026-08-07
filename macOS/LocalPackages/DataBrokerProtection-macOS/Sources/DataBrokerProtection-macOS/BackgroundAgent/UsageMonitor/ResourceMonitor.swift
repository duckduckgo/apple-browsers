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

public protocol ResourceMonitoring: AnyObject {
    var debugResourceUsage: DBPDebugResourceUsage { get }
    func start()
    func stop()
}

/// Monitors resource usage for one accepted PIR queue run.
///
/// Reports include:
/// - CPU: cumulative agent and WebContent time, plus average core-equivalent utilization; for example,
///   `agent: 3.2s`, `WebContent: 7.1s`, and `average: 1.7%`.
/// - Memory: current and peak physical footprints for the agent and summed WebContent processes; for example,
///   `agent: 120/150 MiB` and `WebContent: 2.1/2.8 GiB` for current/peak usage.
/// - WebContent: current process count; for example, `18` processes.
/// - Pressure: whether critical memory pressure occurred during the run; for example, `true` after one event.
/// - Pixels: a bucketed summary when the run ends, CPU thresholds as they are crossed, and critical pressure.
public final class ResourceMonitor: ResourceMonitoring, @unchecked Sendable {

    // MARK: - Run State

    private struct ActiveRun {
        var cpu: CPUUsageMonitor
        var memory: MemoryUsageMonitor
        var cpuSamplesUntilNextReport: Int
        let timer: DispatchSourceTimer
        let memoryPressureSource: DispatchSourceMemoryPressure
    }

    // MARK: - Dependencies and State

    private struct Constants {
        static let cpuSampleInterval: TimeInterval = .seconds(10)
        static let cpuSamplesPerReport = 6
        static let bytesPerMebibyte = Double(1 << 20)
        static let bytesPerGibibyte = Double(1 << 30)
    }

    // Mutable monitoring state is accessed only on this queue; debug reads use the locked store below.
    private let monitorQueue = DispatchQueue(label: "com.duckduckgo.pir.resource-monitor", qos: .utility)
    // Stores the latest published state for reads that do not run on monitorQueue.
    private let resourceUsageStore = ResourceUsageStore()

    private let webContentProcessIDProvider = WebContentProcessIDProvider()
    private let pixelReporter: ResourceUsagePixelReporting
    private var activeRun: ActiveRun?

    // MARK: - Public API

    /// A thread-safe view of the monitor state exposed by the debug server.
    public var debugResourceUsage: DBPDebugResourceUsage {
        resourceUsageStore.get()
    }

    public init() {
        pixelReporter = ResourceUsagePixelReporter()
    }

    init(pixelReporter: ResourceUsagePixelReporting) {
        self.pixelReporter = pixelReporter
    }

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
        let webContentPIDs = webContentProcessIDProvider.currentProcessIDs()
        var cpu = CPUUsageMonitor()
        cpu.start(
            webContentPIDs: Set(webContentPIDs ?? []),
            runStartAbsoluteTime: runStartAbsoluteTime
        )
        var memory = MemoryUsageMonitor()
        memory.start(webContentPIDs: webContentPIDs)
        pixelReporter.start()

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
            memoryPressureSource: memoryPressureSource
        )
        resourceUsageStore.setMonitoring(true)
        timer.resume()
        memoryPressureSource.resume()
    }

    private func stopMonitoring() {
        guard activeRun != nil else { return }

        if let snapshot = recordResourcesAndPublishSnapshot() {
            pixelReporter.reportCPUTime(snapshot.cpu.totalTime)
            pixelReporter.reportRun(snapshot)
        }
        activeRun?.timer.cancel()
        activeRun?.memoryPressureSource.cancel()
        activeRun = nil
        resourceUsageStore.setMonitoring(false)
    }

    // MARK: - Sampling and Publication

    private func handleTimerEvent() {
        let webContentPIDs = webContentProcessIDProvider.currentProcessIDs()
        activeRun?.cpu.recordSample(webContentPIDs: Set(webContentPIDs ?? []))
        if let cpuTime = activeRun?.cpu.makeReport().totalTime {
            pixelReporter.reportCPUTime(cpuTime)
        }
        activeRun?.cpuSamplesUntilNextReport -= 1

        guard activeRun?.cpuSamplesUntilNextReport == 0 else { return }

        activeRun?.cpuSamplesUntilNextReport = Constants.cpuSamplesPerReport
        activeRun?.memory.recordSample(webContentPIDs: webContentPIDs)
        publishDebugSnapshot()
    }

    @discardableResult
    private func recordResourcesAndPublishSnapshot() -> ResourceSnapshot? {
        let webContentPIDs = webContentProcessIDProvider.currentProcessIDs()
        activeRun?.cpu.recordSample(webContentPIDs: Set(webContentPIDs ?? []))
        activeRun?.memory.recordSample(webContentPIDs: webContentPIDs)
        return publishDebugSnapshot()
    }
}

// MARK: - Debugging & logging

private extension ResourceMonitor {
    @discardableResult
    private func publishDebugSnapshot() -> ResourceSnapshot? {
        guard let activeRun else { return nil }

        let snapshot = ResourceSnapshot(
            reportedAt: Date(),
            cpu: activeRun.cpu.makeReport(),
            memory: activeRun.memory.makeReport()
        )
        resourceUsageStore.publish(DBPDebugResourceUsage.Sample(snapshot))
        log(snapshot)
        return snapshot
    }

    private func log(_ snapshot: ResourceSnapshot) {
        let webContentFootprint = snapshot.memory.webContent.footprintBytes.map(Self.formattedMemory) ?? "unavailable"
        let peakWebContentFootprint = snapshot.memory.webContent.peakFootprintBytes
            .map(Self.formattedMemory) ?? "unavailable"
        let webContentCount = snapshot.memory.webContent.processCount.map(String.init) ?? "unavailable"
        let fields = [
            "agentCPUTimeSeconds=\(snapshot.cpu.agentTime)",
            "webContentCPUTimeSeconds=\(snapshot.cpu.webContentTime)",
            "totalCPUTimeSeconds=\(snapshot.cpu.totalTime)",
            "averageCPUPercent=\(snapshot.cpu.averagePercent)",
            "agentFootprint=\(Self.formattedMemory(snapshot.memory.agent.footprintBytes))",
            "peakAgentFootprint=\(Self.formattedMemory(snapshot.memory.agent.peakFootprintBytes))",
            "webContentFootprint=\(webContentFootprint)",
            "peakWebContentFootprint=\(peakWebContentFootprint)",
            "webContentProcessCount=\(webContentCount)",
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
}

private extension DBPDebugResourceUsage.Sample {
    init(_ snapshot: ResourceSnapshot) {
        self.init(
            reportedAt: snapshot.reportedAt,
            cpu: .init(
                totalTimeSeconds: snapshot.cpu.totalTime,
                agentTimeSeconds: snapshot.cpu.agentTime,
                webContentTimeSeconds: snapshot.cpu.webContentTime,
                averagePercent: snapshot.cpu.averagePercent
            ),
            memory: .init(
                agent: .init(
                    footprintBytes: snapshot.memory.agent.footprintBytes,
                    peakFootprintBytes: snapshot.memory.agent.peakFootprintBytes
                ),
                webContent: .init(
                    footprintBytes: snapshot.memory.webContent.footprintBytes,
                    peakFootprintBytes: snapshot.memory.webContent.peakFootprintBytes,
                    processCount: snapshot.memory.webContent.processCount
                ),
                hadCriticalPressure: snapshot.memory.hadCriticalPressure
            )
        )
    }
}

// MARK: - Private

// Every access is serialized by the lock; Sendable allows debug-server reads off the main actor.
private final class ResourceUsageStore: @unchecked Sendable {
    private let lock = NSLock()
    private var resourceUsage = DBPDebugResourceUsage(isMonitoring: false, latestSample: nil)

    func get() -> DBPDebugResourceUsage {
        lock.withLock { resourceUsage }
    }

    func setMonitoring(_ isMonitoring: Bool) {
        lock.withLock {
            resourceUsage = DBPDebugResourceUsage(
                isMonitoring: isMonitoring,
                latestSample: resourceUsage.latestSample
            )
        }
    }

    func publish(_ sample: DBPDebugResourceUsage.Sample) {
        lock.withLock {
            resourceUsage = DBPDebugResourceUsage(
                isMonitoring: resourceUsage.isMonitoring,
                latestSample: sample
            )
        }
    }
}

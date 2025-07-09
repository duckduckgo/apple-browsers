//
//  Watchdog.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

/// A watchdog that monitors the main thread for hangs and crashes the app to generate stack traces
public final class Watchdog {
    private let monitor: WatchdogMonitor
    private let timeout: TimeInterval
    private let checkInterval: TimeInterval
    private let logger = Logger(subsystem: "com.duckduckgo.watchdog", category: "hang-detection")

    private var monitoringTask: Task<Void, Never>?

    @MainActor
    public var isRunning: Bool {
        guard let task = monitoringTask else { return false }
        return !task.isCancelled
    }

    @MainActor
    public init(timeout: TimeInterval = 10.0, checkInterval: TimeInterval = 2.0) {
        self.timeout = timeout
        self.checkInterval = checkInterval
        self.monitor = WatchdogMonitor()
    }

    deinit {
        monitoringTask?.cancel()
    }

    @MainActor
    public func start() {
        // Cancel any existing task
        monitoringTask?.cancel()

        logger.info("Watchdog started monitoring main thread with timeout: \(self.timeout)s")

        monitoringTask = Task {
            await startMonitoring()
        }
    }

    @MainActor
    public func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil

        logger.info("Watchdog stopped monitoring")
    }

    private func startMonitoring() async {
        await monitor.resetHeartbeat()

        while !Task.isCancelled {
            // Schedule heartbeat update on main thread (key: this might not execute if main thread is hung)
            Task { @MainActor in
                await self.monitor.updateHeartbeat()
            }

            // Sleep for check interval
            do {
                let nanoseconds = UInt64(checkInterval * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                // Task was cancelled
                break
            }

            // Check if the heartbeat was actually updated
            let timeSinceLastCheck = await monitor.timeSinceLastHeartbeat()

            if timeSinceLastCheck > timeout {
                logger.critical("Main thread hang detected! Last heartbeat: \(timeSinceLastCheck)s ago (timeout: \(self.timeout)s)")

                // Give main thread one more chance
                let finalCheckSucceeded = await performFinalResponsivenessCheck()

                if finalCheckSucceeded {
                    logger.warning("Main thread responded to final check. Continuing monitoring.")
                    await monitor.updateHeartbeat()
                } else {
                    logger.critical("Main thread is completely unresponsive. Crashing app to generate stack trace.")
                    killApp()
                }
            }
        }
    }

    private func performFinalResponsivenessCheck() async -> Bool {
        let finalCheckTime: TimeInterval = 2.0

        return await withTaskGroup(of: Bool.self) { group in
            // Task 1: Try to execute on main thread
            group.addTask { @MainActor in
                return true
            }

            // Task 2: Timeout after finalCheckTime
            group.addTask {
                do {
                    let nanoseconds = UInt64(finalCheckTime * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    return false
                } catch {
                    // Task was cancelled, main thread responded
                    return true
                }
            }

            // Return the result of whichever task completes first
            let result = await group.next() ?? true
            group.cancelAll()
            return result
        }
    }

    private func killApp() {
        // Log before crashing to help with debugging
        logger.critical("Watchdog is terminating the app due to main thread hang")

        // Use fatalError to generate crash report with stack trace
        fatalError("Main thread hang detected by Watchdog (timeout: \(timeout)s). This crash is intentional to provide debugging information.")
    }
}

/// Actor that manages the heartbeat timestamp in a thread-safe way
private actor WatchdogMonitor {
    private var lastHeartbeat = Date()

    func resetHeartbeat() {
        lastHeartbeat = Date()
    }

    func updateHeartbeat() {
        lastHeartbeat = Date()
    }

    func timeSinceLastHeartbeat() -> TimeInterval {
        Date().timeIntervalSince(lastHeartbeat)
    }
}

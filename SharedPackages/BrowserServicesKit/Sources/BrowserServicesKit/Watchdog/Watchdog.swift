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

/// The current state of the main thread.
private enum HangState {
    case responsive
    case hanging
    case timeout
}

/// A watchdog that monitors the main thread for hangs. Hangs of at least one second will be reported via a pixel.
///
public final class Watchdog {
    private let monitor: WatchdogMonitor

    private let minimumHangDuration: TimeInterval
    private let maximumHangDuration: TimeInterval
    private let checkInterval: TimeInterval

    private static var logger = { Logger(subsystem: "com.duckduckgo.watchdog", category: "hang-detection") }()

    private var monitoringTask: Task<Void, Never>?
    private var heartbeatUpdateTask: Task<Void, Never>?

    private var hangState: HangState = .responsive
    private var hangStartTime: Date?

    // Used for debugging purposes, toggled via debug menu option
    public var crashOnTimeout: Bool = false

    @MainActor
    public var isRunning: Bool {
        guard let task = monitoringTask else { return false }
        return !task.isCancelled
    }

    /// - Parameters:
    ///   - minimumHangDuration: The minimum duration of hang to be detected.
    ///   - maximumHangDuration: The maximum duration of hang to be detected. After this point, the hang will stop being measured
    ///                          and will be reported as a timeout.
    ///   - checkInterval: The interval at which the main thread is checked for hangs.
    @MainActor
    public init(minimumHangDuration: TimeInterval = 1.0, maximumHangDuration: TimeInterval = 10.0, checkInterval: TimeInterval = 0.25) {
        assert(checkInterval > 0, "checkInterval must be greater than 0")
        assert(minimumHangDuration >= 0, "minimumHangDuration must be greater than or equal to 0")
        assert(maximumHangDuration >= 0, "maximumHangDuration must be greater than or equal to 0")
        assert(minimumHangDuration <= maximumHangDuration, "minimumHangDuration must be less than maximumHangDuration")

        self.minimumHangDuration = minimumHangDuration
        self.maximumHangDuration = maximumHangDuration
        self.checkInterval = checkInterval

        self.monitor = WatchdogMonitor()
    }

    deinit {
        monitoringTask?.cancel()
        heartbeatUpdateTask?.cancel()
    }

    @MainActor
    public func start() {
        // Cancel any existing task
        monitoringTask?.cancel()
        heartbeatUpdateTask?.cancel()

        Self.logger.info("Watchdog started monitoring main thread with timeout: \(self.maximumHangDuration)s")

        monitoringTask = Task.detached { [weak self] in
            await self?.startMonitoring()
        }
    }

    @MainActor
    public func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil

        heartbeatUpdateTask?.cancel()
        heartbeatUpdateTask = nil

        Self.logger.info("Watchdog stopped monitoring")
    }

    private func startMonitoring() async {
        await monitor.resetHeartbeat()

        while !Task.isCancelled {
            heartbeatUpdateTask?.cancel()

            // Schedule heartbeat update on main thread (key: this might not execute if main thread is hung)
            heartbeatUpdateTask = Task { @MainActor [weak self] in
                await self?.monitor.updateHeartbeat()

                self?.heartbeatUpdateTask = nil
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
            handleHangDetection(timeSinceLastCheck: timeSinceLastCheck)
        }
    }

    private func handleHangDetection(timeSinceLastCheck: TimeInterval) {
        let now = Date()

        switch hangState {
        case .responsive:
            if timeSinceLastCheck > minimumHangDuration {
                // Start of hang detected
                hangState = .hanging
                hangStartTime = now.addingTimeInterval(-timeSinceLastCheck)
                Self.logger.info("Main thread hang detected! Last heartbeat: \(timeSinceLastCheck)s ago.")
            }
        case .hanging:
            if timeSinceLastCheck <= minimumHangDuration {
                // Hang ended
                logHangDuration(message: "Main thread hang ended.", currentTime: now)

                hangState = .responsive
                hangStartTime = nil
            } else if timeSinceLastCheck > maximumHangDuration {
                hangState = .timeout
                logHangDuration(message: "Main thread hang timeout reached.", currentTime: now)
            } else {
                // Still hanging
                logHangDuration(message: "Ongoing main thread hang.", currentTime: now)
            }
        case .timeout:
            if timeSinceLastCheck <= minimumHangDuration {
                // Hang became responsive again after timeout. Reset hang state.
                hangState = .responsive
                hangStartTime = nil
                logHangDuration(message: "Main thread hang ended after timeout.", currentTime: now)
            } else if timeSinceLastCheck > maximumHangDuration && crashOnTimeout {
                killApp()
            }
        }
    }

    private func logHangDuration(message: String, currentTime: Date) {
        guard let hangStartTime else { return }

        let hangDuration = currentTime.timeIntervalSince(hangStartTime)
        Self.logger.info("\(message) Duration: \(self.formattedHangDuration(duration: hangDuration))s")
    }

    private func killApp() {
        // Log before crashing to help with debugging
        Self.logger.critical("Watchdog is terminating the app due to main thread hang")

        // Use fatalError to generate crash report with stack trace`
        fatalError("Main thread hang detected by Watchdog (timeout: \(maximumHangDuration)s). This crash is intentional to provide debugging information.")
    }

    private func formattedHangDuration(duration: TimeInterval) -> String {
        return String(format: "%.1f", duration)
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

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

import Combine
import Common
import Foundation
import os.log

/// A watchdog that monitors the main thread for hangs. Hangs of at least one second will be reported via a pixel.
///
public final actor Watchdog {
    /// The current state of the main thread.
    public enum HangState {
        case responsive
        case hanging
        case timeout
    }

    /// Events for use with an EventMapper.
    ///
    public enum Event {
        /// A 'not recovered' hang is one that is still ongoing at the time of reporting.
        case uiHangNotRecovered(durationSeconds: Int)
        /// A recovered hang is one that has ended by the time we report it.
        case uiHangRecovered(durationSeconds: Int)
    }

    private let monitor: WatchdogMonitor
    private let eventMapper: EventMapping<Watchdog.Event>?

    private let minimumHangDuration: TimeInterval
    private let maximumHangDuration: TimeInterval
    private let checkInterval: TimeInterval

    private static var logger = { Logger(subsystem: "com.duckduckgo.watchdog", category: "hang-detection") }()

    private var killAppFunction: ((TimeInterval) -> Void)?

    private var monitoringTask: Task<Void, Never>?
    private var heartbeatUpdateTask: Task<Void, Never>?

    private var hangStartTime: Date?
    private var hangState: HangState = .responsive {
        didSet {
            if hangState != oldValue {
                let duration = hangStartTime.map { Date().timeIntervalSince($0) }
                hangStateSubject.send((hangState, duration))
            }
        }
    }

    // Publisher for state changes – used for testing only
    private let hangStateSubject = PassthroughSubject<(HangState, TimeInterval?), Never>() // (state, duration)
    internal var hangStatePublisher: AnyPublisher<(HangState, TimeInterval?), Never> {
        hangStateSubject.eraseToAnyPublisher()
    }

    // Used for debugging purposes, toggled via debug menu option
    public private(set) var crashOnTimeout: Bool = false

    public func setCrashOnTimeout(_ state: Bool) async {
        crashOnTimeout = state
    }

    @MainActor
    public private(set) var isRunning: Bool = false

    @MainActor
    private func setIsRunning(_ state: Bool) {
        isRunning = state
    }

    /// - Parameters:
    ///   - minimumHangDuration: The minimum duration of hang to be detected.
    ///   - maximumHangDuration: The maximum duration of hang to be detected. After this point, the hang will stop being measured
    ///                          and will be reported as a timeout.
    ///   - checkInterval: The interval at which the main thread is checked for hangs.
    ///   - eventMapper: An event mapper that can map between watchdog events and pixels.
    ///   - crashOnTimeout: Whether the watchdog should kill the app once the maximum hang duration has been reached (used for debugging purposes)
    ///   - killAppFunction: A closure to be executed when the maximum hang duration has been reached (used for testing purposes)
    ///
    public init(minimumHangDuration: TimeInterval = 1.0, maximumHangDuration: TimeInterval = 5.0, checkInterval: TimeInterval = 0.5, eventMapper: EventMapping<Watchdog.Event>? = nil, crashOnTimeout: Bool = false, killAppFunction: ((TimeInterval) -> Void)? = nil) {

        assert(checkInterval > 0, "checkInterval must be greater than 0")
        assert(minimumHangDuration >= 0, "minimumHangDuration must be greater than or equal to 0")
        assert(maximumHangDuration >= 0, "maximumHangDuration must be greater than or equal to 0")
        assert(minimumHangDuration <= maximumHangDuration, "minimumHangDuration must be less than maximumHangDuration")

        self.minimumHangDuration = minimumHangDuration
        self.maximumHangDuration = maximumHangDuration
        self.checkInterval = checkInterval
        self.eventMapper = eventMapper
        self.crashOnTimeout = crashOnTimeout
        self.killAppFunction = killAppFunction

        self.monitor = WatchdogMonitor()
    }

    deinit {
        monitoringTask?.cancel()
        heartbeatUpdateTask?.cancel()

        monitoringTask = nil
        heartbeatUpdateTask = nil
    }

    public func start() async {
        // Cancel any existing task
        monitoringTask?.cancel()
        heartbeatUpdateTask?.cancel()

        Self.logger.info("Watchdog started monitoring main thread with timeout: \(self.maximumHangDuration)s")

        monitoringTask = Task.detached { [weak self] in
            await self?.runMonitoringLoop()
        }

        await setIsRunning(true)
    }

    public func stop() async {
        monitoringTask?.cancel()
        monitoringTask = nil

        heartbeatUpdateTask?.cancel()
        heartbeatUpdateTask = nil

        Self.logger.info("Watchdog stopped monitoring")

        await setIsRunning(false)
    }

    private func runMonitoringLoop() async {
        await monitor.resetHeartbeat()

        while !Task.isCancelled {
            heartbeatUpdateTask?.cancel()

            // Schedule heartbeat update on main thread (key: this might not execute if main thread is hung)
            heartbeatUpdateTask = Task { @MainActor [weak self] in
                await self?.monitor.updateHeartbeat()
                await self?.clearHeartbeatTask()
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
    private func clearHeartbeatTask() {
        heartbeatUpdateTask = nil
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
                fireHangEvent(Watchdog.Event.uiHangRecovered, currentTime: now)

                hangState = .responsive
                hangStartTime = nil
            } else if timeSinceLastCheck > maximumHangDuration {
                hangState = .timeout

                logHangDuration(message: "Main thread hang timeout reached.", currentTime: now)
                fireHangEvent(Watchdog.Event.uiHangNotRecovered, currentTime: now)
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
                logHangDuration(message: "Main thread hang timeout reached. Crashing app.", currentTime: now)
                killAppFunction?(maximumHangDuration) ?? killApp(timeout: maximumHangDuration)
            }
        }
    }

    private func killApp(timeout: TimeInterval) {
        // Use `fatalError` to generate crash report with stack trace
        fatalError("Main thread hang detected by Watchdog (timeout: \(maximumHangDuration)s). This crash is intentional to provide debugging information.")
    }

    // MARK: Event firing

    private func fireHangEvent(_ eventFactory: (Int) -> Watchdog.Event, currentTime: Date) {
        let actualHangDuration = currentHangDuration(currentTime: currentTime)
        let nearestSecond = hangDurationToNearestSecond(duration: actualHangDuration)
        eventMapper?.fire(eventFactory(nearestSecond))
    }

    // MARK: Duration handling

    private func currentHangDuration(currentTime: Date) -> TimeInterval {
        return hangStartTime.map { currentTime.timeIntervalSince($0) } ?? 0
    }

    private func hangDurationToNearestSecond(duration: TimeInterval) -> Int {
        return Int(duration.rounded())
    }

    private func formattedHangDuration(duration: TimeInterval) -> String {
        return String(format: "%.1f", duration)
    }

    private func logHangDuration(message: String, currentTime: Date) {
        guard hangStartTime != nil else { return }

        let hangDuration = currentHangDuration(currentTime: currentTime)
        Self.logger.info("\(message) Duration: \(self.formattedHangDuration(duration: hangDuration))s")
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

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
    public enum HangState: String {
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
                let duration = currentHangDuration(currentTime: Date())
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

    /// Encapsulates recovery detection state and logic
    private var recoveryState: RecoveryState

    @MainActor
    public private(set) var isRunning: Bool = false

    @MainActor
    private func setIsRunning(_ state: Bool) {
        isRunning = state
    }

    public private(set) var isPaused: Bool = false

    /// - Parameters:
    ///   - minimumHangDuration: The minimum duration of hang to be detected.
    ///   - maximumHangDuration: The maximum duration of hang to be detected. After this point, the hang will stop being measured
    ///                          and will be reported as a timeout.
    ///   - checkInterval: The interval at which the main thread is checked for hangs.
    ///   - requiredRecoveryHeartbeats: The number of consecutive responsive heartbeats required to detect recovery.
    ///   - eventMapper: An event mapper that can map between watchdog events and pixels.
    ///   - crashOnTimeout: Whether the watchdog should kill the app once the maximum hang duration has been reached (used for debugging purposes)
    ///   - killAppFunction: A closure to be executed when the maximum hang duration has been reached (used for testing purposes)
    ///
    public init(minimumHangDuration: TimeInterval = 2.0, maximumHangDuration: TimeInterval = 5.0, checkInterval: TimeInterval = 0.5, requiredRecoveryHeartbeats: Int = 4, eventMapper: EventMapping<Watchdog.Event>? = nil, crashOnTimeout: Bool = false, killAppFunction: ((TimeInterval) -> Void)? = nil) {

        assert(checkInterval > 0, "checkInterval must be greater than 0")
        assert(minimumHangDuration >= 0, "minimumHangDuration must be greater than or equal to 0")
        assert(maximumHangDuration >= 0, "maximumHangDuration must be greater than or equal to 0")
        assert(minimumHangDuration <= maximumHangDuration, "minimumHangDuration must be less than maximumHangDuration")

        self.minimumHangDuration = minimumHangDuration
        self.maximumHangDuration = maximumHangDuration
        self.checkInterval = checkInterval
        self.recoveryState = RecoveryState(requiredHeartbeats: requiredRecoveryHeartbeats)
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

    // MARK: - State management

    /// Starts the watchdog running.
    ///
    public func start() async {
        let isCurrentlyRunning = await isRunning
        guard !isCurrentlyRunning else { return }

        cancelAndClearTasks()
        resetHangState()
        isPaused = false

        monitoringTask = Task.detached { [weak self] in
            await self?.runMonitoringLoop()
        }

        await setIsRunning(true)

        Self.logger.info("Watchdog started monitoring main thread with timeout: \(self.maximumHangDuration)s")
    }

    /// Stops the watchdog entirely.
    ///
    public func stop() async {
        let isCurrentlyRunning = await isRunning
        guard isCurrentlyRunning else { return }

        cancelAndClearTasks()

        Self.logger.info("Watchdog stopped monitoring")

        await setIsRunning(false)
    }

    private func cancelAndClearTasks() {
        monitoringTask?.cancel()
        monitoringTask = nil

        heartbeatUpdateTask?.cancel()
        heartbeatUpdateTask = nil
    }

    /// Pauses the watchdog, if running. Can be resumed with `resume`.
    ///
    public func pause() async {
        guard await isRunning else { return }

        Self.logger.info("Watchdog paused")
        isPaused = true
        await stop()
    }

    /// Resumes the watchdog after being paused. Will only resume if the watchdog was previously running.
    ///
    public func resume() async {
        guard isPaused else { return }

        Self.logger.info("Watchdog resumed")

        // Reset the heartbeat and state to start fresh after resume
        await monitor.resetHeartbeat()
        resetHangState()

        await start()
    }

    private func resetHangState() {
        hangState = .responsive
        hangStartTime = nil
        recoveryState.reset()
    }

    // MARK: - Monitoring

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
            let timeSinceLastHeartbeat = await monitor.timeSinceLastHeartbeat()
            handleHangDetection(timeSinceLastHeartbeat: timeSinceLastHeartbeat)
        }
    }

    private func clearHeartbeatTask() {
        heartbeatUpdateTask = nil
    }

    private func handleHangDetection(timeSinceLastHeartbeat: TimeInterval) {
        let now = Date()

        // Skip hang detection checks if the watchdog is paused
        guard !isPaused else {
            Self.logger.debug("Ignoring hang detection while paused. Last heartbeat: \(timeSinceLastHeartbeat)s ago.")
            return
        }

        switch hangState {
        case .responsive:
            if timeSinceLastHeartbeat > minimumHangDuration {
                transition(from: .responsive, to: .hanging, at: now, timeSinceLastHeartbeat: timeSinceLastHeartbeat)
            }
        case .hanging:
            if timeSinceLastHeartbeat <= minimumHangDuration {
                handleRecoveryDetection(at: now, timeSinceLastHeartbeat: timeSinceLastHeartbeat)
            } else if currentHangDuration(currentTime: now) > maximumHangDuration {
                transition(from: .hanging, to: .timeout, at: now, timeSinceLastHeartbeat: timeSinceLastHeartbeat)
            } else {
                recoveryState.reset()
                logHangDuration(message: "Ongoing main thread hang.", currentTime: now)
            }
        case .timeout:
            if timeSinceLastHeartbeat <= minimumHangDuration {
                handleRecoveryDetection(at: now, timeSinceLastHeartbeat: timeSinceLastHeartbeat)
            } else if currentHangDuration(currentTime: now) > maximumHangDuration && crashOnTimeout {
                logHangDuration(message: "Main thread hang timeout reached. Crashing app.", currentTime: now)
                killAppFunction?(maximumHangDuration) ?? killApp(timeout: maximumHangDuration)
            } else {
                recoveryState.reset()
            }
        }
    }

    private func killApp(timeout: TimeInterval) {
        // Use `fatalError` to generate crash report with stack trace
        fatalError("Main thread hang detected by Watchdog (timeout: \(maximumHangDuration)s). This crash is intentional to provide debugging information.")
    }

    // MARK: - State transitions

    private func transition(from currentState: HangState, to newState: HangState, at time: Date, timeSinceLastHeartbeat: TimeInterval) {
        guard currentState != newState else { return }

        switch (currentState, newState) {
        case (.responsive, .hanging):
            hangState = .hanging
            // Account for half the check interval - the hang will likely have started earlier than the last missed heartbeat
            // The max() guards against potential negative values – if the time since last heartbeat is less than the check interval/2.
            hangStartTime = time.addingTimeInterval(-max((timeSinceLastHeartbeat - checkInterval / 2), 0))
            Self.logger.info("Main thread hang detected! Last heartbeat: \(timeSinceLastHeartbeat)s ago.")
        case (.hanging, .responsive):
            logHangDuration(message: "Main thread hang ended.", currentTime: time)
            fireHangEvent(Watchdog.Event.uiHangRecovered, currentTime: time)
            resetHangState()
        case (.hanging, .timeout):
            hangState = .timeout
            logHangDuration(message: "Main thread hang timeout reached.", currentTime: time)
            fireHangEvent(Watchdog.Event.uiHangNotRecovered, currentTime: time)
        case (.timeout, .responsive):
            logHangDuration(message: "Main thread hang ended after timeout.", currentTime: time)
            resetHangState()
        case (.responsive, .responsive), (.hanging, .hanging), (.timeout, .timeout),
             (.responsive, .timeout), (.timeout, .hanging):
            // We can't timeout from a responsive state, or go back to hanging from a timeout state
            // and we should never transition to the same state we're already in
            Self.logger.warning("Invalid transition from \(currentState.rawValue) to \(newState.rawValue)")
        }
    }

    private func handleRecoveryDetection(at time: Date, timeSinceLastHeartbeat: TimeInterval) {
        recoveryState.recordHeartbeat(at: time)

        if recoveryState.isRecovered {
            transition(from: hangState, to: .responsive, at: time, timeSinceLastHeartbeat: timeSinceLastHeartbeat)
        }
    }

    // MARK: Event firing

    private func fireHangEvent(_ eventFactory: (Int) -> Watchdog.Event, currentTime: Date) {
        let actualHangDuration = currentHangDuration(currentTime: currentTime)
        let nearestSecond = hangDurationToNearestSecond(duration: actualHangDuration)
        let reportedSecond = max(Int(minimumHangDuration), min(nearestSecond, Int(maximumHangDuration)))
        eventMapper?.fire(eventFactory(reportedSecond))
    }

    // MARK: Duration handling

    private func currentHangDuration(currentTime: Date) -> TimeInterval {
        guard let hangStartTime = hangStartTime else { return 0 }

        let hangEndTime = recoveryState.hangEndTime ?? currentTime
        return hangEndTime.timeIntervalSince(hangStartTime)
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

/// Encapsulates recovery detection state and logic
private final class RecoveryState {
    let requiredHeartbeats: Int
    private(set) var detectedResponsiveHeartbeats: Int = 0
    private(set) var firstHeartbeatResponseTime: Date?

    init(requiredHeartbeats: Int) {
        self.requiredHeartbeats = requiredHeartbeats
    }

    func recordHeartbeat(at time: Date) {
        if detectedResponsiveHeartbeats == 0 {
            firstHeartbeatResponseTime = time
        }
        detectedResponsiveHeartbeats += 1
    }

    var isRecovered: Bool {
        detectedResponsiveHeartbeats >= requiredHeartbeats
    }

    func reset() {
        detectedResponsiveHeartbeats = 0
        firstHeartbeatResponseTime = nil
    }

    var hangEndTime: Date? {
        firstHeartbeatResponseTime
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

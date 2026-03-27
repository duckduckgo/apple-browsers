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

// MARK: - Settings

public struct WatchdogSettings {
    let checkInterval: TimeInterval
    let minimumHangDuration: TimeInterval
    let maximumHangDuration: TimeInterval
    let requiredRecoveryHeartbeats: Int

    public static let `default` = WatchdogSettings(checkInterval: 0.5, minimumHangDuration: 2.0, maximumHangDuration: 5.0, requiredRecoveryHeartbeats: 4)
}

// MARK: - A watchdog that monitors the main thread for hangs. Hangs of at least one second will be reported via a pixel.

public final class Watchdog: @unchecked Sendable {

    public enum RecoveryOrigin: String {
        case hanging
        case timeout
    }

    public enum DetectionState: Equatable {
        case responsive
        case hanging
        case timeout
        case recovery(after: RecoveryOrigin, heartbeatCount: Int)
        case recovered(after: RecoveryOrigin)
    }

    public enum Event {
        case uiHangNotRecovered(durationSeconds: Int)
        case uiHangRecovered(durationSeconds: Int)
    }

    // MARK: -  Private Helpers
    private let logger = Logger(subsystem: "com.duckduckgo.watchdog", category: "hang-detection")
    private let watchdogQueue = DispatchQueue(label: "com.duckduckgo.watchdog.monitor", qos: .userInitiated)
    private var timer: DispatchSourceTimer?

    // MARK: - Settings + Reporting
    private let eventMapper: EventMapping<Watchdog.Event>?
    private let settings: WatchdogSettings
    private var heartbeatWorkItem: DispatchWorkItem?

    // MARK: - State
    private var timestamps: WatchdogTracker
    private var detectionState: DetectionState
    private var running: Bool = false
    private var paused: Bool = false

    // MARK: - Observability / Unit Testing Helpers
    private let detectionStateSubject = PassthroughSubject<(DetectionState), Never>()
    internal var detectionStatePublisher: AnyPublisher<(DetectionState), Never> {
        detectionStateSubject.eraseToAnyPublisher()
    }

    public var isRunning: Bool {
        watchdogQueue.sync {
            running
        }
    }

    public var isPaused: Bool {
        watchdogQueue.sync {
            paused
        }
    }

    /// - Parameters:
    ///   - settings: Watchdog's constants used to determine state transitions
    ///   - eventMapper: An event mapper that can map between watchdog events and pixels.
    ///
    public init(settings: WatchdogSettings = .default, eventMapper: EventMapping<Watchdog.Event>? = nil) {
        assert(settings.checkInterval > 0, "checkInterval must be greater than 0")
        assert(settings.minimumHangDuration >= 0, "minimumHangDuration must be greater than or equal to 0")
        assert(settings.maximumHangDuration >= 0, "maximumHangDuration must be greater than or equal to 0")
        assert(settings.minimumHangDuration <= settings.maximumHangDuration, "minimumHangDuration must be less than maximumHangDuration")

        self.eventMapper = eventMapper
        self.settings = settings
        self.timestamps = WatchdogTracker()
        self.detectionState = .responsive
    }

    deinit {
        timer?.cancel()
    }
}

// MARK: - State management

public extension Watchdog {

    /// Starts the watchdog running.
    func start() {
        watchdogQueue.sync {
            startMonitoring()
        }
    }

    /// Stops the watchdog entirely.
    func stop() {
        watchdogQueue.sync {
            stopMonitoring()
        }
    }

    /// Pauses the watchdog, if running. Can be resumed with `resume`.
    func pause() {
        watchdogQueue.sync {
            guard running else {
                return
            }

            logger.info("Watchdog paused")
            paused = true
            stopMonitoring()
        }
    }

    /// Resumes the watchdog after being paused. Will only resume if the watchdog was previously running.
    ///
    func resume() {
        watchdogQueue.sync {
            guard paused else {
                return
            }

            logger.info("Watchdog resumed")
            startMonitoring()
        }
    }
}

// MARK: - State management

private extension Watchdog {

    func startMonitoring() {
        if running {
            return
        }

        cancelTimer()

        timestamps.signalHangRecovered()
        timestamps.signalHeartbeat()

        detectionState = .responsive
        paused = false
        running = true

        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + settings.checkInterval, repeating: settings.checkInterval)
        timer.setEventHandler { [weak self] in
            self?.processTimerEvent()
        }

        self.timer = timer
        timer.resume()

        logger.info("Watchdog started monitoring main thread with timeout: \(self.settings.maximumHangDuration)s")
    }

    func stopMonitoring() {
        guard running else {
            return
        }

        cancelTimer()
        running = false
        paused = false

        logger.info("Watchdog stopped monitoring")
    }

    func cancelTimer() {
        timer?.cancel()
        timer = nil
    }
}

// MARK: - Monitoring

private extension Watchdog {

    func processTimerEvent() {
        if paused || !running {
            return
        }

        performHangDetection()
        enqueueHeartbeatSignal()
    }

    func enqueueHeartbeatSignal() {
        let work = DispatchWorkItem { [weak self] in
            self?.timestamps.signalHeartbeat()
        }

        heartbeatWorkItem?.cancel()
        heartbeatWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    func performHangDetection() {
        let secondsSinceLastHeartbeat = timestamps.secondsSinceLastHeartbeat
        let secondsSinceHangStarted = timestamps.secondsSinceHangStarted

        let nextState = nextState(currentState: detectionState, secondsSinceLastHeartbeat: secondsSinceLastHeartbeat, secondsSinceHangStarted: secondsSinceHangStarted)
        if nextState == detectionState {
            return
        }

        processActions(for: nextState, secondsSinceLastHeartbeat: secondsSinceLastHeartbeat, secondsSinceHangStarted: secondsSinceHangStarted)
        detectionState = nextState
        detectionStateSubject.send(nextState)
    }
}

// MARK: - State Machine

private extension Watchdog {

    /// # Flows:
    ///     .responsive > .hanging -> .recovery > .recovered >.responsive
    ///     .responsive > .hanging -> .timeout -> .recovery -> .recovered > .responsive
    func nextState(currentState: DetectionState, secondsSinceLastHeartbeat: TimeInterval, secondsSinceHangStarted: TimeInterval) -> DetectionState {
        switch currentState {
        case .responsive where secondsSinceLastHeartbeat > settings.minimumHangDuration:
            return .hanging

        case .responsive:
            return .responsive

        /// # Hanging: Enter Recovery if we're seeing heartbeats again
        case .hanging:
            if secondsSinceLastHeartbeat <= settings.minimumHangDuration {
                return .recovery(after: .hanging, heartbeatCount: 0)
            }

            if secondsSinceHangStarted <= settings.maximumHangDuration {
                return .hanging
            }

            return .timeout

        /// # Timeout: Enter Recovery if we're seeing heartbeats again
        case .timeout:
            if secondsSinceLastHeartbeat <= settings.minimumHangDuration {
                return .recovery(after: .timeout, heartbeatCount: 0)
            }

            return .timeout

        /// # Recovery: We'll loop back into this state, should the heartbeat become stale again
        case .recovery(let reason, let heartbeatCount):
            /// # Re-enqueue:
            ///     If we started hanging again, loop thru `recovery` (or go straight to `.hanging` if we haven't done so before)
            if secondsSinceLastHeartbeat > settings.minimumHangDuration {
                let previouslyHanging = reason == .hanging
                return previouslyHanging ? .hanging : .recovery(after: reason, heartbeatCount: 0)
            }

            /// # Track the number of Heartbeats, until we match the recovery settings
            ///
            if heartbeatCount < settings.requiredRecoveryHeartbeats {
                return .recovery(after: reason, heartbeatCount: heartbeatCount + 1)
            }

            /// # Recovered State will track the `uiHangRecovered` only if we came from `.hanging`. Timeouts are doomed
            return .recovered(after: reason)

        case .recovered:
            return .responsive
        }
    }

    func processActions(for heartbeatState: DetectionState, secondsSinceLastHeartbeat: TimeInterval, secondsSinceHangStarted: TimeInterval) {
        switch heartbeatState {
        case .hanging:
            logger.info("Main thread hang detected! Last heartbeat [\(secondsSinceLastHeartbeat)s] ago")
            timestamps.signalHangDetected(secondsSinceLastHeartbeat: secondsSinceLastHeartbeat, checkInterval: settings.checkInterval)

        case .timeout:
            logger.info("Main thread Timeout Reached. Last heartbeat [\(secondsSinceLastHeartbeat)s] ago")
            fireHangEvent(Watchdog.Event.uiHangNotRecovered, secondsSinceHangStarted: secondsSinceHangStarted)

        case .responsive:
            logger.info("Main thread hang ended after Hanging for [\(secondsSinceHangStarted)] seconds")
            timestamps.signalHangRecovered()

        case .recovery(let reason, let count):
            logger.info("Heartbeat [\(count)] detected after \(reason.rawValue)! - Last heartbeat [\(secondsSinceLastHeartbeat)s] ago")

        case .recovered(let reason):
            logger.info("Main thread recovered after \(reason.rawValue) for [\(secondsSinceHangStarted)] seconds")

            if reason == .hanging {
                fireHangEvent(Watchdog.Event.uiHangRecovered, secondsSinceHangStarted: secondsSinceHangStarted)
            }
        }
    }
}

// MARK: Event Reporting

private extension Watchdog {

    func fireHangEvent(_ eventFactory: (Int) -> Watchdog.Event, secondsSinceHangStarted: TimeInterval) {
        let nearestSecond = Int(secondsSinceHangStarted.rounded())
        let reportedSecond = max(Int(settings.minimumHangDuration), min(nearestSecond, Int(settings.maximumHangDuration)))

        eventMapper?.fire(eventFactory(reportedSecond))
    }
}

// MARK: - WatchdogTracker

private final class WatchdogTracker {

    private let lock = NSLock()
    private var heartbeatTimestamp: DispatchTime = .now()
    private var hangStartTimestamp: DispatchTime?

    func signalHeartbeat() {
        lock.withLock {
            heartbeatTimestamp = .now()
        }
    }

    func signalHangDetected(secondsSinceLastHeartbeat: TimeInterval, checkInterval: TimeInterval) {
        lock.withLock {
            let delta = max(secondsSinceLastHeartbeat - checkInterval / 2, 0)
            hangStartTimestamp = DispatchTime.now(subtractingSeconds: delta)
        }
    }

    func signalHangRecovered() {
        lock.withLock {
            hangStartTimestamp = nil
        }
    }

    var lastHeartbeatTimestamp: DispatchTime {
        lock.withLock {
            heartbeatTimestamp
        }
    }

    var lastHangStartTimestamp: DispatchTime? {
        lock.withLock {
            hangStartTimestamp
        }
    }

    var secondsSinceLastHeartbeat: TimeInterval {
        lastHeartbeatTimestamp.secondsElapsedSinceNow
    }

    var secondsSinceHangStarted: TimeInterval {
        lastHangStartTimestamp?.secondsElapsedSinceNow ?? .zero
    }
}

private extension DispatchTime {

    var secondsElapsedSinceNow: TimeInterval {
        let delta = DispatchTime.now().uptimeNanoseconds - uptimeNanoseconds
        return TimeInterval(Double(delta) / .nanosecondsPerSecond)
    }

    static func now(subtractingSeconds delta: TimeInterval) -> DispatchTime {
        let adjustmentNanoseconds = delta * .nanosecondsPerSecond
        return DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds - UInt64(adjustmentNanoseconds))
    }
}

private extension Double {

    static let nanosecondsPerSecond = Double(NSEC_PER_SEC)
}

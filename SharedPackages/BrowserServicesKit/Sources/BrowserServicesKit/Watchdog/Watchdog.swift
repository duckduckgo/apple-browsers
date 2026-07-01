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
import FoundationExtensions
import Foundation
import os.log

// MARK: - Settings

public struct WatchdogSettings {
    let checkInterval: TimeInterval
    let minimumHangDuration: TimeInterval
    let maximumHangDuration: TimeInterval
    let requiredRecoveryHeartbeats: Int
    let timeoutRepeatCooldown: TimeInterval

    public static let `default` = WatchdogSettings(checkInterval: 0.5, minimumHangDuration: 2.0, maximumHangDuration: 5.0, requiredRecoveryHeartbeats: 4, timeoutRepeatCooldown: 60.0)
}

// MARK: - A watchdog that monitors the main thread for hangs. Hangs of at least one second will be reported via a pixel.

public final class Watchdog: @unchecked Sendable {

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
    private var detectionState: WatchdogDetectionState
    private var running: Bool = false
    private var paused: Bool = false

    // MARK: - Observability / Unit Testing Helpers
    private let detectionStateSubject = PassthroughSubject<(WatchdogDetectionState), Never>()
    internal var detectionStatePublisher: AnyPublisher<(WatchdogDetectionState), Never> {
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

        logger.info("Watchdog stopped monitoring")
    }

    func cancelTimer() {
        timer?.cancel()
        timer = nil
    }
}

// MARK: - Timer Management

private extension Watchdog {

    func processTimerEvent() {
        if paused || !running {
            return
        }

        enqueueHeartbeatSignal()
        performHangDetection()
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

        let nextState = WatchdogDetectionState.nextState(currentState: detectionState, settings: settings, secondsSinceLastHeartbeat: secondsSinceLastHeartbeat, secondsSinceHangStarted: secondsSinceHangStarted)
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

    func processActions(for heartbeatState: WatchdogDetectionState, secondsSinceLastHeartbeat: TimeInterval, secondsSinceHangStarted: TimeInterval) {
        switch heartbeatState {
        case .hanging:
            logger.info("Main thread hang detected! Last heartbeat [\(secondsSinceLastHeartbeat)s] ago")
            timestamps.signalHangDetectedIfNeeded(secondsSinceLastHeartbeat: secondsSinceLastHeartbeat, checkInterval: settings.checkInterval)

        case .timeout:
            if let elapsed = timestamps.secondsSinceLastTimeoutFire, elapsed < settings.timeoutRepeatCooldown {
                logger.info("Main thread Timeout Reached: Within Cooldown Period")
                return
            }

            logger.info("Main thread Timeout Reached. Last heartbeat [\(secondsSinceLastHeartbeat)s] ago")
            fireHangEvent(Watchdog.Event.uiHangNotRecovered, secondsSinceHangStarted: secondsSinceHangStarted)
            timestamps.signalTimeoutFired()

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

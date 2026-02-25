//
//  StartupProfiler.swift
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
import QuartzCore
import os.log

// MARK: - StartupProfilerDelegate

protocol StartupProfilerDelegate: AnyObject {
    func startupProfiler(_ profiler: StartupProfiler, didCompleteWithMetrics metrics: StartupMetrics)
}

// MARK: - StartupProfiler

final class StartupProfiler: @unchecked Sendable {

    private let lock = NSLock()
    private var metrics = StartupMetrics()
    private let logger: Logger
    weak var delegate: StartupProfilerDelegate?

    init(logger: Logger = .profiler) {
        self.logger = logger
    }

    func startMeasuring(_ step: StartupStep) -> StartupProfilerToken {
        let startTime = currentTime()

        return StartupProfilerToken { [weak self] in
            guard let self else {
                return
            }

            processStepEnded(step: step, startTime: startTime, endTime: currentTime())
        }
    }

    func measureSequence(initialStep: StartupStep) -> StartupProfilerSequence {
        StartupProfilerSequence(
            initialStep: initialStep,
            timeProvider: { [weak self] in
                self?.currentTime() ?? ProcessInfo.processInfo.systemUptime
            },
            onStepCompleted: { [weak self] step, startTime, endTime in
                self?.processStepEnded(step: step, startTime: startTime, endTime: endTime)
            })
    }

    func measureOnce(_ step: StartupStep, startStep referenceStep: StartupStep) {
        let endTime = currentTime()
        let updatedMetrics = updateMetric(step: step, startStep: referenceStep, endTime: endTime)

        notifyCompletionIfNeeded(metrics: updatedMetrics)
    }

    func exportMetrics() -> StartupMetrics {
        lock.withLock {
            metrics
        }
    }
}

// MARK: - Private Helpers

private extension StartupProfiler {

    func currentTime() -> TimeInterval {
        CACurrentMediaTime()
    }

    func processStepEnded(step: StartupStep, startTime: TimeInterval, endTime: TimeInterval) {
        let updatedMetrics = updateMetric(step: step, startTime: startTime, endTime: endTime)

        notifyCompletionIfNeeded(metrics: updatedMetrics)
    }

    func updateMetric(step: StartupStep, startTime: TimeInterval, endTime: TimeInterval) -> StartupMetrics {
        lock.withLock {
            metrics.update(step: step, startTime: startTime, endTime: endTime)
        }
    }

    func updateMetric(step: StartupStep, startStep referenceStep: StartupStep, endTime: TimeInterval) -> StartupMetrics? {
        lock.withLock {
            guard metrics.intervals[step] == nil, let startTime = metrics.intervals[referenceStep]?.start else {
                return nil
            }

            return metrics.update(step: step, startTime: startTime, endTime: endTime)
        }
    }

    func notifyCompletionIfNeeded(metrics: StartupMetrics?) {
        guard let metrics, metrics.isComplete else {
            return
        }

        logger.log(level: .debug, "🏁 [Startup Metrics]\n\(metrics.description, privacy: .public)")
        delegate?.startupProfiler(self, didCompleteWithMetrics: metrics)
    }
}

// MARK: - StartupProfilerToken

final class StartupProfilerToken: @unchecked Sendable {
    private let lock = NSLock()
    private var onStop: (() -> Void)?

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
    }

    func stop() {
        let action = lock.withLock {
            let action = onStop
            onStop = nil
            return action
        }

        action?()
    }
}

// MARK: - StartupProfilerSequence

final class StartupProfilerSequence: @unchecked Sendable {

    private let lock = NSLock()
    private var activeMeasurement: (step: StartupStep, startTime: TimeInterval)?
    private let timeProvider: () -> TimeInterval
    private let onStepCompleted: (_ step: StartupStep, _ startTime: TimeInterval, _ endTime: TimeInterval) -> Void

    init(initialStep: StartupStep, timeProvider: @escaping () -> TimeInterval, onStepCompleted: @escaping (StartupStep, TimeInterval, TimeInterval) -> Void) {
        self.timeProvider = timeProvider
        self.onStepCompleted = onStepCompleted
        self.activeMeasurement = (initialStep, timeProvider())
    }

    func advance(to nextStep: StartupStep) {
        let nextStartTime = timeProvider()

        guard let previous = consumeActiveMeasurement() else {
            assertionFailure("Advancing after sequence was stopped")
            return
        }

        signalCompletion(step: previous.step, startTime: previous.startTime, endTime: nextStartTime)
        beginStep(step: nextStep, startTime: nextStartTime)
    }

    func stop() {
        guard let previous = consumeActiveMeasurement() else {
            assertionFailure()
            return
        }

        signalCompletion(step: previous.step, startTime: previous.startTime, endTime: timeProvider())
    }
}

private extension StartupProfilerSequence {

    func beginStep(step: StartupStep, startTime: TimeInterval) {
        lock.withLock {
            activeMeasurement = (step, startTime)
        }
    }

    func consumeActiveMeasurement() -> (step: StartupStep, startTime: TimeInterval)? {
        lock.withLock {
            let output = activeMeasurement
            activeMeasurement = nil
            return output
        }
    }

    func signalCompletion(step: StartupStep, startTime: TimeInterval, endTime: TimeInterval) {
        onStepCompleted(step, startTime, endTime)
    }
}

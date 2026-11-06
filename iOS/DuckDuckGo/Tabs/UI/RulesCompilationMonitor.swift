//
//  RulesCompilationMonitor.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Core
import PixelKit
import UIKit

/// Measures setup waiting under the existing compilation-result pixel, once per process.
/// Extensions and rules prepare concurrently; the first main-frame HTTP(S) navigation waits at
/// their gates in sequence. Fractions describe those waits, not the parallel preparation work.
@MainActor
final class RulesCompilationMonitor: NSObject {

    enum Stage {
        case webExtensions
        case contentBlocking
    }

    typealias Outcome = Pixel.Event.CompileRulesResult

    static let shared = RulesCompilationMonitor(isOnboarding: !DefaultTutorialSettings().hasSeenOnboarding)

    private struct Measurement {
        let id = UUID()
        let start: TimeInterval
        var stage: Stage?
        var stageStart: TimeInterval?
        var webExtensionsWait: TimeInterval = 0
        var contentBlockingWait: TimeInterval = 0
        var didWait = false
    }

    private let pixelFiring: PixelFiring?
    private let isOnboarding: Bool
    private let now: () -> TimeInterval
    private let notificationCenter: NotificationCenter
    private let isInBackground: @MainActor () -> Bool
    private var measurement: Measurement?
    private var didReport = false

    init(pixelFiring: PixelFiring? = PixelKit.shared,
         isOnboarding: Bool,
         now: @escaping () -> TimeInterval = { CACurrentMediaTime() },
         notificationCenter: NotificationCenter = .default,
         isInBackground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .background }) {
        self.pixelFiring = pixelFiring
        self.isOnboarding = isOnboarding
        self.now = now
        self.notificationCenter = notificationCenter
        self.isInBackground = isInBackground
        super.init()
        notificationCenter.addObserver(self, selector: #selector(didEnterBackground),
                                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(willTerminate),
                                       name: UIApplication.willTerminateNotification, object: nil)
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    /// One navigation owns the sample; its ID survives retries and excludes stale callbacks.
    func begin() -> UUID? {
        guard !didReport, measurement == nil, !isInBackground() else { return nil }
        let measurement = Measurement(start: now())
        self.measurement = measurement
        return measurement.id
    }

    func beginStage(_ stage: Stage, for id: UUID?) {
        guard let id, var measurement, measurement.id == id, measurement.stage == nil else { return }
        measurement.stage = stage
        if case .webExtensions = stage, !measurement.didWait {
            // WebKit can prepare background content while producing the waiter.
            // That synchronous time is part of the extension wait.
            measurement.stageStart = measurement.start
        } else {
            measurement.stageStart = now()
        }
        measurement.didWait = true
        self.measurement = measurement
    }

    func endStage(for id: UUID?) {
        guard let id, var measurement, measurement.id == id,
              let stage = measurement.stage, let start = measurement.stageStart else { return }
        let duration = max(0, now() - start)
        switch stage {
        case .webExtensions: measurement.webExtensionsWait += duration
        case .contentBlocking: measurement.contentBlockingWait += duration
        }
        measurement.stage = nil
        measurement.stageStart = nil
        self.measurement = measurement
    }

    func finish(_ id: UUID?, outcome: Outcome) {
        guard let id, measurement?.id == id else { return }
        endStage(for: id)
        guard let measurement else { return }
        self.measurement = nil
        didReport = true
        // Without a gate wait, policy bookkeeping is still time_0.
        let totalWait = measurement.didWait ? max(0, now() - measurement.start) : 0
        pixelFiring?.fire(Pixel.Event.compilationResult(result: outcome,
                                                       waitTime: Pixel.Event.BucketAggregation(number: totalWait),
                                                       appState: isOnboarding ? .onboarding : .regular),
                          options: .parameters([
                            "waitTime": String(totalWait),
                            "web_extensions_wait_fraction": Self.fractionBucket(measurement.webExtensionsWait, of: totalWait),
                            "content_blocking_wait_fraction": Self.fractionBucket(measurement.contentBlockingWait, of: totalWait)
                          ]))
    }

    /// Each fraction rounds up independently: a 40%/60% split becomes 0.5/0.75.
    /// Bucket labels need not sum to one.
    private static func fractionBucket(_ duration: TimeInterval, of total: TimeInterval) -> String {
        guard total > 0, duration > 0 else { return "0" }
        switch min(1, duration / total) {
        case ...0.1: return "0.1"
        case ...0.25: return "0.25"
        case ...0.5: return "0.5"
        case ...0.75: return "0.75"
        case ...0.9: return "0.9"
        default: return "1"
        }
    }

    @objc private func didEnterBackground() {
        // Suspended time is not visible waiting, even if navigation completes after resume.
        finish(measurement?.id, outcome: .appBackgrounded)
    }

    @objc private func willTerminate() {
        finish(measurement?.id, outcome: .appQuit)
    }
}

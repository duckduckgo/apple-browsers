//
//  InteractionIntegrityMonitor.swift
//  DuckDuckGo
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

import UIKit
import OSLog
import Core

/// Breadcrumb watchdog over container pans that arbitrate with web scrolling, for the hard-to-reproduce
/// "web view can't scroll but taps still work" freeze. A healthy pan emits `changed` repeatedly then a
/// terminal state; if it goes quiet while still active with no touch down (the touch ended without the
/// recognizer reaching a terminal state), it is wedged — we LOG it (a breadcrumb visible in the in-app
/// Log Viewer and the Interaction Diagnostics snapshot). It does NOT fire a population pixel: the signal
/// is too narrow (one gesture) to be a reliable user metric, but it's useful evidence in a captured trace.
///
/// Not a singleton: owned as an instance by the controller that feeds it gesture state.
/// All methods are main-thread only (gesture callbacks run on main).
@MainActor
final class InteractionIntegrityMonitor {

    private enum Constant {
        static let watchdogTimeout: TimeInterval = 4
    }

    private var watchdog: Timer?
    private weak var armedRecognizer: UIGestureRecognizer?
    private var armedLabel: String?

    /// Feed gesture state transitions of any container pan that competes with web scrolling.
    func noteGestureState(_ recognizer: UIGestureRecognizer, label: String) {
        switch recognizer.state {
        case .began:
            Logger.interaction.debug("\(label, privacy: .public) pan: began")
            arm(recognizer, label: label)
        case .changed:
            extend(recognizer, label: label)
        case .ended, .cancelled, .failed:
            Logger.interaction.debug("\(label, privacy: .public) pan: \(recognizer.state.diagnosticName, privacy: .public)")
            disarm()
        default:
            break
        }
    }

    // MARK: - Watchdog

    private func arm(_ recognizer: UIGestureRecognizer, label: String) {
        armedRecognizer = recognizer
        armedLabel = label
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(timeInterval: Constant.watchdogTimeout,
                                        target: self,
                                        selector: #selector(watchdogFired(_:)),
                                        userInfo: nil,
                                        repeats: false)
    }

    /// Push the deadline out on each `.changed` rather than recreating the timer, which would churn the
    /// run loop ~60×/sec during an active pan.
    private func extend(_ recognizer: UIGestureRecognizer, label: String) {
        guard let watchdog else {
            arm(recognizer, label: label)
            return
        }
        armedRecognizer = recognizer
        armedLabel = label
        watchdog.fireDate = Date(timeIntervalSinceNow: Constant.watchdogTimeout)
    }

    private func disarm() {
        watchdog?.invalidate()
        watchdog = nil
        armedRecognizer = nil
        armedLabel = nil
    }

    /// Logs only for a genuine wedge: the armed recognizer is still mid-gesture (`began`/`changed`) but is
    /// tracking no touches. A finger held still keeps `numberOfTouches >= 1`, so paused drags are excluded.
    /// Runs synchronously on the main run loop, so a gesture that ended first has already invalidated this.
    @objc private func watchdogFired(_ timer: Timer) {
        defer { disarm() }
        guard let recognizer = armedRecognizer,
              recognizer.state == .began || recognizer.state == .changed,
              recognizer.numberOfTouches == 0 else {
            return
        }
        let label = armedLabel ?? "unknown"
        Logger.interaction.error("Gesture watchdog: \(label, privacy: .public) wedged in \(recognizer.state.diagnosticName, privacy: .public) with no active touch")
    }
}

extension UIGestureRecognizer.State {

    var diagnosticName: String {
        switch self {
        case .possible: return "possible"
        case .began: return "began"
        case .changed: return "changed"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

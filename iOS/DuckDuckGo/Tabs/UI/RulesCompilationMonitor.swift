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

/// Measures how long the first foreground main-frame HTTP(S) navigation of a process waits for the page to be
/// ready, and how much of that each setup stage adds, in one pixel. A navigation that replaces a waiting one in
/// the same tab continues the sample, so its wait is not cut off. Extensions and rules prepare concurrently;
/// the navigation waits at their gates in sequence, so each stage reports the time spent waiting at its gate,
/// not the parallel preparation work.
@MainActor
final class RulesCompilationMonitor: NSObject {

    enum Stage {
        case webExtensions
        case contentBlocking
    }

    enum Outcome: String {
        /// The setup gates released navigation.
        case success
        case cancelled
        /// The Web Extension startup gate's deadline released navigation before extensions were ready.
        case timeout
        case tabClosed = "tab_closed"
        case appQuit = "app_quit"
        case appBackgrounded = "app_backgrounded"
    }

    static let shared = RulesCompilationMonitor()

    private struct Measurement {
        var id = UUID()
        let start: TimeInterval
        var isSerp: Bool
        var stage: Stage?
        var stageStart: TimeInterval?
        var webExtensionsWait: TimeInterval = 0
        var contentBlockingWait: TimeInterval = 0
        var didWait = false
        var didExtensionGateTimeOut = false
    }

    /// Resolved at fire time, so the shared monitor picks up `PixelKit.setUp` whenever it ran.
    private let pixelFiring: () -> (any PixelKitFiring)?
    private let isOnboarding: Bool
    private let now: () -> TimeInterval
    private let notificationCenter: NotificationCenter
    private let isInBackground: @MainActor () -> Bool
    private var measurement: Measurement?
    private var didReport = false

    init(pixelFiring: @escaping () -> (any PixelKitFiring)? = { PixelKit.shared },
         isOnboarding: Bool = !DefaultTutorialSettings().hasSeenOnboarding,
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
    /// A navigation replacing the owner passes the owner's ID as `continuing` and takes over the open sample
    /// instead, keeping its start and stage times and reporting its own `isSerp`.
    func begin(isSerp: Bool, continuing id: UUID? = nil) -> UUID? {
        if let id, measurement?.id == id {
            measurement?.isSerp = isSerp
            return handOver(id)
        }
        guard !didReport, measurement == nil, !isInBackground() else { return nil }
        let measurement = Measurement(start: now(), isSerp: isSerp)
        self.measurement = measurement
        return measurement.id
    }

    /// Ends the owner's in-flight stage and gives the open sample a new ID, so the owner's cancelled waits can no
    /// longer end it. Returns the new ID, or `nil` when `id` does not own the sample.
    func handOver(_ id: UUID?) -> UUID? {
        guard let id, measurement?.id == id else { return nil }
        endStage(for: id)
        let newID = UUID()
        measurement?.id = newID
        return newID
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

    /// `extensionGateTimedOut` marks a Web Extension gate released by its deadline, which a later
    /// `.success` finish reports as `.timeout`.
    func endStage(for id: UUID?, extensionGateTimedOut: Bool = false) {
        guard let id, var measurement, measurement.id == id,
              let stage = measurement.stage, let start = measurement.stageStart else { return }
        measurement.didExtensionGateTimeOut = measurement.didExtensionGateTimeOut || extensionGateTimedOut
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
        // Without a gate wait, policy bookkeeping still reports 0.
        let totalWait = measurement.didWait ? max(0, now() - measurement.start) : 0
        let reported = outcome == .success && measurement.didExtensionGateTimeOut ? Outcome.timeout : outcome
        let pixel = NavigationSetupWaitPixel.finished(outcome: reported,
                                                      waitTime: Pixel.Event.BucketAggregation(number: totalWait),
                                                      webExtensionsWait: Pixel.Event.BucketAggregation(number: measurement.webExtensionsWait),
                                                      contentBlockingWait: Pixel.Event.BucketAggregation(number: measurement.contentBlockingWait),
                                                      isOnboarding: isOnboarding,
                                                      isSerp: measurement.isSerp)
        pixelFiring()?.fire(pixel, frequency: .standard)
    }

    @objc private func didEnterBackground() {
        // Suspended time is not visible waiting, even if navigation completes after resume.
        finish(measurement?.id, outcome: .appBackgrounded)
    }

    @objc private func willTerminate() {
        finish(measurement?.id, outcome: .appQuit)
    }
}

//
//  DataClearingPixelsReporter.swift
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

import Foundation
import PixelKit
import QuartzCore

final class DataClearingPixelsReporter {

    var timeProvider: () -> CFTimeInterval
    private let pixelFiring: PixelFiring?

    @MainActor
    private var lastFireTime: CFTimeInterval?
    private let retriggerWindow: TimeInterval = 20.0

    /// Start of the burn for the burn currently in progress
    @MainActor
    private var currentBurnMeasurement: Measurement?

    // MARK: - Initialization

    init(pixelFiring: PixelFiring? = PixelKit.shared,
         timeProvider: @escaping () -> CFTimeInterval = { CACurrentMediaTime() }) {
        self.pixelFiring = pixelFiring
        self.timeProvider = timeProvider
    }

    // MARK: - Secondary SLI Pixels

    /// Fires a pixel if manual fire is triggered within 20 seconds of a previous manual fire.
    ///
    /// Only tracks manual fire triggers to detect user perceived failures
    /// (users rapidly pressing the fire button, indicating potential clearing issues).
    /// Auto-clear triggers are excluded as they follow system timing, not user behavior.
    @MainActor
    func fireRetriggerPixelIfNeeded(request: FireRequest) {
        guard request.trigger == .manualFire else { return }
        let now = timeProvider()
        if let lastFireTime, (now - lastFireTime) <= retriggerWindow {
            pixelFiring?.fire(DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        }
        lastFireTime = now
    }

    /// Marks the start of a burn, so `fireDroppedBurnPixel` can report how long it had been running.
    @MainActor
    func burnDidStart() {
        currentBurnMeasurement = beginMeasurement()
    }

    /// Fires when a burn request is dropped because another burn is still in progress.
    @MainActor
    func fireDroppedBurnPixel(request: FireRequest) {
        let elapsed = currentBurnMeasurement.map { duration(of: $0) } ?? 0
        let pixel = DataClearingPixels.burnDropped(trigger: request.trigger.pixelValue,
                                                   scope: request.scope.pixelValue,
                                                   elapsed: .init(seconds: elapsed))
        pixelFiring?.fire(pixel, frequency: .dailyAndCount)
    }

    func fireUserActionBeforeCompletionPixel() {
        pixelFiring?.fire(DataClearingPixels.userActionBeforeCompletion, frequency: .dailyAndStandard)
    }

    // MARK: - Data Clearing Completion

    /// An in-flight duration measurement. Opaque so callers cannot mint or adjust a start time
    /// themselves; the clock stays the injected `timeProvider`.
    struct Measurement {
        fileprivate let start: CFTimeInterval
    }

    /// Starts measuring. Pair with `duration(of:)` once the measured work completes.
    func beginMeasurement() -> Measurement {
        Measurement(start: timeProvider())
    }

    func duration(of measurement: Measurement) -> TimeInterval {
        timeProvider() - measurement.start
    }

    func fireDataClearingCompletionPixel(_ pixel: DataClearingCompletionPixels) {
        pixelFiring?.fire(pixel, frequency: .standard)
    }
}

// MARK: - Pixel Parameter Values

private extension FireRequest.Trigger {

    var pixelValue: String {
        switch self {
        case .manualFire: return "manual_fire"
        case .autoClearOnLaunch: return "auto_clear_on_launch"
        case .autoClearOnForeground: return "auto_clear_on_foreground"
        case .fireModeAutoClear: return "fire_mode_auto_clear"
        }
    }
}

private extension FireRequest.Scope {

    var pixelValue: String {
        switch self {
        case .tab: return "tab"
        case .fireMode: return "fire_mode"
        case .normalMode: return "normal_mode"
        case .all: return "all"
        }
    }
}

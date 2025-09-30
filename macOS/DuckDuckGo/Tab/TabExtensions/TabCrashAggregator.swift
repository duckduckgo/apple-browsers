//
//  TabCrashAggregator.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Detects and reports WebKit process crash bursts by aggregating individual crash events.
///
/// Individual tab crashes are already tracked per-tab with debouncing, but this can miss
/// burst scenarios where multiple tabs crash simultaneously (e.g., memory pressure, system issues).
/// This aggregator captures the total count of crashes occurring within a short time window.
final class TabCrashAggregator {
    private var crashCount = 0
    private var debounceTask: Task<Void, Never>?

    /// Records a single tab crash event for burst detection.
    ///
    /// Each call increments the crash counter and resets the debounce timer. After 100ms
    /// of no additional crashes, fires an aggregated pixel with the total count.
    ///
    /// - Note: 100ms debounce chosen to capture simultaneous crashes while avoiding
    ///         false grouping of unrelated crashes.
    func recordCrash() {
        crashCount += 1

        debounceTask?.cancel()
        debounceTask = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                await MainActor.run {
                    self.fireAggregatedPixel()
                }
            } catch {
                // Task was cancelled - don't fire the pixel
                return
            }
        }
    }

    /// Fires the aggregated crash pixel and resets state.
    ///
    /// Only fires if crashes were recorded. Includes crash count as parameter
    /// to distinguish single crashes from burst scenarios.
    private func fireAggregatedPixel() {
        guard crashCount > 0 else { return }

        let parameters = ["tab_count": "\(crashCount)"]
        PixelKit.fire(GeneralPixel.webKitDidTerminateNonRecoverableAggregated,
                     frequency: .dailyAndStandard,
                     withAdditionalParameters: parameters)

        crashCount = 0
        debounceTask = nil
    }
}

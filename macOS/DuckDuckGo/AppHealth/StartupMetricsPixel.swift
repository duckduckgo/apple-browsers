//
//  StartupMetricsPixel.swift
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

// MARK: - StartupMetricsPixel

struct StartupMetricsPixel: PixelKitEvent {

    /// Whether the Mac is running on battery power at launch time.
    let isOnBattery: Bool

    /// Architecture of the current build (`"ARM"` or `"Intel"`).
    let architecture: String

    /// Number of active logical processors at launch time, or `nil` if unavailable.
    let activeProcessorCount: Int?

    /// Time spent in the app's `init` method (seconds), or `nil` if unavailable.
    let durationOfAppInit: TimeInterval?

    /// Time spent in `applicationWillFinishLaunching(_:)` (seconds), or `nil` if unavailable.
    let durationOfAppWillFinishLaunching: TimeInterval?

    /// Time spent in `applicationDidFinishLaunching(_:)` before state restoration begins (seconds), or `nil` if unavailable.
    let durationOfAppDidFinishLaunchingBeforeStateRestoration: TimeInterval?

    /// Time spent in `applicationDidFinishLaunching(_:)` after state restoration completes (seconds), or `nil` if unavailable.
    let durationOfAppDidFinishLaunchingAfterStateRestoration: TimeInterval?

    /// Time spent restoring window and tab state (seconds), or `nil` if unavailable. Only sent when greater than zero.
    let durationOfAppStateRestoration: TimeInterval?

    /// Elapsed time between the end of `init` and the start of `applicationWillFinishLaunching(_:)` (seconds), or `nil` if unavailable.
    let deltaBetweenAppInitAndWillFinishLaunching: TimeInterval?

    /// Elapsed time between `applicationWillFinishLaunching(_:)` and `applicationDidFinishLaunching(_:)` (seconds), or `nil` if unavailable.
    let deltaBetweenAppWillFinishAndDidFinishLaunching: TimeInterval?

    /// Elapsed time from app launch to the first interface display (seconds), or `nil` if unavailable.
    let deltaBetweenLaunchAndDidDisplayInterface: TimeInterval?

    /// Number of windows restored during state restoration, or `nil` if unavailable.
    let numberOfWindowsRestored: Int?

    /// Number of tabs restored during state restoration, or `nil` if unavailable.
    let numberOfTabsRestored: Int?

    /// Pixel Name
    var name: String {
        "m_mac_startup_performance_metrics"
    }

    /// Returns context parameters as a dictionary suitable for pixel firing.
    var parameters: [String: String]? {
        var params = [String: String]()

        params["battery_power"] = isOnBattery.description
        params["architecture"] = architecture

        if let count = activeProcessorCount {
            params["active_processor_count"] = StartupMetricsBuckets.bucketProcessorCount(count)
        }
        if let duration = durationOfAppInit {
            params["duration_of_app_init"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let duration = durationOfAppWillFinishLaunching {
            params["duration_of_app_will_finish_launching"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let duration = durationOfAppDidFinishLaunchingBeforeStateRestoration {
            params["duration_of_app_did_finish_launching_before_state_restoration"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let duration = durationOfAppDidFinishLaunchingAfterStateRestoration {
            params["duration_of_app_did_finish_launching_after_state_restoration"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let duration = durationOfAppStateRestoration, duration > 0 {
            params["duration_of_app_state_restoration"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let delta = deltaBetweenAppInitAndWillFinishLaunching {
            params["delta_between_app_init_and_app_will_finish_launching"] = StartupMetricsBuckets.bucketMilliseconds(delta)
        }
        if let delta = deltaBetweenAppWillFinishAndDidFinishLaunching {
            params["delta_between_app_will_finish_and_app_did_finish"] = StartupMetricsBuckets.bucketMilliseconds(delta)
        }
        if let delta = deltaBetweenLaunchAndDidDisplayInterface {
            params["delta_between_launch_and_did_display_interface"] = StartupMetricsBuckets.bucketMilliseconds(delta)
        }
        if let count = numberOfWindowsRestored {
            params["number_of_windows_restored"] = StartupMetricsBuckets.bucketWindowCount(count)
        }
        if let count = numberOfTabsRestored {
            params["number_of_tabs_restored"] = StartupMetricsBuckets.bucketTabCount(count)
        }

        return params
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}

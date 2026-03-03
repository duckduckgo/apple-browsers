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

    // MARK: - System

    /// Architecture of the current build (`"ARM"` or `"Intel"`).
    let architecture: String

    /// Number of active logical processors at launch time, or `nil` if unavailable.
    let activeProcessorCount: Int?

    /// Whether the Mac is running on battery power at launch time, or `nil` if power source information is unavailable.
    let isOnBattery: Bool?

    /// Indicates if Session Restoration was enabled
    let sessionRestoration: Bool

    /// Number of windows restored during state restoration, or `nil` if unavailable.
    let windows: Int?

    /// Number of standard tabs restored during state restoration, or `nil` if unavailable.
    let standardTabs: Int?

    /// Number of pinned tabs restored during state restoration, or `nil` if unavailable.
    let pinnedTabs: Int?

    // MARK: - Timing

    /// Time spent in the App Delegate `init` method (seconds), or `nil` if unavailable.
    let appDelegateInit: TimeInterval?

    /// Time spent in the Main Menu `init` method (seconds), or `nil` if unavailable.
    let mainMenuInit: TimeInterval?

    /// Time spent in `applicationWillFinishLaunching(_:)` (seconds), or `nil` if unavailable.
    let appWillFinishLaunching: TimeInterval?

    /// Time spent in `applicationDidFinishLaunching(_:)` before state restoration begins (seconds), or `nil` if unavailable.
    let appDidFinishLaunchingBeforeStateRestoration: TimeInterval?

    /// Time spent in `applicationDidFinishLaunching(_:)` after state restoration completes (seconds), or `nil` if unavailable.
    let appDidFinishLaunchingAfterStateRestoration: TimeInterval?

    /// Time spent restoring window and tab state (seconds), or `nil` if unavailable. Only sent when greater than zero.
    let appStateRestoration: TimeInterval?

    // MARK: - Delta

    /// Elapsed time between the end of `init` and the start of `applicationWillFinishLaunching(_:)` (seconds), or `nil` if unavailable.
    let initToWillFinishLaunching: TimeInterval?

    /// Elapsed time between `applicationWillFinishLaunching(_:)` and `applicationDidFinishLaunching(_:)` (seconds), or `nil` if unavailable.
    let appWillFinishToDidFinishLaunching: TimeInterval?

    /// Elapsed time from app launch to the first interface display (seconds), or `nil` if unavailable.
    let timeToInteractive: TimeInterval?

    /// Pixel Name
    var name: String {
        "m_mac_startup_performance_metrics"
    }

    /// Returns context parameters as a dictionary suitable for pixel firing.
    var parameters: [String: String]? {
        var params = [String: String]()

        params["architecture"] = architecture
        params["session_restoration"] = sessionRestoration.description

        if let count = activeProcessorCount {
            params["active_processor_count"] = StartupMetricsBuckets.bucketProcessorCount(count)
        }

        if let isOnBattery {
            params["battery_power"] = isOnBattery.description
        }
        if let count = standardTabs {
            params["standard_tabs"] = MemoryReportingBuckets.bucketStandardTabCount(count).description
        }
        if let count = pinnedTabs {
            params["pinned_tabs"] = MemoryReportingBuckets.bucketPinnedTabCount(count).description
        }
        if let count = windows {
            params["windows"] = MemoryReportingBuckets.bucketWindowCount(count).description
        }

        // Timing
        if let duration = appDelegateInit {
            params["app_delegate_init"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let duration = mainMenuInit {
            params["main_menu_init"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let duration = appWillFinishLaunching {
            params["app_will_finish_launching"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let duration = appDidFinishLaunchingBeforeStateRestoration {
            params["app_did_finish_launching_before_state_restoration"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let duration = appDidFinishLaunchingAfterStateRestoration {
            params["app_did_finish_launching_after_state_restoration"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }
        if let duration = appStateRestoration, duration > 0 {
            params["app_state_restoration"] = StartupMetricsBuckets.bucketMilliseconds(duration)
        }

        // Deltas
        if let delta = initToWillFinishLaunching {
            params["init_to_will_finish_launching"] = StartupMetricsBuckets.bucketMilliseconds(delta)
        }
        if let delta = appWillFinishToDidFinishLaunching {
            params["app_will_finish_to_app_did_finish_launching"] = StartupMetricsBuckets.bucketMilliseconds(delta)
        }
        if let delta = timeToInteractive {
            params["time_to_interactive"] = StartupMetricsBuckets.bucketMilliseconds(delta)
        }

        return params
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}

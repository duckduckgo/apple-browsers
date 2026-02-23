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

    let isOnBattery: Bool
    let activeProcessorCount: Int?
    let durationOfAppInit: TimeInterval?
    let durationOfAppWillFinishLaunching: TimeInterval?
    let durationOfAppDidFinishLaunchingBeforeStateRestoration: TimeInterval?
    let durationOfAppDidFinishLaunchingAfterStateRestoration: TimeInterval?
    let durationOfAppStateRestoration: TimeInterval?
    let deltaBetweenAppInitAndWillFinishLaunching: TimeInterval?
    let deltaBetweenAppWillFinishAndDidFinishLaunching: TimeInterval?
    let deltaBetweenLaunchAndDidDisplayInterface: TimeInterval?

    var name: String {
        "m_mac_startup_performance_metrics"
    }

    var parameters: [String: String]? {
        var params = [String: String]()

        params["is_on_battery"] = isOnBattery.description

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

        return params
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}

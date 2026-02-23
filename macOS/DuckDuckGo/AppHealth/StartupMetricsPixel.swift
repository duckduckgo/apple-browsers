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
        var params = [
            "is_on_battery": isOnBattery.description
        ]

        if let duration = durationOfAppInit {
            params["duration_of_app_init"] = bucket(seconds: duration)
        }
        if let duration = durationOfAppWillFinishLaunching {
            params["duration_of_app_will_finish_launching"] = bucket(seconds: duration)
        }
        if let duration = durationOfAppDidFinishLaunchingBeforeStateRestoration {
            params["duration_of_app_did_finish_launching_before_state_restoration"] = bucket(seconds: duration)
        }
        if let duration = durationOfAppDidFinishLaunchingAfterStateRestoration {
            params["duration_of_app_did_finish_launching_after_state_restoration"] = bucket(seconds: duration)
        }
        if let duration = durationOfAppStateRestoration, duration > 0 {
            params["duration_of_app_state_restoration"] = bucket(seconds: duration)
        }
        if let delta = deltaBetweenAppInitAndWillFinishLaunching {
            params["delta_between_app_init_and_app_will_finish_launching"] = bucket(seconds: delta)
        }
        if let delta = deltaBetweenAppWillFinishAndDidFinishLaunching {
            params["delta_between_app_will_finish_and_app_did_finish"] = bucket(seconds: delta)
        }
        if let delta = deltaBetweenLaunchAndDidDisplayInterface {
            params["delta_between_launch_and_did_display_interface"] = bucket(seconds: delta)
        }

        return params
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}

private extension StartupMetricsPixel {

    func bucket(seconds: TimeInterval) -> String {
        let ms = Int(seconds * 1000)
        let bucket: Int

        switch ms {
        case ..<100:
            bucket = 0
        case ..<250:
            bucket = 100
        case ..<500:
            bucket = 250
        case ..<1000:
            bucket = 500
        case ..<2000:
            bucket = 1000
        case ..<3000:
            bucket = 2000
        case ..<5000:
            bucket = 3000
        case ..<10000:
            bucket = 5000
        default:
            bucket = 10000
        }

        return String(bucket)
    }
}

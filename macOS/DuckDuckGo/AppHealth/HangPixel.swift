//
//  HangPixel.swift
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

import PixelKit

enum HangPixel: PixelKitEvent {

    case uiHangRecovered(durationSeconds: Int, inForeground: Bool?, anyWindowVisible: Bool?, batteryPower: BatteryPower?, openBrowserWindowCount: Int?, openBrowserTabCount: Int?, stackTrace: String?)
    case uiHangNotRecovered(durationSeconds: Int, inForeground: Bool?, anyWindowVisible: Bool?, batteryPower: BatteryPower?, openBrowserWindowCount: Int?, openBrowserTabCount: Int?, stackTrace: String?)
    case uiHangDeadlock(durationSeconds: Int, inForeground: Bool?, anyWindowVisible: Bool?, batteryPower: BatteryPower?, openBrowserWindowCount: Int?, openBrowserTabCount: Int?, stackTrace: String?)

    enum BatteryPower: String, CustomStringConvertible {
        var description: String { rawValue }

        case onBattery = "on-battery"
        case pluggedIn = "plugged-in"
    }

    var name: String {
        switch self {
        case .uiHangRecovered:
            return "m_mac_ui_hang_recovered"
        case .uiHangNotRecovered:
            return "m_mac_ui_hang_not-recovered"
        case .uiHangDeadlock:
            return "m_mac_ui_hang_deadlock"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .uiHangRecovered(let durationSeconds, let inForeground, let anyWindowVisible, let batteryPower, let openBrowserWindowCount, let openBrowserTabCount, let stackTrace),
             .uiHangNotRecovered(let durationSeconds, let inForeground, let anyWindowVisible, let batteryPower, let openBrowserWindowCount, let openBrowserTabCount, let stackTrace),
             .uiHangDeadlock(let durationSeconds, let inForeground, let anyWindowVisible, let batteryPower, let openBrowserWindowCount, let openBrowserTabCount, let stackTrace):

            var params: [String: String] = [:]

            params["duration_seconds"] = "\(durationSeconds)"

            if let inForeground {
                params["in_foreground"] = inForeground ? "true" : "false"
            }

            if let anyWindowVisible {
                params["any_window_visible"] = anyWindowVisible ? "true" : "false"
            }

            if let batteryPower {
                params["battery_power"] = batteryPower.rawValue
            }

            if let openBrowserWindowCount {
                params["open_browser_window_count"] = "\(openBrowserWindowCount)"
            }

            if let openBrowserTabCount {
                params["open_browser_tab_count"] = "\(openBrowserTabCount)"
            }

            if let stackTrace {
                params["stack_trace"] = stackTrace
            }

            return params
        }
    }
}

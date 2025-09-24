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

    case uiHangRecovered(seconds: Int, inForeground: Bool?, anyWindowVisible: Bool?, freeMemoryPercent: Double?, batteryPower: BatteryPower?, openBrowserWindows: Int?, openBrowserTabs: Int?)
    case uiHangNotRecovered(seconds: Int, inForeground: Bool?, anyWindowVisible: Bool?, freeMemoryPercent: Double?, batteryPower: BatteryPower?, openBrowserWindows: Int?, openBrowserTabs: Int?)
    case uiHangDeadlock(seconds: Int, inForeground: Bool?, anyWindowVisible: Bool?, freeMemoryPercent: Double?, batteryPower: BatteryPower?, openBrowserWindows: Int?, openBrowserTabs: Int?)

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
        case .uiHangRecovered(let seconds, let inForeground, let anyWindowVisible, let freeMemoryPercent, let batteryPower, let openBrowserWindows, let openBrowserTabs),
             .uiHangNotRecovered(let seconds, let inForeground, let anyWindowVisible, let freeMemoryPercent, let batteryPower, let openBrowserWindows, let openBrowserTabs),
             .uiHangDeadlock(let seconds, let inForeground, let anyWindowVisible, let freeMemoryPercent, let batteryPower, let openBrowserWindows, let openBrowserTabs):

            var params: [String: String] = [:]

            params["seconds"] = "\(seconds)"

            if let inForeground = inForeground {
                params["in_foreground"] = inForeground ? "true" : "false"
            }

            if let anyWindowVisible = anyWindowVisible {
                params["any_window_visible"] = anyWindowVisible ? "true" : "false"
            }

            if let freeMemoryPercent = freeMemoryPercent {
                params["free_memory_percent"] = String(format: "%.1f", freeMemoryPercent)
            }

            if let batteryPower = batteryPower {
                params["battery_power"] = batteryPower.rawValue
            }

            if let openBrowserWindows = openBrowserWindows {
                params["open_browser_windows"] = "\(openBrowserWindows)"
            }

            if let openBrowserTabs = openBrowserTabs {
                params["open_browser_tabs"] = "\(openBrowserTabs)"
            }

            return params
        }
    }
}

//
//  AttributionPixel.swift
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

enum AttributionPixel: PixelKitEvent {
    case userRetentionWeek(defaultBrowser: Bool, count: Int)
    case userRetentionMonth(defaultBrowser: Bool, count: Int)
    case userActivePastWeek(days: Int)
    case userAverageSearchesPastWeekFirstMonth(count: Int)
    case userAverageSearchesPastWeek(count: Int)
    case userAverageAdClicksPastWeek(count: Int)
    case userAverageDuckAiUsagePastWeek(count: Int)
    case userSubscribed(length: Int)
    case userSyncedDevice(devices: Int)

    var name: String {
        switch self {
        case .userRetentionWeek:
            return "user_retention_week"
        case .userRetentionMonth:
            return "user_retention_month"
        case .userActivePastWeek:
            return "user_active_past_week"
        case .userAverageSearchesPastWeekFirstMonth:
            return "user_average_searches_past_week_first_month"
        case .userAverageSearchesPastWeek:
            return "user_average_searches_past_week"
        case .userAverageAdClicksPastWeek:
            return "user_average_ad_clicks_past_week"
        case .userAverageDuckAiUsagePastWeek:
            return "user_average_duck_ai_usage_past_week"
        case .userSubscribed:
            return "user_subscribed"
        case .userSyncedDevice:
            return "user_synced_device"
        }
    }

    private struct ConstantKeys {
        static let defaultBrowser = "default_browser"
        static let count = "count"
        static let days = "days"
        static let length = "length"
        static let numberOfDevices = "number_of_devices"
    }

    var parameters: [String : String]? {
        switch self {
        case .userRetentionWeek(defaultBrowser: let defaultBrowser, count: let count),
                .userRetentionMonth(defaultBrowser: let defaultBrowser, count: let count):
            return [ConstantKeys.defaultBrowser: defaultBrowser.payloadString,
                    ConstantKeys.count: count.payloadString]
        case .userActivePastWeek(days: let days):
            return [ConstantKeys.days: days.payloadString]
        case .userAverageSearchesPastWeekFirstMonth(count: let count),
                .userAverageSearchesPastWeek(count: let count),
                .userAverageAdClicksPastWeek(count: let count),
                .userAverageDuckAiUsagePastWeek(count: let count):
            return [ConstantKeys.count: count.payloadString]
        case .userSubscribed(length: let length):
            return [ConstantKeys.length: length.payloadString]
        case .userSyncedDevice(devices: let devices):
            return [ConstantKeys.numberOfDevices: devices.payloadString]
        }
    }
}

private extension Bool {

    var payloadString: String { self ? "true" : "false" }
}

private extension Int {

    var payloadString: String { "\(self)" }
}

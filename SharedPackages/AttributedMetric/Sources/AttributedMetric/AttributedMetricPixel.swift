//
//  AttributedMetricPixel.swift
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
import Common

/// Note: These pixels will need to be sent with a custom PixelKit instance that is not sending ATB, app version as specified in https://app.asana.com/1/137249556945/project/72649045549333/task/1210849966244847?focus=true
/// All pixels below will not
/// - Send any default parameters such as app version and ATB
/// - Appending app/OS version in the User-Agent header
/// - Send default suffixes such as [phone|tablet]  or [store|direct]
enum AttributedMetricPixel: PixelKitEvent {

    // Metrics
    case userRetentionWeek(origin: String?, installDate: String?, defaultBrowser: Bool, count: String)
    case userRetentionMonth(origin: String?, installDate: String?, defaultBrowser: Bool, count: String)
    case userActivePastWeek(origin: String?, installDate: String?, days: Int)
    case userAverageSearchesPastWeekFirstMonth(origin: String?, installDate: String?, count: String)
    case userAverageSearchesPastWeek(origin: String?, installDate: String?, count: String)
    case userAverageAdClicksPastWeek(origin: String?, installDate: String?, count: String)
    case userAverageDuckAiUsagePastWeek(origin: String?, installDate: String?, count: String)
    case userSubscribed(origin: String?, installDate: String?, length: String)
    case userSyncedDevice(origin: String?, installDate: String?, devices: String)

    // Errors
    case dataStoreError(error: any DDGError)

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
        case .dataStoreError:
            return "attributed_metric_data_store_error"
        }
    }

    private struct ConstantKeys {
        static let defaultBrowser = "default_browser"
        static let count = "count"
        static let days = "days"
        static let length = "length"
        static let numberOfDevices = "number_of_devices"
        static let origin = "origin"
        static let installDate = "install_date"
    }

    var parameters: [String: String]? {
        switch self {
        case .userRetentionWeek(origin: let origin,
                                installDate: let installDate,
                                defaultBrowser: let defaultBrowser,
                                count: let count),
                .userRetentionMonth(origin: let origin, installDate: let installDate, defaultBrowser: let defaultBrowser, count: let count):
            var result = [ConstantKeys.defaultBrowser: defaultBrowser.payloadString,
                         ConstantKeys.count: count]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .userActivePastWeek(origin: let origin, installDate: let installDate, days: let days):
            var result = [ConstantKeys.days: days.payloadString]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .userAverageSearchesPastWeekFirstMonth(origin: let origin, installDate: let installDate, count: let count),
                .userAverageSearchesPastWeek(origin: let origin, installDate: let installDate, count: let count),
                .userAverageAdClicksPastWeek(origin: let origin, installDate: let installDate, count: let count),
                .userAverageDuckAiUsagePastWeek(origin: let origin, installDate: let installDate, count: let count):
            var result = [ConstantKeys.count: count]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .userSubscribed(origin: let origin, installDate: let installDate, length: let length):
            var result = [ConstantKeys.length: length]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .userSyncedDevice(origin: let origin, installDate: let installDate, devices: let devices):
            var result = [ConstantKeys.numberOfDevices: devices]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .dataStoreError:
            return [:]
        }
    }

    func addBaseParamFor(dictionary: inout [String: String], origin: String?, installDate: String?) {
        if let origin {
            dictionary[ConstantKeys.origin] = origin
        } else if let installDate {
            dictionary[ConstantKeys.installDate] = installDate
        }
    }
}

private extension Bool {

    var payloadString: String { self ? "true" : "false" }
}

private extension Int {

    var payloadString: String { "\(self)" }
}

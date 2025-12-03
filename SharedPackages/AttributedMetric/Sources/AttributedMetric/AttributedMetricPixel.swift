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

enum AttributedMetricPixelName: String {
    case userRetentionWeek = "attributed_metric_retention_week"
    case userRetentionMonth = "attributed_metric_retention_month"
    case userActivePastWeek = "attributed_metric_active_past_week"
    case userAverageSearchesPastWeekFirstMonth = "attributed_metric_average_searches_past_week_first_month"
    case userAverageSearchesPastWeek = "attributed_metric_average_searches_past_week"
    case userAverageAdClicksPastWeek = "attributed_metric_average_ad_clicks_past_week"
    case userAverageDuckAiUsagePastWeek = "attributed_metric_average_duck_ai_usage_past_week"
    case userSubscribed = "attributed_metric_subscribed"
    case userSyncedDevice = "attributed_metric_synced_device"
    case dataStoreError = "attributed_metric_data_store_error"
}

/// Note: These pixels will need to be sent with a custom PixelKit instance that is not sending ATB, app version as specified in https://app.asana.com/1/137249556945/project/72649045549333/task/1210849966244847?focus=true
/// All pixels below will not
/// - Send any default parameters such as app version and ATB
/// - Appending app/OS version in the User-Agent header
/// - Send default suffixes such as [phone|tablet]  or [store|direct]
enum AttributedMetricPixel: PixelKitEvent {

    // Metrics
    case userRetentionWeek(origin: String?, installDate: String?, defaultBrowser: Bool, count: Int, bucketVersion: Int)
    case userRetentionMonth(origin: String?, installDate: String?, defaultBrowser: Bool, count: Int, bucketVersion: Int)
    case userActivePastWeek(origin: String?, installDate: String?, days: Int, daysSinceInstalled: Int?, bucketVersion: Int)
    case userAverageSearchesPastWeekFirstMonth(origin: String?, installDate: String?, count: Int, bucketVersion: Int)
    case userAverageSearchesPastWeek(origin: String?, installDate: String?, count: Int, bucketVersion: Int)
    case userAverageAdClicksPastWeek(origin: String?, installDate: String?, count: Int, bucketVersion: Int)
    case userAverageDuckAiUsagePastWeek(origin: String?, installDate: String?, count: Int, bucketVersion: Int)
    case userSubscribed(origin: String?, installDate: String?, month: Int, bucketVersion: Int)
    case userSyncedDevice(origin: String?, installDate: String?, devices: Int, bucketVersion: Int)

    // Errors
    case dataStoreError(error: any DDGError)

    var name: String {
        switch self {
        case .userRetentionWeek:
            return AttributedMetricPixelName.userRetentionWeek.rawValue
        case .userRetentionMonth:
            return AttributedMetricPixelName.userRetentionMonth.rawValue
        case .userActivePastWeek:
            return AttributedMetricPixelName.userActivePastWeek.rawValue
        case .userAverageSearchesPastWeekFirstMonth:
            return AttributedMetricPixelName.userAverageSearchesPastWeekFirstMonth.rawValue
        case .userAverageSearchesPastWeek:
            return AttributedMetricPixelName.userAverageSearchesPastWeek.rawValue
        case .userAverageAdClicksPastWeek:
            return AttributedMetricPixelName.userAverageAdClicksPastWeek.rawValue
        case .userAverageDuckAiUsagePastWeek:
            return AttributedMetricPixelName.userAverageDuckAiUsagePastWeek.rawValue
        case .userSubscribed:
            return AttributedMetricPixelName.userSubscribed.rawValue
        case .userSyncedDevice:
            return AttributedMetricPixelName.userSyncedDevice.rawValue
        case .dataStoreError:
            return AttributedMetricPixelName.dataStoreError.rawValue
        }
    }

    private struct ConstantKeys {
        static let defaultBrowser = "default_browser"
        static let count = "count"
        static let days = "days"
        static let daysSinceInstalled = "daysSinceInstalled"
        static let month = "month"
        static let numberOfDevices = "number_of_devices"
        static let origin = "origin"
        static let installDate = "install_date"
        static let bucketVersion = "version"
    }

    var parameters: [String: String]? {
        switch self {
        case .userRetentionWeek(origin: let origin,
                                installDate: let installDate,
                                defaultBrowser: let defaultBrowser,
                                count: let count,
                                bucketVersion: let bucketVersion),
                .userRetentionMonth(origin: let origin, installDate: let installDate, defaultBrowser: let defaultBrowser, count: let count, bucketVersion: let bucketVersion):
            var result = [ConstantKeys.defaultBrowser: defaultBrowser.payloadString,
                          ConstantKeys.count: count.payloadString,
                          ConstantKeys.bucketVersion: bucketVersion.payloadString]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .userActivePastWeek(origin: let origin, installDate: let installDate, days: let days, daysSinceInstalled: let daysSinceInstalled, bucketVersion: let bucketVersion):
            var result = [ConstantKeys.days: days.payloadString,
                          ConstantKeys.bucketVersion: bucketVersion.payloadString]
            if let daysSinceInstalled {
                result[ConstantKeys.daysSinceInstalled] = daysSinceInstalled.payloadString
            }
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .userAverageSearchesPastWeekFirstMonth(origin: let origin, installDate: let installDate, count: let count, bucketVersion: let bucketVersion):
            var result = [ConstantKeys.count: count.payloadString,
                          ConstantKeys.bucketVersion: bucketVersion.payloadString]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .userAverageSearchesPastWeek(origin: let origin, installDate: let installDate, count: let count, bucketVersion: let bucketVersion),
                .userAverageAdClicksPastWeek(origin: let origin, installDate: let installDate, count: let count, bucketVersion: let bucketVersion),
                .userAverageDuckAiUsagePastWeek(origin: let origin, installDate: let installDate, count: let count, bucketVersion: let bucketVersion):
            var result = [ConstantKeys.count: count.payloadString,
                          ConstantKeys.bucketVersion: bucketVersion.payloadString]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .userSubscribed(origin: let origin, installDate: let installDate, month: let month, bucketVersion: let bucketVersion):
            var result = [ConstantKeys.month: month.payloadString,
                          ConstantKeys.bucketVersion: bucketVersion.payloadString]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .userSyncedDevice(origin: let origin, installDate: let installDate, devices: let devices, bucketVersion: let bucketVersion):
            var result = [ConstantKeys.numberOfDevices: devices.payloadString,
                          ConstantKeys.bucketVersion: bucketVersion.payloadString]
            addBaseParamFor(dictionary: &result, origin: origin, installDate: installDate)
            return result
        case .dataStoreError:
            return [:]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .userRetentionWeek,
                .userRetentionMonth,
                .userActivePastWeek,
                .userAverageSearchesPastWeekFirstMonth,
                .userAverageSearchesPastWeek,
                .userAverageAdClicksPastWeek,
                .userAverageDuckAiUsagePastWeek,
                .userSubscribed,
                .userSyncedDevice:
            return [] // pixelSource is not included for AttributedMetric pixels
        case .dataStoreError:
            return [.pixelSource]
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

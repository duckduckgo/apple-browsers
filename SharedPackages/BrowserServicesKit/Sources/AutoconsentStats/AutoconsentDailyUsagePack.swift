//
//  AutoconsentDailyUsagePack.swift
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

public struct AutoconsentDailyUsagePack {

    public enum Constants {
        public static let averageClicksBlockingCookiePopUp = "averageClicksBlockingCookiePopUp"
        public static let totalCookiePopUpsBlockedBucket = "totalCookiePopUpsBlockedBucket"
        public static let totalTimeBlockingCookiePopUpsBucket = "totalTimeBlockingCookiePopUpsBucket"
    }

    public let totalCookiePopUpsBlocked: Int64
    public let totalClicksMadeBlockingCookiePopUps: Int64
    public let totalTotalTimeSpentBlockingCookiePopUps: TimeInterval

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        formatter.decimalSeparator = "."
        return formatter
    }()

    public init(totalCookiePopUpsBlocked: Int64, totalClicksMadeBlockingCookiePopUps: Int64, totalTotalTimeSpentBlockingCookiePopUps: TimeInterval) {
        self.totalCookiePopUpsBlocked = totalCookiePopUpsBlocked
        self.totalClicksMadeBlockingCookiePopUps = totalClicksMadeBlockingCookiePopUps
        self.totalTotalTimeSpentBlockingCookiePopUps = totalTotalTimeSpentBlockingCookiePopUps
    }

    public func asPixelParameters() -> [String: String] {
        return [
            Constants.averageClicksBlockingCookiePopUp: formattedAverageClicksBlockingCookiePopUp(),
            Constants.totalCookiePopUpsBlockedBucket: totalCookiePopUpsBlockedBucket(),
            Constants.totalTimeBlockingCookiePopUpsBucket: totalTimeBlockingCookiePopUpsBucket()
        ]
    }

    private func averageClicksBlockingCookiePopUp() -> Double {
        guard totalCookiePopUpsBlocked > 0 else {
            return 0.0
        }
        return Double(totalClicksMadeBlockingCookiePopUps) / Double(totalCookiePopUpsBlocked)
    }

    private func formattedAverageClicksBlockingCookiePopUp() -> String {
        return Self.numberFormatter.string(from: NSNumber(value: averageClicksBlockingCookiePopUp())) ?? "0"
    }

    /// Bucket defined in https://app.asana.com/1/137249556945/project/481882893211075/task/1211623429595274?focus=true
    private func totalCookiePopUpsBlockedBucket() -> String {
        switch totalCookiePopUpsBlocked {
        case 0:
            return "0"
        case 1...10:
            return "1-10"
        case 11...50:
            return "11-50"
        case 51...100:
            return "51-100"
        case 101...150:
            return "101-150"
        case 151...200:
            return "151-200"
        case 201...250:
            return "201-250"
        case 251...300:
            return "251-300"
        case 301...500:
            return "301-500"
        case 501...:
            return "500+"
        default:
            return "unknown"
        }
    }

    /// Bucket defined in https://app.asana.com/1/137249556945/project/481882893211075/task/1211623429595274?focus=true
    private func totalTimeBlockingCookiePopUpsBucket() -> String {
        switch totalTotalTimeSpentBlockingCookiePopUps {
        case _ where totalTotalTimeSpentBlockingCookiePopUps < .seconds(1):
            return "0s"
        case (.seconds(1))..<(.seconds(10)):
            return "1-10s"
        case (.seconds(10))..<(.minutes(1)):
            return "10-60s"
        case (.minutes(1))..<(.minutes(5)):
            return "1-5min"
        case (.minutes(5))..<(.minutes(10)):
            return "5-10min"
        case (.minutes(10))..<(.minutes(20)):
            return "10-20min"
        case (.minutes(20))..<(.minutes(40)):
            return "20-40min"
        case (.minutes(40))..<(.hours(1)):
            return "40-60min"
        case (.hours(1))..<(.hours(2)):
            return "1-2hr"
        case (.hours(2))...:
            return "2hr+"
        default:
            return "unknown"
        }
    }
}

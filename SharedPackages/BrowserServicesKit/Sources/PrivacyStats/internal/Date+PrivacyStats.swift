//
//  Date+PrivacyStats.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Common
import Foundation

extension Date {

    /**
     * Returns privacy stats pack timestamp for the current date.
     *
     * See `privacyStatsPackTimestamp`.
     */
    static var currentPrivacyStatsPackTimestamp: Date {
        Date().privacyStatsPackTimestamp
    }

    /**
     * Returns a valid timestamp for `DailyBlockedTrackersEntity` instance matching the sender.
     *
     * Blocked trackers are packed by day so the timestap of the pack must be the exact start of a day.
     */
    var privacyStatsPackTimestamp: Date {
        startOfDay
    }

    /**
     * Returns the oldest valid timestamp for `DailyBlockedTrackersEntity` instance matching the sender.
     *
     * Privacy Stats only keeps track of 7 days worth of tracking history, so the oldest timestamp is
     * beginning of the day 6 days ago.
     */
    var privacyStatsOldestPackTimestamp: Date {
        privacyStatsPackTimestamp.daysAgo(6)
    }
}

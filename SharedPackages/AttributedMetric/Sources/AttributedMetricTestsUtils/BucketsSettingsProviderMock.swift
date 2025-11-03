//
//  BucketsSettingsProviderMock.swift
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
import AttributedMetric

public class BucketsSettingsProviderMock: BucketsSettingsProviding {

    public init() {}

    public var bucketsSettings: [String: Any] {
        [
            "user_retention_week": [
                "buckets": [1, 2, 3],
                "version": 1
            ],
            "user_retention_month": [
                "buckets": [2, 3, 4, 5],
                "version": 1
            ],
            "user_active_past_week": [
                "buckets": [2, 4],
                "version": 1
            ],
            "user_average_searches_past_week_first_month": [
                "buckets": [5, 9],
                "version": 1
            ],
            "user_average_searches_past_week": [
                "buckets": [5, 9],
                "version": 1
            ],
            "user_average_ad_clicks_past_week": [
                "buckets": [2, 5],
                "version": 1
            ],
            "user_average_duck_ai_usage_past_week": [
                "buckets": [5, 9],
                "version": 1
            ],
            "user_subscribed": [
                "buckets": [0, 1],
                "version": 1
            ],
            "user_synced_device": [
                "buckets": [1],
                "version": 1
            ]
        ]
    }
}

//
//  EventHubAttribution.swift
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

/// Computes a pixel's `attributionPeriod`: the start of the interval (of length `periodSeconds`)
/// containing a given period-start timestamp, expressed as UTC epoch seconds.
public enum EventHubAttribution {
    /// Rounds `periodStartMillis` (UTC epoch milliseconds) down to the start of the interval of length
    /// `periodSeconds`, returning UTC epoch seconds: `floor((periodStartMillis / 1000) / periodSeconds) * periodSeconds`.
    public static func startOfIntervalSeconds(periodStartMillis: Int64, periodSeconds: Int64) -> Int64 {
        periodStartMillis / 1000 / periodSeconds * periodSeconds
    }
}

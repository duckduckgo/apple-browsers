//
//  MemoryUsageIntervalPixel.swift
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

import PixelKit
import Foundation

/// Interval memory usage pixel that fires at startup and scheduled intervals with context parameters.
///
/// Each trigger (startup, 1h, 2h, 4h, 8h, 24h) fires at most once per app session.
/// Context parameters include bucketed memory usage, window count, tab count, and architecture.
///
enum MemoryUsageIntervalPixel: PixelKitEvent {

    case memoryUsage(trigger: Trigger, context: MemoryReportingContext)

    /// The trigger that caused this pixel to fire.
    enum Trigger: String, CaseIterable {
        case startup
        case h1 = "1h"
        case h2 = "2h"
        case h4 = "4h"
        case h8 = "8h"
        case h24 = "24h"

        /// The elapsed time threshold in seconds for this trigger. `nil` for startup.
        var elapsedSeconds: TimeInterval? {
            switch self {
            case .startup: return nil
            case .h1: return 3600
            case .h2: return 7200
            case .h4: return 14400
            case .h8: return 28800
            case .h24: return 86400
            }
        }
    }

    var name: String {
        "m_mac_memory_usage"
    }

    var parameters: [String: String]? {
        switch self {
        case .memoryUsage(let trigger, let context):
            var params = context.parameters
            params["trigger"] = trigger.rawValue
            return params
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}

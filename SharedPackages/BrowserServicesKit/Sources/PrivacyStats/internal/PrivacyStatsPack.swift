//
//  PrivacyStatsPack.swift
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

import Foundation

/**
 * This struct keeps track of the summary of blocked trackers for a single unit of time (1 day).
 */
struct PrivacyStatsPack: Equatable {
    let timestamp: Date
    var trackers: [String: Int64]

    init(timestamp: Date, trackers: [String: Int64] = [:]) {
        self.timestamp = timestamp
        self.trackers = trackers
    }
}

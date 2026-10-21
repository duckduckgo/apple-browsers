//
//  BWRetryInterval.swift
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

/// Exponential backoff for Bitwarden connection attempts, so a persistently
/// failing proxy process isn't relaunched every second.
struct BWRetryInterval {

    static let initialInterval: TimeInterval = 1
    static let maximumInterval: TimeInterval = 16

    private var current: TimeInterval = BWRetryInterval.initialInterval

    /// Returns the interval to wait before the next attempt and advances the backoff
    mutating func next() -> TimeInterval {
        defer {
            current = min(current * 2, Self.maximumInterval)
        }
        return current
    }

    mutating func reset() {
        current = Self.initialInterval
    }

}

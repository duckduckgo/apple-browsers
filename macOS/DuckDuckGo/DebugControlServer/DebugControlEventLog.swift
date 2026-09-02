//
//  DebugControlEventLog.swift
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

#if DEBUG

import Foundation

/// A bounded, timestamped record of events observed for one tab.
@MainActor
final class DebugControlEventLog {

    private let limit: Int
    private var entries: [[String: Any]] = []
    private(set) var droppedCount = 0

    init(limit: Int = 5000) {
        self.limit = limit
    }

    static func timestamp() -> Double {
        (Date().timeIntervalSince1970 * 1000).rounded()
    }

    func record(_ fields: [String: Any]) {
        var entry = fields
        if entry["ts"] == nil {
            entry["ts"] = Self.timestamp()
        }
        entries.append(entry)
        if entries.count > limit {
            let overflow = entries.count - limit
            entries.removeFirst(overflow)
            droppedCount += overflow
        }
    }

    func snapshot(since: Double?) -> [[String: Any]] {
        guard let since else { return entries }
        return entries.filter { ($0["ts"] as? Double ?? 0) > since }
    }

    func clear() {
        entries.removeAll()
        droppedCount = 0
    }
}

#endif

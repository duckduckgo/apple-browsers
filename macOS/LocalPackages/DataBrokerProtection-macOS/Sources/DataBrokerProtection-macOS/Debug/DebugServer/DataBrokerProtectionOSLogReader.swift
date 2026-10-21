//
//  DataBrokerProtectionOSLogReader.swift
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

import DataBrokerProtectionCore
import DataBrokerProtectionDebugServer
import Foundation
import OSLog

struct DataBrokerProtectionOSLogReader: DebugLogReading {

    private let monitor = DataBrokerLogMonitorService()

    func logLines(since: Date?, category: String?, limit: Int) throws -> [DebugLogLine] {
        let predicate = LogFilterSettings().subsystemPredicate
        let entries = try monitor.fetchLogs(matching: predicate, since: since)

        let filtered = entries.compactMap { entry -> DebugLogLine? in
            if let category, entry.rawCategory.caseInsensitiveCompare(category) != .orderedSame { return nil }
            return DebugLogLine(timestamp: entry.timestamp,
                                level: entry.level.description,
                                category: entry.rawCategory,
                                subsystem: entry.subsystem,
                                process: entry.process,
                                message: entry.message)
        }
        return limit > 0 ? Array(filtered.suffix(limit)) : filtered
    }
}

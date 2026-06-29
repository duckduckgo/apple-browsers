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
import Foundation
import OSLog

/// macOS `DebugLogReading` for the debug server's `/api/logs` endpoint, backed by the unified log
/// via `DataBrokerLogMonitorService` (`OSLogStore`). iOS has no `OSLogStore` equivalent, so it
/// injects no reader and the endpoint is omitted there.
struct DataBrokerProtectionOSLogReader: DebugLogReading {

    private let monitor = DataBrokerLogMonitorService()

    func logLines(since: Date?, minLevel: String?, category: String?, limit: Int) throws -> [DebugLogLine] {
        // Default filter targets the PIR subsystem in the duckduckgo process — the agent's own logs.
        let predicate = LogFilterSettings().subsystemPredicate
        let entries = try monitor.fetchLogs(matching: predicate, since: since)

        let threshold = minLevel.flatMap(Self.levelRank(forName:))
        let filtered = entries.compactMap { entry -> DebugLogLine? in
            if let threshold, Self.levelRank(entry.level) < threshold { return nil }
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

    private static func levelRank(_ level: OSLogEntryLog.Level) -> Int {
        switch level {
        case .debug: return 0
        case .info: return 1
        case .notice: return 2
        case .error: return 3
        case .fault: return 4
        default: return 2
        }
    }

    private static func levelRank(forName name: String) -> Int? {
        switch name.lowercased() {
        case "debug": return 0
        case "info": return 1
        case "notice": return 2
        case "error": return 3
        case "fault": return 4
        default: return nil
        }
    }
}

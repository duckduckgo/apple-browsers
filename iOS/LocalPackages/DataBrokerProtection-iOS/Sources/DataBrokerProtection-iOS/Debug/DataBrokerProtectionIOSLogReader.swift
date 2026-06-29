//
//  DataBrokerProtectionIOSLogReader.swift
//  DuckDuckGo
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

/// iOS `DebugLogReading` for the debug server's `/api/logs`, backed by the app's own unified log via
/// `OSLogStore(scope: .currentProcessIdentifier)`. On iOS, PIR runs in the main app process, so the
/// current process's log is where the PIR (subsystem `"PIR"`) entries live — no special entitlement
/// needed (the same scope the in-app log viewer uses).
struct DataBrokerProtectionIOSLogReader: DebugLogReading {

    /// Lookback used when no explicit start is given, bounding the first payload.
    private static let defaultLookback: TimeInterval = 5 * 60

    func logLines(since: Date?, minLevel: String?, category: String?, limit: Int) throws -> [DebugLogLine] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: since ?? Date().addingTimeInterval(-Self.defaultLookback))
        let predicate = NSPredicate(format: "subsystem == %@", Logger.dbpSubsystem)
        let entries = try store.getEntries(at: position, matching: predicate)

        let threshold = minLevel.flatMap(Self.levelRank(forName:))
        let lines = entries.compactMap { entry -> DebugLogLine? in
            guard let log = entry as? OSLogEntryLog else { return nil }
            if let threshold, Self.levelRank(log.level) < threshold { return nil }
            if let category, log.category.caseInsensitiveCompare(category) != .orderedSame { return nil }
            return DebugLogLine(timestamp: log.date,
                                level: Self.levelName(log.level),
                                category: log.category,
                                subsystem: log.subsystem,
                                process: log.process,
                                message: log.composedMessage)
        }
        return limit > 0 ? Array(lines.suffix(limit)) : lines
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        case .undefined: return "UNDEFINED"
        @unknown default: return "UNKNOWN"
        }
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

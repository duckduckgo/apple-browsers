//
//  DataBrokerLogMonitorModels.swift
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
import OSLog
import DataBrokerProtectionCore

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let level: OSLogEntryLog.Level
    let category: DataBrokerProtectionLoggerCategory
    let subsystem: String
    let message: String
    let process: String

    init?(from osLogEntry: OSLogEntry) {
        guard let logEntry = osLogEntry as? OSLogEntryLog else {
            return nil
        }

        self.timestamp = logEntry.date
        self.level = logEntry.level
        self.message = logEntry.composedMessage
        self.subsystem = logEntry.subsystem
        self.process = logEntry.process
        self.category = DataBrokerProtectionLoggerCategory(rawValue: logEntry.category) ?? .dataBrokerProtection
    }

    var levelIcon: String {
        switch level {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .notice: return "📢"
        case .error: return "❌"
        case .fault: return "💥"
        default: return "📝"
        }
    }

    var levelDescription: String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        default: return "UNKNOWN"
        }
    }
}

struct LogFilterSettings {
    var logLevels: Set<OSLogEntryLog.Level> = [.debug, .info, .notice, .error, .fault]
    var categories: Set<DataBrokerProtectionLoggerCategory> = Set(DataBrokerProtectionLoggerCategory.allCases)
    var searchText: String = ""
    var autoScroll: Bool = true

    func matches(_ log: LogEntry) -> Bool {
        let categoryMatch = categories.contains(log.category)
        let levelMatch = logLevels.contains(log.level)
        let searchMatch = searchText.isEmpty ||
                         log.message.localizedCaseInsensitiveContains(searchText) ||
                         log.category.rawValue.localizedCaseInsensitiveContains(searchText)

        return categoryMatch && levelMatch && searchMatch
    }

    var hasActiveFilters: Bool {
        categories.count != DataBrokerProtectionLoggerCategory.allCases.count ||
        logLevels.count != OSLogEntryLog.Level.allPirSupportedLevels.count ||
        !searchText.isEmpty
    }
}

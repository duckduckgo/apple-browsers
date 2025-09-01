//
//  LogEntry+Formatting.swift
//  DuckDuckGo
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
import UIKit

struct FormattedLogEntry {
    let timestamp: Date
    let level: OSLogEntryLog.Level
    let subsystem: String
    let category: String
    let process: String
    let message: String

    init(from osLogEntry: OSLogEntryLog) {
        self.timestamp = osLogEntry.date
        self.level = osLogEntry.level
        self.subsystem = osLogEntry.subsystem
        self.category = osLogEntry.category
        self.process = osLogEntry.process
        self.message = osLogEntry.composedMessage
    }

    init(timestamp: Date, level: OSLogEntryLog.Level, subsystem: String, category: String, process: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.message = message
    }

    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }
    
    var levelColor: UIColor {
        switch level {
        case .debug, .info, .notice: return UIColor(designSystemColor: .textPrimary)
        case .error, .fault: return UIColor.systemRed
        case .undefined: return UIColor(designSystemColor: .textPrimary)
        @unknown default: return UIColor(designSystemColor: .textPrimary)
        }
    }

    var timestampWithContext: String {
        let baseString = "\(formattedTimestamp) • \(subsystem)"
        if category.isEmpty {
            return baseString
        } else {
            return baseString + " • \(category)"
        }
    }
    
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}

struct LogFilter {
    let subsystemFilter: String?
    let categoryFilter: String?
    let levelFilter: OSLogEntryLog.Level?
    let searchText: String?
    let filterEmptySubsystems: Bool
    let filterAppleLogs: Bool

    func matches(_ entry: FormattedLogEntry) -> Bool {
        if let levelFilter = levelFilter {
            if entry.level.rawValue < levelFilter.rawValue {
                return false
            }
        }

        if let searchText = searchText, !searchText.isEmpty {
            let searchString = searchText.lowercased()
            return entry.message.lowercased().contains(searchString) ||
                   entry.subsystem.lowercased().contains(searchString) ||
                   entry.category.lowercased().contains(searchString)
        }
        
        return true
    }
    
    static let allLogsFilter = LogFilter(
        subsystemFilter: nil,
        categoryFilter: nil,
        levelFilter: nil,
        searchText: nil,
        filterEmptySubsystems: true,
        filterAppleLogs: true
    )
}

extension OSLogEntryLog.Level {
    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .error: return "Error"
        case .fault: return "Fault"
        case .undefined: return "Undefined"
        @unknown default: return "Unknown"
        }
    }
}

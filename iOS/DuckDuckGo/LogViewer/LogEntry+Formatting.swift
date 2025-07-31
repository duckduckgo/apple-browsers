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

/// Formatted log entry for display in the Log Viewer
struct FormattedLogEntry {
    let id: UUID = UUID()
    let timestamp: Date
    let level: OSLogEntryLog.Level
    let subsystem: String
    let category: String
    let process: String
    let message: String
    let composedMessage: String
    
    /// Initialize with all parameters
    init(timestamp: Date, level: OSLogEntryLog.Level, subsystem: String, category: String, process: String, message: String, composedMessage: String) {
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.message = message
        self.composedMessage = composedMessage
    }
    
    /// Human-readable timestamp format
    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }
    
    /// Level indicator for UI display (removed emojis for cleaner UI)
    var levelIndicator: String {
        switch level {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .notice:
            return "NOTICE"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        case .undefined:
            return "UNKNOWN"
        @unknown default:
            return "UNKNOWN"
        }
    }
    
    var levelColor: UIColor {
        switch level {
        case .debug, .info, .notice:
            return UIColor(designSystemColor: .textPrimary)
        case .error, .fault:
            return UIColor.systemRed
        case .undefined:
            return UIColor(designSystemColor: .textPrimary)
        @unknown default:
            return UIColor(designSystemColor: .textPrimary)
        }
    }

    var displayText: String {
        return "\(levelIndicator) \(formattedTimestamp) [\(subsystem)/\(category)] \(composedMessage)"
    }
    
    /// Shortened display text for list view
    var shortDisplayText: String {
        let truncatedMessage = composedMessage.count > 100 ?
            String(composedMessage.prefix(100)) + "..." : composedMessage
        return "\(levelIndicator) \(formattedTimestamp) \(truncatedMessage)"
    }
    
    /// Formatted timestamp with subsystem and category for bottom display
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
        // formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

extension FormattedLogEntry {
    init(from osLogEntry: OSLogEntryLog) {
        self.timestamp = osLogEntry.date
        self.level = osLogEntry.level
        self.subsystem = osLogEntry.subsystem
        self.category = osLogEntry.category
        self.process = osLogEntry.process
        self.message = osLogEntry.composedMessage
        self.composedMessage = osLogEntry.composedMessage
    }
}

struct LogFilter {
    let subsystemFilter: String?
    let categoryFilter: String?
    let levelFilter: OSLogEntryLog.Level?
    let searchText: String?

    func matches(_ entry: FormattedLogEntry) -> Bool {
        // Implicitly filter out Apple system logs and empty subsystems
        if entry.subsystem.hasPrefix("com.apple") || entry.subsystem.isEmpty {
            return false
        }
        
        // Subsystem filter
        if let subsystemFilter = subsystemFilter, !subsystemFilter.isEmpty {
            if !entry.subsystem.localizedCaseInsensitiveContains(subsystemFilter) {
                return false
            }
        }
        
        // Category filter
        if let categoryFilter = categoryFilter, !categoryFilter.isEmpty {
            if !entry.category.localizedCaseInsensitiveContains(categoryFilter) {
                return false
            }
        }
        
        // Level filter (show this level and above)
        if let levelFilter = levelFilter {
            if entry.level.rawValue < levelFilter.rawValue {
                return false
            }
        }
        
        // Search text filter
        if let searchText = searchText, !searchText.isEmpty {
            let searchString = searchText.lowercased()
            return entry.composedMessage.lowercased().contains(searchString) ||
                   entry.subsystem.lowercased().contains(searchString) ||
                   entry.category.lowercased().contains(searchString)
        }
        
        return true
    }
    
    static let allLogsFilter = LogFilter(
        subsystemFilter: nil,
        categoryFilter: nil,
        levelFilter: nil,
        searchText: nil
    )
}

extension OSLogEntryLog.Level: @retroactive Comparable {
    public static func < (lhs: OSLogEntryLog.Level, rhs: OSLogEntryLog.Level) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
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

//
//  LogExporter.swift
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
import AppKit

@available(macOS 10.15, *)
struct LogExporter {

    struct LogFilter {
        var predicate: NSPredicate
        var destinationFileName: String
    }

    static func export(configuration: LogExporterConfiguration) async throws {
        Logger.general.log("Exporting logs...")

        var filters = [LogFilter]()

        if configuration.includeAllDDG {
            filters.append(
                LogFilter(predicate: NSPredicate(format: "process CONTAINS[c] %@", "duckduckgo"),
                          destinationFileName: "duckduckgo.log"
                         ))
        }

        if configuration.includeSparkle {
            filters.append(
                LogFilter(predicate: NSPredicate(format: """
                (process == "org.sparkle-project.Sparkle" OR processImagePath CONTAINS[c] "Sparkle") \
                OR (subsystem == "Updates") OR (process == "Autoupdate")
            """),
                          destinationFileName: "updater.log"
                ))
        }

        if configuration.includeNetworkProtection {
            filters.append(
                LogFilter(predicate: NSPredicate(format: "subsystem == %@ AND category == %@", "com.apple.extensionkit", "NSExtension"),
                          destinationFileName: "extensionkit_nsextension.log"
                         ))
            filters.append(
                LogFilter(
                    predicate: NSPredicate(format: "subsystem == %@", "com.apple.networkextension"),
                    destinationFileName: "networkextension.log"
                ))

            filters.append(
                LogFilter(
                    predicate: NSPredicate(format: "subsystem == %@", "Network protection"),
                    destinationFileName: "network_protection.log"
                ))
        }

        if configuration.includePersonalInformationRemoval {
            filters.append(
                LogFilter(
                    predicate: NSPredicate(format: "subsystem == %@ AND process CONTAINS[c] %@", "PIR", "DuckDuckGo"),
                    destinationFileName: "personal_information_removal.log"
                ))
        }

        try await exportFilteredLogsToDesktop(minutesBack: configuration.timeInterval, logFilters: filters)
    }

    static func exportFilteredLogsToDesktop(minutesBack: Int, logFilters: [LogFilter]) async throws {
        let store = try OSLogStore.local()
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(TimeInterval(-minutesBack * 60))
        let position = store.position(date: startDate)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for filter in logFilters {
            let entries = try store.getEntries(at: position, matching: filter.predicate)
            let logs = entries.compactMap { $0 as? OSLogEntryLog }

            guard !logs.isEmpty else { continue }

            let formatted: String = logs.map { entry in
                let timestamp = ISO8601DateFormatter().string(from: entry.date)
                let level = entry.level.description != nil ? entry.level.description!+"\t" : ""
                return "\(level)[\(timestamp)]\t[\(entry.process)]\t[\(entry.subsystem)]\t[\(entry.category)]\t\(entry.composedMessage)"
            }.joined(separator: "\n")

            let fileURL = tempDir.appendingPathComponent(filter.destinationFileName)
            try formatted.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Zip all .log files to Desktop
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH:mm:ss"
        let zipURL = desktopURL.appendingPathComponent("ddg_logs_\(formatter.string(from: Date())).zip")

        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.arguments = ["-j", zipURL.path] + (try FileManager.default.contentsOfDirectory(atPath: tempDir.path)).map {
            tempDir.appendingPathComponent($0).path
        }

        try zipProcess.run()
        zipProcess.waitUntilExit()

        try FileManager.default.removeItem(at: tempDir)
    }
}

extension OSLogEntryLog.Level {
    var description: String? {
        switch self {
        case .undefined:
            return "undefined"
        case .debug:
            return "debug"
        case .info:
            return "info"
        case .notice:
            return "notice"
        case .error:
            return "error"
        case .fault:
            return "fault"
        @unknown default:
            return nil
        }
    }
}

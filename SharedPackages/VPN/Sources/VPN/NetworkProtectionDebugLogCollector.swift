//
//  NetworkProtectionDebugLogCollector.swift
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
import os

final class NetworkProtectionDebugLogCollector {

    enum LogCollectionError: Error {
        case appGroupContainerNotFound
        case logStoreCreationFailed
        case logEnumerationFailed
        case fileWriteFailed
        case noLogsFound
    }

    private let appGroupIdentifier: String
    private let fileManager = FileManager.default

    init() {
        self.appGroupIdentifier = "group.com.duckduckgo.alpha.netp"
    }

    func createLogSnapshot() async throws -> URL {
        let containerURL = try getAppGroupContainer()
        let logsDirectory = containerURL.appendingPathComponent("debug-logs")

        try createDirectoryIfNeeded(logsDirectory)

        let timestamp = DateFormatter().apply {
            $0.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        }.string(from: Date())

        let logFileURL = logsDirectory.appendingPathComponent("vpn-logs-\(timestamp).txt")
        let logContent = try await collectLogs()
        try logContent.write(to: logFileURL, atomically: true, encoding: .utf8)

        cleanupOldLogs(in: logsDirectory)

        return logFileURL
    }

    func getExistingLogFiles() throws -> [URL] {
        let containerURL = try getAppGroupContainer()
        let logsDirectory = containerURL.appendingPathComponent("debug-logs")

        guard fileManager.fileExists(atPath: logsDirectory.path) else {
            return []
        }

        let logFiles = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey], options: [])
            .filter { $0.pathExtension == "txt" && $0.lastPathComponent.hasPrefix("vpn-logs-") }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }

        return logFiles
    }

    private func getAppGroupContainer() throws -> URL {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw LogCollectionError.appGroupContainerNotFound
        }
        return containerURL
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func collectLogs() async throws -> String {
        guard let logStore = try? OSLogStore.init(scope: .currentProcessIdentifier) else {
            throw LogCollectionError.logStoreCreationFailed
        }

        let predicate = NSPredicate(format: "subsystem CONTAINS[c] 'duckduckgo' OR subsystem CONTAINS[c] 'netp' OR subsystem CONTAINS[c] 'vpn' OR subsystem CONTAINS[c] 'network' OR process CONTAINS[c] 'DuckDuckGoVPN' OR process CONTAINS[c] 'PacketTunnelProvider'")
        let position = logStore.position(timeIntervalSinceLatestBoot: 0)

        guard let enumerator = try? logStore.getEntries(at: position, matching: predicate) else {
            throw LogCollectionError.logEnumerationFailed
        }

        var logEntries: [String] = []
        let dateFormatter = DateFormatter().apply {
            $0.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        }

        for entry in enumerator {
            if let logEntry = entry as? OSLogEntryLog {
                let timestamp = dateFormatter.string(from: logEntry.date)
                let level = "Test" // logLevelString(for: logEntry)
                let process = logEntry.process
                let subsystem = logEntry.subsystem
                let category = logEntry.category
                let message = logEntry.composedMessage

                let logLine = "[\(timestamp)] [\(level)] [\(process)] [\(subsystem)/\(category)] \(message)"
                logEntries.append(logLine)
            }
        }

        guard !logEntries.isEmpty else {
            throw LogCollectionError.noLogsFound
        }

        return logEntries.joined(separator: "\n")
    }

//    private func logLevelString(for entry: OSLogEntry) -> String {
//        switch entry.level {
//        case .debug:
//            return "DEBUG"
//        case .info:
//            return "INFO"
//        case .notice:
//            return "NOTICE"
//        case .error:
//            return "ERROR"
//        case .fault:
//            return "FAULT"
//        default:
//            return "UNKNOWN"
//        }
//    }

    private func cleanupOldLogs(in directory: URL) {
        do {
            let logFiles = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [])
                .filter { $0.pathExtension == "txt" && $0.lastPathComponent.hasPrefix("vpn-logs-") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }

            if logFiles.count > 5 {
                let filesToDelete = Array(logFiles.dropFirst(5))
                for file in filesToDelete {
                    try? fileManager.removeItem(at: file)
                }
            }
        } catch {
            Logger.networkProtection.error("Failed to cleanup old logs: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension DateFormatter {
    func apply(_ configuration: (DateFormatter) -> Void) -> DateFormatter {
        configuration(self)
        return self
    }
}

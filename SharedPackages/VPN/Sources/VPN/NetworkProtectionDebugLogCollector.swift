//
//  NetworkProtectionDebugLogCollector.swift
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

@available(macOS 12.0, *)
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
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    init() {
        self.appGroupIdentifier = Bundle.main.vpnAppGroupName
    }

    func createLogSnapshot() async throws -> URL {
        let containerURL = try getAppGroupContainer()
        let logsDirectory = containerURL.appendingPathComponent("debug-logs")

        try createDirectoryIfNeeded(logsDirectory)

        let timestamp = dateFormatter.string(from: Date())
        let logFileURL = logsDirectory.appendingPathComponent("iOS-VPN-logs-\(timestamp).txt")
        let logContent = try await collectLogs()
        try logContent.write(to: logFileURL, atomically: true, encoding: .utf8)

        return logFileURL
    }

    func getExistingLogFiles() throws -> [URL] {
        let containerURL = try getAppGroupContainer()
        let logsDirectory = containerURL.appendingPathComponent("debug-logs")

        guard fileManager.fileExists(atPath: logsDirectory.path) else {
            return []
        }

        let logFiles = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey], options: [])
            .filter { $0.pathExtension == "txt" && $0.lastPathComponent.hasPrefix("iOS-VPN-logs-") }
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

        guard let enumerator = try? logStore.getEntries() else {
            throw LogCollectionError.logEnumerationFailed
        }

        var logEntries: [String] = []

        for entry in enumerator {
            if let logEntry = entry as? OSLogEntryLog {
                let timestamp = dateFormatter.string(from: logEntry.date)
                let subsystem = logEntry.subsystem
                let category = logEntry.category
                let message = logEntry.composedMessage

                let logLine = "[\(timestamp)] [\(subsystem)/\(category)] \(message)"
                logEntries.append(logLine)
            }
        }

        guard !logEntries.isEmpty else {
            throw LogCollectionError.noLogsFound
        }

        return logEntries.joined(separator: "\n")
    }

}

public extension Bundle {
    var vpnAppGroupName: String {
        guard let appGroup = object(forInfoDictionaryKey: "VPN_APP_GROUP") as? String else {
            assertionFailure("Failed to get app group key")
            return ""
        }
        return appGroup
    }
}

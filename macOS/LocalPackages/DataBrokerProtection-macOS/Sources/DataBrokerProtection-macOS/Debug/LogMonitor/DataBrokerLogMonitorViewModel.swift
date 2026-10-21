//
//  DataBrokerLogMonitorViewModel.swift
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
import Combine
import AppKit
import DataBrokerProtectionCore
import os.log

@MainActor
final class DataBrokerLogMonitorViewModel: ObservableObject {

    @Published var filteredLogs: [LogEntry] = []
    @Published var isMonitoring: Bool = false
    @Published var filterSettings = LogFilterSettings() {
        didSet {
            if oldValue.subsystemPresets != filterSettings.subsystemPresets
                || oldValue.shouldUseCustomSubsystem != filterSettings.shouldUseCustomSubsystem
                || oldValue.customSubsystem != filterSettings.customSubsystem {
                allLogs.removeAll()
                logService.resetPosition()
            }
            applyFiltersToExistingLogs()
        }
    }
    @Published var retentionLimitText: String = "2000"
    @Published var errorMessage: String?

    private var allLogs: [LogEntry] = []
    private var monitoringTask: Task<Void, Never>?
    private let logService: DataBrokerLogMonitorService
    private let pollInterval: TimeInterval = 2.0

    var logCount: Int { filteredLogs.count }
    var totalLogCount: Int { allLogs.count }

    /// Read-only summary of the active subsystem filter, shown in the toolbar.
    var subsystemDisplayName: String {
        if filterSettings.shouldUseCustomSubsystem {
            return filterSettings.customSubsystem.isEmpty
                ? "(enter subsystem)"
                : filterSettings.customSubsystem
        }
        if filterSettings.subsystemPresets.isEmpty {
            return "(all)"
        }
        return filterSettings.subsystemPresets.map(\.rawValue).sorted().joined(separator: " + ")
    }

    init(logService: DataBrokerLogMonitorService = DataBrokerLogMonitorService()) {
        self.logService = logService
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        allLogs.removeAll()
        filteredLogs.removeAll()
        errorMessage = nil

        logService.resetPosition()

        isMonitoring = true
        startLogPolling()

        Logger.dataBrokerProtection.info("Log monitoring started")
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        isMonitoring = false

        Logger.dataBrokerProtection.info("Log monitoring stopped")
    }

    private static let exportFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }()

    private static let exportTimestampFormatter = ISO8601DateFormatter()

    /// Writes the currently filtered logs to a timestamped `.log` file on the Desktop and reveals it in Finder.
    func exportFilteredLogs() {
        guard !filteredLogs.isEmpty else { return }

        let filename = "log_monitor_\(Self.exportFilenameFormatter.string(from: Date())).log"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent(filename)

        let lines: [String] = filteredLogs.map { log in
            let timestamp = Self.exportTimestampFormatter.string(from: log.timestamp)
            return "\(log.levelDescription)\t[\(timestamp)]\t[\(log.process)]\t[\(log.subsystem)]\t[\(log.rawCategory)]\t\(log.message)"
        }
        let content = lines.joined(separator: "\n")

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            Logger.dataBrokerProtection.info("Exported \(self.filteredLogs.count) log entries to \(url.path, privacy: .public)")
        } catch {
            errorMessage = "Failed to export logs: \(error.localizedDescription)"
        }
    }

    func clearLogs() {
        allLogs.removeAll()
        filteredLogs.removeAll()
        errorMessage = nil

        logService.resetPosition()

        Logger.dataBrokerProtection.debug("Log monitor cleared")
    }

    private func startLogPolling() {
        let retentionLimit = parseRetentionLimit()

        monitoringTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled && isMonitoring {
                do {
                    let newLogs = try await logService.fetchRecentLogs(
                        matching: filterSettings.subsystemPredicate,
                        since: logService.currentPosition
                    )

                    if !newLogs.isEmpty {
                        allLogs.append(contentsOf: newLogs)

                        if allLogs.count > retentionLimit {
                            allLogs = Array(allLogs.suffix(retentionLimit))
                        }

                        applyFiltersToExistingLogs()
                    }

                } catch {
                    errorMessage = "Failed to fetch logs: \(error.localizedDescription)"
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
    }

    private func parseRetentionLimit() -> Int {
        let limit = Int(retentionLimitText) ?? 2000
        return max(100, min(10000, limit))
    }

    private func applyFiltersToExistingLogs() {
        filteredLogs = allLogs.filter { filterSettings.matches($0) }
    }

    deinit {
        monitoringTask?.cancel()
    }
}

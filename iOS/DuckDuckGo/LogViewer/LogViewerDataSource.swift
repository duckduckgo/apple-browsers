//
//  LogViewerDataSource.swift
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
import Combine
import os.log

protocol LogViewerDataSourceDelegate: AnyObject {
    func logViewerDataSource(_ dataSource: LogViewerDataSource, didUpdateEntries entries: [FormattedLogEntry])
    func logViewerDataSource(_ dataSource: LogViewerDataSource, didEncounterError error: Error)
}

/// Manages OSLogStore access and real-time log fetching
@available(iOS 15.0, *)
final class LogViewerDataSource {
    
    // MARK: - Public Properties
    
    weak var delegate: LogViewerDataSourceDelegate?
    
    private(set) var isRunning = false
    private(set) var currentFilter = LogFilter.allLogsFilter
    
    private(set) var logEntries: [FormattedLogEntry] = [] {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.logViewerDataSource(self, didUpdateEntries: self.logEntries)
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var refreshTimer: Timer?
    private var logStore: OSLogStore?
    private var lastFetchTime: Date?
    private let refreshInterval: TimeInterval = 1.0
    private let maxLogEntries = 2000
    private let backgroundQueue = DispatchQueue(label: "LogViewerDataSource", qos: .utility)
    
    // MARK: - Initialization
    
    init() {
        setupLogStore()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods
    
    /// Start real-time log fetching
    func start() {
        guard !isRunning else { return }
        
        isRunning = true
        fetchLogs()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] timer in
            guard let self = self, self.isRunning else {
                timer.invalidate()
                return
            }
            self.fetchLogs()
        }
        
        // Add timer to run loop for better reliability
        if let timer = refreshTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    func stop() {
        guard isRunning else { return }
        
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func updateFilter(_ filter: LogFilter) {
        currentFilter = filter
        if isRunning {
            fetchLogs()
        }
    }

    func clearLogs() {
        DispatchQueue.main.async {
            self.logEntries = []
        }
    }

    func exportLogs() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        let header = """
        DuckDuckGo iOS Log Export
        Generated: \(dateFormatter.string(from: Date()))
        Total Entries: \(logEntries.count)
        
        ---
        
        """
        
        let logText = logEntries.map { entry in
            let timestamp = dateFormatter.string(from: entry.timestamp)
            return "[\(timestamp)] [\(entry.level.displayName)] [\(entry.subsystem)/\(entry.category)] \(entry.composedMessage)"
        }.joined(separator: "\n")
        
        return "\(header)\(logText)"
    }
    
    // MARK: - Private Methods
    
    private func setupLogStore() {
        logStore = try? OSLogStore(scope: .currentProcessIdentifier)
    }
    
    private func fetchLogs() {
        backgroundQueue.async {
            self.performLogFetch()
        }
    }
    
    private func performLogFetch() {
        guard let logStore = logStore else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.logViewerDataSource(self, didEncounterError: LogViewerError.logStoreUnavailable)
            }
            return
        }
        
        do {
            try fetchLogs(from: logStore)
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.logViewerDataSource(self, didEncounterError: LogViewerError.fetchFailed(error))
            }
        }
    }
    
    private func fetchLogs(from logStore: OSLogStore) throws {
        let endDate = Date()
        let startDate = lastFetchTime ?? Date.distantPast
        let predicate = createPredicate()
        
        let position = logStore.position(date: startDate)
        let entries: AnySequence<OSLogEntry>
        if let predicate = predicate {
            entries = try logStore.getEntries(at: position, matching: predicate)
        } else {
            entries = try logStore.getEntries(at: position)
        }
        
        var newEntries: [FormattedLogEntry] = []

        for entry in entries {
            guard entry.date > startDate else { continue }

            // Convert OSLogEntry to our FormattedLogEntry
            if let logEntry = entry as? OSLogEntryLog {
                let formattedEntry = FormattedLogEntry(from: logEntry)
                if currentFilter.matches(formattedEntry) {
                    newEntries.append(formattedEntry)
                }
            }
        }

        var updatedEntries = logEntries + newEntries

        if updatedEntries.count > maxLogEntries {
            updatedEntries = Array(updatedEntries.prefix(maxLogEntries))
        }

        logEntries = updatedEntries
        lastFetchTime = endDate
    }
    
    private func createPredicate() -> NSPredicate? {
        // Filter out logs with no subsystem or Apple subsystems at the OSLogStore level
        // This is more efficient than fetching all logs and filtering them afterward
        
        // Handle both nil and empty string cases for subsystem
        let hasSubsystem = NSPredicate(format: "subsystem != nil AND subsystem != ''")
        let noAppleSubsystem = NSPredicate(format: "NOT subsystem BEGINSWITH 'com.apple'")
        
        return NSCompoundPredicate(andPredicateWithSubpredicates: [hasSubsystem, noAppleSubsystem])
    }
}

// MARK: - Error Types

enum LogViewerError: LocalizedError {
    case logStoreUnavailable
    case osLogNotSupported
    case fetchFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .logStoreUnavailable:
            return "Log store is not available on this device"
        case .osLogNotSupported:
            return "OSLog is not supported on this iOS version"
        case .fetchFailed(let error):
            return "Failed to fetch logs: \(error.localizedDescription)"
        }
    }
}

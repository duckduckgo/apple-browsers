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

protocol LogViewerDataSourceDelegate: AnyObject {
    func logViewerDataSource(_ dataSource: LogViewerDataSource, didUpdateEntries entries: [FormattedLogEntry])
    func logViewerDataSource(_ dataSource: LogViewerDataSource, didEncounterError error: Error)
    func logViewerDataSource(_ dataSource: LogViewerDataSource, didUpdateLoadingState isLoading: Bool)
}

final class LogViewerDataSource {

    weak var delegate: LogViewerDataSourceDelegate?

    private var logStore: OSLogStore?
    private(set) var currentFilter = LogFilter.allLogsFilter
    private let fetchQueue = DispatchQueue(label: "LogViewerDataSource", qos: .utility)
    private(set) var logEntries: [FormattedLogEntry] = [] {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.logViewerDataSource(self, didUpdateEntries: self.logEntries)
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        setupLogStore()
    }
    
    // MARK: - Public Methods

    func refresh() {
        logEntries = []

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.logViewerDataSource(self, didUpdateLoadingState: true)
        }
        
        fetchLogs()
    }

    func updateFilter(_ filter: LogFilter) {
        currentFilter = filter
        logEntries = []
        refresh()
    }
    
    func exportLogsToFile() -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "DuckDuckGo_iOS_Logs_\(timestamp).txt"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        let consoleFormatter = DateFormatter()
        consoleFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        consoleFormatter.timeZone = TimeZone.current
        
        let logContent: String = logEntries.map { entry in
            let timestamp = consoleFormatter.string(from: entry.timestamp)
            let processName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DuckDuckGo"
            return "\(timestamp) \(processName)\(entry.level.displayName): (\(entry.subsystem)) [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
        
        do {
            try logContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func setupLogStore() {
        logStore = try? OSLogStore(scope: .currentProcessIdentifier)
    }
    
    private func fetchLogs() {
        fetchQueue.async {
            self.performLogFetch()
        }
    }
    
    private func performLogFetch() {
        guard let logStore = logStore else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.logViewerDataSource(self, didUpdateLoadingState: false)
                self.delegate?.logViewerDataSource(self, didEncounterError: LogViewerError.logStoreUnavailable)
            }
            return
        }
        
        do {
            try fetchLogs(from: logStore)
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.logViewerDataSource(self, didUpdateLoadingState: false)
                self.delegate?.logViewerDataSource(self, didEncounterError: LogViewerError.fetchFailed(error))
            }
        }
    }
    
    private func fetchLogs(from logStore: OSLogStore) throws {
        let entries = try logStore.getEntries(matching: createPredicate())
        logEntries = entries.compactMap { entry in
            if let logEntry = entry as? OSLogEntryLog {
                let formattedEntry = FormattedLogEntry(from: logEntry)
                if currentFilter.matches(formattedEntry) {
                    return formattedEntry
                }
            }

            return nil
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.logViewerDataSource(self, didUpdateLoadingState: false)
        }
    }
    
    private func createPredicate() -> NSPredicate {
        var predicates: [NSPredicate] = []
        
        // Conditionally filter out logs with no subsystem based on toggle
        if currentFilter.filterEmptySubsystems {
            let hasSubsystem = NSPredicate(format: "subsystem != nil AND subsystem != ''")
            predicates.append(hasSubsystem)
        }
        
        // Conditionally filter out Apple subsystems based on toggle
        if currentFilter.filterAppleLogs {
            let noAppleSubsystem = NSPredicate(format: "NOT subsystem BEGINSWITH 'com.apple'")
            predicates.append(noAppleSubsystem)
        }

        if let subsystemFilter = currentFilter.subsystemFilter, !subsystemFilter.isEmpty {
            let subsystemPredicate = NSPredicate(format: "subsystem CONTAINS[cd] %@", subsystemFilter)
            predicates.append(subsystemPredicate)
        }

        if let categoryFilter = currentFilter.categoryFilter, !categoryFilter.isEmpty {
            let categoryPredicate = NSPredicate(format: "category CONTAINS[cd] %@", categoryFilter)
            predicates.append(categoryPredicate)
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
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

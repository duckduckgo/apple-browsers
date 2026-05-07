//
//  DataBrokerLogMonitorService.swift
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
import DataBrokerProtectionCore

public class DataBrokerLogMonitorService {
    private var lastLogPosition: OSLogPosition?
    private var currentSubsystem: String

    public init(subsystem: String = Logger.dbpSubsystem) {
        self.currentSubsystem = subsystem
    }

    /// Updates the subsystem to monitor and resets log position
    public func updateSubsystem(_ newSubsystem: String) {
        guard newSubsystem != currentSubsystem else { return }
        currentSubsystem = newSubsystem
        resetPosition() // Reset position when changing subsystems
    }

    /// Returns the currently monitored subsystem
    public var monitoredSubsystem: String {
        return currentSubsystem
    }

    var currentPosition: OSLogPosition? {
        return lastLogPosition
    }

    func fetchRecentLogs(since lastPosition: OSLogPosition? = nil) async throws -> [LogEntry] {
        let store = try OSLogStore.local()

        let position: OSLogPosition
        if let lastPosition = lastPosition {
            position = lastPosition
        } else {
            let startDate = Date().addingTimeInterval(-5*60)
            position = store.position(date: startDate)
        }

        let predicate = NSPredicate(format: "subsystem == %@", currentSubsystem)
        let entries = try store.getEntries(at: position, matching: predicate)
        let logEntries = entries.compactMap { entry in
            LogEntry(from: entry)
        }

        if !logEntries.isEmpty {
            lastLogPosition = store.position(date: Date())
        }

        return logEntries
    }

    func resetPosition() {
        lastLogPosition = nil
    }
}

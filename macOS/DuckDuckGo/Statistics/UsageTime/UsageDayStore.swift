//
//  UsageDayStore.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Persistence

struct UsageDayRecord: Codable, Equatable {
    let firstSignal: Date
    var open: TimeInterval = 0
    var active: TimeInterval = 0
    var delivery: Delivery?

    struct Delivery: Codable, Equatable {
        let finalizedAt: Date
        let payload: DailyUsagePayload
    }

    mutating func add(open: TimeInterval, active: TimeInterval) {
        guard delivery == nil else { return }
        self.open = min(86_400, self.open + open)
        self.active = min(self.open, self.active + active)
    }
}

/// Confined to the monitor's serial queue. Dirty usage survives unsuccessful writes in memory.
final class UsageDayStore {
    private static let fileName = "UsageTimeKeyValueStore"
    private static let snapshotKey = "days.v1"
    private let directory: URL
    private let onDiscard: () -> Void
    private var file: KeyValueFileStore?
    private(set) var days: [Date: UsageDayRecord] = [:]

    init(directory: URL, onDiscard: @escaping () -> Void) {
        self.directory = directory
        self.onDiscard = onDiscard
    }

    func restore() throws {
        guard file == nil else { return }
        let existing = try loadOrDiscard()
        let opened = try existing?.file ?? KeyValueFileStore(location: directory, name: Self.fileName)
        var restored = existing?.days ?? [:]
        for (date, pending) in days {
            restored[date, default: UsageDayRecord(firstSignal: pending.firstSignal)].add(open: pending.open, active: pending.active)
        }
        days = restored
        file = opened
    }

    private func loadOrDiscard() throws -> (file: KeyValueFileStore, days: [Date: UsageDayRecord])? {
        let opened = try KeyValueFileStore(location: directory, name: Self.fileName)
        do {
            return (opened, try Self.read(opened))
        } catch {
            // Only remove the dedicated file after acquiring it. Never remove a directory at this path.
            let attributes = try FileManager.default.attributesOfItem(atPath: opened.fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw error }
            try FileManager.default.removeItem(at: opened.fileURL)
            onDiscard()
            return nil
        }
    }

    private static func read(_ file: KeyValueFileStore) throws -> [Date: UsageDayRecord] {
        guard let value = try file.object(forKey: snapshotKey) else { return [:] }
        guard let data = value as? Data else { throw CocoaError(.coderReadCorrupt) }
        let records = try JSONDecoder().decode([UsageDayRecord].self, from: data)
        var result: [Date: UsageDayRecord] = [:]
        for record in records {
            let day = UsageTimeTracker.calendar.startOfDay(for: record.firstSignal)
            guard record.open >= 0, record.open <= 86_400, record.active >= 0, record.active <= record.open,
                  result.updateValue(record, forKey: day) == nil else { throw CocoaError(.coderReadCorrupt) }
        }
        return result
    }

    @discardableResult
    func add(_ increments: [UsageTimeIncrement]) -> Bool {
        var created = false
        for increment in increments {
            let day = UsageTimeTracker.calendar.startOfDay(for: increment.start)
            if days[day] == nil { created = true }
            days[day, default: UsageDayRecord(firstSignal: increment.start)].add(open: increment.open, active: increment.active)
        }
        return created
    }

    @discardableResult
    func checkpoint(at date: Date, finalize: ((UsageDayRecord) -> UsageDayRecord.Delivery?)? = nil) throws -> [UsageDayRecord.Delivery] {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        let calendar = UsageTimeTracker.calendar
        let today = calendar.startOfDay(for: date)
        let oldest = calendar.date(byAdding: .day, value: -7, to: today)!
        var snapshot = days.filter { $0.key >= oldest }
        var deliveries: [UsageDayRecord.Delivery] = []
        for (day, record) in snapshot where record.delivery == nil {
            if let delivery = finalize?(record) {
                snapshot[day]?.delivery = delivery
                deliveries.append(delivery)
            }
        }
        let data = try JSONEncoder().encode(Array(snapshot.values))
        try file.set(data, forKey: Self.snapshotKey)
        days = snapshot
        return deliveries
    }
}

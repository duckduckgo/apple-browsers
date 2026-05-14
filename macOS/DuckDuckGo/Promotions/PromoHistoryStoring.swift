//
//  PromoHistoryStoring.swift
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

import Combine
import Common
import Foundation
import os.log
import Persistence

/// Storage for promo history.
///
/// **Threading contract:** All methods must be called from `PromoService`'s `stateQueue`.
/// Implementations may assert this via `dispatchPrecondition(condition: .onQueue(stateQueue))`
/// when the expected queue is provided at initialization.
protocol PromoHistoryStoring {
    func record(for promoId: String) -> PromoHistoryRecord
    func save(_ record: PromoHistoryRecord)

    /// Clears all history records. For debug reset.
    func resetAll()
}

final class PromoHistoryStore: PromoHistoryStoring {

    private static let storageKey = "com.duckduckgo.promo.history"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private let store: ThrowingKeyValueStoring
    private let queue: DispatchQueue?
    private var records: [String: PromoHistoryRecord]

    init(store: ThrowingKeyValueStoring, queue: DispatchQueue?) {
        self.store = store
        self.queue = queue
        let loaded = Self.load(from: store)
        self.records = loaded
    }

    private func assertOnExpectedQueue() {
        if let queue {
            dispatchPrecondition(condition: .onQueue(queue))
        }
    }

    func record(for promoId: String) -> PromoHistoryRecord {
        assertOnExpectedQueue()
        return records[promoId] ?? PromoHistoryRecord(id: promoId)
    }

    func save(_ record: PromoHistoryRecord) {
        assertOnExpectedQueue()
        records[record.id] = record
        persist()
    }

    func resetAll() {
        assertOnExpectedQueue()
        records = [:]
        persist()
    }

    private func persist() {
        do {
            let data = try Self.encoder.encode(records)
            try store.set(data, forKey: Self.storageKey)
        } catch {
            Logger.general.error("PromoHistoryStore failed to persist: \(error.localizedDescription)")
        }
    }

    private static func load(from store: ThrowingKeyValueStoring) -> [String: PromoHistoryRecord] {
        do {
            guard let data = try store.object(forKey: storageKey) as? Data else { return [:] }
            return try decoder.decode([String: PromoHistoryRecord].self, from: data)
        } catch {
            Logger.general.error("PromoHistoryStore failed to load: \(error.localizedDescription)")
            return [:]
        }
    }
}

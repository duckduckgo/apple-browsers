//
//  PixelRetryQueue.swift
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
import os.log
import Persistence

/// Retry queue for failed PixelKit fires.
///
/// `PixelRetryQueue` decorates the `PixelKit.FireRequest` network closure. When a fire fails it persists
/// the fully-resolved request; when a fire succeeds it triggers a throttled drain that replays queued
/// items through the *underlying* closure (so replays never re-enter this decorator). Items older than
/// 28 days are dropped without sending.
///
/// `PixelKit` creates and owns this internally: it wraps the `FireRequest` passed to `PixelKit.setUp`,
/// reuses the same `defaults` for throttling state, and drains the queue after each successful send.
/// Consumers of `PixelKit` don't interact with it directly.
///
/// This is a port of iOS `PersistentPixel`; a Swift Concurrency modernisation can follow later.
final class PixelRetryQueue {

    enum Constants {
        static let lastProcessingDateKey = "com.duckduckgo.pixelkit.retry-queue.last-processing-timestamp"
        static let expiryDays = 28
#if DEBUG
        static let minimumProcessingInterval: TimeInterval = 60          // 1 minute
#else
        static let minimumProcessingInterval: TimeInterval = 60 * 60     // 1 hour
#endif
    }

    /// Wire parameter keys, matching iOS so the backend sees identical data.
    enum Parameters {
        static let originalPixelTimestamp = "originalPixelTimestamp"
        static let retriedPixel = "retriedPixel"
    }

    private let underlyingFireRequest: PixelKit.FireRequest
    private let store: PixelRetryQueueStoring
    private let lastProcessingDateStorage: ThrowingKeyValueStoring
    private let lastProcessingDateKey: String
    private let calendar: Calendar
    private let dateGenerator: () -> Date

    /// In-memory source of truth for the last drain time, seeded once from `lastProcessingDateStorage` at
    /// init and written through on update. Reading it from memory (rather than from disk on every drain)
    /// means a persistent read failure can't be misread as "never drained" and trigger a drain on every
    /// fire. Only accessed on `workQueue` after the initial seed.
    private var lastProcessingDate: Date?

    private let workQueue = DispatchQueue(label: "PixelKit Retry Queue")
    private let logger = Logger(subsystem: "PixelKit", category: "PixelRetryQueue")

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(fireRequest: @escaping PixelKit.FireRequest,
         store: PixelRetryQueueStoring = PixelRetryQueueFileStore(),
         lastProcessingDateStorage: ThrowingKeyValueStoring = UserDefaults.standard,
         lastProcessingDateKey: String = Constants.lastProcessingDateKey,
         calendar: Calendar = .current,
         dateGenerator: @escaping () -> Date = Date.init) {
        self.underlyingFireRequest = fireRequest
        self.store = store
        self.lastProcessingDateStorage = lastProcessingDateStorage
        self.lastProcessingDateKey = lastProcessingDateKey
        self.calendar = calendar
        self.dateGenerator = dateGenerator
        self.lastProcessingDate = ((try? lastProcessingDateStorage.object(forKey: lastProcessingDateKey)) ?? nil) as? Date
    }

    /// The decorated closure PixelKit routes its fires through.
    var fireRequest: PixelKit.FireRequest {
        { [weak self] pixelName, headers, parameters, allowedChars, callBackOnMainThread, onComplete in
            guard let self else {
                onComplete(false, nil)
                return
            }
            self.underlyingFireRequest(pixelName, headers, parameters, allowedChars, callBackOnMainThread) { success, error in
                onComplete(success, error)
                if success {
                    self.sendQueuedPixels()
                } else {
                    self.enqueueFailedPixel(pixelName: pixelName,
                                            headers: headers,
                                            parameters: parameters,
                                            allowedQueryReservedCharacters: allowedChars)
                }
            }
        }
    }

    private func enqueueFailedPixel(pixelName: String,
                                    headers: [String: String],
                                    parameters: [String: String],
                                    allowedQueryReservedCharacters: CharacterSet?) {
        let now = dateGenerator()
        var parameters = parameters
        parameters[Parameters.originalPixelTimestamp] = dateFormatter.string(from: now)

        let item = PixelRetryQueueItem(pixelName: pixelName,
                                       headers: headers,
                                       parameters: parameters,
                                       allowedQueryReservedCharacters: allowedQueryReservedCharacters,
                                       timestamp: now)
        // Best-effort prune of already-expired items, so a long offline stretch (only failures, no drains)
        // can't keep known-dead pixels queued. Kept separate from the append below so a prune failure can
        // never prevent the new failed pixel from being queued for retry.
        if let cutoff = expiryCutoff(from: now) {
            do {
                let expiredIDs = Set(try store.storedItems().filter { $0.timestamp < cutoff }.map(\.id))
                if !expiredIDs.isEmpty {
                    try store.remove(itemsWithIDs: expiredIDs)
                }
            } catch {
                logger.error("Failed to prune expired pixels from the retry queue: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try store.append([item])
        } catch {
            logger.error("Failed to persist pixel \(pixelName, privacy: .public) for retry: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The cutoff date before which queued items are considered expired (older than `expiryDays`).
    private func expiryCutoff(from now: Date) -> Date? {
        calendar.date(byAdding: .day, value: -Constants.expiryDays, to: now)
    }

    /// Drains the queue: replays each item not older than 28 days through the underlying closure, drops
    /// expired items, and removes anything successfully sent. Throttled to `minimumProcessingInterval`.
    func sendQueuedPixels(completion: @escaping (PixelRetryQueueStorageError?) -> Void = { _ in }) {
        workQueue.async {
            if let lastProcessingDate = self.lastProcessingDate {
                let threshold = self.dateGenerator().addingTimeInterval(-Constants.minimumProcessingInterval)
                if threshold <= lastProcessingDate {
                    completion(nil)
                    return
                }
            }

            let queuedItems: [PixelRetryQueueItem]
            do {
                queuedItems = try self.store.storedItems()
            } catch {
                completion(.readError(error))
                return
            }

            guard !queuedItems.isEmpty else {
                completion(nil)
                return
            }

            // Advance the throttle only once there's work to process, so empty drains (the common case
            // after a successful send) don't block replay of failures queued shortly afterwards. The
            // in-memory value is the source of truth; the disk write is best-effort.
            let now = self.dateGenerator()
            self.lastProcessingDate = now
            try? self.lastProcessingDateStorage.set(now, forKey: self.lastProcessingDateKey)

            self.fire(queuedItems: queuedItems) { idsToRemove in
                do {
                    try self.store.remove(itemsWithIDs: idsToRemove)
                    completion(nil)
                } catch {
                    completion(.writeError(error))
                }
            }
        }
    }

    /// Replays the given items, calling back with the ids to remove (sent or expired).
    private func fire(queuedItems: [PixelRetryQueueItem], completion: @escaping (Set<UUID>) -> Void) {
        let dispatchGroup = DispatchGroup()
        let idsAccessQueue = DispatchQueue(label: "PixelKit Retry Queue IDs Access Queue")
        var idsToRemove: Set<UUID> = []
        let now = dateGenerator()
        let cutoff = expiryCutoff(from: now)

        for item in queuedItems {
            if let cutoff, item.timestamp < cutoff {
                idsAccessQueue.sync { _ = idsToRemove.insert(item.id) }
                continue
            }

            var parameters = item.parameters
            parameters[Parameters.retriedPixel] = "1"

            dispatchGroup.enter()
            underlyingFireRequest(item.pixelName, item.headers, parameters, item.allowedQueryReservedCharacters, false) { success, _ in
                if success {
                    idsAccessQueue.sync { _ = idsToRemove.insert(item.id) }
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .global()) {
            completion(idsToRemove)
        }
    }
}

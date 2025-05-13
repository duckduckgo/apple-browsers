//
//  PrivacyStats.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import CoreData
import Foundation
import os.log
import Persistence
import TrackerRadarKit

/**
 * Errors that may be reported by `PrivacyStats`.
 */
public enum PrivacyStatsError: CustomNSError {
    case failedToFetchPrivacyStatsSummary(Error)
    case failedToStorePrivacyStats(Error)
    case failedToClearPrivacyStats(Error)
    case failedToLoadCurrentPrivacyStats(Error)
    case failedToFetchPrivacyStatsTotalCount(Error)

    public static let errorDomain: String = "PrivacyStatsError"

    public var errorCode: Int {
        switch self {
        case .failedToFetchPrivacyStatsSummary:
            return 1
        case .failedToStorePrivacyStats:
            return 2
        case .failedToLoadCurrentPrivacyStats:
            return 3
        case .failedToClearPrivacyStats:
            return 4
        case .failedToFetchPrivacyStatsTotalCount:
            return 5
        }
    }

    public var errorUserInfo: [String: Any] {
        [NSUnderlyingErrorKey: underlyingError]
    }

    public var underlyingError: Error {
        switch self {
        case .failedToFetchPrivacyStatsSummary(let error),
                .failedToStorePrivacyStats(let error),
                .failedToLoadCurrentPrivacyStats(let error),
                .failedToClearPrivacyStats(let error),
                .failedToFetchPrivacyStatsTotalCount(let error):
            return error
        }
    }
}

/**
 * This protocol describes database provider consumed by `PrivacyStats`.
 */
public protocol PrivacyStatsDatabaseProviding {
    func initializeDatabase() -> CoreDataDatabase
}

/**
 * This protocol describes `PrivacyStats` interface.
 */
public protocol PrivacyStatsCollecting {

    /**
     * Record a tracker for a given `companyName`.
     *
     * `PrivacyStats` implementation calls the `CurrentPack` actor under the hood,
     * and as such it can safely be called on multiple threads concurrently.
     */
    func recordBlockedTracker(_ name: String) async

    /**
     * Publisher emitting values whenever updated privacy stats were persisted to disk.
     */
    var statsUpdatePublisher: AnyPublisher<Void, Never> { get }

    /**
     * This function fetches privacy stats in a dictionary format
     * with keys being company names and values being total number
     * of tracking attempts blocked in past 7 days.
     */
    func fetchPrivacyStats() async -> [String: Int64]

    func fetchPrivacyStatsTotalCount() async -> Int64

    /**
     * This function clears all blocked tracker stats from the database.
     */
    func clearPrivacyStats() async

    /**
     * This function saves all pending changes to the persistent storage.
     *
     * It should only be used in response to app termination because otherwise
     * the `PrivacyStats` object schedules persisting internally.
     */
    func handleAppTermination() async
}

public final class PrivacyStats: PrivacyStatsCollecting {

    public static let bundle = Bundle.module

    public let statsUpdatePublisher: AnyPublisher<Void, Never>

    private let db: CoreDataDatabase
    private let context: NSManagedObjectContext
    private let currentPack: CurrentPack
    private let statsUpdateSubject = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []

    private let errorEvents: EventMapping<PrivacyStatsError>?

    public init(databaseProvider: PrivacyStatsDatabaseProviding, errorEvents: EventMapping<PrivacyStatsError>? = nil) {
        self.db = databaseProvider.initializeDatabase()
        self.context = db.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "PrivacyStats")
        self.errorEvents = errorEvents
        self.currentPack = .init(pack: Self.initializeCurrentPack(in: context, errorEvents: errorEvents))
        statsUpdatePublisher = statsUpdateSubject.eraseToAnyPublisher()

        currentPack.commitChangesPublisher
            .sink { [weak self] pack in
                Task {
                    await self?.commitChanges(pack)
                }
            }
            .store(in: &cancellables)
    }

    public func recordBlockedTracker(_ companyName: String) async {
        await currentPack.recordBlockedTracker(companyName)
    }

    public func fetchPrivacyStats() async -> [String: Int64] {
        return await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume(returning: [:])
                    return
                }
                do {
                    let stats = try PrivacyStatsUtils.load7DayStats(in: context)
                    continuation.resume(returning: stats)
                } catch {
                    errorEvents?.fire(.failedToFetchPrivacyStatsSummary(error))
                    continuation.resume(returning: [:])
                }
            }
        }
    }

    public func fetchPrivacyStatsTotalCount() async -> Int64 {
        return await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume(returning: 0)
                    return
                }
                do {
                    let totalCount = try PrivacyStatsUtils.load7DaysTotalBlockedTrackersCount(in: context)
                    continuation.resume(returning: totalCount)
                } catch {
                    errorEvents?.fire(.failedToFetchPrivacyStatsTotalCount(error))
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    public func clearPrivacyStats() async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                do {
                    try PrivacyStatsUtils.deleteAllStats(in: context)
                    Logger.privacyStats.debug("Deleted outdated entries")
                } catch {
                    Logger.privacyStats.error("Save error: \(error)")
                    errorEvents?.fire(.failedToClearPrivacyStats(error))
                }
                continuation.resume()
            }
        }
        await currentPack.resetPack()
        statsUpdateSubject.send()
    }

    public func handleAppTermination() async {
        await commitChanges(currentPack.pack)
    }

    // MARK: - Private

    private func commitChanges(_ pack: PrivacyStatsPack) async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                // Check if the pack we're currently storing is from a previous day.
                let isCurrentDayPack = pack.timestamp == Date.currentPrivacyStatsPackTimestamp

                do {
                    let statsObjects = try PrivacyStatsUtils.fetchOrInsertCurrentStats(for: Set(pack.trackers.keys), in: context)
                    statsObjects.forEach { stats in
                        if let count = pack.trackers[stats.companyName] {
                            stats.count = count
                        }
                    }

                    guard context.hasChanges else {
                        continuation.resume()
                        return
                    }

                    try context.save()
                    Logger.privacyStats.debug("Saved stats \(pack.timestamp) \(pack.trackers)")

                    if isCurrentDayPack {
                        // Only emit update event when saving current-day pack. For previous-day pack,
                        // a follow-up commit event will come and we'll emit the update then.
                        statsUpdateSubject.send()
                    } else {
                        // When storing a pack from a previous day, we may have outdated packs, so delete them as needed.
                        try PrivacyStatsUtils.deleteOutdatedPacks(in: context)
                    }
                } catch {
                    Logger.privacyStats.error("Save error: \(error)")
                    errorEvents?.fire(.failedToStorePrivacyStats(error))
                }
                continuation.resume()
            }
        }
    }

    /**
     * This function is only called in the initializer. It performs a blocking call to the database
     * to spare us the hassle of declaring the initializer async or spawning tasks from within the
     * initializer without being able to await them, thus making testing trickier.
     */
    private static func initializeCurrentPack(in context: NSManagedObjectContext, errorEvents: EventMapping<PrivacyStatsError>?) -> PrivacyStatsPack {
        var pack: PrivacyStatsPack?
        context.performAndWait {
            let timestamp = Date.currentPrivacyStatsPackTimestamp
            do {
                let currentDayStats = try PrivacyStatsUtils.loadCurrentDayStats(in: context)
                Logger.privacyStats.debug("Loaded stats \(timestamp) \(currentDayStats)")
                pack = PrivacyStatsPack(timestamp: timestamp, trackers: currentDayStats)

                try PrivacyStatsUtils.deleteOutdatedPacks(in: context)
            } catch {
                Logger.privacyStats.error("Failed to load current stats: \(error)")
                errorEvents?.fire(.failedToLoadCurrentPrivacyStats(error))
            }
        }
        return pack ?? PrivacyStatsPack(timestamp: Date.currentPrivacyStatsPackTimestamp)
    }
}

//
//  AutoconsentStats.swift
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
import Persistence
import Common
import Combine

/**
 * Errors that may be reported by `AutoconsentStats`.
 */
public enum AutoconsentStatsError: CustomNSError {
    case failedToRecordAutoconsentAction(Error)
    case failedToFetchTotalCookiePopUpsBlocked(Error)
    case failedToFetchTotalClicksMadeBlockingCookiePopUps(Error)
    case failedToFetchTotalTimeSpentBlockingCookiePopUps(Error)
    case failedToClearAutoconsentStats(Error)

    public static let errorDomain: String = "AutoconsentStatsError"

    public var errorCode: Int {
        switch self {
        case .failedToRecordAutoconsentAction:
            return 1
        case .failedToFetchTotalCookiePopUpsBlocked:
            return 2
        case .failedToFetchTotalClicksMadeBlockingCookiePopUps:
            return 3
        case .failedToFetchTotalTimeSpentBlockingCookiePopUps:
            return 4
        case .failedToClearAutoconsentStats:
            return 5
        }
    }

    public var errorUserInfo: [String: Any] {
        [NSUnderlyingErrorKey: underlyingError]
    }

    public var underlyingError: Error {
        switch self {
        case .failedToRecordAutoconsentAction(let error),
                .failedToFetchTotalCookiePopUpsBlocked(let error),
                .failedToFetchTotalClicksMadeBlockingCookiePopUps(let error),
                .failedToFetchTotalTimeSpentBlockingCookiePopUps(let error),
                .failedToClearAutoconsentStats(let error):
            return error
        }
    }
}

public protocol AutoconsentStatsCollecting {
    /**
     * Record an autoconsent action with interaction metrics.
     * - Parameters:
     *   - clicksMade: The number of clicks made during the autoconsent interaction
     *   - timeSpent: The time spent handling the autoconsent interaction
     */
    func recordAutoconsentAction(clicksMade: Int64, timeSpent: TimeInterval) async

    /**
     * Publisher emitting values whenever the autoconsent stats were updated.
     */
    var statsUpdatePublisher: AnyPublisher<Void, Never> { get }

    /**
     * This function fetches total count of cookie pop ups blocked.
     */
    func fetchTotalCookiePopUpsBlocked() async -> Int64

    /**
     * This function fetches the daily usage pack containing all autoconsent statistics.
     */
    func fetchAutoconsentDailyUsagePack() async -> AutoconsentDailyUsagePack

    /**
     * This function clears all autoconsent stats from the storage.
     */
    func clearAutoconsentStats() async

    /**
     * Is stats collecting enabled.
     */
    func isEnabled() async -> Bool
}

public actor AutoconsentStats: AutoconsentStatsCollecting {

    public enum Constants {
        public static let totalCookiePopUpsBlockedKey = "com.duckduckgo.autoconsent.cookie.popups.blocked"
        public static let totalClicksMadeBlockingCookiePopUpsKey = "com.duckduckgo.autoconsent.clicks.made"
        public static let totalTimeSpentBlockingCookiePopUpsKey = "com.duckduckgo.autoconsent.time.spent"
    }

    public nonisolated let statsUpdatePublisher: AnyPublisher<Void, Never>
    private nonisolated let statsUpdateSubject = PassthroughSubject<Void, Never>()

    private let keyValueStore: ThrowingKeyValueStoring
    private let errorEvents: EventMapping<AutoconsentStatsError>?
    private let isFeatureEnabled: () -> Bool

    public init(keyValueStore: ThrowingKeyValueStoring,
                errorEvents: EventMapping<AutoconsentStatsError>? = nil,
                isFeatureEnabled: @escaping @Sendable () -> Bool) {
        self.keyValueStore = keyValueStore
        self.errorEvents = errorEvents
        self.isFeatureEnabled = isFeatureEnabled
        statsUpdatePublisher = statsUpdateSubject.eraseToAnyPublisher()
    }

    public func recordAutoconsentAction(clicksMade: Int64, timeSpent: TimeInterval) async {
        do {
            let currentStats = await fetchAutoconsentDailyUsagePack()

            let newTotalCookiePopUpsBlocked = currentStats.totalCookiePopUpsBlocked + 1
            try keyValueStore.set(newTotalCookiePopUpsBlocked, forKey: Constants.totalCookiePopUpsBlockedKey)

            let newTotalClicks = currentStats.totalClicksMadeBlockingCookiePopUps + clicksMade
            try keyValueStore.set(newTotalClicks, forKey: Constants.totalClicksMadeBlockingCookiePopUpsKey)

            let newTotalTimeSpent = currentStats.totalTotalTimeSpentBlockingCookiePopUps + timeSpent
            try keyValueStore.set(newTotalTimeSpent, forKey: Constants.totalTimeSpentBlockingCookiePopUpsKey)
        } catch {
            errorEvents?.fire(.failedToRecordAutoconsentAction(error))
        }

        statsUpdateSubject.send()
    }

    public func fetchTotalCookiePopUpsBlocked() async -> Int64 {
        do {
            if let value = try keyValueStore.object(forKey: Constants.totalCookiePopUpsBlockedKey) as? Int64 {
                return value
            }
            return 0
        } catch {
            errorEvents?.fire(.failedToFetchTotalCookiePopUpsBlocked(error))
            return 0
        }
    }

    private func fetchTotalClicksMadeBlockingCookiePopUps() async -> Int64 {
        do {
            if let value = try keyValueStore.object(forKey: Constants.totalClicksMadeBlockingCookiePopUpsKey) as? Int64 {
                return value
            }
            return 0
        } catch {
            errorEvents?.fire(.failedToFetchTotalClicksMadeBlockingCookiePopUps(error))
            return 0
        }
    }

    private func fetchTotalTotalTimeSpentBlockingCookiePopUps() async -> TimeInterval {
        do {
            if let value = try keyValueStore.object(forKey: Constants.totalTimeSpentBlockingCookiePopUpsKey) as? TimeInterval {
                return value
            }
            return 0
        } catch {
            errorEvents?.fire(.failedToFetchTotalTimeSpentBlockingCookiePopUps(error))
            return 0
        }
    }

    public func fetchAutoconsentDailyUsagePack() async -> AutoconsentDailyUsagePack {
        let totalCookiePopUpsBlocked = await fetchTotalCookiePopUpsBlocked()
        let totalClicksMade = await fetchTotalClicksMadeBlockingCookiePopUps()
        let totalTimeSpent = await fetchTotalTotalTimeSpentBlockingCookiePopUps()

        return AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: totalCookiePopUpsBlocked,
            totalClicksMadeBlockingCookiePopUps: totalClicksMade,
            totalTotalTimeSpentBlockingCookiePopUps: totalTimeSpent
        )
    }

    public func clearAutoconsentStats() async {
        do {
            try keyValueStore.removeObject(forKey: Constants.totalCookiePopUpsBlockedKey)
            try keyValueStore.removeObject(forKey: Constants.totalClicksMadeBlockingCookiePopUpsKey)
            try keyValueStore.removeObject(forKey: Constants.totalTimeSpentBlockingCookiePopUpsKey)
        } catch {
            errorEvents?.fire(.failedToClearAutoconsentStats(error))
        }

        statsUpdateSubject.send()
    }

    public func isEnabled() async -> Bool {
        isFeatureEnabled()
    }
}

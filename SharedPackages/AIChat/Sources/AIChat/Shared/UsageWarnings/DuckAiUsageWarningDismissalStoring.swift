//
//  DuckAiUsageWarningDismissalStoring.swift
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

/// Scoped to one window's reset period and ladder rung, like web's `duckaiUsageLimitBannerDismissal`,
/// so the message comes back once `resetsAt` moves on or usage climbs to the next rung.
public struct DuckAiUsageWarningDismissal: Equatable, Codable {

    /// Raw, so a message web adds later can still be recorded as dismissed.
    public let noticeID: String

    /// Whole seconds: this is compared for equality, and `Codable` can drift a `Date`.
    public let resetsAtEpochSeconds: Int

    public let threshold: Int

    public init(noticeID: String, resetsAt: Date, threshold: Int) {
        self.noticeID = noticeID
        self.resetsAtEpochSeconds = Self.epochSeconds(for: resetsAt)
        self.threshold = threshold
    }

    public init(notice: DuckAiUsageNotice) {
        self.init(noticeID: notice.id.rawValue,
                  resetsAt: notice.resetsAt,
                  threshold: notice.window.redisplayThreshold(forPercent: notice.percentUsed))
    }

    public func applies(to notice: DuckAiUsageNotice) -> Bool {
        noticeID == notice.id.rawValue
            && resetsAtEpochSeconds == Self.epochSeconds(for: notice.resetsAt)
            && notice.window.redisplayThreshold(forPercent: notice.percentUsed) <= threshold
    }

    private static func epochSeconds(for date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }
}

extension DuckAiUsageWindow {

    /// Web's `redisplayByWindow`. Web keeps sending `approaching` all the way to 99%, so without it a
    /// message dismissed at 50% would stay hidden until the reset.
    var redisplayLadder: [Int] {
        switch self {
        case .daily: return [50, 90, 100]
        case .weekly: return [50, 75, 90, 100]
        }
    }

    func redisplayThreshold(forPercent percent: Int) -> Int {
        redisplayLadder.last { percent >= $0 } ?? 0
    }
}

/// The contract's rule: do not re-show a notice the user acted on until `usageLimits` itself changes.
public struct DuckAiUsageWarningActedSnapshot: Equatable, Codable {

    public let noticeID: String
    public let signature: String

    public init(noticeID: String, signature: String) {
        self.noticeID = noticeID
        self.signature = signature
    }

    /// An unsigned snapshot can't be compared, and showing the message again is the safe failure.
    public func applies(to notice: DuckAiUsageNotice, signature: String?) -> Bool {
        guard let signature else { return false }
        return noticeID == notice.id.rawValue && self.signature == signature
    }
}

public protocol DuckAiUsageWarningDismissalStoring {
    func dismissal(for window: DuckAiUsageWindow) -> DuckAiUsageWarningDismissal?
    func setDismissal(_ dismissal: DuckAiUsageWarningDismissal?, for window: DuckAiUsageWindow)
    func actedSnapshot() -> DuckAiUsageWarningActedSnapshot?
    func setActedSnapshot(_ actedSnapshot: DuckAiUsageWarningActedSnapshot?)
}

public struct DuckAiUsageWarningDismissalStore: DuckAiUsageWarningDismissalStoring {

    private enum Key: String {
        // One per window, so dismissing the daily message can't bring back a weekly one.
        case dailyDismissal = "aichat.usage-warning.dismissal.daily"
        case weeklyDismissal = "aichat.usage-warning.dismissal.weekly"
        case actedSnapshot = "aichat.usage-warning.acted-snapshot"

        static func dismissal(for window: DuckAiUsageWindow) -> Self {
            switch window {
            case .daily: return .dailyDismissal
            case .weekly: return .weeklyDismissal
            }
        }
    }

    private let keyValueStore: ThrowingKeyValueStoring

    public init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    public func dismissal(for window: DuckAiUsageWindow) -> DuckAiUsageWarningDismissal? {
        read(DuckAiUsageWarningDismissal.self, forKey: .dismissal(for: window))
    }

    public func setDismissal(_ dismissal: DuckAiUsageWarningDismissal?, for window: DuckAiUsageWindow) {
        write(dismissal, forKey: .dismissal(for: window))
    }

    public func actedSnapshot() -> DuckAiUsageWarningActedSnapshot? {
        read(DuckAiUsageWarningActedSnapshot.self, forKey: .actedSnapshot)
    }

    public func setActedSnapshot(_ actedSnapshot: DuckAiUsageWarningActedSnapshot?) {
        write(actedSnapshot, forKey: .actedSnapshot)
    }

    /// Undecodable reads as absent: showing the message again is the safe failure.
    private func read<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        guard let data = try? keyValueStore.object(forKey: key.rawValue) as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T?, forKey key: Key) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            try? keyValueStore.removeObject(forKey: key.rawValue)
            return
        }
        try? keyValueStore.set(data, forKey: key.rawValue)
    }
}

/// For tests and any caller that wants dismissals to die with the session.
public final class InMemoryDuckAiUsageWarningDismissalStore: DuckAiUsageWarningDismissalStoring {

    private var storedDismissals: [DuckAiUsageWindow: DuckAiUsageWarningDismissal] = [:]
    private var storedActedSnapshot: DuckAiUsageWarningActedSnapshot?

    public init() {}

    public func dismissal(for window: DuckAiUsageWindow) -> DuckAiUsageWarningDismissal? { storedDismissals[window] }

    public func setDismissal(_ dismissal: DuckAiUsageWarningDismissal?, for window: DuckAiUsageWindow) {
        storedDismissals[window] = dismissal
    }

    public func actedSnapshot() -> DuckAiUsageWarningActedSnapshot? { storedActedSnapshot }

    public func setActedSnapshot(_ actedSnapshot: DuckAiUsageWarningActedSnapshot?) {
        storedActedSnapshot = actedSnapshot
    }
}

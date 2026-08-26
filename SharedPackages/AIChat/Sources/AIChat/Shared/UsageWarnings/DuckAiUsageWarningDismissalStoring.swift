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

/// A dismissed notice, scoped to the reset period it was dismissed in: once `resetsAt` moves on the
/// record is stale and the message comes back. Native equivalent of web's `duckaiUsageLimitBannerDismissal`.
public struct DuckAiUsageWarningDismissal: Equatable, Codable {

    /// The raw notice id, so a message web adds later can still be recorded as dismissed.
    public let noticeID: String

    /// Whole seconds, not a `Date`: this is compared for exact equality, and `Codable` can drift a
    /// `Date` by a fraction of a second.
    public let resetsAtEpochSeconds: Int

    public init(noticeID: String, resetsAt: Date) {
        self.noticeID = noticeID
        self.resetsAtEpochSeconds = Self.epochSeconds(for: resetsAt)
    }

    public init(notice: DuckAiUsageNotice) {
        self.init(noticeID: notice.id.rawValue, resetsAt: notice.resetsAt)
    }

    public func applies(to notice: DuckAiUsageNotice) -> Bool {
        noticeID == notice.id.rawValue && resetsAtEpochSeconds == Self.epochSeconds(for: notice.resetsAt)
    }

    private static func epochSeconds(for date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }
}

/// The notice whose CTA the user has already run, against the exact snapshot it was offered from.
/// The contract's rule: do not re-show until `usageLimits` itself changes.
public struct DuckAiUsageWarningActedSnapshot: Equatable, Codable {

    public let noticeID: String
    public let signature: String

    public init(noticeID: String, signature: String) {
        self.noticeID = noticeID
        self.signature = signature
    }

    /// An unsigned snapshot can't be compared, so it is never suppressed — showing the message again
    /// is the safe failure.
    public func applies(to notice: DuckAiUsageNotice, signature: String?) -> Bool {
        guard let signature else { return false }
        return noticeID == notice.id.rawValue && self.signature == signature
    }
}

public protocol DuckAiUsageWarningDismissalStoring {
    func dismissal() -> DuckAiUsageWarningDismissal?
    func setDismissal(_ dismissal: DuckAiUsageWarningDismissal?)
    func actedSnapshot() -> DuckAiUsageWarningActedSnapshot?
    func setActedSnapshot(_ actedSnapshot: DuckAiUsageWarningActedSnapshot?)
}

public struct DuckAiUsageWarningDismissalStore: DuckAiUsageWarningDismissalStoring {

    private enum Key: String {
        // One notice at a time, so a single key replaces the earlier per-window pair.
        case dismissal = "aichat.usage-warning.dismissal"
        case actedSnapshot = "aichat.usage-warning.acted-snapshot"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    public init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    public func dismissal() -> DuckAiUsageWarningDismissal? {
        read(DuckAiUsageWarningDismissal.self, forKey: .dismissal)
    }

    public func setDismissal(_ dismissal: DuckAiUsageWarningDismissal?) {
        write(dismissal, forKey: .dismissal)
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

    private var storedDismissal: DuckAiUsageWarningDismissal?
    private var storedActedSnapshot: DuckAiUsageWarningActedSnapshot?

    public init() {}

    public func dismissal() -> DuckAiUsageWarningDismissal? { storedDismissal }

    public func setDismissal(_ dismissal: DuckAiUsageWarningDismissal?) { storedDismissal = dismissal }

    public func actedSnapshot() -> DuckAiUsageWarningActedSnapshot? { storedActedSnapshot }

    public func setActedSnapshot(_ actedSnapshot: DuckAiUsageWarningActedSnapshot?) {
        storedActedSnapshot = actedSnapshot
    }
}

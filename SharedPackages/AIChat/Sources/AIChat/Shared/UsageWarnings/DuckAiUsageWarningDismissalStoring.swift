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

/// Scoped to one window *and* one reset period: once `resetsAt` moves on, the record is stale and the
/// message comes back. Native equivalent of web's `duckaiUsageLimitBannerDismissal`.
public struct DuckAiUsageWarningDismissal: Equatable, Codable {

    /// Whole seconds, not a `Date`: this is compared for exact equality, and `Codable` can drift a
    /// `Date` by a fraction of a second.
    public let resetsAtEpochSeconds: Int

    public let threshold: Int

    public init(resetsAt: Date, threshold: Int) {
        self.resetsAtEpochSeconds = Self.epochSeconds(for: resetsAt)
        self.threshold = threshold
    }

    public func applies(to resetsAt: Date) -> Bool {
        resetsAtEpochSeconds == Self.epochSeconds(for: resetsAt)
    }

    private static func epochSeconds(for date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }
}

public protocol DuckAiUsageWarningDismissalStoring {
    func dismissal(for window: DuckAiUsageWindow) -> DuckAiUsageWarningDismissal?
    func setDismissal(_ dismissal: DuckAiUsageWarningDismissal?, for window: DuckAiUsageWindow)
}

public struct DuckAiUsageWarningDismissalStore: DuckAiUsageWarningDismissalStoring {

    private enum Key: String {
        case daily = "aichat.usage-warning.dismissal.daily"
        case weekly = "aichat.usage-warning.dismissal.weekly"

        init(_ window: DuckAiUsageWindow) {
            switch window {
            case .daily: self = .daily
            case .weekly: self = .weekly
            }
        }
    }

    private let keyValueStore: ThrowingKeyValueStoring

    public init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    public func dismissal(for window: DuckAiUsageWindow) -> DuckAiUsageWarningDismissal? {
        guard let data = try? keyValueStore.object(forKey: Key(window).rawValue) as? Data else { return nil }
        // Undecodable reads as not-dismissed: showing the message again is the safe failure.
        return try? JSONDecoder().decode(DuckAiUsageWarningDismissal.self, from: data)
    }

    public func setDismissal(_ dismissal: DuckAiUsageWarningDismissal?, for window: DuckAiUsageWindow) {
        let key = Key(window).rawValue
        guard let dismissal, let data = try? JSONEncoder().encode(dismissal) else {
            try? keyValueStore.removeObject(forKey: key)
            return
        }
        try? keyValueStore.set(data, forKey: key)
    }
}

/// Burner surfaces: a dismissal must not outlive the session it was made in.
public final class InMemoryDuckAiUsageWarningDismissalStore: DuckAiUsageWarningDismissalStoring {

    private var dismissals: [DuckAiUsageWindow: DuckAiUsageWarningDismissal] = [:]

    public init() {}

    public func dismissal(for window: DuckAiUsageWindow) -> DuckAiUsageWarningDismissal? {
        dismissals[window]
    }

    public func setDismissal(_ dismissal: DuckAiUsageWarningDismissal?, for window: DuckAiUsageWindow) {
        dismissals[window] = dismissal
    }
}

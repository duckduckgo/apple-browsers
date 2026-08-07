//
//  SubscriptionOnboardingProgressStore.swift
//  DuckDuckGo
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
import os.log

/// Persisted onboarding progress.
///
/// Checklist *items* are stored rather than sections, so re-ordering or re-slicing the flow's sections never
/// migrates anyone's saved progress.
protocol SubscriptionOnboardingProgressStoring {
    var completedItems: Set<SubscriptionOnboardingChecklistItem> { get set }
    /// When the Subscription Settings card was first shown, which starts its 14-day window.
    var cardFirstShownDate: Date? { get set }
    /// When the checklist first reached 100%. The card survives until the next launch after this, so the
    /// customer sees their own completion rather than the card vanishing under their finger.
    var fullyCompletedAt: Date? { get set }
}

/// Process-scoped: whether the checklist was finished during *this* run of the app.
///
/// Deliberately a flag and not a launch timestamp. A `static let Date()` is initialised lazily on first
/// access, which here is inside the very comparison that uses it — so it lands *after* the completion it is
/// meant to predate, and the card disappears the instant the customer reaches 100%.
enum SubscriptionOnboardingSession {
    fileprivate(set) static var didCompleteDuringThisSession = false
}

extension SubscriptionOnboardingProgressStoring {
    /// Records completion the first time it is seen, then reports whether the card should still show.
    /// True while the checklist is unfinished, and for the rest of the session in which it was finished.
    mutating func shouldShowSetupCard(percentage: Int, now: Date) -> Bool {
        guard percentage >= 100 else { return true }
        if fullyCompletedAt == nil {
            fullyCompletedAt = now
            SubscriptionOnboardingSession.didCompleteDuringThisSession = true
        }
        return SubscriptionOnboardingSession.didCompleteDuringThisSession
    }

    mutating func markComplete(_ item: SubscriptionOnboardingChecklistItem) {
        guard !completedItems.contains(item) else { return }
        completedItems.insert(item)
    }

    /// First write wins, so the 14-day window is anchored to the first display and not extended by later ones.
    mutating func recordCardFirstShownIfNeeded(now: Date) {
        guard cardFirstShownDate == nil else { return }
        cardFirstShownDate = now
    }
}

struct SubscriptionOnboardingProgressStore: SubscriptionOnboardingProgressStoring {

    enum Key: String {
        case completedItems = "subscription.onboarding.completed-items"
        case cardFirstShownDate = "subscription.onboarding.card-first-shown-date"
        case fullyCompletedAt = "subscription.onboarding.fully-completed-at"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    /// Unrecognised raw values are dropped rather than failing the whole read, so a downgrade after a new
    /// checklist item ships leaves the remaining progress intact.
    var completedItems: Set<SubscriptionOnboardingChecklistItem> {
        get {
            let stored = read(.completedItems) as? [String] ?? []
            return Set(stored.compactMap(SubscriptionOnboardingChecklistItem.init(rawValue:)))
        }
        set { write(newValue.map(\.rawValue).sorted(), for: .completedItems) }
    }

    var cardFirstShownDate: Date? {
        get { read(.cardFirstShownDate) as? Date }
        set { write(newValue, for: .cardFirstShownDate) }
    }

    var fullyCompletedAt: Date? {
        get { read(.fullyCompletedAt) as? Date }
        set { write(newValue, for: .fullyCompletedAt) }
    }
}

// MARK: - Storage

/// A failed read makes a customer look like they made no progress; a failed write silently loses a step they
/// just completed. Neither is worth blocking the flow over, but both are worth being able to see.
private extension SubscriptionOnboardingProgressStore {

    func read(_ key: Key) -> Any? {
        do {
            return try keyValueStore.object(forKey: key.rawValue)
        } catch {
            Logger.subscription.error("Onboarding progress read failed for \(key.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func write(_ value: Any?, for key: Key) {
        do {
            if let value {
                try keyValueStore.set(value, forKey: key.rawValue)
            } else {
                try keyValueStore.removeObject(forKey: key.rawValue)
            }
        } catch {
            Logger.subscription.error("Onboarding progress write failed for \(key.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

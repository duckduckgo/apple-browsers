//
//  SubscriptionOnboardingProgress.swift
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

/// Storage for onboarding progress. Reads and writes only — no rules about what the values mean.
protocol SubscriptionOnboardingProgressPersisting {
    var completedItems: Set<SubscriptionOnboardingChecklistItem> { get set }
    /// When the Subscription Settings card was first shown, which starts its 14-day window.
    var cardFirstShownDate: Date? { get set }
    /// When the checklist first reached 100%.
    var fullyCompletedAt: Date? { get set }
}

extension SubscriptionOnboardingProgressPersisting {

    mutating func markComplete(_ item: SubscriptionOnboardingChecklistItem) {
        guard !completedItems.contains(item) else { return }
        completedItems.insert(item)
    }

    /// First write wins, so a later display cannot extend the 14-day window.
    mutating func recordCardFirstShownIfNeeded(now: Date) {
        guard cardFirstShownDate == nil else { return }
        cardFirstShownDate = now
    }
}

struct SubscriptionOnboardingProgressPersistor: SubscriptionOnboardingProgressPersisting {

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

// MARK: - Progress

/// This customer's checklist and how much of it they have completed.
///
/// Every reader goes through this — the flow, the progress screen and the Subscription Settings card — so
/// none of them can disagree about a customer's completion.
struct SubscriptionOnboardingProgress {

    /// Four items when PIR is unreachable, so that customer's ceiling is still 100%.
    let checklistItems: [SubscriptionOnboardingChecklistItem]

    private var persistor: SubscriptionOnboardingProgressPersisting

    init(persistor: SubscriptionOnboardingProgressPersisting, isPIRAvailable: Bool) {
        self.persistor = persistor
        self.checklistItems = SubscriptionOnboardingChecklistItem.checklist(isPIRAvailable: isPIRAvailable)
    }

    /// Read on demand, since items complete outside whatever screen is asking.
    var completedItems: Set<SubscriptionOnboardingChecklistItem> {
        persistor.completedItems
    }

    var percentage: Int {
        SubscriptionOnboardingChecklistItem.completionPercentage(completed: completedItems,
                                                                checklist: checklistItems)
    }

    mutating func markComplete(_ item: SubscriptionOnboardingChecklistItem) {
        persistor.markComplete(item)
    }

    /// The card stays up for the rest of the run in which the checklist was finished and goes on the next
    /// launch, which is what `session` being held in memory rather than stored buys.
    mutating func shouldShowSetupCard(now: Date, session: SubscriptionOnboardingSessionStating) -> Bool {
        guard percentage >= 100 else { return true }
        if persistor.fullyCompletedAt == nil {
            persistor.fullyCompletedAt = now
            session.recordCompletedDuringThisSession()
        }
        return session.didCompleteDuringThisSession
    }
}

extension SubscriptionOnboardingProgress {

    /// Fixed progress with no storage behind it, for previews and debug rows.
    init(completedItems: Set<SubscriptionOnboardingChecklistItem>, isPIRAvailable: Bool = true) {
        self.init(persistor: FixedPersistor(completedItems: completedItems), isPIRAvailable: isPIRAvailable)
    }

    private struct FixedPersistor: SubscriptionOnboardingProgressPersisting {
        var completedItems: Set<SubscriptionOnboardingChecklistItem>
        var cardFirstShownDate: Date?
        var fullyCompletedAt: Date?
    }
}

// MARK: - Storage

/// A failed read makes a customer look like they made no progress; a failed write silently loses a step.
private extension SubscriptionOnboardingProgressPersistor {

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

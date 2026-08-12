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
import FoundationExtensions
import Persistence
import os.log

/// Serializes the read-decide-write sequences below across every `SubscriptionOnboardingProgressPersisting`
/// conformer.
private let progressLock = NSLock()

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
        progressLock.lock()
        defer { progressLock.unlock() }
        guard !completedItems.contains(item) else { return }
        completedItems.insert(item)
    }

    /// First write wins, so a later display cannot extend the 14-day window.
    mutating func recordCardFirstShownIfNeeded(now: Date) {
        progressLock.lock()
        defer { progressLock.unlock() }
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

    /// How long the Subscription Settings card lives, measured from its first display.
    private static let cardLifetime: TimeInterval = .days(14)

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

    /// - On reaching 100% the card stays up for the rest of that run and goes on the next launch
    /// - It expires 14 days after it first appeared, whether or not the customer finished.
    mutating func shouldShowSetupCard(now: Date, session: SubscriptionOnboardingSessionStating) -> Bool {
        if percentage >= 100 {
            let wasAlreadyComplete: Bool
            do {
                progressLock.lock()
                defer { progressLock.unlock() }
                wasAlreadyComplete = persistor.fullyCompletedAt != nil
                if !wasAlreadyComplete {
                    persistor.fullyCompletedAt = now
                }
            }

            if !wasAlreadyComplete {
                session.recordCompletedDuringThisSession()
            }
            guard session.didCompleteDuringThisSession else { return false }
        }

        persistor.recordCardFirstShownIfNeeded(now: now)
        return isWithinCardLifetime(now: now)
    }

    // A failed write leaves no anchor to measure from; but showing the card beats hiding it forever.
    private func isWithinCardLifetime(now: Date) -> Bool {
        guard let firstShown = persistor.cardFirstShownDate else { return true }
        return now.timeIntervalSince(firstShown) < Self.cardLifetime
    }

    /// A read-only preview of ``shouldShowSetupCard(now:session:)`` from whatever is already persisted —
    /// never writes. Safe to call from a View `init` to seed `@State`; `.onAppear`'s `refresh()` then calls
    /// the real, write-performing decision once the view has actually appeared.
    func previewShouldShowSetupCard(now: Date, session: SubscriptionOnboardingSessionStating) -> Bool {
        if percentage >= 100 {
            guard session.didCompleteDuringThisSession else { return false }
        }
        return isWithinCardLifetime(now: now)
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

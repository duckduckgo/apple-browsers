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

/// Serializes the read-decide-write sequences below across every `SubscriptionOnboardingProgressPersisting` conformer.
private let progressLock = NSLock()

/// Storage for onboarding progress. Reads and writes only — no rules about what the values mean.
protocol SubscriptionOnboardingProgressPersisting {
    var completedItems: Set<SubscriptionOnboardingChecklistItem> { get set }
    /// When the Subscription Settings card was first shown, which starts its 14-day window.
    var cardFirstShownDate: Date? { get set }
    /// When the checklist first reached 100%.
    var fullyCompletedAt: Date? { get set }
    /// How many times the card has been shown since reaching 100%, for the 2-view cap.
    var completionViewCount: Int { get set }
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

    mutating func recordCompletionView() {
        progressLock.lock()
        defer { progressLock.unlock() }
        completionViewCount += 1
    }

    mutating func recordFullyCompletedIfNeeded(now: Date) -> Bool {
        progressLock.lock()
        defer { progressLock.unlock() }
        guard fullyCompletedAt == nil else { return false }
        fullyCompletedAt = now
        return true
    }
}

struct SubscriptionOnboardingProgressPersistor: SubscriptionOnboardingProgressPersisting {

    enum Key: String {
        case completedItems = "subscription.onboarding.completed-items"
        case cardFirstShownDate = "subscription.onboarding.card-first-shown-date"
        case fullyCompletedAt = "subscription.onboarding.fully-completed-at"
        case completionViewCount = "subscription.onboarding.completion-view-count"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    /// Unrecognised raw values are dropped rather than failing the whole read, so a downgrade after a new checklist item ships leaves the remaining progress intact.
    var completedItems: Set<SubscriptionOnboardingChecklistItem> {
        get {
            let stored: [String] = read(.completedItems) ?? []
            return Set(stored.compactMap(SubscriptionOnboardingChecklistItem.init(rawValue:)))
        }
        set { write(newValue.map(\.rawValue).sorted(), for: .completedItems) }
    }

    var cardFirstShownDate: Date? {
        get { read(.cardFirstShownDate) }
        set { write(newValue, for: .cardFirstShownDate) }
    }

    var fullyCompletedAt: Date? {
        get { read(.fullyCompletedAt) }
        set { write(newValue, for: .fullyCompletedAt) }
    }

    var completionViewCount: Int {
        get { read(.completionViewCount) ?? 0 }
        set { write(newValue, for: .completionViewCount) }
    }
}

// MARK: - Progress

/// This customer's checklist and how much of it they have completed; every reader (flow, progress screen, settings card) goes through this so none of them can disagree.
struct SubscriptionOnboardingProgress {

    /// How long the Subscription Settings card lives, measured from its first display.
    private static let cardLifetime: TimeInterval = .days(14)

    /// Once complete, the card is shown at most this many times before it's hidden for good.
    private static let maxCompletionViews = 2

    /// This run's checklist
    let checklist: [SubscriptionOnboardingChecklistItem]

    private var persistor: SubscriptionOnboardingProgressPersisting

    init(persistor: SubscriptionOnboardingProgressPersisting, isPIRAvailable: Bool) {
        self.persistor = persistor
        self.checklist = SubscriptionOnboardingChecklistItem.checklist(isPIRAvailable: isPIRAvailable)
    }

    /// Read on demand, since items complete outside whatever screen is asking.
    var completedItems: Set<SubscriptionOnboardingChecklistItem> {
        persistor.completedItems
    }

    var percentage: Int {
        SubscriptionOnboardingChecklistItem.completionPercentage(completed: completedItems,
                                                                checklist: checklist)
    }

    mutating func markComplete(_ item: SubscriptionOnboardingChecklistItem) {
        persistor.markComplete(item)
    }

    /// Stays up for the rest of the run once complete, capped at 2 views total once complete, and expires 14 days after it first appeared regardless.
    mutating func shouldShowSetupCard(now: Date, session: SubscriptionOnboardingSessionStateManaging) -> Bool {
        let isComplete = percentage >= 100
        if isComplete {
            if persistor.recordFullyCompletedIfNeeded(now: now) {
                session.recordCompletedDuringThisSession()
            }
            guard isWithinCompletionCriteria(session: session) else { return false }
        }

        persistor.recordCardFirstShownIfNeeded(now: now)
        guard isWithinCardLifetime(now: now) else { return false }

        if isComplete {
            persistor.recordCompletionView()
        }
        return true
    }

    /// The session latch and view cap, evaluated together since both callers below need the same pair. Read-only.
    private func isWithinCompletionCriteria(session: SubscriptionOnboardingSessionStateManaging) -> Bool {
        session.didCompleteDuringThisSession && persistor.completionViewCount < Self.maxCompletionViews
    }

    // A failed write leaves no anchor to measure from; but showing the card beats hiding it forever.
    private func isWithinCardLifetime(now: Date) -> Bool {
        guard let firstShown = persistor.cardFirstShownDate else { return true }
        return now.timeIntervalSince(firstShown) < Self.cardLifetime
    }

    /// A non-writing preview of ``shouldShowSetupCard(now:session:)``, safe to call from a View `init`.
    func previewShouldShowSetupCard(now: Date, session: SubscriptionOnboardingSessionStateManaging) -> Bool {
        if percentage >= 100 {
            guard isWithinCompletionCriteria(session: session) else { return false }
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
        var completionViewCount: Int = 0
    }
}

// MARK: - Storage

/// A failed read makes a customer look like they made no progress; a failed write silently loses a step.
private extension SubscriptionOnboardingProgressPersistor {

    func read<T>(_ key: Key) -> T? {
        do {
            return try keyValueStore.object(forKey: key.rawValue) as? T
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

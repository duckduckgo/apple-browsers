//
//  AppRatingPromptCoordinator.swift
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

/// Persisted state for the App Store rating prompt's participation in the Promo Queue.
struct AppRatingPromptSlotStore {

    enum StorageKey: String {
        case unredeemedSlotCount = "com.duckduckgo.app-rating-prompt.unredeemed-slot-count"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    /// Consecutive foregrounds that took the slot without a search following.
    var unredeemedSlotCount: Int {
        get { (try? keyValueStore.object(forKey: StorageKey.unredeemedSlotCount.rawValue)) as? Int ?? 0 }
        nonmutating set { try? keyValueStore.set(newValue, forKey: StorageKey.unredeemedSlotCount.rawValue) }
    }
}

/// The search-time half of the rating prompt, used by `PromoCoordinationService`.
///
/// The prompt is evaluated at foreground but fires on search, so it is split across
/// `ModalPromptProvider` (foreground) and this protocol (search time).
@MainActor
protocol AppRatingPromptCoordinating: AnyObject {
    /// Whether the prompt participates in the Promo Queue. Already accounts for the queue's own
    /// mode, so callers need not check it.
    var isCoordinationEnabled: Bool { get }

    /// Records a page load towards the unique-usage-day counter. Every page, not only searches.
    func registerUsage()

    /// Whether to request the dialog uncoordinated, used when coordination is off.
    func shouldRequestUncoordinated() -> Bool

    /// The dialog was requested. Consumes the prompt's eligibility.
    func didRequestRating()

    /// Consecutive foregrounds that took the slot without a search following.
    var unredeemedSlotCount: Int { get }

    /// Debug only: clears the unredeemed count and the prompt's eligibility state.
    func resetForDebug()
}

/// Brings the App Store rating prompt into the Promo Queue.
///
/// The system dialog is not ours to present and fires on a search, not at the foreground
/// checkpoint. So this is a `.deferred` provider: selecting it holds the slot, and the user's
/// next search redeems it.
@MainActor
final class AppRatingPromptCoordinator: ModalPromptProvider, AppRatingPromptCoordinating {

    private let appRatingPrompt: AppRatingPrompt
    private let coordinationPolicy: AppRatingPromptCoordinationPolicying
    private let store: AppRatingPromptSlotStore

    init(
        appRatingPrompt: AppRatingPrompt,
        coordinationPolicy: AppRatingPromptCoordinationPolicying,
        store: AppRatingPromptSlotStore
    ) {
        self.appRatingPrompt = appRatingPrompt
        self.coordinationPolicy = coordinationPolicy
        self.store = store
    }

    // MARK: - ModalPromptProvider

    var presentationKind: ModalPromptPresentationKind { .deferred }

    func isEligibleToPresent(isOnboardingComplete: Bool) -> Bool {
        guard isCoordinationEnabled else { return false }

        guard !isUnredeemedSlotCapReached else {
            Logger.modalPrompt.debug("[App Rating Prompt] - Unredeemed slot cap reached; not taking the slot.")
            return false
        }

        return appRatingPrompt.shouldPrompt()
    }

    /// Stop taking the slot after this many foregrounds with no search, so a user who does not
    /// search cannot starve the queue. A remote value of zero or less removes the cap.
    private var isUnredeemedSlotCapReached: Bool {
        let cap = coordinationPolicy.maxUnredeemedSlots
        guard cap > 0 else { return false }

        return store.unredeemedSlotCount >= cap
    }

    /// Never called: the manager short-circuits `.deferred` providers after eligibility.
    func provideModalPrompt() -> ModalPromptConfiguration? {
        nil
    }

    /// Deliberately empty. This fires only when a slot was taken *and* redeemed, never in the legacy path.
    /// Eligibility is consumed at the request site, the one point common to every path.
    func didPresentModal() {}

    func didReleaseDeferredSlot() {
        store.unredeemedSlotCount += 1
        Logger.modalPrompt.debug("[App Rating Prompt] - Slot released without a search.")
    }

    // MARK: - AppRatingPromptCoordinating

    var isCoordinationEnabled: Bool {
        coordinationPolicy.isCoordinationEnabled
    }

    var unredeemedSlotCount: Int {
        store.unredeemedSlotCount
    }

    func registerUsage() {
        appRatingPrompt.registerUsage()
    }

    func shouldRequestUncoordinated() -> Bool {
        appRatingPrompt.shouldPrompt()
    }

    func didRequestRating() {
        store.unredeemedSlotCount = 0
        appRatingPrompt.shown()
    }

    func resetForDebug() {
        store.unredeemedSlotCount = 0
        appRatingPrompt.storage.firstShown = nil
        appRatingPrompt.storage.lastShown = nil
        appRatingPrompt.storage.uniqueAccessDays = 0
    }
}

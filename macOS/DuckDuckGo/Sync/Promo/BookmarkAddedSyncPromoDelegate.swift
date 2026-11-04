//
//  BookmarkAddedSyncPromoDelegate.swift
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

import Combine
import ConcurrencyExtensions
import DDGSync
import FeatureFlags_macOS
import Foundation
import Persistence
import PrivacyConfig

struct BookmarkAddedSyncPromoSettings: StoringKeys {
    let didDismissLegacyButton = StorageKey<Bool>(UserDefaultsKeys.bookmarkAddedSyncPromoDismissed, assertionHandler: { _ in })
    let presentedCount = StorageKey<Int>(UserDefaultsKeys.bookmarkAddedSyncPromoPresentedCount, assertionHandler: { _ in })
}

/// Shows the "Sync Bookmarks Across Devices" button in the Add Bookmark popover and the Add/Edit Bookmark dialog through the promo queue.
final class BookmarkAddedSyncPromoDelegate: InternalPromoDelegate, SyncDeviceButtonPromoPresenting {

    private static let maxPresentationCount = 5

    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing?
    private let storage: KeyedStorage<BookmarkAddedSyncPromoSettings>
    private let recordResult: @MainActor (_ promoID: String, PromoResult) -> Void
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)
    private let isPromoActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private let eligibilityQueue = DispatchQueue(label: "com.duckduckgo.bookmarkAddedSyncPromo.eligibility", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var didStartSetupFromPromo = false
    private var isForcedSession = false

    /// - Parameter recordResult: Records a result with the promo queue, including after the promo has been hidden.
    init(featureFlagger: FeatureFlagger,
         syncService: DDGSyncing?,
         storage: KeyedStorage<BookmarkAddedSyncPromoSettings>,
         recordResult: @escaping @MainActor (_ promoID: String, PromoResult) -> Void) {
        self.featureFlagger = featureFlagger
        self.syncService = syncService
        self.storage = storage
        self.recordResult = recordResult

        subscribeToEligibilityChanges()
    }

    // MARK: - Promo queue eligibility

    var isEligible: Bool {
        isEligibleSubject.value
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func refreshEligibility() {
        refreshEligibility(authState: syncService?.authState)
    }

    private func refreshEligibility(authState: SyncAuthState?) {
        isEligibleSubject.send(computeEligibility(authState: authState))
    }

    private func computeEligibility(authState: SyncAuthState?) -> Bool {
        featureFlagger.isFeatureOn(.promoQueueBookmarkAddedSyncPromo)
            && featureFlagger.isNewSyncEntryPointsFeatureOn
            && syncService != nil
            && authState == .inactive
    }

    private func subscribeToEligibilityChanges() {
        let authStateChanges = syncService?.authStatePublisher.dropFirst()

        authStateChanges?
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                MainActor.assumeMainThread {
                    self?.recordActionedIfSyncTurnedOn(authState)
                }
            }
            .store(in: &cancellables)

        authStateChanges?
            .receive(on: eligibilityQueue)
            .sink { [weak self] authState in
                self?.refreshEligibility(authState: authState)
            }
            .store(in: &cancellables)

        featureFlagger.updatesPublisher
            .receive(on: eligibilityQueue)
            .sink { [weak self] in
                self?.refreshEligibility()
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func recordActionedIfSyncTurnedOn(_ authState: SyncAuthState) {
        guard authState == .active || authState == .addingNewDevice, didStartSetupFromPromo else { return }
        // The queue may already have hidden the promo as ineligible; recording `.actioned` still applies to it.
        didStartSetupFromPromo = false
        recordResult(PromoServiceFactory.bookmarkAddedSyncPromoID, .actioned())
    }

    // MARK: - Promo queue display

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        // Users who dismissed the legacy button or saw it the maximum number of times never see it again.
        if !force, storage.didDismissLegacyButton == true || (storage.presentedCount ?? 0) >= Self.maxPresentationCount {
            return .retired
        }

        isForcedSession = force
        // Only a CTA tap during this showing can make it actioned.
        didStartSetupFromPromo = false
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
            isPromoActiveSubject.send(true)
        }
    }

    @MainActor
    func hide() {
        // Hidden because sync is being turned on: `recordActionedIfSyncTurnedOn` can still record `.actioned`.
        if resultContinuation != nil, syncService?.authState == .inactive {
            didStartSetupFromPromo = false
        }
        resolve(with: .noChange)
    }

    var isPromoActive: Bool {
        isPromoActiveSubject.value
    }

    var isPromoActivePublisher: AnyPublisher<Bool, Never> {
        isPromoActiveSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func syncSetupStarted() {
        // Tapping the CTA alone doesn't resolve the promo; it's actioned only if sync turns on.
        didStartSetupFromPromo = true
    }

    @MainActor
    func syncButtonDismissed() {
        resolve(with: .ignored())
    }

    @MainActor
    func syncButtonSurfaceClosed() {
        guard resultContinuation != nil else { return }
        guard !isForcedSession else {
            resolve(with: .noChange)
            return
        }
        let presentedCount = (storage.presentedCount ?? 0) + 1
        storage.presentedCount = presentedCount
        resolve(with: presentedCount >= Self.maxPresentationCount ? .ignored() : .ignored(cooldown: 0))
    }

    @MainActor
    private func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        isForcedSession = false
        isPromoActiveSubject.send(false)
        continuation.resume(returning: result)
    }
}

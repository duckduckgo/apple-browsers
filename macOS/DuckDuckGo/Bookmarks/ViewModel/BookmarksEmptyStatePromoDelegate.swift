//
//  BookmarksEmptyStatePromoDelegate.swift
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
import DDGSync
import FeatureFlags_macOS
import Foundation
import PrivacyConfig

protocol ImportSyncEmptyStatePromoPresenting: AnyObject {
    var isPromoActive: Bool { get }
    var isPromoActivePublisher: AnyPublisher<Bool, Never> { get }
    @MainActor func importStarted()
    @MainActor func importFinished()
    @MainActor func syncSetupStarted()
    @MainActor func syncSetupFinished()
}

/// Shows the message and import/sync CTAs of the "No bookmarks yet" empty state through the promo queue.
final class BookmarksEmptyStatePromoDelegate: InternalPromoDelegate, ImportSyncEmptyStatePromoPresenting {

    private let featureFlagger: FeatureFlagger
    private let hasTopLevelEntitiesProvider: () -> Bool
    private let syncService: DDGSyncing?
    private let recordResult: @MainActor (_ promoID: String, PromoResult) -> Void
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)
    private let isPromoActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private let eligibilityQueue = DispatchQueue(label: "com.duckduckgo.bookmarksEmptyStatePromo.eligibility", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var isImportFromEmptyStateInProgress = false
    private var isSyncSetupFromEmptyStateInProgress = false
    private var isActionedPending = false

    /// - Parameters:
    ///   - hasTopLevelEntitiesProvider: Must be synchronous and safe to call off the main thread.
    ///   - bookmarksChangedPublisher: Emits whenever bookmarks are added or removed.
    ///   - dataImportCompletedPublisher: Emits when an import of every selected data type succeeds.
    ///   - recordResult: Records a result with the promo queue, including after the promo has been hidden.
    init(featureFlagger: FeatureFlagger,
         hasTopLevelEntitiesProvider: @escaping () -> Bool,
         bookmarksChangedPublisher: AnyPublisher<Void, Never>,
         dataImportCompletedPublisher: AnyPublisher<Void, Never>,
         syncService: DDGSyncing?,
         recordResult: @escaping @MainActor (_ promoID: String, PromoResult) -> Void) {
        self.featureFlagger = featureFlagger
        self.hasTopLevelEntitiesProvider = hasTopLevelEntitiesProvider
        self.syncService = syncService
        self.recordResult = recordResult

        featureFlagger.updatesPublisher
            .merge(with: bookmarksChangedPublisher)
            .receive(on: eligibilityQueue)
            .sink { [weak self] in
                self?.refreshEligibility()
            }
            .store(in: &cancellables)

        dataImportCompletedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeMainThread {
                    self?.noteDataImportCompleted()
                }
            }
            .store(in: &cancellables)

        syncService?.authStatePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                MainActor.assumeMainThread {
                    self?.noteSyncAuthStateChange(authState)
                }
            }
            .store(in: &cancellables)

        bookmarksChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeMainThread {
                    self?.recordActionedIfPendingAndBookmarksAppeared()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Promo queue eligibility

    var isEligible: Bool {
        isEligibleSubject.value
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func refreshEligibility() {
        isEligibleSubject.send(featureFlagger.isFeatureOn(.promoQueueBookmarksEmptyStatePromo) && !hasTopLevelEntitiesProvider())
    }

    // MARK: - Promo queue result

    @MainActor
    func importStarted() {
        isImportFromEmptyStateInProgress = true
    }

    @MainActor
    func importFinished() {
        isImportFromEmptyStateInProgress = false
    }

    @MainActor
    func syncSetupStarted() {
        isSyncSetupFromEmptyStateInProgress = true
    }

    @MainActor
    func syncSetupFinished() {
        isSyncSetupFromEmptyStateInProgress = false
    }

    @MainActor
    private func noteDataImportCompleted() {
        guard isImportFromEmptyStateInProgress else { return }
        isImportFromEmptyStateInProgress = false
        isActionedPending = true
        recordActionedIfPendingAndBookmarksAppeared()
    }

    @MainActor
    private func noteSyncAuthStateChange(_ authState: SyncAuthState) {
        guard authState == .active || authState == .addingNewDevice, isSyncSetupFromEmptyStateInProgress else { return }
        isSyncSetupFromEmptyStateInProgress = false
        isActionedPending = true
        recordActionedIfPendingAndBookmarksAppeared()
    }

    /// Waits for bookmarks to replace the empty state, so recording the result never hides the CTAs from a visible empty state.
    /// The queue may already have hidden the promo as ineligible; recording the result still applies to it.
    @MainActor
    private func recordActionedIfPendingAndBookmarksAppeared() {
        guard isActionedPending, hasTopLevelEntitiesProvider() else { return }
        isActionedPending = false
        recordResult(PromoServiceFactory.bookmarksEmptyStateImportSyncPromoID, .actioned(cooldown: 0))
    }

    // MARK: - Promo queue display

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        resolve(with: .noChange)
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
            isPromoActiveSubject.send(true)
        }
    }

    @MainActor
    func hide() {
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
    private func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        isPromoActiveSubject.send(false)
        continuation.resume(returning: result)
    }
}

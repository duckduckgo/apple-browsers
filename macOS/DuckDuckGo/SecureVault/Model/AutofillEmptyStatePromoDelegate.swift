//
//  AutofillEmptyStatePromoDelegate.swift
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

/// Shows the import/sync CTAs of the Passwords panel empty states through the promo queue.
final class AutofillEmptyStatePromoDelegate: InternalPromoDelegate, ImportSyncEmptyStatePromoPresenting {

    private let featureFlagger: FeatureFlagger
    private let isAnyCategoryEmptyProvider: () -> Bool
    private let recordResult: @MainActor (_ promoID: String, PromoResult) -> Void
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)
    private let isPromoActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private let eligibilityQueue = DispatchQueue(label: "com.duckduckgo.autofillEmptyStatePromo.eligibility", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var isImportFromEmptyStateInProgress = false
    private var isSyncSetupFromEmptyStateInProgress = false

    /// - Parameters:
    ///   - isAnyCategoryEmptyProvider: Whether passwords, identities or credit cards has no items.
    ///     Must be synchronous and safe to call off the main thread.
    ///   - dataImportCompletedPublisher: Emits when an import of every selected data type succeeds.
    ///   - recordResult: Records a result with the promo queue, including after the promo has been hidden.
    init(featureFlagger: FeatureFlagger,
         isAnyCategoryEmptyProvider: @escaping () -> Bool,
         dataImportCompletedPublisher: AnyPublisher<Void, Never>,
         syncService: DDGSyncing?,
         recordResult: @escaping @MainActor (_ promoID: String, PromoResult) -> Void) {
        self.featureFlagger = featureFlagger
        self.isAnyCategoryEmptyProvider = isAnyCategoryEmptyProvider
        self.recordResult = recordResult

        featureFlagger.updatesPublisher
            .receive(on: eligibilityQueue)
            .sink { [weak self] in
                self?.refreshEligibility()
            }
            .store(in: &cancellables)

        dataImportCompletedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeMainThread {
                    self?.recordActionedIfImportStartedFromEmptyState()
                }
            }
            .store(in: &cancellables)

        syncService?.authStatePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                MainActor.assumeMainThread {
                    self?.recordActionedIfSyncSetUpFromEmptyState(authState)
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
        isEligibleSubject.send(featureFlagger.isFeatureOn(.promoQueueAutofillEmptyStatePromo) && isAnyCategoryEmptyProvider())
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
    private func recordActionedIfImportStartedFromEmptyState() {
        guard isImportFromEmptyStateInProgress else { return }
        isImportFromEmptyStateInProgress = false
        recordResult(PromoServiceFactory.autofillEmptyStateImportSyncPromoID, .actioned(cooldown: 0))
    }

    @MainActor
    private func recordActionedIfSyncSetUpFromEmptyState(_ authState: SyncAuthState) {
        guard authState == .active || authState == .addingNewDevice, isSyncSetupFromEmptyStateInProgress else { return }
        isSyncSetupFromEmptyStateInProgress = false
        recordResult(PromoServiceFactory.autofillEmptyStateImportSyncPromoID, .actioned(cooldown: 0))
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

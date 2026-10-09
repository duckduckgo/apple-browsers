//
//  BookmarksBarSyncPromoDelegate.swift
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
import FoundationExtensions
import Persistence
import PrivacyConfig

/// State written by `DismissableSyncDeviceButtonModel` for the bookmarks bar button before it moved to the promo queue.
struct BookmarksBarSyncPromoLegacySettings: StoringKeys {
    let didDismissLegacyButton = StorageKey<Bool>(UserDefaultsKeys.bookmarksBarSyncPromoDismissed, assertionHandler: { _ in })
    let legacyFirstPresentedDate = StorageKey<Date>(UserDefaultsKeys.bookmarksBarSyncPromoFirstPresentedDate, assertionHandler: { _ in })
}

protocol BookmarksBarSyncPromoPresenting: AnyObject {
    var isPromoActivePublisher: AnyPublisher<Bool, Never> { get }
    @MainActor func syncSetupStarted()
}

/// Shows the "Sync Bookmarks" button in the bookmarks bar through the promo queue.
final class BookmarksBarSyncPromoDelegate: InternalPromoDelegate, BookmarksBarSyncPromoPresenting {

    private static let legacyPresentationDays = 7

    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing?
    private let isBookmarksBarSettingOn: () -> Bool
    private let notificationCenter: NotificationCenter
    private let legacyStorage: KeyedStorage<BookmarksBarSyncPromoLegacySettings>
    private let dateProvider: () -> Date
    private let recordResult: @MainActor (_ promoID: String, PromoResult) -> Void
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)
    private let isPromoActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private let eligibilityQueue = DispatchQueue(label: "com.duckduckgo.bookmarksBarSyncPromo.eligibility", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var didStartSetupFromPromo = false

    /// - Parameters:
    ///   - isBookmarksBarSettingOn: Must be safe to call off the main thread.
    ///   - recordResult: Records a result with the promo queue, including after the promo has been hidden.
    init(featureFlagger: FeatureFlagger,
         syncService: DDGSyncing?,
         isBookmarksBarSettingOn: @escaping () -> Bool,
         notificationCenter: NotificationCenter = .default,
         legacyStorage: KeyedStorage<BookmarksBarSyncPromoLegacySettings>,
         dateProvider: @escaping () -> Date = Date.init,
         recordResult: @escaping @MainActor (_ promoID: String, PromoResult) -> Void) {
        self.featureFlagger = featureFlagger
        self.syncService = syncService
        self.isBookmarksBarSettingOn = isBookmarksBarSettingOn
        self.notificationCenter = notificationCenter
        self.legacyStorage = legacyStorage
        self.dateProvider = dateProvider
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
        guard featureFlagger.isFeatureOn(.promoQueueBookmarksBarSyncPromo),
              featureFlagger.isNewSyncEntryPointsFeatureOn,
              syncService != nil,
              authState == .inactive,
              isBookmarksBarSettingOn() else {
            return false
        }
        guard let legacyFirstPresentedDate = legacyStorage.legacyFirstPresentedDate else {
            return true
        }
        return legacyFirstPresentedDate > dateProvider().addingTimeInterval(-TimeInterval.days(Self.legacyPresentationDays))
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
            .merge(with: notificationCenter.publisher(for: AppearancePreferences.Notifications.showBookmarksBarSettingChanged).map { _ in })
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
        recordResult(PromoServiceFactory.bookmarksBarSyncPromoID, .actioned)
    }

    // MARK: - Promo queue display

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        // Users who dismissed the legacy button never see it again.
        if !force, legacyStorage.didDismissLegacyButton == true {
            return .retired
        }

        // Only a CTA tap during this showing can make it actioned.
        didStartSetupFromPromo = false
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
            isPromoActiveSubject.send(true)
        }
    }

    @MainActor
    func hide() {
        // Hidden because sync turned on: `recordActionedIfSyncTurnedOn` can still record `.actioned`.
        if syncService?.authState == .inactive {
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
    private func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        isPromoActiveSubject.send(false)
        continuation.resume(returning: result)
    }
}

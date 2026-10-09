//
//  SyncPromoManager.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine
import ConcurrencyExtensions
import DDGSync
import FeatureFlags_macOS
import Foundation
import Persistence
import PrivacyConfig

protocol SyncPromoManaging {
    var isPromoActive: Bool { get }
    var isPromoActivePublisher: AnyPublisher<Bool, Never> { get }
    @MainActor func goToSyncSettings(for touchpoint: SyncPromoManager.Touchpoint)
    @MainActor func promoDismissed()
}

enum SyncPromoContent {
    case bookmarks
    case autofill

    var promoID: String {
        switch self {
        case .bookmarks: PromoServiceFactory.syncSetupBookmarksPromoID
        case .autofill: PromoServiceFactory.syncSetupAutofillPromoID
        }
    }

    var promoFlag: FeatureFlag {
        switch self {
        case .bookmarks: .promoQueueSyncSetupBookmarksPromo
        case .autofill: .promoQueueSyncSetupAutofillPromo
        }
    }

    var promotionSubfeature: SyncPromotionSubfeature {
        switch self {
        case .bookmarks: .bookmarks
        case .autofill: .passwords
        }
    }

    func contains(_ touchpoint: SyncPromoManager.Touchpoint) -> Bool {
        switch touchpoint {
        case .bookmarks:
            self == .bookmarks
        case .autofill, .passwords, .creditCards, .identities:
            self == .autofill
        }
    }
}

/// Dismissals recorded by the sync promos before they moved to the promo queue.
struct SyncPromoLegacySettings: StoringKeys {
    let bookmarksDismissedDate = StorageKey<Date>(UserDefaultsKeys.syncPromoBookmarksDismissed, assertionHandler: { _ in })
    let passwordsDismissedDate = StorageKey<Date>(UserDefaultsKeys.syncPromoPasswordsDismissed, assertionHandler: { _ in })
}

final class SyncPromoManager: SyncPromoManaging, InternalPromoDelegate {

    enum Touchpoint: String {
        case bookmarks
        case autofill
        case passwords
        case creditCards
        case identities
    }

    public struct SyncPromoManagerNotifications {
        public static let didGoToSync = NSNotification.Name(rawValue: "com.duckduckgo.syncPromo.didGoToSync")
    }

    public struct Constants {
        public static let syncPromoSourceKey = "source"
        public static let syncPromoBookmarksSource = "promotion_bookmarks"
        public static let syncPromoPasswordsSource = "promotion_passwords"
        public static let syncPromoAutofillSource = "promotion_autofill"
        public static let syncPromoCreditCardsSource = "promotion_creditcards"
        public static let syncPromoIdentitiesSource = "promotion_identities"
    }

    private let content: SyncPromoContent
    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing?
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let contentCountProvider: () -> Int
    private let isDuckDuckGoPasswordManager: () -> Bool
    private let legacyStorage: KeyedStorage<SyncPromoLegacySettings>
    private let openSyncSettings: @MainActor () -> Void
    private let recordResult: @MainActor (_ promoID: String, PromoResult) -> Void
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)
    private let isPromoActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    /// Runs the refreshes this class starts itself, so counting content never blocks the main thread.
    private let eligibilityQueue = DispatchQueue(label: "com.duckduckgo.syncPromoManager.eligibility", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var didStartSetupFromPromo = false

    /// Builds an instance that serves as the promo queue delegate for `content`.
    /// - Parameters:
    ///   - contentCountProvider: Number of items of `content` the user has. Must be synchronous and safe to call off the main thread.
    ///   - isDuckDuckGoPasswordManager: Whether DuckDuckGo is the selected password manager. Only used for `.autofill`.
    ///     Must be safe to call off the main thread.
    ///   - recordResult: Records a result with the promo queue, including after the promo has been hidden.
    ///
    /// Eligibility isn't computed until `refreshEligibility()` is first called, which `PromoService` does before reading it.
    init(content: SyncPromoContent,
         featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         syncService: DDGSyncing?,
         contentCountProvider: @escaping () -> Int,
         isDuckDuckGoPasswordManager: @escaping () -> Bool,
         legacyStorage: KeyedStorage<SyncPromoLegacySettings>,
         openSyncSettings: @escaping @MainActor () -> Void,
         recordResult: @escaping @MainActor (_ promoID: String, PromoResult) -> Void) {
        self.content = content
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.syncService = syncService
        self.contentCountProvider = contentCountProvider
        self.isDuckDuckGoPasswordManager = isDuckDuckGoPasswordManager
        self.legacyStorage = legacyStorage
        self.openSyncSettings = openSyncSettings
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
            .merge(with: privacyConfigurationManager.updatesPublisher)
            .receive(on: eligibilityQueue)
            .sink { [weak self] in
                self?.refreshEligibility()
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func recordActionedIfSyncTurnedOn(_ authState: SyncAuthState) {
        guard Self.isSyncTurnedOn(authState), didStartSetupFromPromo else { return }
        // The queue may already have hidden the promo as ineligible; recording `.actioned` still applies to it.
        didStartSetupFromPromo = false
        recordResult(content.promoID, .actioned)
    }

    private static func isSyncTurnedOn(_ authState: SyncAuthState) -> Bool {
        authState == .active || authState == .addingNewDevice
    }

    private func computeEligibility(authState: SyncAuthState?) -> Bool {
        guard featureFlagger.isFeatureOn(content.promoFlag) else { return false }

        let privacyConfig = privacyConfigurationManager.privacyConfig
        guard authState == .inactive,
              privacyConfig.isSubfeatureEnabled(content.promotionSubfeature),
              privacyConfig.isSubfeatureEnabled(SyncSubfeature.level0ShowSync) else {
            return false
        }

        switch content {
        case .bookmarks:
            return contentCountProvider() > 0
        case .autofill:
            return (isPromoActive || isDuckDuckGoPasswordManager()) && contentCountProvider() > 0
        }
    }

    // MARK: - Promo queue display

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        if !force, isDismissedInLegacyPromo {
            return .retired
        }

        resolve(with: .noChange)
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
    func promoDismissed() {
        resolve(with: .ignored())
    }

    private var isDismissedInLegacyPromo: Bool {
        switch content {
        case .bookmarks:
            legacyStorage.bookmarksDismissedDate != nil
        case .autofill:
            legacyStorage.passwordsDismissedDate != nil
        }
    }

    /// Single funnel for every resolution path.
    @MainActor
    private func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        isPromoActiveSubject.send(false)
        continuation.resume(returning: result)
    }

    @MainActor func goToSyncSettings(for touchpoint: Touchpoint) {
        assert(content.contains(touchpoint), "\(touchpoint) doesn't belong to the \(content) sync promo")
        // Tapping the CTA alone doesn't resolve the promo; it's actioned only if sync turns on in this session.
        didStartSetupFromPromo = true

        openSyncSettings()

        var source: String
        switch touchpoint {
        case .bookmarks:
            source = Constants.syncPromoBookmarksSource
        case .passwords:
            source = Constants.syncPromoPasswordsSource
        case .autofill:
            source = Constants.syncPromoAutofillSource
        case .creditCards:
            source = Constants.syncPromoCreditCardsSource
        case .identities:
            source = Constants.syncPromoIdentitiesSource
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            NotificationCenter.default.post(name: SyncPromoManagerNotifications.didGoToSync, object: self, userInfo: [
                Constants.syncPromoSourceKey: source
            ])
        }
    }
}

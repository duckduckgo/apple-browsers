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
import DDGSync
import FeatureFlags_macOS
import Foundation
import PrivacyConfig

protocol SyncPromoManaging {
    func shouldPresentPromoFor(_ touchpoint: SyncPromoManager.Touchpoint) -> Bool
    func goToSyncSettings(for touchpoint: SyncPromoManager.Touchpoint)
    func dismissPromoFor(_ touchpoint: SyncPromoManager.Touchpoint)
    func resetPromos()
}

enum SyncPromoContent {
    case bookmarks
    case autofill

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
}

final class SyncPromoManager: SyncPromoManaging {

    enum Touchpoint: String {
        case bookmarks
        case autofill
        case passwords
        case creditCards
        case identities
    }

    public struct SyncPromoManagerNotifications {
        public static let didDismissPromo = NSNotification.Name(rawValue: "com.duckduckgo.syncPromo.didDismiss")
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

    /// `nil` for an instance built with the legacy initializer, which takes no part in the promo queue.
    private let content: SyncPromoContent?
    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing?
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let contentCountProvider: () -> Int
    private let isDuckDuckGoPasswordManager: () -> Bool
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)
    /// Runs the refreshes this class starts itself, so counting content never blocks the main thread.
    private let eligibilityQueue = DispatchQueue(label: "com.duckduckgo.syncPromoManager.eligibility", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private let autofillPrefs = AutofillPreferences()

    @UserDefaultsWrapper(key: .syncPromoBookmarksDismissed, defaultValue: nil)
    private var syncPromoBookmarksDismissed: Date?

    @UserDefaultsWrapper(key: .syncPromoPasswordsDismissed, defaultValue: nil)
    private var syncPromoPasswordsDismissed: Date?

    /// Builds an instance that serves as the promo queue delegate for `content`.
    /// - Parameters:
    ///   - contentCountProvider: Number of items of `content` the user has. Must be synchronous and safe to call off the main thread.
    ///   - isDuckDuckGoPasswordManager: Whether DuckDuckGo is the selected password manager. Only used for `.autofill`.
    ///     Must be safe to call off the main thread.
    ///
    /// Eligibility isn't computed until `refreshEligibility()` is first called, which `PromoService` does before reading it.
    init(content: SyncPromoContent,
         featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         syncService: DDGSyncing?,
         contentCountProvider: @escaping () -> Int,
         isDuckDuckGoPasswordManager: @escaping () -> Bool) {
        self.content = content
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.syncService = syncService
        self.contentCountProvider = contentCountProvider
        self.isDuckDuckGoPasswordManager = isDuckDuckGoPasswordManager

        subscribeToEligibilityChanges()
    }

    init(syncService: DDGSyncing? = NSApp.delegateTyped.syncService,
         privacyConfigurationManager: PrivacyConfigurationManaging = NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager) {
        self.content = nil
        self.featureFlagger = NSApp.delegateTyped.featureFlagger
        self.syncService = syncService
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentCountProvider = { 0 }
        self.isDuckDuckGoPasswordManager = { false }
    }

    // MARK: - Promo queue eligibility

    var isEligible: Bool {
        isEligibleSubject.value
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func refreshEligibility() {
        isEligibleSubject.send(computeEligibility())
    }

    private func subscribeToEligibilityChanges() {
        // The hop to another queue also means `syncService.authState` holds the new value when eligibility is recomputed.
        syncService?.authStatePublisher
            .dropFirst()
            .receive(on: eligibilityQueue)
            .sink { [weak self] _ in
                self?.refreshEligibility()
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

    private func computeEligibility() -> Bool {
        guard let content, featureFlagger.isFeatureOn(content.promoFlag) else { return false }

        let privacyConfig = privacyConfigurationManager.privacyConfig
        guard let syncService,
              syncService.authState == .inactive,
              privacyConfig.isSubfeatureEnabled(content.promotionSubfeature),
              privacyConfig.isSubfeatureEnabled(SyncSubfeature.level0ShowSync) else {
            return false
        }

        switch content {
        case .bookmarks:
            return contentCountProvider() > 0
        case .autofill:
            return isDuckDuckGoPasswordManager() && contentCountProvider() > 0
        }
    }

    func shouldPresentPromoFor(_ touchpoint: Touchpoint) -> Bool {
        guard let syncService = syncService else {
            return false
        }

        switch touchpoint {
        case .bookmarks:
            if privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncPromotionSubfeature.bookmarks),
               privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncSubfeature.level0ShowSync),
               syncService.authState == .inactive,
               syncPromoBookmarksDismissed == nil {
                return true
            }
        case .passwords, .autofill:
            if privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncPromotionSubfeature.passwords),
               privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncSubfeature.level0ShowSync),
               autofillPrefs.passwordManager == .duckduckgo,
               syncService.authState == .inactive,
               syncPromoPasswordsDismissed == nil {
                return true
            }
        case .creditCards:
            if privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncPromotionSubfeature.passwords),
               privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncSubfeature.syncCreditCards),
               privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncSubfeature.level0ShowSync),
               autofillPrefs.passwordManager == .duckduckgo,
               syncService.authState == .inactive,
               syncPromoPasswordsDismissed == nil {
                return true
            }
        case .identities:
            if privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncPromotionSubfeature.passwords),
               privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncSubfeature.syncIdentities),
               privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncSubfeature.level0ShowSync),
               autofillPrefs.passwordManager == .duckduckgo,
               syncService.authState == .inactive,
               syncPromoPasswordsDismissed == nil {
                return true
            }
        }

        return false
    }

    @MainActor func goToSyncSettings(for touchpoint: Touchpoint) {
        Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .sync)

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

    func dismissPromoFor(_ touchpoint: Touchpoint) {
        switch touchpoint {
        case .bookmarks:
            syncPromoBookmarksDismissed = Date()
            NotificationCenter.default.post(name: SyncPromoManagerNotifications.didDismissPromo, object: nil)
        default:
            syncPromoPasswordsDismissed = Date()
        }
    }

    func resetPromos() {
        syncPromoBookmarksDismissed = nil
        syncPromoPasswordsDismissed = nil
        NotificationCenter.default.post(name: SyncPromoManagerNotifications.didDismissPromo, object: nil)
    }
}

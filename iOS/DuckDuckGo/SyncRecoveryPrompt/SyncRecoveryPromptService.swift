//
//  SyncRecoveryPromptService.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import UIKit
import Core
import BrowserServicesKit
import Persistence
import DDGSync

@MainActor
final class SyncRecoveryPromptService {

    private(set) lazy var presenter: SyncRecoveryPromptPresenting = SyncRecoveryPromptPresenter()

    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing
    private let keyValueStore: ThrowingKeyValueStoring
    private let isOnboardingComplete: Bool
    private let secureVault: (any AutofillSecureVault)?
    private let autofillUsageStore: AutofillUsageStore
    private let vaultDateProvider: VaultCreationDateProvider?
    private lazy var defaultVaultDateProvider: VaultCreationDateProvider = KeychainVaultDateProvider()

    enum Key {
        static let hasPerformedSyncRecoveryCheck: String = "com.duckduckgo.syncrecovery.check.performed"
    }

    init(featureFlagger: FeatureFlagger,
         syncService: DDGSyncing,
         keyValueStore: ThrowingKeyValueStoring,
         isOnboardingComplete: Bool,
         secureVault: (any AutofillSecureVault)? = nil,
         autofillUsageStore: AutofillUsageStore? = nil,
         vaultDateProvider: VaultCreationDateProvider? = nil) {
        self.featureFlagger = featureFlagger
        self.syncService = syncService
        self.keyValueStore = keyValueStore
        self.isOnboardingComplete = isOnboardingComplete
        self.secureVault = secureVault
        self.autofillUsageStore = autofillUsageStore ?? AutofillUsageStore()
        self.vaultDateProvider = vaultDateProvider
    }

    func shouldShowPrompt() -> Bool {
        guard isFeatureFlagEnabled else {
            Logger.sync.debug("[Sync Recovery] Feature flag disabled")
            return false
        }

        guard !hasPerformedCheck else {
            Logger.sync.debug("[Sync Recovery] Already performed check")
            return false
        }

        hasPerformedCheck = true

        guard isOnboardingComplete else {
            Logger.sync.debug("[Sync Recovery] Onboarding not complete")
            return false
        }

        guard !isSyncAlreadyEnabled else {
            Logger.sync.debug("[Sync Recovery] Sync already enabled")
            return false
        }

        guard vaultIsEmpty else {
            Logger.sync.debug("[Sync Recovery] Vault is not empty")
            return false
        }

        guard isFormerAutofillUser else {
            Logger.sync.debug("[Sync Recovery] Is not a former autofill user")
            return false
        }

        Logger.sync.debug("[Sync Recovery] All conditions met - prompt can be shown")

        return true
    }

    @discardableResult
    func tryPresentSyncRecoveryPrompt(from viewController: UIViewController,
                                      onSyncFlowSelected: @escaping (String) -> Void) -> Bool {
        guard shouldShowPrompt() else {
            return false
        }

        presenter.presentSyncRecoveryPrompt(
            from: viewController,
            onSyncFlowSelected: onSyncFlowSelected
        )
        return true
    }

    // MARK: - Private

    private var isFeatureFlagEnabled: Bool {
        featureFlagger.isFeatureOn(.newDeviceSyncPrompt)
    }

    private var hasPerformedCheck: Bool {
        get {
            (try? keyValueStore.object(forKey: Key.hasPerformedSyncRecoveryCheck) as? Bool) ?? false
        }
        set {
            try? keyValueStore.set(newValue, forKey: Key.hasPerformedSyncRecoveryCheck)
        }
    }

    private var isSyncAlreadyEnabled: Bool {
        syncService.account != nil
    }

    private var vaultIsEmpty: Bool {
        do {
            let vault = try getOrCreateVault()
            let accountsCount = try vault.accountsCount()
            Logger.sync.debug("[Sync Recovery] Vault accounts count: \(accountsCount)")
            return accountsCount == 0
        } catch {
            Logger.sync.error("[Sync Recovery] Failed to check vault: \(error)")
            return false
        }
    }

    private func getOrCreateVault() throws -> any AutofillSecureVault {
        if let secureVault = secureVault {
            return secureVault
        }
        return try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
    }

    private var isFormerAutofillUser: Bool {
        let lastActiveDate = autofillUsageStore.lastActiveDate
        let lastFillDate = autofillUsageStore.fillDate

        let hasAutofillHistory = (lastActiveDate != nil && lastActiveDate != .distantPast) || (lastFillDate != nil && lastFillDate != .distantPast)

        guard hasAutofillHistory else {
            return false
        }

        let mostRecentAutofillDate: Date? = {
            switch (lastActiveDate, lastFillDate) {
            case (let activeDate?, let fillDate?) where activeDate != .distantPast && fillDate != .distantPast:
                return max(activeDate, fillDate)
            case (let activeDate?, _) where activeDate != .distantPast:
                return activeDate
            case (_, let fillDate?) where fillDate != .distantPast:
                return fillDate
            default:
                return nil
            }
        }()

        guard let autofillDate = mostRecentAutofillDate,
              let vaultDate = vaultCreationDate else {
            return false
        }

        // Vault must have been created after autofill was last used
        return vaultDate > autofillDate
    }

    private var vaultCreationDate: Date? {
        let provider = vaultDateProvider ?? defaultVaultDateProvider
        return provider.getVaultCreationDate()
    }
}

// MARK: - Vault Creation Date Provider

protocol VaultCreationDateProvider {
    func getVaultCreationDate() -> Date?
}

struct KeychainVaultDateProvider: VaultCreationDateProvider {
    func getVaultCreationDate() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrService as String: "DuckDuckGo Secure Vault v4"
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let items = result as? [[String: Any]], !items.isEmpty {
            guard let firstItem = items.first,
                  let creationDate = firstItem[kSecAttrCreationDate as String] as? Date else {
                return nil
            }
            return creationDate
        }

        Logger.sync.debug("[Sync Recovery] No v4 keychain items found")
        return nil
    }
}

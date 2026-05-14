//
//  AutofillExtensionPromotionManager.swift
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
import AuthenticationServices
import BrowserServicesKit
import Core
import Persistence
import PrivacyConfig

enum ExtensionPromotionPlacement: CaseIterable {
    case passwords
    case browser
}

protocol AutofillExtensionPromotionManaging {
    var domainExtensionPromptLastShownOn: String? { get set }
    func shouldShowPromotion(for placement: ExtensionPromotionPlacement, totalCredentialsCount: Int?, completion: @escaping (Bool) -> Void)
    func markPromotionDismissed(for placement: ExtensionPromotionPlacement)
    func resetPromotionDismissal(for placement: ExtensionPromotionPlacement)
    func markPromotionPresented(for placement: ExtensionPromotionPlacement)
}

final class AutofillExtensionPromotionManager: AutofillExtensionPromotionManaging {

    private enum Constants {
        static let defaultMinimumCredentialCount = 4
        static let defaultMinimumInstallAgeDays = 7
        static let maximumBrowserPresentationCount = 5
        static let daysSinceInstalledKey = "daysSinceInstalled"
        static let minNumberPasswordsKey = "minNumberPasswords"
    }

    private enum Key {
        static let passwordsPromotionDismissed = "com.duckduckgo.autofill.extension.promo.passwords.dismissed"
        static let browserPromotionDismissed = "com.duckduckgo.autofill.extension.promo.browser.dismissed"
        static let browserPromotionPresentationCount = "com.duckduckgo.autofill.extension.promo.browser.presentationCount"

        static func dismissedKey(for placement: ExtensionPromotionPlacement) -> String {
            switch placement {
            case .passwords:
                return Self.passwordsPromotionDismissed
            case .browser:
                return Self.browserPromotionDismissed
            }
        }
    }

    private let featureFlagger: FeatureFlagger
    private let credentialStore: ASCredentialIdentityStoring
    private let installDateProvider: () -> Date?
    private let currentDateProvider: () -> Date
    private let keyValueStore: ThrowingKeyValueStoring
    private let privacyConfigurationManager: PrivacyConfigurationManaging

    var domainExtensionPromptLastShownOn: String?

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         credentialStore: ASCredentialIdentityStoring = ASCredentialIdentityStore.shared,
         keyValueStore: ThrowingKeyValueStoring,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         installDateProvider: @escaping () -> Date? = { StatisticsUserDefaults().installDate },
         currentDateProvider: @escaping () -> Date = { Date() }) {
        self.featureFlagger = featureFlagger
        self.credentialStore = credentialStore
        self.keyValueStore = keyValueStore
        self.privacyConfigurationManager = privacyConfigurationManager
        self.installDateProvider = installDateProvider
        self.currentDateProvider = currentDateProvider
    }

    func shouldShowPromotion(for placement: ExtensionPromotionPlacement, totalCredentialsCount: Int?, completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self else {
                await MainActor.run {
                    completion(false)
                }
                return
            }

            let result = await self.evaluateShouldShowPromotion(for: placement, totalCredentialsCount: totalCredentialsCount)
            await MainActor.run {
                completion(result)
            }
        }
    }

    func markPromotionDismissed(for placement: ExtensionPromotionPlacement) {
        setPromotionDismissed(true, for: placement)
    }

    func resetPromotionDismissal(for placement: ExtensionPromotionPlacement) {
        setPromotionDismissed(false, for: placement)
        resetPresentationCount(for: placement)
    }

    func markPromotionPresented(for placement: ExtensionPromotionPlacement) {
        incrementPresentationCount(for: placement)
    }

    // MARK: - Private

    private func evaluateShouldShowPromotion(for placement: ExtensionPromotionPlacement, totalCredentialsCount: Int?) async -> Bool {
        guard #available(iOS 18.0, *) else {
            return false
        }

        guard featureFlagger.isFeatureOn(featureFlag(for: placement)) else {
            return false
        }

        guard !hasBeenDismissed(for: placement) else {
            return false
        }

        guard hasRemainingPresentations(for: placement) else {
            return false
        }

        guard hasSatisfiedInstallAge(for: placement) else {
            return false
        }

        guard await !credentialProviderState() else {
            return false
        }

        guard await meetsMinimumCredentialRequirement(for: placement, totalCredentialsCount: totalCredentialsCount) else {
            return false
        }

        return true
    }

    private func featureFlag(for placement: ExtensionPromotionPlacement) -> FeatureFlag {
        switch placement {
        case .passwords:
            return .canPromoteAutofillExtensionInPasswordManagement
        case .browser:
            return .canPromoteAutofillExtensionInBrowser
        }
    }

    private func hasBeenDismissed(for placement: ExtensionPromotionPlacement) -> Bool {
        promotionDismissed(for: placement)
    }

    private var promotionDismissed: Bool {
        get {
            guard let didDismiss = try? keyValueStore.object(forKey: Key.passwordsPromotionDismissed) as? Bool else {
                return false
            }
            return didDismiss
        }
        set {
            try? keyValueStore.set(newValue, forKey: Key.passwordsPromotionDismissed)
        }
    }

    private func hasSatisfiedInstallAge(for placement: ExtensionPromotionPlacement) -> Bool {
        guard let installDate = installDateProvider() else {
            return false
        }

        let minimumDays = daysSinceInstalled(for: placement)
        let minimumAge = TimeInterval(minimumDays * 24 * 60 * 60)
        return currentDateProvider().timeIntervalSince(installDate) >= minimumAge
    }

    @available(iOS 18.0, *)
    private func credentialProviderState() async -> Bool {
        return await credentialStore.state().isEnabled
    }

    private func promotionDismissed(for placement: ExtensionPromotionPlacement) -> Bool {
        guard let didDismiss = try? keyValueStore.object(forKey: Key.dismissedKey(for: placement)) as? Bool else {
            return false
        }
        return didDismiss
    }

    private func setPromotionDismissed(_ dismissed: Bool, for placement: ExtensionPromotionPlacement) {
        try? keyValueStore.set(dismissed, forKey: Key.dismissedKey(for: placement))
    }

    private func meetsMinimumCredentialRequirement(for placement: ExtensionPromotionPlacement, totalCredentialsCount: Int?) async -> Bool {
        let minimumCount = minNumberPasswords(for: placement)

        if let totalCredentialsCount {
            return totalCredentialsCount >= minimumCount
        }

        guard let fetchedCount = await fetchCredentialsCount() else {
            return false
        }

        return fetchedCount >= minimumCount
    }

    private func fetchCredentialsCount() async -> Int? {
        do {
            return try await Task.detached(priority: .userInitiated) { () throws -> Int in
                let vault = try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
                return try vault.accountsCount()
            }.value
        } catch {
            Logger.general.error("Failed to fetch credentials count: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func hasRemainingPresentations(for placement: ExtensionPromotionPlacement) -> Bool {
        switch placement {
        case .passwords:
            return true
        case .browser:
            return presentationCount(for: .browser) < Constants.maximumBrowserPresentationCount
        }
    }

    private func presentationCount(for placement: ExtensionPromotionPlacement) -> Int {
        guard placement == .browser,
              let value = try? keyValueStore.object(forKey: Key.browserPromotionPresentationCount) as? Int else {
            return 0
        }
        return value
    }

    private func incrementPresentationCount(for placement: ExtensionPromotionPlacement) {
        guard placement == .browser else {
            return
        }

        let updatedValue = presentationCount(for: placement) + 1
        try? keyValueStore.set(updatedValue, forKey: Key.browserPromotionPresentationCount)
    }

    private func resetPresentationCount(for placement: ExtensionPromotionPlacement) {
        guard placement == .browser else {
            return
        }

        try? keyValueStore.set(0, forKey: Key.browserPromotionPresentationCount)
    }

    // MARK: - Privacy Config Helpers

    private func subfeature(for placement: ExtensionPromotionPlacement) -> any PrivacySubfeature {
        switch placement {
        case .passwords:
            return AutofillSubfeature.canPromoteAutofillExtensionInPasswordManagement
        case .browser:
            return AutofillSubfeature.canPromoteAutofillExtensionInBrowser
        }
    }

    private func daysSinceInstalled(for placement: ExtensionPromotionPlacement) -> Int {
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: subfeature(for: placement)),
              let jsonData = settings.data(using: .utf8) else {
            return Constants.defaultMinimumInstallAgeDays
        }

        do {
            if let settingsDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
               let daysStr = settingsDict[Constants.daysSinceInstalledKey],
               let days = Int(daysStr), days >= 1 {
                return days
            }
        } catch {
            Logger.general.error("Failed to parse daysSinceInstalled from privacy config: \(error.localizedDescription, privacy: .public)")
        }

        return Constants.defaultMinimumInstallAgeDays
    }

    private func minNumberPasswords(for placement: ExtensionPromotionPlacement) -> Int {
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: subfeature(for: placement)),
              let jsonData = settings.data(using: .utf8) else {
            return Constants.defaultMinimumCredentialCount
        }

        do {
            if let settingsDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
               let countStr = settingsDict[Constants.minNumberPasswordsKey],
               let count = Int(countStr), count >= 1 {
                return count
            }
        } catch {
            Logger.general.error("Failed to parse minNumberPasswords from privacy config: \(error.localizedDescription, privacy: .public)")
        }

        return Constants.defaultMinimumCredentialCount
    }
}

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

protocol AutofillExtensionPromotionManaging {
    func shouldShowPromotion(totalCredentialsCount: Int, completion: @escaping (Bool) -> Void)
    func markPromotionDismissed()
    func resetPromotionDismissal()
}

final class AutofillExtensionPromotionManager: AutofillExtensionPromotionManaging {

    private enum Constants {
        static let minimumCredentialCount = 4
        static let minimumInstallAge: TimeInterval = 60 * 60 * 24 * 7 // 7 days
    }

    private enum Key {
        static let passwordsPromotionDismissed = "com.duckduckgo.autofill.extension.promo.passwords.dismissed"

    }

    private let featureFlagger: FeatureFlagger
    private let credentialStore: ASCredentialIdentityStoring
    private let installDateProvider: () -> Date?
    private let currentDateProvider: () -> Date
    private let keyValueStore: ThrowingKeyValueStoring

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         credentialStore: ASCredentialIdentityStoring = ASCredentialIdentityStore.shared,
         keyValueStore: ThrowingKeyValueStoring,
         installDateProvider: @escaping () -> Date? = { StatisticsUserDefaults().installDate },
         currentDateProvider: @escaping () -> Date = { Date() }) {
        self.featureFlagger = featureFlagger
        self.credentialStore = credentialStore
        self.keyValueStore = keyValueStore
        self.installDateProvider = installDateProvider
        self.currentDateProvider = currentDateProvider
    }

    func shouldShowPromotion(totalCredentialsCount: Int, completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self else {
                await MainActor.run {
                    completion(false)
                }
                return
            }

            let result = await self.evaluateShouldShowPromotion(totalCredentialsCount: totalCredentialsCount)
            await MainActor.run {
                completion(result)
            }
        }
    }

    func markPromotionDismissed() {
        promotionDismissed = true
    }

    func resetPromotionDismissal() {
        promotionDismissed = false
    }

    // MARK: - Private

    private func evaluateShouldShowPromotion(totalCredentialsCount: Int) async -> Bool {
        guard #available(iOS 18.0, *) else {
            return false
        }

        guard featureFlagger.isFeatureOn(.canPromoteAutofillExtensionInPasswordManagement) else {
            return false
        }

        guard !hasBeenDismissed else {
            return false
        }

        guard hasSatisfiedInstallAge else {
            return false
        }

        guard await !credentialProviderState() else {
            return false
        }

        guard totalCredentialsCount >= Constants.minimumCredentialCount else {
            return false
        }

        return true
    }

    private var hasBeenDismissed: Bool {
        promotionDismissed
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

    private var hasSatisfiedInstallAge: Bool {
        guard let installDate = installDateProvider() else {
            return false
        }

        return currentDateProvider().timeIntervalSince(installDate) >= Constants.minimumInstallAge
    }

    @available(iOS 18.0, *)
    private func credentialProviderState() async -> Bool {
        return await credentialStore.state().isEnabled
    }
}

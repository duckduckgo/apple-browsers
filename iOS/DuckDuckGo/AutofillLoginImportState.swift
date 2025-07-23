//
//  AutofillLoginImportState.swift
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

import BrowserServicesKit
import Foundation
import Persistence

final class AutofillLoginImportState: AutofillLoginImportStateProvider, AutofillLoginImportStateStoring {

    private enum Key {
        static let hasImportedLogins: String = "com.duckduckgo.logins.hasImportedLogins"
        static let isCredentialsImportViaBrowserPromptPermanentlyDismissed: String = "com.duckduckgo.logins.isCredentialsImportBrowserPromptPermanentlyDismissed"
        static let isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed: String = "com.duckduckgo.logins.isCredentialsImportPasswordsPromoPermanentlyDismissed"
        static let credentialsImportPromptPresentationCount: String = "com.duckduckgo.logins.credentialsImportPromptPresentationCount"
    }

    private let featureFlagger: FeatureFlagger
    private let keyValueStore: ThrowingKeyValueStoring

    public var isImportPromoInBrowserPromptFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.canPromoteImportPasswordsInBrowser)
    }

    public var isImportPromoInPasswordsScreenFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.canPromoteImportPasswordsInPasswordManagement)
    }

    public var hasImportedLogins: Bool {
        get {
            guard let didImport = try? keyValueStore.object(forKey: Key.hasImportedLogins) as? Bool else {
                return false
            }
            return didImport
        }

        set {
            try? keyValueStore.set(newValue, forKey: Key.hasImportedLogins)
        }
    }

    public var isAutofillEnabled: Bool {
        AutofillSettingStatus.isAutofillEnabledInSettings
    }

    public var isCredentialsImportPromoInBrowserPermanentlyDismissed: Bool {
        get {
            guard let didDismiss = try? keyValueStore.object(forKey: Key.isCredentialsImportViaBrowserPromptPermanentlyDismissed) as? Bool else {
                return false
            }
            return didDismiss
        }

        set {
            try? keyValueStore.set(newValue, forKey: Key.isCredentialsImportViaBrowserPromptPermanentlyDismissed)
        }
    }

    public var isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed: Bool {
        get {
            guard let didDismiss = try? keyValueStore.object(forKey: Key.isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed) as? Bool else {
                return false
            }
            return didDismiss
        }

        set {
            try? keyValueStore.set(newValue, forKey: Key.isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed)
        }
    }

    public var credentialsImportPromptPresentationCount: Int {
        get {
            guard let presentationCount = try? keyValueStore.object(forKey: Key.credentialsImportPromptPresentationCount) as? Int else {
                return 0
            }

            return presentationCount
        }

        set {
            try? keyValueStore.set(newValue, forKey: Key.credentialsImportPromptPresentationCount)
        }
    }

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger, keyValueStore: ThrowingKeyValueStoring) {
        self.featureFlagger = featureFlagger
        self.keyValueStore = keyValueStore
    }

    func hasNeverPromptWebsitesFor(_ domain: String) -> Bool {
        AppDependencyProvider.shared.autofillNeverPromptWebsitesManager.hasNeverPromptWebsitesFor(domain: domain)
    }
}

//
//  AutofillCredentialsImportPresentationManager.swift
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
import BrowserServicesKit

public protocol AutofillCredentialsImportPresentationDelegate: AnyObject {
    func autofillDidRequestCredentialsImportFlow(onFinished: @escaping () -> Void, onCancelled: @escaping () -> Void)
}

public protocol AutofillLoginImportStateProvider {
    var isImportPromoInBrowserPromptFeatureEnabled: Bool { get }
    var isImportPromoInPasswordsScreenFeatureEnabled: Bool { get }
    var hasImportedLogins: Bool { get }
    var isAutofillEnabled: Bool { get }
    var isCredentialsImportPromoInBrowserPermanentlyDismissed: Bool { get }
    var isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed: Bool { get }
    var credentialsImportPromptPresentationCount: Int { get }
    func hasNeverPromptWebsitesFor(_ domain: String) -> Bool
}

final public class AutofillCredentialsImportPresentationManager {
    private var loginImportStateProvider: AutofillLoginImportStateProvider & AutofillLoginImportStateStoring

    weak var presentationDelegate: AutofillCredentialsImportPresentationDelegate?

    var domainPasswordImportLastShownOn: String?

    init(loginImportStateProvider: AutofillLoginImportStateProvider & AutofillLoginImportStateStoring) {
        self.loginImportStateProvider = loginImportStateProvider
    }
}

extension AutofillCredentialsImportPresentationManager: AutofillPasswordImportDelegate {
    private struct CredentialsImportInputContext: Decodable {
        var inputType: String
        var credentialsImport: Bool
    }

    public func autofillUserScriptDidRequestPasswordImportFlow(_ completion: @escaping () -> Void) {}

    public func autofillUserScriptDidFinishImportWithImportedCredentialForCurrentDomain() {}

    public func autofillUserScriptDidRequestPermanentCredentialsImportPromptDismissal() {
        loginImportStateProvider.isCredentialsImportPromoInBrowserPermanentlyDismissed = true
    }

    public func passwordsScreenDidRequestPermanentCredentialsImportPromptDismissal() {
        loginImportStateProvider.isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed = true
    }

    public func incrementCredentialsImportPromptPresentationCount() {
        loginImportStateProvider.credentialsImportPromptPresentationCount += 1
    }

    public func autofillUserScriptShouldDisplayOverlay(_ serializedInputContext: String, for domain: String) -> Bool {
        // no-op on iOS
        return false
    }

    public func autofillUserScriptShouldShowPasswordImportDialog(domain: String, credentials: [SecureVaultModels.WebsiteCredentials], credentialsProvider: SecureVaultModels.CredentialsProvider, totalCredentialsCount: Int) -> Bool {
        guard #available(iOS 18.2, *) else {
            return false
        }
        guard credentials.isEmpty else {
            return false
        }
        guard totalCredentialsCount < 25 else {
            return false
        }
        guard loginImportStateProvider.shouldShowPasswordImportDialog(for: domain) else {
            return false
        }
        return true
    }

    public func passwordsScreenShouldShowPasswordImportPromotion(totalCredentialsCount: Int) -> Bool {
        guard #available(iOS 18.2, *) else {
            return false
        }
        guard totalCredentialsCount < 25 else {
            return false
        }
        guard loginImportStateProvider.shouldShowPasswordsScreenImportPromotion() else {
            return false
        }
        return true
    }
}

private extension AutofillLoginImportStateProvider {
    func shouldShowPasswordImportDialog(for domain: String) -> Bool {
        guard isAutofillEnabled else {
            return false
        }
        guard !hasImportedLogins else {
            return false
        }
        guard isImportPromoInBrowserPromptFeatureEnabled else {
            return false
        }
        guard !hasNeverPromptWebsitesFor(domain) else {
            return false
        }
        guard !isCredentialsImportPromoInBrowserPermanentlyDismissed else {
            return false
        }
        guard credentialsImportPromptPresentationCount < 5 else {
            return false
        }
        return true
    }

    func shouldShowPasswordsScreenImportPromotion() -> Bool {
        guard !hasImportedLogins else {
            return false
        }
        guard isImportPromoInPasswordsScreenFeatureEnabled else {
            return false
        }
        guard !isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed else {
            return false
        }
        return true
    }
}

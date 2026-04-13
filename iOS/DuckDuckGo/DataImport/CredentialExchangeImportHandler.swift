//
//  CredentialExchangeImportHandler.swift
//  DuckDuckGo
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

import Foundation
import AuthenticationServices
import BrowserServicesKit
import SecureStorage
import os.log

/// Handles ASCredential exchange import activities by receiving credentials via ASCredentialImportManager
/// and importing passwords into the secure vault. Passwords only in this phase.
final class CredentialExchangeImportHandler {

    private let loginImporter: LoginImporter
    private let reporter: SecureVaultReporting

    init(loginImporter: LoginImporter = SecureVaultLoginImporter(),
         reporter: SecureVaultReporting = SecureVaultReporter()) {
        self.loginImporter = loginImporter
        self.reporter = reporter
    }

    func handleImport(token: UUID) async -> DataImportSummary? {
        if #available(iOS 26, *) {
            return await performImport(token: token)
        }
        Logger.autofill.error("ASCredential exchange not available on this OS version")
        return nil
    }

    @available(iOS 26, *)
    private func performImport(token: UUID) async -> DataImportSummary? {
        do {
            let importManager = ASCredentialImportManager()
            let credentialData = try await importManager.importCredentials(token: token)
            let importedLogins = importedLoginCredentials(from: credentialData)

            let summary = try loginImporter.importLogins(importedLogins, reporter: reporter) { _ in }
            Logger.autofill.debug(
                "Credential exchange: imported \(summary.successful) passwords, \(summary.duplicate) duplicates, \(summary.failed) failed"
            )
            return [.passwords: .success(summary)]
        } catch {
            Logger.autofill.error("Credential exchange import failed: \(error)")
            return nil
        }
    }

    @available(iOS 26, *)
    private func importedLoginCredentials(from credentialData: ASExportedCredentialData) -> [ImportedLoginCredential] {
        var importedLogins: [ImportedLoginCredential] = []

        for account in credentialData.accounts {
            for item in account.items {
                for credential in item.credentials {
                    guard case .basicAuthentication(let basicAuth) = credential,
                          let passwordField = basicAuth.password else { continue }

                    let password = passwordField.value
                    let username = nonEmptyString(basicAuth.userName?.value)
                        ?? nonEmptyString(account.userName)
                        ?? nonEmptyString(account.email)
                        ?? ""
                    let domain = preferredDomain(for: item)
                    let title = nonEmptyString(item.title)

                    importedLogins.append(
                        ImportedLoginCredential(
                            title: title,
                            url: domain,
                            username: username,
                            password: password
                        )
                    )
                }
            }
        }

        return importedLogins
    }

    @available(iOS 26, *)
    private func preferredDomain(for item: ASImportableItem) -> String? {
        if let firstURL = item.scope?.urls.first {
            return firstURL.absoluteString
        }

        if let subtitle = nonEmptyString(item.subtitle) {
            return subtitle
        }

        guard let title = nonEmptyString(item.title),
              title.contains(".") || title.contains("://") else {
            return nil
        }
        return title
    }

    private func nonEmptyString(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }
}

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
import Common
import SecureStorage

/// Handles ASCredential exchange import activities by receiving credentials via ASCredentialImportManager
/// and importing passwords into the secure vault. Passwords only in this phase.
final class CredentialExchangeImportHandler {

    private let loginImporter: LoginImporter
    private let reporter: SecureVaultReporting
    private let tld: TLD

    init(loginImporter: LoginImporter = SecureVaultLoginImporter(),
         reporter: SecureVaultReporting = SecureVaultReporter(),
         tld: TLD = AppDependencyProvider.shared.storageCache.tld) {
        self.loginImporter = loginImporter
        self.reporter = reporter
        self.tld = tld
    }

    func handleImport(token: UUID) async -> CredentialExchangeImportResult? {
        if #available(iOS 26, *) {
            return await performImport(token: token)
        }
        Logger.autofill.error("ASCredential exchange not available on this OS version")
        return nil
    }

    @available(iOS 26, *)
    private func performImport(token: UUID) async -> CredentialExchangeImportResult? {
        do {
            let importManager = ASCredentialImportManager()
            let credentialData = try await importManager.importCredentials(token: token)
            let source = sourceIdentifier(from: credentialData)
            let importedLogins = importedLoginCredentials(from: credentialData)

            let summary = try loginImporter.importLogins(importedLogins, reporter: reporter) { _ in }
            Logger.autofill.debug(
                "Credential exchange: imported \(summary.successful) passwords, \(summary.duplicate) duplicates, \(summary.failed) failed"
            )
            let dataImportSummary: DataImportSummary = [.passwords: .success(summary)]
            return CredentialExchangeImportResult(summary: dataImportSummary, source: source)
        } catch {
            Logger.autofill.error("Credential exchange import failed: \(error)")
            return nil
        }
    }

    @available(iOS 26, *)
    func importedLoginCredentials(from credentialData: ASExportedCredentialData) -> [ImportedLoginCredential] {
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
                    let title = preferredTitle(for: item, domain: domain)

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
    private func preferredDomain(for item: ASImportableItem) -> String {
        let scopedDomains = item.scope?.urls.compactMap { scopeURL in
            nonEmptyString(scopeURL.host) ?? nonEmptyString(scopeURL.absoluteString)
        } ?? []
        if let preferredScopedDomain = selectPreferredDomain(from: scopedDomains) {
            return preferredScopedDomain
        }

        if let subtitle = nonEmptyString(item.subtitle) {
            return subtitle
        }

        guard let title = nonEmptyString(item.title) else {
            return ""
        }

        // Apple sometimes sends host:port only in title with empty scope URLs.
        if scopedDomains.isEmpty, containsHostAndPort(title) {
            return title
        }

        guard title.contains(".") || title.contains("://") else {
            return ""
        }

        return title
    }

    @available(iOS 26, *)
    private func preferredTitle(for item: ASImportableItem, domain: String) -> String? {
        guard let title = nonEmptyString(item.title) else {
            return nil
        }

        let sharedNormalizedTitle = SecureVaultModels.WebsiteAccount(
            title: title,
            username: nil,
            domain: domain
        ).patternMatchedTitle()
        guard !sharedNormalizedTitle.isEmpty else {
            return nil
        }

        let scopeDomains = item.scope?.urls.compactMap { scopeURL in
            nonEmptyString(scopeURL.host) ?? nonEmptyString(scopeURL.absoluteString)
        } ?? []
        if scopeDomains.contains(where: { shouldDropTitle(sharedNormalizedTitle, forDomain: $0) }) {
            return nil
        }

        if shouldDropTitle(sharedNormalizedTitle, forDomain: domain) {
            return nil
        }

        return title
    }

    private func shouldDropTitle(_ normalizedTitle: String, forDomain domain: String) -> Bool {
        let normalizedTitleHost = normalizedHost(from: normalizedTitle)
        let normalizedDomainHost = normalizedHost(from: domain)

        if let titleETldPlusOne = tld.eTLDplus1(normalizedTitleHost),
           let domainETldPlusOne = tld.eTLDplus1(normalizedDomainHost),
           titleETldPlusOne == domainETldPlusOne {
            return true
        }

        if normalizedTitleHost == normalizedDomainHost {
            return true
        }

        if normalizedDomainHost.hasSuffix(".\(normalizedTitleHost)") {
            return true
        }

        return false
    }

    private func normalizedHost(from value: String) -> String {
        let lowercasedValue = value.lowercased()
        return URL(string: lowercasedValue)?.host
            ?? URL(string: "https://\(lowercasedValue)")?.host
            ?? lowercasedValue
    }

    private func selectPreferredDomain(from domains: [String]) -> String? {
        guard !domains.isEmpty else { return nil }

        if domains.count == 1 {
            return domains[0]
        }

        if let baseDomain = domains.first(where: isBaseDomain) {
            return baseDomain
        }

        if let wwwDomain = domains.first(where: isWWWDomain) {
            return wwwDomain
        }

        return domains.min { lhs, rhs in
            let lhsHost = normalizedHost(from: lhs)
            let rhsHost = normalizedHost(from: rhs)
            let lhsSegments = lhsHost.split(separator: ".").count
            let rhsSegments = rhsHost.split(separator: ".").count

            if lhsSegments != rhsSegments {
                return lhsSegments < rhsSegments
            }
            return lhsHost < rhsHost
        }
    }

    private func isBaseDomain(_ domain: String) -> Bool {
        let host = normalizedHost(from: domain)
        return host == eTldPlusOne(for: host)
    }

    private func isWWWDomain(_ domain: String) -> Bool {
        let host = normalizedHost(from: domain)
        let components = host.split(separator: ".")
        guard components.first == "www" else {
            return false
        }
        return components.dropFirst().joined(separator: ".") == eTldPlusOne(for: host)
    }

    private func eTldPlusOne(for host: String) -> String {
        tld.eTLDplus1(host) ?? host
    }

    private func containsHostAndPort(_ value: String) -> Bool {
        if let components = URLComponents(string: value),
           components.host != nil,
           components.port != nil {
            return true
        }

        if let components = URLComponents(string: "https://\(value)"),
           components.host != nil,
           components.port != nil {
            return true
        }

        return false
    }

    private func nonEmptyString(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }

    @available(iOS 26, *)
    private func sourceIdentifier(from credentialData: ASExportedCredentialData) -> String {
        nonEmptyString(credentialData.exporterRelyingPartyIdentifier) ?? DataImportHubPixelConstants.unknownSource
    }
}

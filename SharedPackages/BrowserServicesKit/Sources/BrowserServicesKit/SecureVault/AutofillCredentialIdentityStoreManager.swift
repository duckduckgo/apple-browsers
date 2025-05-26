//
//  AutofillCredentialIdentityStoreManager.swift
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

import Foundation
import AuthenticationServices
import Common
import SecureStorage
import os.log

public protocol AutofillCredentialIdentityStoreManaging {
    func credentialStoreStateEnabled() async -> Bool
    func populateCredentialStore() async
    func replaceCredentialStore(with accounts: [SecureVaultModels.WebsiteAccount]) async
    func updateCredentialStore(for domain: String) async
    func updateCredentialStoreWith(updatedAccounts: [SecureVaultModels.WebsiteAccount], deletedAccounts: [SecureVaultModels.WebsiteAccount]) async
}

final public class AutofillCredentialIdentityStoreManager: AutofillCredentialIdentityStoreManaging {

    private let credentialStore: ASCredentialIdentityStoring
    private var vault: (any AutofillSecureVault)?
    private let reporter: SecureVaultReporting
    private let tld: TLD

    public init(credentialStore: ASCredentialIdentityStoring = ASCredentialIdentityStore.shared,
                vault: (any AutofillSecureVault)? = nil,
                reporter: SecureVaultReporting,
                tld: TLD) {
        self.credentialStore = credentialStore
        self.vault = vault
        self.reporter = reporter
        self.tld = tld
    }

    // MARK: - Credential Store State

    public func credentialStoreStateEnabled() async -> Bool {
        let state = await credentialStore.state()
        return state.isEnabled
    }

    // MARK: - Credential Store Operations

    public func populateCredentialStore() async {
        guard await credentialStoreStateEnabled() else { return }

        do {
            let accounts = try fetchAccounts()
            try await generateAndSaveCredentialIdentities(from: accounts)
        } catch {
            Logger.autofill.error("Failed to populate credential store: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func replaceCredentialStore(with accounts: [SecureVaultModels.WebsiteAccount]) async {
        guard await credentialStoreStateEnabled() else { return }

        do {
            if #available(iOS 17, macOS 14.0, *) {
                let credentialIdentities = try await generateCredentialIdentities(from: accounts) as [any ASCredentialIdentity]
                try await replaceCredentialStoreIdentities(credentialIdentities)
            } else {
                let credentialIdentities = try await generateCredentialIdentities(from: accounts) as [ASPasswordCredentialIdentity]
                try await replaceCredentialStoreIdentities(with: credentialIdentities)
            }
        } catch {
            Logger.autofill.error("Failed to replace credential store: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func updateCredentialStore(for domain: String) async {
        guard await credentialStoreStateEnabled() else { return }

        do {
            if await storeSupportsIncrementalUpdates() {
                let accounts = try fetchAccountsFor(domain: domain)
                try await generateAndSaveCredentialIdentities(from: accounts)
            } else {
                await replaceCredentialStore()
            }
        } catch {
            Logger.autofill.error("Failed to update credential store \(error.localizedDescription, privacy: .public)")
        }
    }

    public func updateCredentialStoreWith(updatedAccounts: [SecureVaultModels.WebsiteAccount], deletedAccounts: [SecureVaultModels.WebsiteAccount]) async {
        guard await credentialStoreStateEnabled() else { return }

        do {
            if await storeSupportsIncrementalUpdates() {
                if !updatedAccounts.isEmpty {
                    try await generateAndSaveCredentialIdentities(from: updatedAccounts)
                }

                if !deletedAccounts.isEmpty {
                    try await generateAndDeleteCredentialIdentities(from: deletedAccounts)
                }
            } else {
                await replaceCredentialStore()
            }
        } catch {
            Logger.autofill.error("Failed to update credential store with updated / deleted accounts \(error.localizedDescription, privacy: .public)")
        }

    }

    // MARK: - Private Store Operations

    private func storeSupportsIncrementalUpdates() async -> Bool {
        let state = await credentialStore.state()
        return state.supportsIncrementalUpdates
    }

    private func replaceCredentialStore() async {
        guard await credentialStoreStateEnabled() else { return }

        do {
            let accounts = try fetchAccounts()

            Task {
                await replaceCredentialStore(with: accounts)
            }
        } catch {
            Logger.autofill.error("Failed to replace credential store: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func generateAndSaveCredentialIdentities(from accounts: [SecureVaultModels.WebsiteAccount]) async throws {
        if #available(iOS 17, macOS 14.0, *) {
            let credentialIdentities = try await generateCredentialIdentities(from: accounts) as [any ASCredentialIdentity]
            try await saveToCredentialStore(credentials: credentialIdentities)
        } else {
            let credentialIdentities = try await generateCredentialIdentities(from: accounts) as [ASPasswordCredentialIdentity]
            try await saveToCredentialStore(credentials: credentialIdentities)
        }
    }

    private func generateAndDeleteCredentialIdentities(from accounts: [SecureVaultModels.WebsiteAccount]) async throws {
        if #available(iOS 17, macOS 14.0, *) {
            let credentialIdentities = try await generateCredentialIdentities(from: accounts) as [any ASCredentialIdentity]
            try await removeCredentialStoreIdentities(credentialIdentities)
        } else {
            let credentialIdentities = try await generateCredentialIdentities(from: accounts) as [ASPasswordCredentialIdentity]
            try await removeCredentialStoreIdentities(credentialIdentities)
        }
    }

    private func saveToCredentialStore(credentials: [ASPasswordCredentialIdentity]) async throws {
        do {
            try await credentialStore.saveCredentialIdentities(credentials)
        } catch {
            Logger.autofill.error("Failed to save credentials to ASCredentialIdentityStore: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @available(iOS 17.0, macOS 14.0, *)
    private func saveToCredentialStore(credentials: [ASCredentialIdentity]) async throws {
        do {
            try await credentialStore.saveCredentialIdentities(credentials)
        } catch {
            Logger.autofill.error("Failed to save credentials to ASCredentialIdentityStore: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func replaceCredentialStoreIdentities(with credentials: [ASPasswordCredentialIdentity]) async throws {
        do {
            try await credentialStore.replaceCredentialIdentities(with: credentials)
        } catch {
            Logger.autofill.error("Failed to replace credentials in ASCredentialIdentityStore: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @available(iOS 17.0, macOS 14.0, *)
    private func replaceCredentialStoreIdentities(_ credentials: [ASCredentialIdentity]) async throws {
        do {
            try await credentialStore.replaceCredentialIdentities(credentials)
        } catch {
            Logger.autofill.error("Failed to replace credentials in ASCredentialIdentityStore: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func removeCredentialStoreIdentities(_ credentials: [ASPasswordCredentialIdentity]) async throws {
        do {
            try await credentialStore.removeCredentialIdentities(credentials)
        } catch {
            Logger.autofill.error("Failed to remove credentials from ASCredentialIdentityStore: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @available(iOS 17.0, macOS 14.0, *)
    private func removeCredentialStoreIdentities(_ credentials: [ASCredentialIdentity]) async throws {
        do {
            try await credentialStore.removeCredentialIdentities(credentials)
        } catch {
            Logger.autofill.error("Failed to remove credentials from ASCredentialIdentityStore: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func generateCredentialIdentities(from accounts: [SecureVaultModels.WebsiteAccount]) async throws -> [ASPasswordCredentialIdentity] {
            let sortedAndDedupedAccounts = accounts.sortedAndDeduplicated(tld: tld)
            let groupedAccounts = Dictionary(grouping: sortedAndDedupedAccounts, by: { $0.domain ?? "" })
            var credentialIdentities: [ASPasswordCredentialIdentity] = []

            for (_, accounts) in groupedAccounts {
                // Since accounts are sorted, ranking can be assigned based on index
                // but first need to be reversed as highest ranking should apply to the most recently used account
                for (rank, account) in accounts.reversed().enumerated() {
                    let credentialIdentity = createPasswordCredentialIdentity(from: account)
                    credentialIdentity.rank = rank
                    credentialIdentities.append(credentialIdentity)
                }
            }

            return credentialIdentities
    }

    private func createPasswordCredentialIdentity(from account: SecureVaultModels.WebsiteAccount) -> ASPasswordCredentialIdentity {
        let serviceIdentifier = ASCredentialServiceIdentifier(identifier: account.domain ?? "", type: .domain)
        return ASPasswordCredentialIdentity(serviceIdentifier: serviceIdentifier,
                                            user: account.username ?? "",
                                            recordIdentifier: account.id)
    }

    // MARK: - Private Secure Vault Operations

    private func secureVault() -> (any AutofillSecureVault)? {
        if vault == nil {
            vault = try? AutofillSecureVaultFactory.makeVault(reporter: reporter)
        }
        return vault
    }

    private func fetchAccounts() throws -> [SecureVaultModels.WebsiteAccount] {
        guard let vault = secureVault() else {
            Logger.autofill.error("Vault not created")
            return []
        }

        do {
            return try vault.accounts()
        } catch {
            Logger.autofill.error("Failed to fetch accounts \(error.localizedDescription, privacy: .public)")
            throw error
        }

    }

    private func fetchAccountsFor(domain: String) throws -> [SecureVaultModels.WebsiteAccount] {
        guard let vault = secureVault() else {
            Logger.autofill.error("Vault not created")
            return []
        }

        do {
            return try vault.accountsFor(domain: domain)
        } catch {
            Logger.autofill.error("Failed to fetch accounts \(error.localizedDescription, privacy: .public)")
            throw error
        }

    }
}

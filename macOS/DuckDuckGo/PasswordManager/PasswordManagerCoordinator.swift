//
//  PasswordManagerCoordinator.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Combine
import BWManagementShared
import Common
import PixelKit
import os.log

enum BWManagerProvider {

    static func makeManager(buildType: ApplicationBuildType = StandardApplicationBuildType()) -> BWManagement? {
        guard !buildType.isAppStoreBuild else {
            return nil
        }

        guard let factory = BWIntegrationFactory.self as? any BWManagementFactory.Type else {
            // BWIntegrationFactory is a shared namespace symbol that BWManagement implements in the
            // concrete package target. This keeps app code decoupled from BWManager.
            assertionFailure("Failed to instantiate Bitwarden manager factory")
            return nil
        }

        return factory.makeManager(isBitwardenPasswordManagerProvider: {
            AutofillPreferences().passwordManager == .bitwarden
        }, showRestartBitwardenAlert: { restart in
            BWNotRespondingAlert().present(restartBitwarden: restart)
        })
    }

}

protocol PasswordManagerCoordinating: BrowserServicesKit.PasswordManager {

    var displayName: String { get }
    var username: String? { get }
    var activeVaultEmail: String? { get }
    var bitwardenManagement: BWManagement? { get }

    func openPasswordManager()
    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials,
                                 completion: @escaping (Error?) -> Void)
    func reportPasswordAutofill()
    func reportPasswordSave()

}

// Encapsulation of third party password managers
final class PasswordManagerCoordinator: PasswordManagerCoordinating {

    enum PasswordManagerCoordinatorError: Error {
        case makingOfUrlFailed
    }

    let bitwardenManagement: BWManagement?

    var isEnabled: Bool {
        return bitwardenManagement?.status != .disabled
    }

    var name: String {
        return "bitwarden"
    }

    var displayName: String {
        return "Bitwarden"
    }

    var username: String? {
        guard let bitwardenManagement,
              case let .connected(vault: vault) = bitwardenManagement.status else {
            return nil
        }
        return vault.email
    }

    var isLocked: Bool {
        guard let bitwardenManagement else { return false }
        switch bitwardenManagement.status {
        case .connected(vault: let vault): return vault.status == .locked
        case .disabled: return false
        default: return true
        }
    }

    var activeVaultEmail: String? {
        guard let bitwardenManagement else { return nil }
        switch bitwardenManagement.status {
        case .connected(vault: let vault): return vault.email
        default: return nil
        }
    }

    var statusCancellable: AnyCancellable?

    init(bitwardenManagement: BWManagement?) {
        self.bitwardenManagement = bitwardenManagement
    }

    func setEnabled(_ enabled: Bool) {
        guard let bitwardenManagement else { return }
        if enabled {
            if !bitwardenManagement.status.isConnected {
                bitwardenManagement.initCommunication()
            }
        } else {
            bitwardenManagement.cancelCommunication()
        }
    }

    func askToUnlock(completionHandler: @escaping () -> Void) {
        guard let bitwardenManagement else { return }
        switch bitwardenManagement.status {
        case .disabled, .notInstalled, .oldVersion, .incompatible, .missingHandshake, .handshakeNotApproved, .error, .accessToContainersNotApproved:
            Task {
                await Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .autofill)
            }
            return
        default:
            break
        }

        bitwardenManagement.openBitwarden()

        statusCancellable = bitwardenManagement.statusPublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self = self else {
                    self?.statusCancellable?.cancel()
                    return
                }

                if case let .connected(vault: vault) = status,
                   vault.status == .unlocked {
                    self.statusCancellable?.cancel()
                    self.statusCancellable = nil
                    completionHandler()
                }
            }
    }

    func openPasswordManager() {
        bitwardenManagement?.openBitwarden()
    }

    func accountsFor(domain: String, completion: @escaping ([BrowserServicesKit.SecureVaultModels.WebsiteAccount], Error?) -> Void) {
        guard let bitwardenManagement else {
            completion([], nil)
            return
        }
        guard !isLocked else {
            completion([], nil)
            return
        }

        guard let url = URL(string: "https://\(domain)") else {
            completion([], PasswordManagerCoordinatorError.makingOfUrlFailed)
            return
        }

        bitwardenManagement.retrieveCredentials(for: url) { [weak self] credentials, error in
            if let error = error {
                completion([], error)
                return
            } else {
                let accounts = credentials.compactMap { return BrowserServicesKit.SecureVaultModels.WebsiteAccount(from: $0) }
                self?.cache(credentials: credentials, for: url)
                completion(accounts, nil)
            }
        }
    }

    func cachedAccountsFor(domain: String) -> [BrowserServicesKit.SecureVaultModels.WebsiteAccount] {
        return cache
            .filter { (_, credential) in
                credential.domain == domain
            }
            .compactMap {
                SecureVaultModels.WebsiteAccount(from: $0.value)
            }
    }
    func cachedWebsiteCredentialsFor(domain: String, username: String) -> BrowserServicesKit.SecureVaultModels.WebsiteCredentials? {
        if let credential: BWCredential = cache.values.first(where: { credential in
            credential.domain == domain && credential.username == username
        }) {
            return SecureVaultModels.WebsiteCredentials(from: credential)
        }
        return nil
    }

    func websiteCredentialsFor(accountId: String, completion: @escaping (BrowserServicesKit.SecureVaultModels.WebsiteCredentials?, Error?) -> Void) {
        guard !isLocked else {
            completion(nil, nil)
            return
        }

        if let credential = cache[accountId] {
            completion(BrowserServicesKit.SecureVaultModels.WebsiteCredentials(from: credential), nil)
        } else {
            assertionFailure("Credentials not cached")
            completion(nil, nil)
        }
    }

    func websiteCredentialsFor(domain: String, completion: @escaping ([BrowserServicesKit.SecureVaultModels.WebsiteCredentials], Error?) -> Void) {
        guard let bitwardenManagement else {
            completion([], nil)
            return
        }
        guard !isLocked else {
            completion([], nil)
            return
        }

        guard let url = URL(string: "https://\(domain)") else {
            completion([], PasswordManagerCoordinatorError.makingOfUrlFailed)
            return
        }

        bitwardenManagement.retrieveCredentials(for: url) { [weak self] credentials, error in
            if let error = error {
                completion([], error)
                return
            } else {
                self?.cache(credentials: credentials, for: url)
                let credentials = credentials.compactMap { BrowserServicesKit.SecureVaultModels.WebsiteCredentials(from: $0) }
                completion(credentials, nil)
            }
        }
    }

    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials,
                                 completion: @escaping (Error?) -> Void) {
        guard let bitwardenManagement,
              case let .connected(vault) = bitwardenManagement.status,
              let bitwardenCredential = BWCredential(from: credentials, vault: vault) else {
            Logger.general.fault("Failed to store credentials: Bitwarden is not connected or bad credential")
            assertionFailure("Bitwarden is not connected or bad credential")
            completion(nil)
            return
        }

        if bitwardenCredential.credentialId == nil {
            bitwardenManagement.create(credential: bitwardenCredential) { [weak self] error in
                self?.websiteCredentialsFor(domain: credentials.account.domain ?? "") { _, _ in
                    completion(error)
                }
            }
        } else {
            bitwardenManagement.update(credential: bitwardenCredential) { [weak self] error in
                self?.websiteCredentialsFor(domain: credentials.account.domain ?? "") { _, _ in
                    completion(error)
                }
            }
        }
    }

    func reportPasswordAutofill() {
        guard isEnabled else { return }

        PixelKit.fire(GeneralPixel.bitwardenPasswordAutofilled)
    }

    func reportPasswordSave() {
        guard isEnabled else { return }

        PixelKit.fire(GeneralPixel.bitwardenPasswordSaved)
    }

    // MARK: - Cache

    private func cache(credentials: [BWCredential], for url: URL) {
        cache.forEach { key, value in
            if value.domain == url.host {
                cache.removeValue(forKey: key)
            }
        }

        credentials.forEach { credential in
            if let credentialId = credential.credentialId {
                cache[credentialId] = credential
            }
        }
    }

    private var cache = [String: BWCredential]()

}

extension BrowserServicesKit.SecureVaultModels.WebsiteAccount {

    init?(from bitwardenCredential: BWCredential) {
        guard let credentialId = bitwardenCredential.credentialId else { return nil }
        self.init(id: credentialId,
                  username: bitwardenCredential.username ?? "",
                  domain: bitwardenCredential.domain,
                  created: Date(),
                  lastUpdated: Date())
    }

}

extension BrowserServicesKit.SecureVaultModels.WebsiteCredentials {

    init?(from bitwardenCredential: BWCredential, emptyPasswordAllowed: Bool = true) {
        guard let account = BrowserServicesKit.SecureVaultModels.WebsiteAccount(from: bitwardenCredential) else {
            assertionFailure("Failed to init account from BitwardenCredential")
            return nil
        }

        let passwordString = emptyPasswordAllowed ? bitwardenCredential.password ?? "" : bitwardenCredential.password

        guard let password = passwordString?.data(using: .utf8) else {
            assertionFailure("Failed to init account from BitwardenCredential")
            return nil
        }
        self.init(account: account, password: password)
    }

}

extension BWCredential {

    init?(from websiteCredentials: BrowserServicesKit.SecureVaultModels.WebsiteCredentials, vault: BWVault) {
        guard let domain = websiteCredentials.account.domain else { return nil }

        self.init(userId: vault.id,
                  credentialId: websiteCredentials.account.id,
                  credentialName: domain,
                  username: websiteCredentials.account.username,
                  password: websiteCredentials.password?.utf8String() ?? "",
                  domain: domain)
    }

}

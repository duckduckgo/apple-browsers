//
//  AutofillCredentialIdentityStoreManagerTests.swift
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

import XCTest
import AuthenticationServices
import Common
import SecureStorage
import SecureStorageTestsUtils
@testable import BrowserServicesKit

final class AutofillCredentialIdentityStoreManagerTests: XCTestCase {

    var mockCryptoProvider = MockCryptoProvider()
    var mockDatabaseProvider = (try! MockAutofillDatabaseProvider())
    var mockKeystoreProvider = MockKeystoreProvider()
    var mockVault: (any AutofillSecureVault)!
    var tld: TLD!

    var manager: AutofillCredentialIdentityStoreManaging!
    var mockStore: MockASCredentialIdentityStore!

    override func setUp() {
        super.setUp()
        mockStore = MockASCredentialIdentityStore()
        let providers = SecureStorageProviders(crypto: mockCryptoProvider,
                                               database: mockDatabaseProvider,
                                               keystore: mockKeystoreProvider)

        mockVault = DefaultAutofillSecureVault(providers: providers)

        tld = TLD()
        manager = AutofillCredentialIdentityStoreManager(credentialStore: mockStore, vault: mockVault, reporter: MockSecureVaultReporting(), tld: tld)
    }

    override func tearDown() {
        manager = nil
        mockStore = nil
        mockVault = nil
        tld = nil
        super.tearDown()
    }

    func testCredentialStoreStateEnabled() async {
        let isEnabled = await manager.credentialStoreStateEnabled()
        XCTAssertTrue(isEnabled)
    }

    func testPopulateCredentialStore() async throws {
        let accounts = [
            createWebsiteAccount(id: "1", domain: "example.com", username: "user1", signature: "1234"),
            createWebsiteAccount(id: "2", domain: "example.org", username: "user2", signature: "5678")
        ]

        mockDatabaseProvider._accounts = accounts
        await manager.populateCredentialStore()

        if #available(iOS 17.0, macOS 14.0, *) {
            XCTAssertEqual(mockStore.savedCredentialIdentities.count, 2)
        } else {
            XCTAssertEqual(mockStore.savedPasswordCredentialIdentities.count, 2)
        }
    }

    func testPopulateCredentialStoreWithDuplicateAccounts() async throws {
        let accounts = [
            createWebsiteAccount(id: "1", domain: "example.com", username: "user1", signature: "1234"),
            createWebsiteAccount(id: "1", domain: "example.com", username: "user1", signature: "1234")
        ]

        mockDatabaseProvider._accounts = accounts
        await manager.populateCredentialStore()

        if #available(iOS 17.0, macOS 14.0, *) {
            XCTAssertEqual(mockStore.savedCredentialIdentities.count, 1)
        } else {
            XCTAssertEqual(mockStore.savedPasswordCredentialIdentities.count, 1)
        }
    }

    func testReplaceCredentialStore() async throws {
        let accounts = [
            createWebsiteAccount(id: "1", domain: "example.com", username: "user1", signature: "1234"),
            createWebsiteAccount(id: "2", domain: "example.org", username: "user2", signature: "5678"),
            createWebsiteAccount(id: "3", domain: "example.org", username: "newUser3", signature: "44")
        ]

        mockDatabaseProvider._accounts = accounts
        await manager.populateCredentialStore()

        let replacementAccounts = [
            createWebsiteAccount(id: "1", domain: "example.com", username: "newUser1", signature: "123"),
            createWebsiteAccount(id: "2", domain: "example.org", username: "newUser2", signature: "567")
        ]
        mockDatabaseProvider._accounts = accounts

        await manager.replaceCredentialStore(with: replacementAccounts)

        if #available(iOS 17.0, macOS 14.0, *) {
            XCTAssertEqual(mockStore.savedCredentialIdentities.count, 2)
            // loop through the saved credential identities and check if the username is updated
            for identity in mockStore.savedCredentialIdentities {
                let replacedAccount = replacementAccounts.first { $0.id == identity.recordIdentifier }
                XCTAssertEqual(identity.user, replacedAccount?.username)
            }

        } else {
            XCTAssertEqual(mockStore.savedPasswordCredentialIdentities.count, 2)
            for identity in mockStore.savedPasswordCredentialIdentities {
                let replacedAccount = replacementAccounts.first { $0.id == identity.recordIdentifier }
                XCTAssertEqual(identity.user, replacedAccount?.username)
            }
        }
    }

    func testUpdateCredentialStoreForDomain() async {
        let accounts = [
            createWebsiteAccount(id: "1", domain: "example.com", username: "user1", signature: "1234"),
            createWebsiteAccount(id: "2", domain: "example.com", username: "user2", signature: "5678"),
            createWebsiteAccount(id: "3", domain: "example.com", username: "newUser3", signature: "44")
        ]

        mockDatabaseProvider._accounts = accounts
        await manager.populateCredentialStore()

        let updatedAccounts = [
            createWebsiteAccount(id: "1", domain: "example.com", username: "user1", signature: "1234", lastUsed: Date() - TimeInterval(60)),
            createWebsiteAccount(id: "2", domain: "example.com", username: "user2", signature: "5678", lastUpdated: Date() - TimeInterval(60)),
            createWebsiteAccount(id: "3", domain: "example.com", username: "newUser3", signature: "44", lastUsed: Date())
        ]
        mockDatabaseProvider._accounts = updatedAccounts

        await manager.updateCredentialStore(for: "example.com")

        if #available(iOS 17.0, macOS 14.0, *) {
            XCTAssertEqual(mockStore.savedCredentialIdentities.count, 3)

            let rankedCredentials = mockStore.savedCredentialIdentities.sorted { $0.rank < $1.rank }
            XCTAssertEqual(rankedCredentials[0].recordIdentifier, "2")
            XCTAssertEqual(rankedCredentials[1].recordIdentifier, "1")
            XCTAssertEqual(rankedCredentials[2].recordIdentifier, "3")
        } else {
            XCTAssertEqual(mockStore.savedPasswordCredentialIdentities.count, 3)

            let rankedCredentials = mockStore.savedPasswordCredentialIdentities.sorted { $0.rank < $1.rank }
            XCTAssertEqual(rankedCredentials[0].recordIdentifier, "2")
            XCTAssertEqual(rankedCredentials[1].recordIdentifier, "1")
            XCTAssertEqual(rankedCredentials[2].recordIdentifier, "3")

        }

    }

    func testUpdateCredentialStoreWithUpdatedAndDeletedAccounts() async {
        let accounts = [
            createWebsiteAccount(id: "1", domain: "example.com", username: "user1", signature: "1234"),
            createWebsiteAccount(id: "2", domain: "example.com", username: "user2", signature: "5678"),
            createWebsiteAccount(id: "3", domain: "example.com", username: "newUser3", signature: "44"),
            createWebsiteAccount(id: "4", domain: "example.com", username: "user4", signature: "4422")
        ]

        mockDatabaseProvider._accounts = accounts
        await manager.populateCredentialStore()

        let updatedAccounts = [
            createWebsiteAccount(id: "1", domain: "example.com", username: "user1a", signature: "1234", lastUsed: Date() - TimeInterval(60)),
            createWebsiteAccount(id: "2", domain: "example.com", username: "user2b", signature: "5678"),
            createWebsiteAccount(id: "5", domain: "example.com", username: "user5IsNew", signature: "1111")
        ]

        let deletedAccounts = [
            createWebsiteAccount(id: "3", domain: "example.com", username: "newUser3", signature: "44")
        ]

        await manager.updateCredentialStoreWith(updatedAccounts: updatedAccounts, deletedAccounts: deletedAccounts)
        if #available(iOS 17.0, macOS 14.0, *) {
            XCTAssertEqual(mockStore.savedCredentialIdentities.count, 4)
            XCTAssertEqual(mockStore.savedCredentialIdentities.first { $0.recordIdentifier == "1" }?.user, "user1a")
            XCTAssertEqual(mockStore.savedCredentialIdentities.first { $0.recordIdentifier == "2" }?.user, "user2b")
            XCTAssertEqual(mockStore.savedCredentialIdentities.first { $0.recordIdentifier == "5" }?.user, "user5IsNew")
            XCTAssertNil(mockStore.savedCredentialIdentities.first { $0.recordIdentifier == "3" })
        } else {
            XCTAssertEqual(mockStore.savedPasswordCredentialIdentities.count, 4)
        }
    }

    // MARK: - Helper Methods

    private func createWebsiteAccount(id: String, domain: String, username: String, signature: String, created: Date = Date(), lastUpdated: Date = Date(), lastUsed: Date? = nil) -> SecureVaultModels.WebsiteAccount {
        return SecureVaultModels.WebsiteAccount(id: id, username: username, domain: domain, signature: signature, created: created, lastUpdated: lastUpdated, lastUsed: lastUsed)
    }

}

private class MockSecureVaultReporting: SecureVaultReporting {
    func secureVaultError(_ error: SecureStorage.SecureStorageError) {}
}

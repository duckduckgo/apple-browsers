//
//  MockAutofillDatabaseProvider.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import GRDB
import SecureStorage
import Common

@testable import BrowserServicesKit

private extension URL {
    static let duckduckgo = URL(string: "https://duckduckgo.com/")!
}

internal class MockAutofillDatabaseProvider: AutofillDatabaseProvider {

    var _accounts = [SecureVaultModels.WebsiteAccount]()
    var _neverPromptWebsites = [SecureVaultModels.NeverPromptWebsites]()
    var _notes = [SecureVaultModels.Note]()
    var _identities = [Int64: SecureVaultModels.Identity]()
    var _creditCards = [Int64: SecureVaultModels.CreditCard]()
    var _forDomain = [String]()
    var _credentialsDict = [Int64: SecureVaultModels.WebsiteCredentials]()
    var _credentialsForDomainDict = [String: [SecureVaultModels.WebsiteCredentials]]()
    var _note: SecureVaultModels.Note?

    var db: DatabaseWriter

    required init(file: URL = .duckduckgo, key: Data = Data()) throws {
        self.db = try! DatabaseQueue(named: "TestQueue")
    }

    static func recreateDatabase(withKey key: Data) throws -> Self {
        return try MockAutofillDatabaseProvider(file: URL(string: "https://duck.com")!, key: Data()) as! Self
    }

    func hasAccountFor(username: String?, domain: String?) throws -> Bool {
        false
    }

    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64 {
        if let accountIdString = credentials.account.id, let accountID = Int64(accountIdString) {
            _credentialsDict[accountID] = credentials
            return accountID
        } else {
            var credentialsToStore = credentials
            let id = Int64(_credentialsDict.count + 1)
            credentialsToStore.account.id = String(id)
            _credentialsDict[id] = credentialsToStore
            _accounts.append(credentialsToStore.account)
            return id
        }
    }

    func websiteCredentialsForAccountId(_ accountId: Int64) throws -> SecureVaultModels.WebsiteCredentials? {
        return _credentialsDict[accountId]
    }

    func websiteCredentialsForDomain(_ domain: String) throws -> [BrowserServicesKit.SecureVaultModels.WebsiteCredentials] {
        return _credentialsForDomainDict[domain] ?? _credentialsDict.values.filter {
            $0.account.domain == domain
        }
    }

    func websiteCredentialsForTopLevelDomain(_ eTLDplus1: String) throws -> [BrowserServicesKit.SecureVaultModels.WebsiteCredentials] {
        return _credentialsForDomainDict[eTLDplus1] ?? _credentialsDict.values.filter {
            TLD().eTLDplus1($0.account.domain) == eTLDplus1
        }
    }

    func websiteAccountsForDomain(_ domain: String) throws -> [SecureVaultModels.WebsiteAccount] {
        self._forDomain.append(domain)
        return _accounts
    }

    func websiteAccountsForTopLevelDomain(_ eTLDplus1: String) throws -> [SecureVaultModels.WebsiteAccount] {
        self._forDomain.append(eTLDplus1)
        return _accounts
    }

    func updateLastUsedForAccountId(_ accountId: Int64) throws {
        if var account = _accounts.first(where: { $0.id == String(accountId) }) {
            account.lastUsed = Date()
        }
    }

    func deleteWebsiteCredentialsForAccountId(_ accountId: Int64) throws {
        self._credentialsDict.removeValue(forKey: accountId)
        self._accounts = self._accounts.filter { $0.id != String(accountId) }
    }

    func deleteAllWebsiteCredentials() throws {
        self._credentialsDict.removeAll()
        self._accounts.removeAll()
    }

    func accounts() throws -> [SecureVaultModels.WebsiteAccount] {
        return _accounts
    }

    func accountsCount() throws -> Int {
        return _accounts.count
    }

    func notes() throws -> [SecureVaultModels.Note] {
        return _notes
    }

    func noteForNoteId(_ noteId: Int64) throws -> SecureVaultModels.Note? {
        return _note
    }

    func deleteNoteForNoteId(_ noteId: Int64) throws {
        self._notes = self._notes.filter { $0.id != noteId }
    }

    func storeNote(_ note: SecureVaultModels.Note) throws -> Int64 {
        _note = note
        return note.id ?? -1
    }

    func identities() throws -> [SecureVaultModels.Identity] {
        return Array(_identities.values)
    }

    func identitiesCount() throws -> Int {
        return _identities.count
    }

    func identityForIdentityId(_ identityId: Int64) throws -> SecureVaultModels.Identity? {
        return _identities[identityId]
    }

    func storeIdentity(_ identity: SecureVaultModels.Identity) throws -> Int64 {
        if let identityID = identity.id {
            _identities[identityID] = identity
            return identityID
        } else {
            return -1
        }
    }

    func deleteIdentityForIdentityId(_ identityId: Int64) throws {
        _identities.removeValue(forKey: identityId)
    }

    func creditCards() throws -> [SecureVaultModels.CreditCard] {
        return Array(_creditCards.values)
    }

    func creditCardsCount() throws -> Int {
        return _creditCards.count
    }

    func creditCardForCardId(_ cardId: Int64) throws -> SecureVaultModels.CreditCard? {
        return _creditCards[cardId]
    }

    func storeCreditCard(_ creditCard: SecureVaultModels.CreditCard) throws -> Int64 {
        if let cardID = creditCard.id {
            _creditCards[cardID] = creditCard
            return cardID
        } else {
            return -1
        }
    }

    func deleteCreditCardForCreditCardId(_ cardId: Int64) throws {
        _creditCards.removeValue(forKey: cardId)
    }

    func inTransaction(_ block: @escaping (Database) throws -> Void) throws {
    }

    func updateSyncTimestamp(in database: Database, tableName: String, objectId: Int64, timestamp: Date?) throws {
    }

    func modifiedWebsiteCredentials() throws -> [SecureVaultModels.SyncableCredentials] {
        []
    }

    func modifiedSyncableCredentials(before date: Date) throws -> [SecureVaultModels.SyncableCredentials] {
        []
    }

    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials, in database: Database) throws -> Int64 {
        try storeWebsiteCredentials(credentials)
    }

    func deleteSyncableCredentials(_ metadata: SecureVaultModels.SyncableCredentials, in database: Database) throws {
        if let accountId = metadata.metadata.objectId {
            try deleteWebsiteCredentialsForAccountId(accountId)
        }
    }

    func syncableCredentialsForSyncIds(_ syncIds: any Sequence<String>, in database: Database) throws -> [SecureVaultModels.SyncableCredentials] {
        []
    }

    func websiteCredentialsForAccountId(_ accountId: Int64, in database: Database) throws -> SecureVaultModels.WebsiteCredentials? {
        try websiteCredentialsForAccountId(accountId)
    }

    func syncableCredentialsForAccountId(_ accountId: Int64, in database: Database) throws -> SecureVaultModels.SyncableCredentials? {
        nil
    }

    func websiteAccountsForDomain(_ domain: String, in database: Database) throws -> [SecureVaultModels.WebsiteAccount] {
        try websiteAccountsForDomain(domain)
    }

    func storeSyncableCredentials(_ metadata: SecureVaultModels.SyncableCredentials, in database: GRDB.Database) throws {
    }

    func modifiedSyncableCredentials() throws -> [SecureVaultModels.SyncableCredentials] {
        []
    }

    func neverPromptWebsites() throws -> [SecureVaultModels.NeverPromptWebsites] {
        return _neverPromptWebsites
    }

    func hasNeverPromptWebsitesFor(domain: String) throws -> Bool {
        return !_neverPromptWebsites.filter { $0.domain == domain }.isEmpty
    }

    func storeNeverPromptWebsite(_ neverPromptWebsite: SecureVaultModels.NeverPromptWebsites) throws -> Int64 {
        if let neverPromptWebsiteId = neverPromptWebsite.id {
            _neverPromptWebsites.append(neverPromptWebsite)
            return neverPromptWebsiteId
        } else {
            return -1
        }
    }

    func deleteAllNeverPromptWebsites() throws {
        _neverPromptWebsites.removeAll()
    }

    func updateNeverPromptWebsite(_ neverPromptWebsite: SecureVaultModels.NeverPromptWebsites) throws {
    }

    func insertNeverPromptWebsite(_ neverPromptWebsite: SecureVaultModels.NeverPromptWebsites) throws {
    }

}

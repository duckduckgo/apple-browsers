//
//  CredentialsProviderTestsBase.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import DDGSync
import Foundation
import GRDB
import Persistence
import SecureStorage
@testable import BrowserServicesKit
@testable import SyncDataProviders

final class MockSecureVaultErrorReporter: SecureVaultReporting {
    var _secureVaultInitFailed: (SecureStorageError) -> Void = { _ in }
    func secureVaultError(_ error: SecureStorageError) {
        _secureVaultInitFailed(error)
    }
}

internal class CredentialsProviderTestsBase: XCTestCase {

    let simpleL1Key = "simple-key".data(using: .utf8)!
    var databaseLocation: URL!
    var databaseProvider: DefaultAutofillDatabaseProvider!

    var metadataDatabase: CoreDataDatabase!
    var metadataDatabaseLocation: URL!

    var crypter = CryptingMock()
    var provider: CredentialsProvider!

    var secureVaultFactory: AutofillVaultFactory!
    var secureVault: (any AutofillSecureVault)!

    func setUpSyncMetadataDatabase() {
        metadataDatabaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = DDGSync.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "SyncMetadata") else {
            XCTFail("Failed to load model")
            return
        }
        metadataDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: metadataDatabaseLocation, model: model)
        metadataDatabase.loadStore()
    }

    func deleteDbFile() throws {
        do {
            let dbFileContainer = databaseLocation.deletingLastPathComponent()
            for file in try FileManager.default.contentsOfDirectory(atPath: dbFileContainer.path) {
                guard ["db", "bak"].contains((file as NSString).pathExtension) else { continue }
                try FileManager.default.removeItem(atPath: dbFileContainer.appendingPathComponent(file).path)
            }

        } catch let error as NSError {
            // File not found
            if error.domain != NSCocoaErrorDomain || error.code != 4 {
                throw error
            }
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        databaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        databaseProvider = try DefaultAutofillDatabaseProvider(file: databaseLocation, key: simpleL1Key)
        secureVaultFactory = AutofillVaultFactory.testFactory(databaseProvider: databaseProvider)
        try makeSecureVault()

        setUpSyncMetadataDatabase()

        provider = try CredentialsProvider(
            secureVaultFactory: secureVaultFactory,
            secureVaultErrorReporter: MockSecureVaultErrorReporter(),
            metadataStore: LocalSyncMetadataStore(database: metadataDatabase),
            syncDidUpdateData: {},
            syncDidFinish: { _ in }
        )
    }

    override func tearDownWithError() throws {
        try deleteDbFile()

        try? metadataDatabase.tearDown(deleteStores: true)
        metadataDatabase = nil
        try? FileManager.default.removeItem(at: metadataDatabaseLocation)

        try super.tearDownWithError()
    }

    // MARK: - Helpers

    func makeSecureVault() throws {
        secureVault = try secureVaultFactory.makeVault(reporter: nil)
        _ = try secureVault.authWith(password: "abcd".data(using: .utf8)!)
    }

    func fetchAllSyncableCredentials() throws -> [SecureVaultModels.SyncableCredentials] {
        try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableCredentials.query.fetchAll(database)
        }
    }

    func handleSyncResponse(sent: [Syncable] = [], received: [Syncable], clientTimestamp: Date = Date(), serverTimestamp: String = "1234") async throws {
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date = Date(), serverTimestamp: String = "1234") async throws {
        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }
}

extension AutofillSecureVault {
    func storeCredentials(domain: String? = nil, username: String? = nil, password: String? = nil, notes: String? = nil) throws {
        let passwordData = password.flatMap { $0.data(using: .utf8) }
        let account = SecureVaultModels.WebsiteAccount(username: username, domain: domain, notes: notes)
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
        try storeWebsiteCredentials(credentials)
    }

    func storeSyncableCredentials(
        _ uuid: String = UUID().uuidString,
        title: String? = nil,
        domain: String? = nil,
        username: String? = nil,
        password: String? = nil,
        notes: String? = nil,
        nullifyOtherFields: Bool = false,
        lastModified: Date? = nil,
        in database: Database? = nil
    ) throws {
        let defaultValue: String? = (nullifyOtherFields ? nil : uuid)

        let title = title ?? defaultValue
        let domain = domain ?? defaultValue
        let username = username ?? defaultValue
        let password = password ?? defaultValue
        let notes = notes ?? defaultValue

        let passwordData = password.flatMap { $0.data(using: .utf8) }
        let account = SecureVaultModels.WebsiteAccount(title: title, username: username, domain: domain, notes: notes)
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
        let syncableCredentials = SecureVaultModels.SyncableCredentials(uuid: uuid, credentials: credentials, lastModified: lastModified?.withMillisecondPrecision)
        if let database {
            try storeSyncableCredentials(syncableCredentials, in: database, encryptedUsing: Data(), hashedUsing: nil)
        } else {
            try inDatabaseTransaction { try storeSyncableCredentials(syncableCredentials, in: $0, encryptedUsing: Data(), hashedUsing: nil) }
        }
    }
}

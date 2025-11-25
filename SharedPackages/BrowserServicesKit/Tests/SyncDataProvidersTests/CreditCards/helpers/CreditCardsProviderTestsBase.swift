//
//  CreditCardsProviderTestsBase.swift
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

import XCTest
import Common
import DDGSync
import Foundation
import GRDB
import Persistence
import SecureStorage
import SecureStorageTestsUtils
@testable import BrowserServicesKit
@testable import SyncDataProviders

internal class CreditCardsProviderTestsBase: XCTestCase {

    let simpleL1Key = "simple-key".data(using: .utf8)!
    var databaseLocation: URL!
    var databaseProvider: DefaultAutofillDatabaseProvider!

    var metadataDatabase: CoreDataDatabase!
    var metadataDatabaseLocation: URL!

    var crypter = CryptingMock()
    var provider: CreditCardsProvider!

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

        provider = try CreditCardsProvider(
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

    func fetchAllSyncableCreditCards() throws -> [SecureVaultModels.SyncableCreditCard] {
        try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableCreditCard.query.fetchAll(database)
        }
    }

    func handleSyncResponse(sent: [Syncable] = [], received: [Syncable], clientTimestamp: Date = Date(), serverTimestamp: String = "1234") async throws {
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date = Date(), serverTimestamp: String = "1234") async throws {
        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    // Some tests need to ensure we do not accidentally double-encrypt card data. The default
    // NoOp crypto used elsewhere returns plaintext and hides those regressions, so we rebuild
    // the vault with a bit-flipping crypto to surface any misuse of already encrypted blobs.
    func reinitializeVaultUsingBitFlipCryptoProvider() throws {
        try reinitializeVault(using: TestBitFlipCryptoProvider.init)
    }

    private func reinitializeVault(using makeCryptoProvider: @escaping () -> SecureStorageCryptoProvider) throws {
        let customFactory = AutofillVaultFactory(
            makeCryptoProvider: makeCryptoProvider,
            makeKeyStoreProvider: { _ in
                let provider = MockKeystoreProvider()
                provider._l1Key = "l1".data(using: .utf8)
                provider._encryptedL2Key = "encrypted".data(using: .utf8)
                provider._generatedPassword = "password".data(using: .utf8)
                return provider
            },
            makeDatabaseProvider: { [unowned self] _, _ in
                self.databaseProvider
            }
        )

        secureVaultFactory = customFactory
        try makeSecureVault()
        provider = try CreditCardsProvider(
            secureVaultFactory: secureVaultFactory,
            secureVaultErrorReporter: MockSecureVaultErrorReporter(),
            metadataStore: LocalSyncMetadataStore(database: metadataDatabase),
            syncDidUpdateData: {},
            syncDidFinish: { _ in }
        )
    }
}

extension AutofillSecureVault {
    func storeCreditCard(
        title: String? = nil,
        cardholderName: String? = nil,
        cardNumber: String,
        cardSecurityCode: String? = nil,
        expirationMonth: Int? = nil,
        expirationYear: Int? = nil
    ) throws {
        let creditCard = SecureVaultModels.CreditCard(
            title: title,
            cardNumber: cardNumber,
            cardholderName: cardholderName,
            cardSecurityCode: cardSecurityCode,
            expirationMonth: expirationMonth,
            expirationYear: expirationYear
        )
        try storeCreditCard(creditCard)
    }

    func storeSyncableCreditCard(
        _ uuid: String = UUID().uuidString,
        title: String? = nil,
        cardholderName: String? = nil,
        cardNumber: String,
        cardSecurityCode: String? = nil,
        expirationMonth: Int? = nil,
        expirationYear: Int? = nil,
        lastModified: Date? = nil,
        in database: Database? = nil
    ) throws {
        let creditCard = SecureVaultModels.CreditCard(
            title: title,
            cardNumber: cardNumber,
            cardholderName: cardholderName,
            cardSecurityCode: cardSecurityCode,
            expirationMonth: expirationMonth,
            expirationYear: expirationYear
        )
        let syncableCreditCard = SecureVaultModels.SyncableCreditCard(
            uuid: uuid,
            creditCard: creditCard,
            lastModified: lastModified?.withMillisecondPrecision
        )
        if let database {
            try storeSyncableCreditCard(syncableCreditCard, in: database, encryptedUsing: Data())
        } else {
            try inDatabaseTransaction { try storeSyncableCreditCard(syncableCreditCard, in: $0, encryptedUsing: Data()) }
        }
    }
}

// Implements an "encryption" that simply bit-flips every byte so encrypting twice is observable.
final class TestBitFlipCryptoProvider: SecureStorageCryptoProvider {

    var hashingSalt: Data?

    var passwordSalt: Data { Data() }
    var keychainServiceName: String { "service" }
    var keychainAccountName: String { "account" }

    func generateSecretKey() throws -> Data { Data("secret".utf8) }
    func generatePassword() throws -> Data { Data("password".utf8) }
    func deriveKeyFromPassword(_ password: Data) throws -> Data { password }
    func generateNonce() throws -> Data { Data() }

    func encrypt(_ data: Data, withKey key: Data) throws -> Data {
        Data(data.map { ~$0 })
    }

    func decrypt(_ data: Data, withKey key: Data) throws -> Data {
        Data(data.map { ~$0 })
    }

    func generateSalt() throws -> Data { Data() }
    func hashData(_ data: Data) throws -> String? { "" }
    func hashData(_ data: Data, salt: Data?) throws -> String? { "" }
}

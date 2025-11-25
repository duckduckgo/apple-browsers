//
//  IdentitiesProviderTestsBase.swift
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
@testable import BrowserServicesKit
@testable import SyncDataProviders

internal class IdentitiesProviderTestsBase: XCTestCase {

    let simpleL1Key = "simple-key".data(using: .utf8)!
    var databaseLocation: URL!
    var databaseProvider: DefaultAutofillDatabaseProvider!

    var metadataDatabase: CoreDataDatabase!
    var metadataDatabaseLocation: URL!

    var crypter = CryptingMock()
    var provider: IdentitiesProvider!

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

        provider = try IdentitiesProvider(
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

    func fetchAllSyncableIdentities() throws -> [SecureVaultModels.SyncableIdentity] {
        try databaseProvider.db.read { database in
            try SecureVaultModels.SyncableIdentity.query.fetchAll(database)
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

    func storeIdentity(
        title: String? = nil,
        firstName: String? = nil,
        middleName: String? = nil,
        lastName: String? = nil,
        birthdayDay: Int? = nil,
        birthdayMonth: Int? = nil,
        birthdayYear: Int? = nil,
        addressStreet: String? = nil,
        addressStreet2: String? = nil,
        addressCity: String? = nil,
        addressProvince: String? = nil,
        addressPostalCode: String? = nil,
        addressCountryCode: String? = nil,
        homePhone: String? = nil,
        emailAddress: String? = nil
    ) throws {
        let identity = SecureVaultModels.Identity(
            id: nil,
            title: title ?? "",
            created: Date(),
            lastUpdated: Date(),
            firstName: firstName,
            middleName: middleName,
            lastName: lastName,
            birthdayDay: birthdayDay,
            birthdayMonth: birthdayMonth,
            birthdayYear: birthdayYear,
            addressStreet: addressStreet,
            addressStreet2: addressStreet2,
            addressCity: addressCity,
            addressProvince: addressProvince,
            addressPostalCode: addressPostalCode,
            addressCountryCode: addressCountryCode,
            homePhone: homePhone,
            mobilePhone: nil,
            emailAddress: emailAddress
        )
        _ = try storeIdentity(identity)
    }

    func storeSyncableIdentity(
        _ uuid: String = UUID().uuidString,
        title: String? = nil,
        firstName: String? = nil,
        middleName: String? = nil,
        lastName: String? = nil,
        birthdayDay: Int? = nil,
        birthdayMonth: Int? = nil,
        birthdayYear: Int? = nil,
        addressStreet: String? = nil,
        addressStreet2: String? = nil,
        addressCity: String? = nil,
        addressProvince: String? = nil,
        addressPostalCode: String? = nil,
        addressCountryCode: String? = nil,
        homePhone: String? = nil,
        emailAddress: String? = nil,
        nullifyOtherFields: Bool = false,
        lastModified: Date? = nil,
        in database: Database? = nil
    ) throws {
        let defaultValue: String? = (nullifyOtherFields ? nil : uuid)

        let identity = SecureVaultModels.Identity(
            id: nil,
            title: title ?? defaultValue ?? "",
            created: Date(),
            lastUpdated: Date(),
            firstName: firstName ?? defaultValue,
            middleName: middleName ?? defaultValue,
            lastName: lastName ?? defaultValue,
            birthdayDay: birthdayDay,
            birthdayMonth: birthdayMonth,
            birthdayYear: birthdayYear,
            addressStreet: addressStreet ?? defaultValue,
            addressStreet2: addressStreet2 ?? defaultValue,
            addressCity: addressCity ?? defaultValue,
            addressProvince: addressProvince ?? defaultValue,
            addressPostalCode: addressPostalCode ?? defaultValue,
            addressCountryCode: addressCountryCode ?? defaultValue,
            homePhone: homePhone ?? defaultValue,
            mobilePhone: nil,
            emailAddress: emailAddress ?? defaultValue
        )

        let syncableIdentity = SecureVaultModels.SyncableIdentity(
            uuid: uuid,
            identity: identity,
            lastModified: lastModified?.withMillisecondPrecision
        )

        if let database {
            try storeSyncableIdentity(syncableIdentity, in: database)
        } else {
            try inDatabaseTransaction { try storeSyncableIdentity(syncableIdentity, in: $0) }
        }
    }
}

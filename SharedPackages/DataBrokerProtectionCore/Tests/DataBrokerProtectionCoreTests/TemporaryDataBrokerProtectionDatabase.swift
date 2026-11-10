//
//  TemporaryDataBrokerProtectionDatabase.swift
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
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
import SecureStorage
import SecureStorageTestsUtils

final class TemporaryDataBrokerProtectionDatabase {

    let database: DataBrokerProtectionDatabase
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DBPTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseProvider = try DefaultDataBrokerProtectionDatabaseProvider(
            file: directory.appendingPathComponent("Vault.db"),
            key: "key".data(using: .utf8)!,
            registerMigrationsHandler: DefaultDataBrokerProtectionDatabaseMigrationsProvider.v10Migrations
        )
        let keyStoreProvider = MockKeystoreProvider()
        keyStoreProvider._encryptedL2Key = "encryptedL2".data(using: .utf8)!
        keyStoreProvider._generatedPassword = "generatedPassword".data(using: .utf8)!
        let vault = DefaultDataBrokerProtectionSecureVault(providers: SecureStorageProviders(
            crypto: NoOpCryptoProvider(),
            database: databaseProvider,
            keystore: keyStoreProvider
        ))

        database = DataBrokerProtectionDatabase(fakeBrokerFlag: DataBrokerDebugFlagFakeBroker(),
                                                pixelHandler: MockDataBrokerProtectionPixelsHandler(),
                                                vault: vault,
                                                localBrokerService: MockLocalBrokerJSONService())
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func saveProfile() async throws {
        try await database.save(DataBrokerProtectionProfile(names: [.init(firstName: "John", lastName: "Doe")],
                                                            addresses: [.init(city: "New York", state: "NY")],
                                                            phones: [],
                                                            birthYear: 1970))
    }

    func saveBroker(fixture: String) throws -> (brokerId: Int64, profileQueryId: Int64) {
        let jsonURL = Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "BundleResources")!
        let brokerId = try database.saveBroker(brokerResource: DataBroker.initFromResource(jsonURL))
        let profileQuery = ProfileQuery(firstName: "John", lastName: "Doe", city: "New York", state: "NY", birthYear: 1970)
        let profileQueryId = try database.saveProfileQuery(profileQuery: profileQuery, profileId: 1)
        try database.saveScanJob(brokerId: brokerId, profileQueryId: profileQueryId, lastRunDate: nil, preferredRunDate: Date())
        return (brokerId, profileQueryId)
    }
}

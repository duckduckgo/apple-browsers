//
//  DataBrokerProtectionProfileTests.swift
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
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
import BrowserServicesKit
import SecureStorage
import SecureStorageTestsUtils

final class DataBrokerProtectionProfileTests: XCTestCase {
    func testProfileQueriesWithSingleAddressMultipleNames() {
        let profile = DataBrokerProtectionProfile(
            names: [
                DataBrokerProtectionProfile.Name(firstName: "John", lastName: "Doe"),
                DataBrokerProtectionProfile.Name(firstName: "Jane", lastName: "Smith")
            ],
            addresses: [
                DataBrokerProtectionProfile.Address(city: "New York", state: "NY")
            ],
            phones: [String](),
            birthYear: 1980
        )

        let queries = profile.profileQueries

        XCTAssertEqual(queries.count, 2)

        let expectedQueries = [
            ProfileQuery(
                firstName: "John",
                lastName: "Doe",
                city: "New York",
                state: "NY",
                birthYear: 1980),
            ProfileQuery(
                firstName: "Jane",
                lastName: "Smith",
                city: "New York",
                state: "NY",
                birthYear: 1980)
        ]

        XCTAssertTrue(queries.contains { query in
            expectedQueries.contains { $0 == query }
        })
    }

    func testProfileQueriesWithMultipleAddressesSingleName() {
        let profile = DataBrokerProtectionProfile(
            names: [
                DataBrokerProtectionProfile.Name(firstName: "John", lastName: "Doe")
            ],
            addresses: [
                DataBrokerProtectionProfile.Address(city: "New York", state: "NY"),
                DataBrokerProtectionProfile.Address(city: "Los Angeles", state: "CA")
            ],
            phones: [String](),
            birthYear: 1980
        )

        let queries = profile.profileQueries

        XCTAssertEqual(queries.count, 2)

        let expectedQueries = [
            ProfileQuery(
                firstName: "John",
                lastName: "Doe",
                city: "New York",
                state: "NY",
                birthYear: 1980
            ),
            ProfileQuery(
                firstName: "John",
                lastName: "Doe",
                city: "Los Angeles",
                state: "CA",
                birthYear: 1980
            )
        ]

        XCTAssertEqual(queries.sorted(), expectedQueries.sorted())

    }

    func testProfileQueriesWithMultipleAddressesAndNames() {
        let profile = DataBrokerProtectionProfile(
            names: [
                DataBrokerProtectionProfile.Name(firstName: "John", lastName: "Doe"),
                DataBrokerProtectionProfile.Name(firstName: "Jane", lastName: "Smith")
            ],
            addresses: [
                DataBrokerProtectionProfile.Address(city: "New York", state: "NY"),
                DataBrokerProtectionProfile.Address(city: "Los Angeles", state: "CA")
            ],
            phones: [String](),
            birthYear: 1980
        )

        let queries = profile.profileQueries

        XCTAssertEqual(queries.count, 4)

        let expectedQueries = [
            ProfileQuery(
                firstName: "John",
                lastName: "Doe",
                city: "New York",
                state: "NY",
                birthYear: 1980
            ),
            ProfileQuery(
                firstName: "John",
                lastName: "Doe",
                city: "Los Angeles",
                state: "CA",
                birthYear: 1980
            ),
            ProfileQuery(
                firstName: "Jane",
                lastName: "Smith",
                city: "New York",
                state: "NY",
                birthYear: 1980
            ),
            ProfileQuery(
                firstName: "Jane",
                lastName: "Smith",
                city: "Los Angeles",
                state: "CA",
                birthYear: 1980
            )
        ]
        XCTAssertEqual(queries.sorted(), expectedQueries.sorted())
    }

    func testProfileQueriesWithNoNamesAndAddresses() {
        let profile = DataBrokerProtectionProfile(names: [], addresses: [], phones: [String](), birthYear: 1980)

        let queries = profile.profileQueries

        XCTAssertEqual(queries.count, 0)
    }

    func testSaveNewProfileQuery_thenSaveProfileQueryIsCalled() async throws {
        let vault: DataBrokerProtectionSecureVaultMock = try DataBrokerProtectionSecureVaultMock(providers:
                                                            SecureStorageProviders(
                                                                crypto: EmptySecureStorageCryptoProviderMock(),
                                                                database: SecureStorageDatabaseProviderMock(),
                                                                keystore: EmptySecureStorageKeyStoreProviderMock()))

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: DataBrokerDebugFlagFakeBroker(),
                                                    pixelHandler: MockDataBrokerProtectionPixelsHandler(),
                                                    vault: vault,
                                                    localBrokerService: MockLocalBrokerJSONService())

        let profile = DataBrokerProtectionProfile(
            names: [
                DataBrokerProtectionProfile.Name(firstName: "John", lastName: "Doe"),
            ],
            addresses: [
                DataBrokerProtectionProfile.Address(city: "New York", state: "NY"),
            ],
            phones: [String](),
            birthYear: 1980
        )

        _ = try! await database.save(profile)
        XCTAssertTrue(vault.wasSaveProfileQueryCalled)
        XCTAssertFalse(vault.wasUpdateProfileQueryCalled)
        XCTAssertFalse(vault.wasDeleteProfileQueryCalled)
    }

    func testSaveNewProfileWithSavedQueriesWithOptOut_thenSaveNewProfileQueryAndUpdateProfileQueryIsCalled() async throws {
        let vault: DataBrokerProtectionSecureVaultMock = try DataBrokerProtectionSecureVaultMock(providers:
                                                            SecureStorageProviders(
                                                                crypto: EmptySecureStorageCryptoProviderMock(),
                                                                database: SecureStorageDatabaseProviderMock(),
                                                                keystore: EmptySecureStorageKeyStoreProviderMock()))

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: DataBrokerDebugFlagFakeBroker(),
                                                    pixelHandler: MockDataBrokerProtectionPixelsHandler(),
                                                    vault: vault,
                                                    localBrokerService: MockLocalBrokerJSONService())

        vault.brokers = [DataBroker.mock]
        vault.profileQueries = [ProfileQuery.mock]
        vault.scanJobData = [ScanJobData.mock]
        vault.optOutJobData = [OptOutJobData.mock(with: ExtractedProfile.mockWithoutRemovedDate)]

        vault.profile = DataBrokerProtectionProfile(
            names: [
                DataBrokerProtectionProfile.Name(firstName: "John", lastName: "Doe"),
            ],
            addresses: [
                DataBrokerProtectionProfile.Address(city: "New York", state: "NY"),
            ],
            phones: [String](),
            birthYear: 1980
        )

        let newProfile = DataBrokerProtectionProfile(
            names: [
                DataBrokerProtectionProfile.Name(firstName: "John", lastName: "Smith"),
            ],
            addresses: [
                DataBrokerProtectionProfile.Address(city: "New York", state: "NY"),
            ],
            phones: [String](),
            birthYear: 1980
        )

        _ = try! await database.save(newProfile)

        XCTAssertTrue(vault.wasSaveProfileQueryCalled)
        XCTAssertTrue(vault.wasUpdateProfileQueryCalled)
        XCTAssertFalse(vault.wasDeleteProfileQueryCalled)
    }

    func testSaveNewProfileWithoutSavedQueriesWithOptOut_thenSaveNewProfileQueryAndDeleteProfileQueryIsCalled() async throws {
        let vault: DataBrokerProtectionSecureVaultMock = try DataBrokerProtectionSecureVaultMock(providers:
                                                            SecureStorageProviders(
                                                                crypto: EmptySecureStorageCryptoProviderMock(),
                                                                database: SecureStorageDatabaseProviderMock(),
                                                                keystore: EmptySecureStorageKeyStoreProviderMock()))

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: DataBrokerDebugFlagFakeBroker(),
                                                    pixelHandler: MockDataBrokerProtectionPixelsHandler(),
                                                    vault: vault,
                                                    localBrokerService: MockLocalBrokerJSONService())

        vault.brokers = [DataBroker.mock]
        vault.profileQueries = [ProfileQuery.mock]
        vault.scanJobData = [ScanJobData.mock]

        vault.profile = DataBrokerProtectionProfile(
            names: [
                DataBrokerProtectionProfile.Name(firstName: "John", lastName: "Doe"),
            ],
            addresses: [
                DataBrokerProtectionProfile.Address(city: "New York", state: "NY"),
            ],
            phones: [String](),
            birthYear: 1980
        )

        let newProfile = DataBrokerProtectionProfile(
            names: [
                DataBrokerProtectionProfile.Name(firstName: "John", lastName: "Smith"),
            ],
            addresses: [
                DataBrokerProtectionProfile.Address(city: "New York", state: "NY"),
            ],
            phones: [String](),
            birthYear: 1980
        )

        _ = try! await database.save(newProfile)

        XCTAssertTrue(vault.wasSaveProfileQueryCalled)
        XCTAssertFalse(vault.wasUpdateProfileQueryCalled)
        XCTAssertTrue(vault.wasDeleteProfileQueryCalled)
    }

    func testChangingProfileThenChangingItBackReactivatesOriginalQuery() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DBPProfileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseProvider = try DefaultDataBrokerProtectionDatabaseProvider(
            file: temporaryDirectory.appendingPathComponent("Vault.db"),
            key: Data("key".utf8),
            registerMigrationsHandler: DefaultDataBrokerProtectionDatabaseMigrationsProvider.v10Migrations
        )
        let keyStoreProvider = MockKeystoreProvider()
        keyStoreProvider._encryptedL2Key = Data("encryptedL2".utf8)
        keyStoreProvider._generatedPassword = Data("generatedPassword".utf8)
        let vault = DefaultDataBrokerProtectionSecureVault(providers: SecureStorageProviders(
            crypto: NoOpCryptoProvider(),
            database: databaseProvider,
            keystore: keyStoreProvider
        ))
        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: DataBrokerDebugFlagFakeBroker(),
                                                    pixelHandler: MockDataBrokerProtectionPixelsHandler(),
                                                    vault: vault,
                                                    localBrokerService: MockLocalBrokerJSONService())

        let brokerURL = try XCTUnwrap(Bundle.module.url(forResource: "valid-broker",
                                                        withExtension: "json",
                                                        subdirectory: "BundleResources"))
        let brokerID = try database.saveBroker(brokerResource: DataBroker.initFromResource(brokerURL))
        let originalProfile = DataBrokerProtectionProfile(names: [.init(firstName: "Alice", lastName: "Example")],
                                                          addresses: [.init(city: "Testville", state: "CA")],
                                                          phones: [],
                                                          birthYear: 1980)
        let changedProfile = DataBrokerProtectionProfile(names: originalProfile.names,
                                                         addresses: originalProfile.addresses,
                                                         phones: originalProfile.phones,
                                                         birthYear: 1981)

        try await database.save(originalProfile)
        let originalQuery = try XCTUnwrap(vault.fetchAllProfileQueries(for: 1).first)
        let originalQueryID = try XCTUnwrap(originalQuery.id)
        try database.saveOptOutJob(
            optOut: .mock(with: ExtractedProfile(),
                          brokerId: brokerID,
                          profileQueryId: originalQueryID,
                          preferredRunDate: Date()),
            extractedProfile: ExtractedProfile()
        )

        try await database.save(changedProfile)

        let changedQueries = try vault.fetchAllProfileQueries(for: 1)
        XCTAssertTrue(try XCTUnwrap(changedQueries.first { $0.birthYear == 1980 }).deprecated)
        XCTAssertFalse(try XCTUnwrap(changedQueries.first { $0.birthYear == 1981 }).deprecated)

        let beforeRevert = Date()
        try await database.save(originalProfile)

        let finalQueries = try vault.fetchAllProfileQueries(for: 1)
        let reactivatedQuery = try XCTUnwrap(finalQueries.first { $0.birthYear == 1980 })
        XCTAssertEqual(reactivatedQuery.id, originalQueryID)
        XCTAssertFalse(reactivatedQuery.deprecated)
        XCTAssertNil(finalQueries.first { $0.birthYear == 1981 })

        let scan = try XCTUnwrap(vault.fetchScan(brokerId: brokerID, profileQueryId: originalQueryID))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(scan.preferredRunDate), beforeRevert)
        XCTAssertEqual(try vault.fetchOptOuts(brokerId: brokerID, profileQueryId: originalQueryID).count, 1)
    }
}

extension ProfileQuery: Comparable {

    public static func < (lhs: ProfileQuery, rhs: ProfileQuery) -> Bool {
        if lhs.firstName != rhs.firstName {
            return lhs.firstName < rhs.firstName
        } else if lhs.lastName != rhs.lastName {
            return lhs.lastName < rhs.lastName
        } else if lhs.city != rhs.city {
            return lhs.city < rhs.city
        } else if lhs.state != rhs.state {
            return lhs.state < rhs.state
        } else if lhs.age != rhs.age {
            return lhs.age < rhs.age
        } else {
            return lhs.fullName < rhs.fullName
        }
    }
}

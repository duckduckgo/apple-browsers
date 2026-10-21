//
//  EarliestBeginDateForBackgroundTaskCalculationTests.swift
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
import GRDB
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
import SecureStorage
import BrowserServicesKit
import SecureStorageTestsUtils

final class EarliestBeginDateForBackgroundTaskCalculationTests: XCTestCase {

    private var databaseProvider: DefaultDataBrokerProtectionDatabaseProvider!
    private var database: DataBrokerProtectionDatabase!
    private var vaultURL: URL!
    private var vault: DefaultDataBrokerProtectionSecureVault<DefaultDataBrokerProtectionDatabaseProvider>!

    override func setUp() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let uniqueDirectory = temporaryDirectory.appendingPathComponent("DBPTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: uniqueDirectory, withIntermediateDirectories: true)
        vaultURL = uniqueDirectory.appendingPathComponent("Vault.db")

        databaseProvider = try DefaultDataBrokerProtectionDatabaseProvider(
            file: vaultURL,
            key: "key".data(using: .utf8)!,
            registerMigrationsHandler: DefaultDataBrokerProtectionDatabaseMigrationsProvider.v10Migrations
        )

        let cryptoProvider = NoOpCryptoProvider()

        let keyStoreProvider = MockKeystoreProvider()
        keyStoreProvider._encryptedL2Key = "encryptedL2".data(using: .utf8)!
        keyStoreProvider._generatedPassword = "generatedPassword".data(using: .utf8)!

        vault = DefaultDataBrokerProtectionSecureVault(providers: SecureStorageProviders(
            crypto: cryptoProvider,
            database: databaseProvider,
            keystore: keyStoreProvider
        ))

        database = DataBrokerProtectionDatabase(
            fakeBrokerFlag: DataBrokerDebugFlagFakeBroker(),
            pixelHandler: MockDataBrokerProtectionPixelsHandler(),
            vault: vault,
            localBrokerService: MockLocalBrokerJSONService()
        )
    }

    override func tearDownWithError() throws {
        if let vaultURL = vaultURL {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: vaultURL.path) {
                try fileManager.removeItem(at: vaultURL)
            }
            let testDirectory = vaultURL.deletingLastPathComponent()
            if fileManager.fileExists(atPath: testDirectory.path) {
                try? fileManager.removeItem(at: testDirectory)
            }
        }
    }

    func testWhenPreferredRunDateIsNow_thenReturnsNow() async throws {
        let now = Date()
        try await setUpTestData(scanDates: Array(repeating: now, count: 3),
                                optOutDates: Array(repeating: now, count: 3))

        let expectedDate = now
        let actualDate = try database.fetchFirstEligibleJobDate(isAuthenticatedUser: true)

        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: expectedDate, date2: actualDate))
    }

    func testWhenUsingChildBroker_thenExcludesAssociatedOptOuts() async throws {
        let weekAgo = Date.weekAgo
        try await setUpTestData(usesChildBroker: true,
                                scanDates: Array(repeating: weekAgo, count: 3),
                                optOutDates: Array(repeating: .monthAgo, count: 3))

        let expectedDate = weekAgo
        let actualDate = try database.fetchFirstEligibleJobDate(isAuthenticatedUser: true)

        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: expectedDate, date2: actualDate))
    }

    func testWhenOptOutsIncludesRemovedDate_thenExcludesAssociatedOptOuts() async throws {
        let nextWeek = Date.daysAgo(-7)
        try await setUpTestData(scanDates: Array(repeating: Date.daysAgo(-14), count: 3),
                                optOutDates: [.daysAgo(-3), nextWeek, .daysAgo(-10)],
                                removedDates: [Date(), nil, Date()])

        let expectedDate = nextWeek
        let actualDate = try database.fetchFirstEligibleJobDate(isAuthenticatedUser: true)

        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: expectedDate, date2: actualDate))
    }

    func testWhenPreferredRunDateIsAllOverThePlace_thenReturnsLeastRecentDate() async throws {
        let monthAgo = Date.monthAgo
        try await setUpTestData(scanDates: [monthAgo, .daysAgo(3), .nowPlus(hours: 120)],
                                optOutDates: [.daysAgo(5), monthAgo, .nowMinus(hours: 20)])

        let expectedDate = monthAgo
        let actualDate = try database.fetchFirstEligibleJobDate(isAuthenticatedUser: true)

        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: expectedDate, date2: actualDate))
    }

    func testWhenFreemiumUserHasGatedBroker_thenFirstEligibleJobDateIgnoresGatedBroker() async throws {
        try await saveProfile()

        let gatedBrokerDate = Date.monthAgo
        let eligibleBrokerDate = Date.daysAgo(3)
        try saveBrokerScan(fixture: "valid-broker-with-token-gated-scan-action",
                           lastRunDate: nil,
                           preferredRunDate: gatedBrokerDate)
        try saveBrokerScan(fixture: "valid-broker",
                           lastRunDate: nil,
                           preferredRunDate: eligibleBrokerDate)

        let freemiumDate = try database.fetchFirstEligibleJobDate(isAuthenticatedUser: false)
        let authenticatedDate = try database.fetchFirstEligibleJobDate(isAuthenticatedUser: true)

        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: eligibleBrokerDate, date2: freemiumDate))
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: gatedBrokerDate, date2: authenticatedDate))
    }

    func testWhenFreemiumUserHasEarlierOptOut_thenFirstEligibleJobDateIgnoresOptOut() async throws {
        let optOutDate = Date.monthAgo
        let scanDate = Date.daysAgo(3)
        try await setUpTestData(scanDates: Array(repeating: scanDate, count: 3),
                                optOutDates: Array(repeating: optOutDate, count: 3))

        let freemiumDate = try database.fetchFirstEligibleJobDate(isAuthenticatedUser: false)
        let authenticatedDate = try database.fetchFirstEligibleJobDate(isAuthenticatedUser: true)

        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: scanDate, date2: freemiumDate))
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: optOutDate, date2: authenticatedDate))
    }

    func testWhenFreemiumUserHasGatedBroker_thenInitialScanCompletionIgnoresGatedBroker() async throws {
        try await saveProfile()

        try saveBrokerScan(fixture: "valid-broker-with-token-gated-scan-action",
                           lastRunDate: nil,
                           preferredRunDate: .now)
        try saveBrokerScan(fixture: "valid-broker",
                           lastRunDate: .now,
                           preferredRunDate: .now)

        XCTAssertTrue(try database.haveAllEligibleScansRunAtLeastOnce(isAuthenticatedUser: false))
        XCTAssertFalse(try database.haveAllEligibleScansRunAtLeastOnce(isAuthenticatedUser: true))
    }

    // MARK: - Utils

    private func saveProfile() async throws {
        try await database.save(DataBrokerProtectionProfile(names: [.init(firstName: "John", lastName: "Doe")],
                                                            addresses: [.init(city: "New York", state: "NY")],
                                                            phones: [],
                                                            birthYear: 1970))
    }

    @discardableResult
    private func saveBrokerScan(fixture: String, lastRunDate: Date?, preferredRunDate: Date) throws -> Int64 {
        let brokerResource = try loadBroker(fixture: fixture)
        let brokerId = try database.saveBroker(brokerResource: brokerResource)
        let profileQuery = ProfileQuery(firstName: "John", lastName: "Doe", city: "New York", state: "NY", birthYear: 1970)
        let profileQueryId = try database.saveProfileQuery(profileQuery: profileQuery, profileId: Int64(1))
        try database.saveScanJob(brokerId: brokerId, profileQueryId: profileQueryId, lastRunDate: lastRunDate, preferredRunDate: preferredRunDate)
        return brokerId
    }

    private func setUpTestData(usesChildBroker: Bool = false,
                               scanDates: [Date],
                               optOutDates: [Date],
                               removedDates: [Date?]? = nil) async throws {
        /// Save profile
        try await database.save(DataBrokerProtectionProfile(names: [.init(firstName: "John", lastName: "Doe"),
                                                                    .init(firstName: "J", lastName: "D")],
                                                            addresses: [.init(city: "New York", state: "NY"),
                                                                        .init(city: "Los Angeles", state: "CA"),
                                                                        .init(city: "Houston", state: "TX")],
                                                            phones: [],
                                                            birthYear: 1970))

        /// Add brokers
        let brokerResource = try loadBroker(fixture: usesChildBroker ? "valid-child-broker" : "valid-broker")
        let brokerId = try database.saveBroker(brokerResource: brokerResource)

        /// Add profile queries + scans
        let profileQueries: [ProfileQuery] = [
            .init(firstName: "John", lastName: "Doe", city: "New York", state: "NY", birthYear: 1970),
            .init(firstName: "J", lastName: "Doe", city: "Houston", state: "TX", birthYear: 1970),
            .init(firstName: "J", lastName: "Doe", city: "Los Angeles", state: "CA", birthYear: 1970),
        ]

        var profileQueryIds: [Int64] = []
        for (index, profileQuery) in profileQueries.enumerated() {
            let profileQueryId = try database.saveProfileQuery(profileQuery: profileQuery, profileId: Int64(1))
            try database.saveScanJob(brokerId: brokerId, profileQueryId: profileQueryId, lastRunDate: nil, preferredRunDate: scanDates[index])

            profileQueryIds.append(profileQueryId)
        }

        /// Add extracted profiles & opt-outs
        for index in 0..<3 {
            try database.saveOptOutJob(optOut: OptOutJobData.mock(with: ExtractedProfile(),
                                                                  brokerId: brokerId,
                                                                  profileQueryId: profileQueryIds[index],
                                                                  preferredRunDate: optOutDates[index]),
                                       extractedProfile: ExtractedProfile())
        }

        let extractedProfiles = try database.fetchExtractedProfiles(for: brokerId)

        /// Add removed dates
        for (index, extractedProfile) in extractedProfiles.enumerated() {
            try database.updateRemovedDate(removedDates?[index], on: extractedProfile.id!)
        }
    }

    private func loadBroker(fixture: String) throws -> BrokerResource {
        let jsonURL = Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "BundleResources")!
        return try DataBroker.initFromResource(jsonURL)
    }
}

//
//  DataBrokerProtectionDatabaseProviderTests.swift
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
import GRDB
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

private extension DataBrokerProtectionDatabaseProvider {
    func restoreDatabase(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let sqlDump = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Invalid SQL dump file", code: 1, userInfo: nil)
        }

        // Filter SQL statements to exclude GRDB migrations table data
        let sqlStatements = sqlDump.components(separatedBy: ";\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.contains("INSERT INTO grdb_migrations") }

        try db.writeWithoutTransaction { db in

            // Disable & enable foreign keys to ignore constraint violations
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            for statement in sqlStatements {
                try db.execute(sql: statement)
            }
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
    }
}

final class DataBrokerProtectionDatabaseProviderTests: XCTestCase {

    typealias Migrations = DefaultDataBrokerProtectionDatabaseMigrationsProvider

    private var sut: DataBrokerProtectionDatabaseProvider!
    private let vaultURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: "DBP", fileName: "Test-Vault.db")
    private let key = "9CA59EDC-5CE8-4F53-AAC6-286A7378F384".data(using: .utf8)!

    override func setUpWithError() throws {
        do {
            // Sets up a test vault and restores data (with violations) from a `test-vault.sql` file
            sut = try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v2Migrations)
            let fileURL = Bundle.module.url(forResource: "test-vault", withExtension: "sql", subdirectory: "BundleResources")!
            try sut.restoreDatabase(from: fileURL)
        } catch {
            XCTFail("Failed to create test-vault and insert data")
        }
    }

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: vaultURL.path) {
            do {
                try fileManager.removeItem(at: vaultURL)
            } catch {
                XCTFail("Failed to delete test-vault")
            }
        }
        MockMigrationsProvider.didCallV2Migrations = false
        MockMigrationsProvider.didCallV3Migrations = false
        MockMigrationsProvider.didCallV4Migrations = false
        MockMigrationsProvider.didCallV5Migrations = false
        MockMigrationsProvider.didCallV6Migrations = false
        MockMigrationsProvider.didCallV7Migrations = false
        MockMigrationsProvider.didCallV8Migrations = false
    }

    func testV3MigrationCleansUpOrphanedRecords_andResultsInNoDataIntegrityIssues() throws {
        // Given
        let failingMigration: (inout DatabaseMigrator) throws -> Void = { migrator in
            migrator.registerMigration("v3") { database in
                try database.checkForeignKeys()
            }
        }

        let passingMigration: (inout DatabaseMigrator) throws -> Void = { migrator in
            migrator.registerMigration("v4") { database in
                try database.checkForeignKeys()
            }
        }

        XCTAssertThrowsError(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: failingMigration))

        // When
        XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v3Migrations))

        // Then
        XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: passingMigration))
    }

    func testV3MigrationRecreatesTablesWithCascadingDeletes_andDeletingProfileQueryDeletesDependentRecords() throws {
        // Given
        XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v5Migrations))
        XCTAssertEqual(try sut.fetchAllScans().filter { $0.profileQueryId == 43 }.count, 50)
        let allBrokerIds = try sut.fetchAllBrokers().map { $0.id! }
        var allExtractedProfiles = try allBrokerIds.flatMap { try sut.fetchExtractedProfiles(for: $0, with: 43) }
        let extractedProfileId = allExtractedProfiles.first!.id
        var optOutAttempt = try sut.fetchAttemptInformation(for: extractedProfileId!)
        var allOptOuts = try allBrokerIds.flatMap { try sut.fetchOptOuts(brokerId: $0, profileQueryId: 43) }
        var allScanHistoryEvents = try allBrokerIds.flatMap { try sut.fetchScanEvents(brokerId: $0, profileQueryId: 43) }
        var allOptOutHistoryEvents = try allBrokerIds.flatMap { try sut.fetchOptOutEvents(brokerId: $0, profileQueryId: 43) }
        XCTAssertNotNil(optOutAttempt)
        XCTAssertEqual(allExtractedProfiles.count, 1)
        XCTAssertEqual(allOptOuts.count, 1)
        XCTAssertEqual(allScanHistoryEvents.count, 656)
        XCTAssertEqual(allOptOutHistoryEvents.count, 4)
        let profileQuery = try sut.fetchProfileQuery(with: 43)!

        // When
        try sut.delete(profileQuery)

        // Then
        XCTAssertEqual(try sut.fetchAllScans().filter { $0.profileQueryId == 43 }.count, 0)
        allExtractedProfiles = try allBrokerIds.flatMap { try sut.fetchExtractedProfiles(for: $0, with: 43) }
        optOutAttempt = try sut.fetchAttemptInformation(for: extractedProfileId!)
        allOptOuts = try allBrokerIds.flatMap { try sut.fetchOptOuts(brokerId: $0, profileQueryId: 43) }
        allScanHistoryEvents = try allBrokerIds.flatMap { try sut.fetchScanEvents(brokerId: $0, profileQueryId: 43) }
        allOptOutHistoryEvents = try allBrokerIds.flatMap { try sut.fetchOptOutEvents(brokerId: $0, profileQueryId: 43) }
        XCTAssertNil(optOutAttempt)
        XCTAssertEqual(allExtractedProfiles.count, 0)
        XCTAssertEqual(allOptOuts.count, 0)
        XCTAssertEqual(allScanHistoryEvents.count, 0)
        XCTAssertEqual(allOptOutHistoryEvents.count, 0)
    }

    func testV3MigrationOfDatabaseWithLotsOfIntegrityIssues() throws {

        var length = 10
        var start: Int64 = 1000
        var end: Int64 = 2000

        repeat {

            // Given
            do {
                try sut.db.writeWithoutTransaction { db in
                    try db.execute(sql: "PRAGMA foreign_keys = OFF")
                }

                let profileQueries = ProfileQueryDB.random(withProfileIds: Int64.randomValues(ofLength: length, start: start, end: end))
                for query in profileQueries {
                    _ = try sut.save(query)
                }

                for broker in BrokerDB.random(count: length) {
                    _ = try sut.save(broker)
                }

                let brokerIds = Int64.randomValues(ofLength: length, start: start, end: end)
                let profileQueryIds = Int64.randomValues(ofLength: length, start: start, end: end)
                let extractedProfileIds = Int64.randomValues(ofLength: length, start: start, end: end)

                for scanHistoryEvent in ScanHistoryEventDB.random(withBrokerIds: brokerIds, profileQueryIds: profileQueryIds) {
                    _ = try sut.save(scanHistoryEvent)
                }

                for optOutHistoryEvent in OptOutHistoryEventDB.random(withBrokerIds: brokerIds, profileQueryIds: profileQueryIds, extractedProfileIds: extractedProfileIds) {
                    _ = try sut.save(optOutHistoryEvent)
                }

                for extractedProfile in ExtractedProfileDB.random(withBrokerIds: brokerIds, profileQueryIds: profileQueryIds) {
                    _ = try sut.save(extractedProfile)
                }

                try sut.db.writeWithoutTransaction { db in
                    try db.execute(sql: "PRAGMA foreign_keys = ON")
                }

            } catch let error as GRDB.DatabaseError where error.message == "table broker has no column named eTag" {
                // no-op, BrokerDB.eTag doesn't exist as of v3 migration so we expect this
            } catch {
                XCTFail("Failed to setup invalid data")
            }

            let failingMigration: (inout DatabaseMigrator) throws -> Void = { migrator in
                migrator.registerMigration("v3") { database in
                    try database.checkForeignKeys()
                }
            }

            let passingMigration: (inout DatabaseMigrator) throws -> Void = { migrator in
                migrator.registerMigration("v4") { database in
                    try database.checkForeignKeys()
                }
            }

            XCTAssertThrowsError(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: failingMigration))

            // When
            XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v3Migrations))

            // Then
            XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: passingMigration))

            length += 1
            start += (start/2)
            end += (end/2)

            try tearDownWithError()
            try setUpWithError()

        } while length < 20
    }

    func testV4Migration() throws {
        // Given
        XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v5Migrations))

        // When
        let optOuts = try sut.fetchAllOptOuts()
        let optOut = optOuts.first!.optOutDB

        // Then
        XCTAssertNil(optOut.submittedSuccessfullyDate)
        XCTAssertFalse(optOut.sevenDaysConfirmationPixelFired)
        XCTAssertFalse(optOut.fourteenDaysConfirmationPixelFired)
        XCTAssertFalse(optOut.twentyOneDaysConfirmationPixelFired)

    }

    func testV5Migration() throws {
        // Given
        XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v5Migrations))

        // When
        let optOuts = try sut.fetchAllOptOuts()
        let optOut = optOuts.first!.optOutDB

        // Then
        XCTAssertEqual(optOut.attemptCount, 0)
    }

    func testV8Migration() throws {
        // Given
        XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v8Migrations))

        // When
        let brokers = try sut.fetchAllBrokers()
        let broker = brokers.first!

        // Then
        XCTAssertNil(broker.removedAt, "New removedAt field should default to nil")
    }

    func testV8Migration_schemaHasRemovedAtColumn() throws {
        // Given
        XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v8Migrations))

        // When/Then
        try sut.db.read { db in
            let columns = try db.columns(in: BrokerDB.databaseTableName)
            let hasRemovedAtColumn = columns.contains { $0.name == "removedAt" }
            XCTAssertTrue(hasRemovedAtColumn, "removedAt column should exist after v8 migration")

            // Verify it's nullable
            let removedAtColumn = columns.first { $0.name == "removedAt" }
            XCTAssertTrue(removedAtColumn?.isNotNull == false, "removedAt column should be nullable")
        }
    }

    func testV8Migration_canSetAndRetrieveRemovedAt() throws {
        // Given
        XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v8Migrations))

        // When: Create broker with removedAt date
        let testDate = Date()
        let newBroker = BrokerDB.random(name: "TestBroker", removedAt: testDate)
        let brokerId = try sut.save(newBroker)

        // Then: Can retrieve the date correctly
        let savedBroker = try sut.fetchBroker(with: brokerId)
        XCTAssertNotNil(savedBroker?.removedAt)
        XCTAssertEqual(savedBroker!.removedAt!.timeIntervalSince1970,
                       testDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testV8Migration_preservesExistingBrokerData() throws {
        // Given: Capture existing broker data before migration
        let existingBrokers = try sut.fetchAllBrokers()
        let firstBroker = existingBrokers.first!
        let originalName = firstBroker.name
        let originalJSON = firstBroker.json
        let originalVersion = firstBroker.version

        // When: Apply v8 migration
        XCTAssertNoThrow(try DefaultDataBrokerProtectionDatabaseProvider(file: vaultURL, key: key, registerMigrationsHandler: Migrations.v8Migrations))

        // Then: All original data preserved
        let migratedBrokers = try sut.fetchAllBrokers()
        XCTAssertEqual(migratedBrokers.count, existingBrokers.count, "Broker count should be preserved")

        let migratedBroker = migratedBrokers.first { $0.id == firstBroker.id }!
        XCTAssertEqual(migratedBroker.name, originalName)
        XCTAssertEqual(migratedBroker.json, originalJSON)
        XCTAssertEqual(migratedBroker.version, originalVersion)
        XCTAssertNil(migratedBroker.removedAt, "Existing brokers should have nil removedAt")
    }

    func testV8Migration_freshInstallDirectlyToV8() throws {
        // Given: Fresh database (no test-vault.sql data)
        let freshVaultURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(
            directoryName: "DBP",
            fileName: "Fresh-V8-Test-Vault.db"
        )

        // When: Create database directly with v8 migrations (fresh install scenario)
        let freshProvider = try DefaultDataBrokerProtectionDatabaseProvider(
            file: freshVaultURL,
            key: key,
            registerMigrationsHandler: Migrations.v8Migrations
        )

        // Then: Schema should be correct and ready for use
        try freshProvider.db.read { db in
            let hasRemovedAtColumn = try db.tableExists(BrokerDB.databaseTableName) &&
                db.columns(in: BrokerDB.databaseTableName).contains { $0.name == "removedAt" }
            XCTAssertTrue(hasRemovedAtColumn, "removedAt column should exist in fresh v8 install")
        }

        // And: Should be able to create brokers with removedAt
        let testBroker = BrokerDB.random(name: "FreshTestBroker", removedAt: Date())
        let brokerId = try freshProvider.save(testBroker)

        let savedBroker = try freshProvider.fetchBroker(with: brokerId)
        XCTAssertNotNil(savedBroker?.removedAt, "Should be able to save removedAt in fresh install")

        // Cleanup
        try? FileManager.default.removeItem(at: freshVaultURL)
    }

    func testV8Migration_updateFromV7ToV8() throws {
        // Given: Database explicitly at v7 (simulating previous app version)
        let updateVaultURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(
            directoryName: "DBP",
            fileName: "V7-to-V8-Update-Test-Vault.db"
        )

        // Create and populate v7 database
        let v7Provider = try DefaultDataBrokerProtectionDatabaseProvider(
            file: updateVaultURL,
            key: key,
            registerMigrationsHandler: Migrations.v7Migrations
        )

        // Add some test data to v7 database (manual insert without removedAt column)
        let v7BrokerId: Int64 = try v7Provider.db.write { db in
            try db.execute(sql: "INSERT INTO broker (name, json, version, url, eTag) VALUES (?, ?, ?, ?, ?)",
                           arguments: [
                            "V7TestBroker",
                            try! JSONSerialization.data(withJSONObject: [:], options: []),
                            "1.0.0",
                            "www.v7testbroker.com",
                            "v7-etag"
                           ])
            return db.lastInsertedRowID
        }
        let v7BrokerCount = try v7Provider.fetchAllBrokers().count

        // When: Update to v8 (simulating app update)
        let v8Provider = try DefaultDataBrokerProtectionDatabaseProvider(
            file: updateVaultURL,
            key: key,
            registerMigrationsHandler: Migrations.v8Migrations
        )

        // Then: v7 data preserved and v8 schema available
        let v8Brokers = try v8Provider.fetchAllBrokers()
        XCTAssertEqual(v8Brokers.count, v7BrokerCount, "Broker count should be preserved during v7→v8 update")

        let updatedBroker = try v8Provider.fetchBroker(with: v7BrokerId)!
        XCTAssertNil(updatedBroker.removedAt, "Existing v7 brokers should have nil removedAt after update")

        // And: Can use new v8 functionality
        let newV8Broker = BrokerDB.random(name: "NewV8TestBroker", removedAt: Date())
        let newBrokerId = try v8Provider.save(newV8Broker)

        let savedNewBroker = try v8Provider.fetchBroker(with: newBrokerId)
        XCTAssertNotNil(savedNewBroker?.removedAt, "Should be able to use removedAt field after v7→v8 update")

        // Cleanup
        try? FileManager.default.removeItem(at: updateVaultURL)
    }

    func testDeleteAllDataSucceedsInRemovingAllData() throws {
        XCTAssertFalse(try sut.db.allTablesAreEmpty())
        XCTAssertNoThrow(try sut.deleteProfileData())
        XCTAssertTrue(try sut.db.allTablesAreEmpty())
    }

    func testWhenFetchAllNonRemovedBrokers_thenFiltersCorrectly() throws {
        // Given
        let (freshProvider, url) = try createFreshTestVault()

        let activeBroker = BrokerDB.random(name: "ActiveBroker", removedAt: nil)
        let removedBroker = BrokerDB.random(name: "RemovedBroker", removedAt: Date())

        // When
        _ = try freshProvider.save(activeBroker)
        _ = try freshProvider.save(removedBroker)

        let allBrokers = try freshProvider.fetchAllBrokers()
        let nonRemovedBrokers = try freshProvider.fetchAllNonRemovedBrokers()

        // Then
        XCTAssertEqual(allBrokers.count, 2, "Should fetch all brokers including removed ones")
        XCTAssertEqual(nonRemovedBrokers.count, 1, "Should only fetch non-removed brokers")
        XCTAssertEqual(nonRemovedBrokers.first?.name, "ActiveBroker", "Should only return active broker")
        XCTAssertNil(nonRemovedBrokers.first?.removedAt, "Returned broker should not have removedAt set")

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    func testWhenFetchAllNonRemovedBrokers_thenReturnsAllBrokers() throws {
        // Given
        let (freshProvider, url) = try createFreshTestVault()

        let broker1 = BrokerDB.random(name: "ActiveBroker1", removedAt: nil)
        let broker2 = BrokerDB.random(name: "ActiveBroker2", removedAt: nil)

        // When
        _ = try freshProvider.save(broker1)
        _ = try freshProvider.save(broker2)

        let allBrokers = try freshProvider.fetchAllBrokers()
        let nonRemovedBrokers = try freshProvider.fetchAllNonRemovedBrokers()

        // Then
        XCTAssertEqual(allBrokers.count, 2, "Should fetch all brokers")
        XCTAssertEqual(nonRemovedBrokers.count, 2, "Should fetch all brokers when none are removed")
        XCTAssertEqual(allBrokers.count, nonRemovedBrokers.count, "Counts should match when no brokers are removed")

        try? FileManager.default.removeItem(at: url)
    }

    func testWhenFetchAllNonRemovedBrokers_thenReturnsEmptyArray() throws {
        // Given
        let (freshProvider, url) = try createFreshTestVault()

        let removedBroker1 = BrokerDB.random(name: "RemovedBroker1", removedAt: Date())
        let removedBroker2 = BrokerDB.random(name: "RemovedBroker2", removedAt: Date())

        // When
        _ = try freshProvider.save(removedBroker1)
        _ = try freshProvider.save(removedBroker2)

        let allBrokers = try freshProvider.fetchAllBrokers()
        let nonRemovedBrokers = try freshProvider.fetchAllNonRemovedBrokers()

        // Then
        XCTAssertEqual(allBrokers.count, 2, "Should fetch all brokers including removed ones")
        XCTAssertEqual(nonRemovedBrokers.count, 0, "Should return empty array when all brokers are removed")

        try? FileManager.default.removeItem(at: url)
    }

    private func createFreshTestVault() throws -> (DefaultDataBrokerProtectionDatabaseProvider, URL) {
        let freshVaultURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(
            directoryName: "DBP",
            fileName: "Fresh-Test-Vault.db"
        )
        try? FileManager.default.removeItem(at: freshVaultURL)

        let freshProvider = try DefaultDataBrokerProtectionDatabaseProvider(
            file: freshVaultURL,
            key: key,
            registerMigrationsHandler: Migrations.v8Migrations
        )

        return (freshProvider, freshVaultURL)
    }
}

private extension DatabaseWriter {

    func allTablesAreEmpty() throws -> Bool {
        return try self.read { db in
            // Get the list of all tables
            let tableNames = try String.fetchAll(db, sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                  AND name NOT LIKE 'sqlite_%';
            """)

            // Check if all tables are empty, ignoring our migrations table
            for tableName in tableNames where tableName != "grdb_migrations" {
                let rowCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(tableName)") ?? 0
                if rowCount > 0 {
                    return false
                }
            }
            return true
        }
    }
}
